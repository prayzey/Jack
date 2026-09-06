import CoreAudio
import Foundation
import OSLog

/// Lowers the system's default output volume while dictation is active so the
/// user's voice doesn't have to compete with background music/video. Restores
/// the original level when dictation stops.
///
/// macOS doesn't expose a clean per-app ducking API outside of CoreAudio's
/// private interfaces, so we operate on the **default output device**'s
/// master volume property. That affects everything routed through the
/// current output (Spotify, browser audio, system sounds), which is a known
/// trade-off — but the user controls how much it dims (0 = no change,
/// 1 = full mute) so it can be tuned to taste.
///
/// Fades are short (~220ms) on both directions so volume changes feel
/// intentional rather than jolting.
@MainActor
final class AudioDucker {
    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "AudioDucker")
    private let fadeSteps = 14
    private let fadeDuration: TimeInterval = 0.22

    /// Volume we captured on the most recent `startDucking`. Restored on stop.
    private var originalVolume: Float?
    /// Device we adjusted last. Cached so a device-switch mid-session still
    /// restores the original device, not whatever's plugged in now.
    private var deviceID: AudioDeviceID?
    private var activeFade: Task<Void, Never>?

    /// Fade the system volume down. `amount` is 0…1: 0 means do nothing,
    /// 1 means fully mute. Stores the pre-duck volume so `stopDucking` can
    /// restore it.
    func startDucking(amount: Double) async {
        let clamped = max(0, min(1, amount))
        guard clamped > 0 else { return }
        guard let device = Self.defaultOutputDevice() else {
            logger.warning("No default output device — skipping duck")
            return
        }
        guard let current = Self.readVolume(on: device) else {
            logger.warning("Couldn't read output volume — skipping duck")
            return
        }
        let target = current * Float(1.0 - clamped)
        deviceID = device
        originalVolume = current
        await fade(on: device, from: current, to: target)
    }

    /// Fade back up to whatever level we captured on `startDucking`. No-op
    /// if we haven't ducked anything.
    func stopDucking() async {
        guard let device = deviceID, let original = originalVolume else { return }
        let now = Self.readVolume(on: device) ?? 0
        await fade(on: device, from: now, to: original)
        originalVolume = nil
        deviceID = nil
    }

    // MARK: - Fade

    private func fade(on device: AudioDeviceID, from: Float, to: Float) async {
        activeFade?.cancel()
        let steps = fadeSteps
        let stepDuration = fadeDuration / Double(steps)
        let task = Task { @MainActor in
            for i in 1...steps {
                if Task.isCancelled { return }
                let progress = Float(i) / Float(steps)
                let v = from + (to - from) * progress
                Self.writeVolume(v, on: device)
                try? await Task.sleep(nanoseconds: UInt64(stepDuration * 1_000_000_000))
            }
        }
        activeFade = task
        await task.value
    }

    // MARK: - CoreAudio helpers
    //
    // Output volume on macOS is exposed through `AudioObject` properties on
    // the default output device. Some devices expose a "master" channel
    // (element 0); others only expose per-channel volumes (elements 1+).
    // We try master first and fall back to writing every available channel.

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        )
        return status == noErr ? deviceID : nil
    }

    private static func readVolume(on device: AudioDeviceID) -> Float? {
        // Try master.
        if let v = readChannel(0, on: device) { return v }
        // Fall back to first two channels averaged.
        let l = readChannel(1, on: device)
        let r = readChannel(2, on: device)
        if let l, let r { return (l + r) / 2 }
        return l ?? r
    }

    private static func writeVolume(_ volume: Float, on device: AudioDeviceID) {
        if writeChannel(0, value: volume, on: device) { return }
        // Some devices don't expose a master — write every channel we can.
        var anyWritten = false
        for channel: UInt32 in 1...8 {
            if writeChannel(channel, value: volume, on: device) {
                anyWritten = true
            } else {
                break
            }
        }
        _ = anyWritten
    }

    private static func readChannel(_ channel: UInt32, on device: AudioDeviceID) -> Float? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: channel
        )
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var volume: Float = 0
        var size = UInt32(MemoryLayout<Float>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume)
        return status == noErr ? volume : nil
    }

    @discardableResult
    private static func writeChannel(_ channel: UInt32, value: Float, on device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: channel
        )
        guard AudioObjectHasProperty(device, &address) else { return false }
        var v = value
        let status = AudioObjectSetPropertyData(
            device, &address, 0, nil,
            UInt32(MemoryLayout<Float>.size), &v
        )
        return status == noErr
    }
}
