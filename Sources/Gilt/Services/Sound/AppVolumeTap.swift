import Accelerate
import AudioToolbox
import CoreAudio
import Foundation

/// Plays one app's audio at a chosen volume, on a chosen output, or just
/// listens to it for a level meter.
///
/// Core Audio taps the app's processes (`CATapDescription`) and, with
/// `.mutedWhenTapped`, silences the app's own output while the tap is being
/// read. A private aggregate device built on the target output reads the tap
/// and writes it back out scaled by `gain`. If Jack stops reading (teardown,
/// crash, quit), the app is audible on its own again.
///
/// A listen-only tap is `.unmuted` and writes silence: the app keeps playing
/// on its own while Jack measures it. That's both the level meter and the
/// permission probe, because without System Audio Recording permission a tap
/// still "works" but only delivers silence, which would mute the app.
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

    enum Source {
        case processes([AudioObjectID])
        /// Everything the Mac plays except these processes (Jack itself).
        case everythingExcept([AudioObjectID])
    }

    let isListenOnly: Bool
    let createdAt = Date()

    /// The gain this tap is heading to. Set it with `setGain(_:rampSeconds:)`.
    var gain: Float { state.target.pointee }

    /// True once the tap delivered a non-silent sample, proving that macOS
    /// lets Jack capture audio.
    var hasHeardAudio: Bool { state.sawAudio.pointee != 0 }

    private let state: RenderState
    private let queue = DispatchQueue(label: "com.praisedev.jack.app-volume-tap")
    // Only touched on `queue` (or in deinit, once no queued work holds self).
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?

    /// - Parameter startGain: the gain the app is audibly at right now (1 for
    ///   an app that wasn't tapped), so a new tap fades to `gain` instead of
    ///   jumping there.
    init(
        source: Source,
        outputDevice: AudioObjectID,
        gain: Float,
        startGain: Float = 1,
        listenOnly: Bool,
        onFailure: @escaping @Sendable (AppVolumeTap, Failure) -> Void
    ) {
        isListenOnly = listenOnly
        state = RenderState(gain: gain, startGain: startGain, isListenOnly: listenOnly)
        queue.async { [self] in
            do {
                try build(source: source, outputDevice: outputDevice)
            } catch {
                // Roll back so an app is never left muted with nothing playing it.
                teardown()
                onFailure(self, error as? Failure ?? .unavailable(kAudioHardwareUnspecifiedError))
            }
        }
    }

    deinit { teardown() }

    /// Moves toward `gain` over `rampSeconds`: about 30 ms for a slider drag
    /// (fast, but no click), longer for automatic ducking so it fades.
    func setGain(_ gain: Float, rampSeconds: Float = 0.03) {
        state.ramp.pointee = rampSeconds
        state.target.pointee = gain
    }

    /// Fades a muffle style in (or out, with nil) over `rampSeconds`.
    func setMuffle(_ muffle: SoundMuffle?, rampSeconds: Float) {
        if let muffle, let index = SoundMuffle.allCases.firstIndex(of: muffle) {
            state.muffleStyle.pointee = Int32(index)
        }
        state.muffleRamp.pointee = rampSeconds
        state.muffleTarget.pointee = muffle == nil ? 0 : 1
    }

    var isMuffled: Bool { state.muffleTarget.pointee > 0 }

    /// Loudest sample (0...1) since the last call, as heard after the gain.
    func takePeak() -> Float {
        let peak = state.peak.pointee
        state.peak.pointee = 0
        return peak
    }

    /// Destroys the tap, which hands the app its normal output back.
    func invalidate() {
        queue.async { [self] in teardown() }
    }

    private func build(source: Source, outputDevice: AudioObjectID) throws {
        let description: CATapDescription
        switch source {
        case .processes(let objects):
            description = CATapDescription(stereoMixdownOfProcesses: objects)
        case .everythingExcept(let objects):
            description = CATapDescription(stereoGlobalTapButExcludeProcesses: objects)
        }
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = isListenOnly ? .unmuted : .mutedWhenTapped
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
        state.sampleRate = Float(sampleRate)
        if !isListenOnly { state.muffler = MuffleProcessor(sampleRate: Float(sampleRate)) }

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
/// thread writes `target`, `ramp`, and the muffle settings and reads `peak`;
/// the render thread owns `current` and `muffleMix` and writes `peak` and
/// `sawAudio`.
final class RenderState: @unchecked Sendable {
    let target = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    /// Seconds for a full 0 to 1 sweep.
    let ramp = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    let peak = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    let sawAudio = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
    /// Index into `SoundMuffle.allCases`; kept after a fade-out starts so
    /// the tail still sounds like the same style.
    let muffleStyle = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
    /// 1 to muffle, 0 to play clean.
    let muffleTarget = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    let muffleRamp = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    private let current = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    private var muffleMix: Float = 0
    private let isListenOnly: Bool
    /// Set before IO starts.
    var sampleRate: Float = 48_000
    var muffler: MuffleProcessor?

    init(gain: Float, startGain: Float = 1, isListenOnly: Bool) {
        self.isListenOnly = isListenOnly
        target.initialize(to: gain)
        ramp.initialize(to: 0.03)
        peak.initialize(to: 0)
        current.initialize(to: isListenOnly ? gain : startGain)
        sawAudio.initialize(to: 0)
        muffleStyle.initialize(to: 0)
        muffleTarget.initialize(to: 0)
        muffleRamp.initialize(to: 0.5)
    }

    deinit {
        target.deallocate()
        ramp.deallocate()
        peak.deallocate()
        sawAudio.deallocate()
        current.deallocate()
        muffleStyle.deallocate()
        muffleTarget.deallocate()
        muffleRamp.deallocate()
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
              let source = tap.mData?.assumingMemoryBound(to: Float.self)
        else { return }
        let tapFrames = Int(tap.mDataByteSize) / (2 * MemoryLayout<Float>.size)
        guard tapFrames > 0 else { return }

        if isListenOnly {
            // The app plays on its own; just measure it.
            var loudest: Float = 0
            vDSP_maxmgv(source, 1, &loudest, vDSP_Length(tapFrames * 2))
            if loudest > 0 { sawAudio.pointee = 1 }
            if loudest > peak.pointee { peak.pointee = loudest }
            return
        }

        guard let first = outputs.first,
              let left = first.mData?.assumingMemoryBound(to: Float.self)
        else { return }
        let nonInterleaved = first.mNumberChannels == 1 && outputs.count > 1
        let mono = first.mNumberChannels == 1 && !nonInterleaved
        let channels = Int(first.mNumberChannels)
        guard channels > 0,
              let right = (nonInterleaved ? outputs[1].mData : first.mData)?.assumingMemoryBound(to: Float.self)
        else { return }
        let frames = min(tapFrames, Int(first.mDataByteSize) / (channels * MemoryLayout<Float>.size))
        guard frames > 0 else { return }

        let start = current.pointee
        let limit = Float(frames) / max(sampleRate * ramp.pointee, 1)
        let end = start + max(-limit, min(limit, target.pointee - start))
        let step = (end - start) / Float(frames)
        current.pointee = end

        // The muffle crossfades from clean to effected the same way.
        let muffleStart = muffleMix
        let muffleLimit = Float(frames) / max(sampleRate * muffleRamp.pointee, 1)
        let muffleEnd = muffleStart + max(-muffleLimit, min(muffleLimit, muffleTarget.pointee - muffleStart))
        let muffleStep = (muffleEnd - muffleStart) / Float(frames)
        muffleMix = muffleEnd
        let muffler = (muffleStart > 0 || muffleEnd > 0) ? self.muffler : nil
        let style = Int(muffleStyle.pointee)

        let rightOffset = channels > 1 ? 1 : 0
        var gain = start
        var mix = muffleStart
        var loudest: Float = 0
        var heard = false
        for frame in 0..<frames {
            gain += step
            mix += muffleStep
            let rawL = source[frame * 2]
            let rawR = source[frame * 2 + 1]
            if rawL != 0 || rawR != 0 { heard = true }
            var l = rawL * gain
            var r = rawR * gain
            if let muffler {
                var wetL = l
                var wetR = r
                muffler.process(&wetL, &wetR, styleIndex: style)
                l += (wetL - l) * mix
                r += (wetR - r) * mix
            }
            loudest = max(loudest, abs(l), abs(r))
            if mono {
                left[frame] = (l + r) * 0.5
            } else {
                left[frame * channels] = l
                right[frame * channels + rightOffset] = r
            }
        }
        if heard { sawAudio.pointee = 1 }
        if loudest > peak.pointee { peak.pointee = loudest }
    }
}
