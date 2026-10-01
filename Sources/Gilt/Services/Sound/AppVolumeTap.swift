import AudioToolbox
import CoreAudio
import Foundation

/// Plays one app's audio at a chosen volume.
///
/// Core Audio taps the app's processes (`CATapDescription`) and, with
/// `.mutedWhenTapped`, silences the app's own output while the tap is being
/// read. A private aggregate device built on the current output reads the tap
/// and writes it back out scaled by `gain`. If Jack stops reading (teardown,
/// crash, quit), the app is audible on its own again.
///
/// Without System Audio Recording permission the tap still "works" but only
/// delivers silence, which would mute the app. So the first tap of a run is a
/// probe: `.unmuted`, writing nothing, until a real sample proves capture works.
///
/// All Core Audio setup and teardown runs on this tap's own serial queue:
/// starting IO can block (the permission prompt, slow devices), and one stuck
/// tap must not stall the UI or other apps' taps.
@available(macOS 14.2, *)
final class AppVolumeTap: @unchecked Sendable {
    enum Failure: Error, Equatable {
        case permissionDenied
        case unavailable(OSStatus)
    }

    let isProbe: Bool
    let createdAt = Date()

    var gain: Float {
        get { state.target.pointee }
        set { state.target.pointee = newValue }
    }

    /// True once the tap delivered a non-silent sample, proving that macOS
    /// lets Jack capture audio.
    var hasHeardAudio: Bool { state.sawAudio.pointee != 0 }

    private let state: RenderState
    private let queue = DispatchQueue(label: "com.praisedev.jack.app-volume-tap")
    // Only touched on `queue` (or in deinit, once no queued work holds self).
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?

    init(
        processObjects: [AudioObjectID],
        outputDevice: AudioObjectID,
        gain: Float,
        probe: Bool,
        onFailure: @escaping @Sendable (AppVolumeTap, Failure) -> Void
    ) {
        isProbe = probe
        state = RenderState(gain: gain, isProbe: probe)
        queue.async { [self] in
            do {
                try build(processObjects: processObjects, outputDevice: outputDevice)
            } catch {
                // Roll back so an app is never left muted with nothing playing it.
                teardown()
                onFailure(self, error as? Failure ?? .unavailable(kAudioHardwareUnspecifiedError))
            }
        }
    }

    deinit { teardown() }

    /// Destroys the tap, which hands the app its normal output back.
    func invalidate() {
        queue.async { [self] in teardown() }
    }

    private func build(processObjects: [AudioObjectID], outputDevice: AudioObjectID) throws {
        let description = CATapDescription(stereoMixdownOfProcesses: processObjects)
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = isProbe ? .unmuted : .mutedWhenTapped
        let tapStatus = AudioHardwareCreateProcessTap(description, &tapID)
        // 'nope' is how Core Audio refuses a tap when capture isn't allowed.
        if tapStatus == kAudioHardwareIllegalOperationError { throw Failure.permissionDenied }
        try check(tapStatus)

        guard let outputUID = outputDevice.readString(kAudioDevicePropertyDeviceUID) else {
            throw Failure.unavailable(kAudioHardwareBadDeviceError)
        }
        let transport: UInt32 = outputDevice.read(kAudioDevicePropertyTransportType) ?? 0
        let isBluetooth = transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
        let composition: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Jack app volume",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                // A Bluetooth output and the tap share the Bluetooth clock;
                // compensating "drift" between them adds a rhythmic crackle.
                kAudioSubTapDriftCompensationKey: !isBluetooth,
            ]],
        ]
        try check(AudioHardwareCreateAggregateDevice(composition as CFDictionary, &aggregateID))

        // The render loop assumes 32-bit float samples. Anything else would
        // be played as loud noise, so leave the app alone instead.
        let format: AudioStreamBasicDescription? = aggregateID.read(kAudioDevicePropertyStreamFormat, scope: kAudioObjectPropertyScopeOutput)
        guard let format, format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mBitsPerChannel == 32
        else { throw Failure.unavailable(kAudioDeviceUnsupportedFormatError) }
        let sampleRate: Float64 = aggregateID.read(kAudioDevicePropertyNominalSampleRate) ?? 48_000
        state.setSampleRate(sampleRate)

        // Capture the render state, never self: the block runs on the HAL's
        // real-time thread and Core Audio retains it until DestroyIOProcID.
        let state = self.state
        try check(AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, nil) { @Sendable _, input, _, output, _ in
            state.render(input, into: output)
        })
        disableDeviceInputs()
        try check(AudioDeviceStart(aggregateID, ioProcID))
    }

    /// An output that also records (AirPods, USB headsets) adds its mic to
    /// the aggregate's inputs. Reading it would turn the mic on and push
    /// Bluetooth headsets into low-quality call mode, so only the tap stream
    /// (always last) stays on.
    private func disableDeviceInputs() {
        let streamCount = aggregateID.readArray(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput).count
        guard streamCount > 1, let ioProcID,
              let flagsOffset = MemoryLayout<AudioHardwareIOProcStreamUsage>.offset(of: \.mStreamIsOn),
              let countOffset = MemoryLayout<AudioHardwareIOProcStreamUsage>.offset(of: \.mNumberStreams)
        else { return }
        let size = flagsOffset + streamCount * MemoryLayout<UInt32>.size
        let usage = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<AudioHardwareIOProcStreamUsage>.alignment)
        defer { usage.deallocate() }
        usage.storeBytes(of: unsafeBitCast(ioProcID, to: UnsafeMutableRawPointer.self), as: UnsafeMutableRawPointer.self)
        usage.storeBytes(of: UInt32(streamCount), toByteOffset: countOffset, as: UInt32.self)
        for stream in 0..<streamCount {
            usage.storeBytes(of: stream == streamCount - 1 ? 1 : 0, toByteOffset: flagsOffset + stream * 4, as: UInt32.self)
        }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyIOProcStreamUsage,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(aggregateID, &address, 0, nil, UInt32(size), usage)
    }

    /// Order matters: stop IO, destroy the IO proc (waits for the current
    /// cycle and releases the render state), then the aggregate, then the tap.
    private func teardown() {
        if let ioProcID {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            self.ioProcID = nil
        }
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    private func check(_ status: OSStatus) throws {
        guard status == noErr else { throw Failure.unavailable(status) }
    }
}

/// State shared with the real-time render thread. Plain aligned 32-bit
/// loads and stores are atomic on arm64 and x86_64, so no locks: the UI
/// thread writes `target`, the render thread reads it and owns `current`.
final class RenderState: @unchecked Sendable {
    let target = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    let sawAudio = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
    private let current = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    private let isProbe: Bool
    /// Largest gain change per frame: a full 0 to 1 sweep takes 30 ms, so
    /// dragging a slider doesn't click. Set before IO starts.
    private var maxStepPerFrame: Float = 1 / 1_440

    init(gain: Float, isProbe: Bool) {
        self.isProbe = isProbe
        target.initialize(to: gain)
        // Start at the target so the first buffer doesn't ramp down from full.
        current.initialize(to: gain)
        sawAudio.initialize(to: 0)
    }

    deinit {
        target.deallocate()
        sawAudio.deallocate()
        current.deallocate()
    }

    func setSampleRate(_ sampleRate: Double) {
        maxStepPerFrame = 1 / max(Float(sampleRate) * 0.03, 1)
    }

    /// Copies the tap's stereo stream to the output's first stereo pair.
    /// Inputs list the output device's own streams first and the tap last.
    /// Runs on the real-time thread: no allocation, locks, or logging.
    func render(_ input: UnsafePointer<AudioBufferList>, into output: UnsafeMutablePointer<AudioBufferList>) {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        for buffer in outputs {
            if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
        }
        guard let tap = inputs.last, tap.mNumberChannels == 2,
              let source = tap.mData?.assumingMemoryBound(to: Float.self),
              let first = outputs.first,
              let left = first.mData?.assumingMemoryBound(to: Float.self)
        else { return }
        let tapFrames = Int(tap.mDataByteSize) / (2 * MemoryLayout<Float>.size)

        if sawAudio.pointee == 0, (0..<tapFrames * 2).contains(where: { source[$0] != 0 }) {
            sawAudio.pointee = 1
        }
        // A probe leaves the app playing on its own and adds nothing.
        if isProbe { return }

        let nonInterleaved = first.mNumberChannels == 1 && outputs.count > 1
        let mono = first.mNumberChannels == 1 && !nonInterleaved
        let channels = Int(first.mNumberChannels)
        guard channels > 0,
              let right = (nonInterleaved ? outputs[1].mData : first.mData)?.assumingMemoryBound(to: Float.self)
        else { return }
        let frames = min(tapFrames, Int(first.mDataByteSize) / (channels * MemoryLayout<Float>.size))
        guard frames > 0 else { return }

        let start = current.pointee
        let limit = maxStepPerFrame * Float(frames)
        let end = start + max(-limit, min(limit, target.pointee - start))
        let step = (end - start) / Float(frames)
        current.pointee = end

        let rightOffset = channels > 1 ? 1 : 0
        var gain = start
        for frame in 0..<frames {
            gain += step
            let l = source[frame * 2] * gain
            let r = source[frame * 2 + 1] * gain
            if mono {
                left[frame] = (l + r) * 0.5
            } else {
                left[frame * channels] = l
                right[frame * channels + rightOffset] = r
            }
        }
    }
}
