@preconcurrency import AVFoundation
import AudioToolbox
import Combine
import CoreAudio
import Foundation
import OSLog

/// One row in the input-device picker.
///
/// `uid` is `kAudioDevicePropertyDeviceUID` (== `AVCaptureDevice.uniqueID`),
/// the only identifier that survives reboots and re-plugging — names collide
/// across same-model mics and `AudioDeviceID` is per-boot. Persist UID.
struct AudioInputDevice: Identifiable, Hashable {
    let uid: String
    let name: String
    let manufacturer: String?
    let transportType: UInt32
    let isSystemDefault: Bool

    var id: String { uid }

    /// True for software-only / loopback devices (BlackHole, ZoomAudioDevice,
    /// "Microsoft Teams Audio"). We hide these by default — they show up in
    /// the input list but aren't real mics.
    var isVirtual: Bool {
        transportType == kAudioDeviceTransportTypeVirtual
    }
}

/// Owns the input-device list and the CoreAudio property writes for binding a
/// device to an `AVAudioEngine` and reading/writing hardware input gain.
///
/// One shared instance — both the dictation and meeting capture paths read
/// from it and both settings pickers display its `availableDevices` list, so
/// plugging in a new mic refreshes everywhere.
@MainActor
final class AudioInputDeviceManager: ObservableObject {
    static let shared = AudioInputDeviceManager()

    /// All input-capable devices, with virtual/loopback drivers filtered out.
    /// Updated on init and whenever CoreAudio posts a device-list change.
    @Published private(set) var availableDevices: [AudioInputDevice] = []

    /// Human-readable name of whatever macOS currently treats as the default
    /// input. Surfaced next to the "Default" row in the picker
    /// ("Default — MacBook Pro Microphone") so users can see what "default"
    /// resolves to right now.
    @Published private(set) var systemDefaultDeviceName: String?

    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "AudioInputDevices")

    /// `AudioObjectAddPropertyListenerBlock` requires us to keep the address
    /// + block alive for as long as we want notifications. We store both here
    /// and tear them down in `deinit`.
    private var devicesListenerAddress: AudioObjectPropertyAddress?
    private var defaultListenerAddress: AudioObjectPropertyAddress?

    private init() {
        refresh()
        startListeningForDeviceChanges()
    }

    deinit {
        // Best-effort cleanup. The listener blocks capture `self` weakly, but
        // we still want to detach so the runloop doesn't fire callbacks into
        // a dead instance.
        if var addr = devicesListenerAddress {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &addr,
                DispatchQueue.main,
                { _, _ in }
            )
        }
        if var addr = defaultListenerAddress {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &addr,
                DispatchQueue.main,
                { _, _ in }
            )
        }
    }

    // MARK: - Enumeration

    /// Force a re-enumeration. The "Refresh" button in the picker calls this.
    /// Cheap (~ms) so safe to call on any UI gesture.
    func refresh() {
        let defaultID = Self.defaultInputDeviceID()
        let defaultName: String? = defaultID.flatMap { Self.deviceName(forID: $0) }

        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: macosInputDeviceTypes(),
            mediaType: .audio,
            position: .unspecified
        )

        let collected: [AudioInputDevice] = session.devices.compactMap { dev in
            // `AVCaptureDevice.uniqueID` IS `kAudioDevicePropertyDeviceUID` on
            // macOS — verified in Apple's CoreAudio/AVFoundation docs. We use
            // it as our stable handle.
            let uid = dev.uniqueID
            let id = Self.deviceID(forUID: uid)
            let transport = id.flatMap { Self.transportType(forID: $0) } ?? kAudioDeviceTransportTypeUnknown
            return AudioInputDevice(
                uid: uid,
                name: dev.localizedName,
                manufacturer: dev.manufacturer,
                transportType: transport,
                isSystemDefault: uid == (defaultID.flatMap { Self.deviceUID(forID: $0) } ?? "")
            )
        }

        // Hide virtual loopback devices by default. They show up in the input
        // list (Microsoft Teams Audio, ZoomAudioDevice, BlackHole, Loopback)
        // but aren't real mics — selecting one produces silence for dictation.
        // Aggregate devices stay visible (legit user-built multi-mic rigs).
        availableDevices = collected
            .filter { !$0.isVirtual }
            .sorted { lhs, rhs in
                if lhs.isSystemDefault != rhs.isSystemDefault { return lhs.isSystemDefault }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        systemDefaultDeviceName = defaultName
    }

    /// Look up a device by UID in the current `availableDevices`.
    func device(forUID uid: String?) -> AudioInputDevice? {
        guard let uid else { return nil }
        return availableDevices.first { $0.uid == uid }
    }

    // MARK: - Engine binding

    /// Binds `engine.inputNode` to the device with the given UID. Pass `nil`
    /// to follow the system default (skips the bind entirely so AVAudioEngine
    /// uses whatever `kAudioHardwarePropertyDefaultInputDevice` resolves to
    /// at engine init time).
    ///
    /// MUST be called BEFORE `installTap` and `engine.start()` — the input
    /// format gets cached at first tap install, and a late switch leaves the
    /// node's format stale, which then crashes inside `installTap` with the
    /// classic `_outputFormat.channelCount == buffer.format.channelCount`
    /// assert. We're safe here because both capture services build a fresh
    /// engine per session.
    ///
    /// Returns `true` if a non-default device was successfully bound. `false`
    /// indicates the saved UID could no longer be resolved (e.g. the user
    /// unplugged it). The engine falls back to the system default in that
    /// case, which is exactly what the user wants when their preferred mic
    /// is gone.
    /// `nonisolated` so callers can dispatch this off MainActor — the
    /// `engine.inputNode.audioUnit!` access below lazily initializes the
    /// AVAudioIOUnit, which synchronously waits on coreaudiod. If MainActor
    /// were to make that call, a wedged coreaudiod would freeze the UI
    /// indefinitely (see `DictationAudioCaptureService.buildAudioEngineSetup`
    /// for the recovery strategy). Pure CoreAudio writes are thread-safe.
    @discardableResult
    nonisolated static func bind(_ engine: AVAudioEngine, toUID uid: String?) -> Bool {
        guard let uid, !uid.isEmpty else { return false }
        guard let deviceID = deviceID(forUID: uid) else {
            Logger(subsystem: AppBrand.logSubsystem, category: "AudioInputDevices")
                .warning("Could not resolve mic UID \(uid, privacy: .public) — falling back to system default")
            return false
        }

        var id = deviceID
        let status = AudioUnitSetProperty(
            engine.inputNode.audioUnit!,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status != noErr {
            Logger(subsystem: AppBrand.logSubsystem, category: "AudioInputDevices")
                .error("AudioUnitSetProperty(CurrentDevice) failed: status=\(status) uid=\(uid, privacy: .public)")
            return false
        }
        return true
    }

    // MARK: - Hardware gain

    /// Whether the device with `uid` exposes a settable hardware input volume.
    /// True for most USB mics and audio interfaces. False for the built-in
    /// MacBook microphone (Apple silicon), most Bluetooth mics, and AirPods.
    ///
    /// When this returns false, callers should fall back to software gain
    /// (multiplying tap samples) instead.
    nonisolated static func canSetHardwareGain(forUID uid: String?) -> Bool {
        guard let uid, let deviceID = deviceID(forUID: uid) else { return false }
        return isVirtualMainVolumeSettable(deviceID: deviceID, scope: kAudioObjectPropertyScopeInput)
    }

    /// Current hardware input volume in `0...1`, or `nil` if the device
    /// doesn't support it.
    nonisolated static func hardwareGain(forUID uid: String?) -> Float? {
        guard let uid, let deviceID = deviceID(forUID: uid) else { return nil }
        return readVirtualMainVolume(deviceID: deviceID, scope: kAudioObjectPropertyScopeInput)
    }

    /// Sets the hardware input volume on the device, in `0...1`. Returns
    /// `true` if the write succeeded. A `false` return means either the
    /// device doesn't support settable gain, or the device disappeared.
    @discardableResult
    nonisolated static func setHardwareGain(_ value: Float, forUID uid: String?) -> Bool {
        guard let uid, let deviceID = deviceID(forUID: uid) else { return false }
        let clamped = max(0, min(1, value))
        return writeVirtualMainVolume(deviceID: deviceID, scope: kAudioObjectPropertyScopeInput, value: clamped)
    }

    /// Convenience for "the system default" — uses `nil` UID semantics. Picks
    /// up whatever device is the default RIGHT NOW. For applying gain to a
    /// session that's about to start in default mode.
    nonisolated static func canSetHardwareGainForSystemDefault() -> Bool {
        guard let id = defaultInputDeviceID() else { return false }
        return isVirtualMainVolumeSettable(deviceID: id, scope: kAudioObjectPropertyScopeInput)
    }

    // MARK: - CoreAudio HAL helpers

    /// `kAudioHardwareServiceDeviceProperty_VirtualMainVolume` is the right
    /// selector for both reading and writing the master input/output level on
    /// a device — Apple introduced it precisely so apps don't have to walk
    /// per-channel volumes and fake a master. Internally the HAL aggregates.
    nonisolated private static let virtualMainVolumeSelector: AudioObjectPropertySelector =
        kAudioHardwareServiceDeviceProperty_VirtualMainVolume

    nonisolated private static func isVirtualMainVolumeSettable(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: virtualMainVolumeSelector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return false }
        var settable = DarwinBoolean(false)
        let status = AudioObjectIsPropertySettable(deviceID, &address, &settable)
        return status == noErr && settable.boolValue
    }

    nonisolated private static func readVirtualMainVolume(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Float? {
        var address = AudioObjectPropertyAddress(
            mSelector: virtualMainVolumeSelector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    @discardableResult
    nonisolated private static func writeVirtualMainVolume(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope, value: Float) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: virtualMainVolumeSelector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return false }
        var v: Float32 = value
        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
        return status == noErr
    }

    /// Resolve `kAudioDevicePropertyDeviceUID` → `AudioDeviceID`. We persist
    /// UID (stable across reboots / replug) but every HAL call wants the ID,
    /// so this translation happens on every read/write.
    nonisolated static func deviceID(forUID uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfUID = uid as CFString
        var deviceID: AudioDeviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafeMutablePointer(to: &cfUID) { ptr -> OSStatus in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<CFString>.size),
                ptr,
                &size,
                &deviceID
            )
        }
        return (status == noErr && deviceID != kAudioObjectUnknown) ? deviceID : nil
    }

    /// Inverse of `deviceID(forUID:)` — used when we have an `AudioDeviceID`
    /// (e.g. the system default) and need to compare against a stored UID.
    nonisolated static func deviceUID(forID deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfStr: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &cfStr)
        guard status == noErr, let unmanaged = cfStr else { return nil }
        return unmanaged.takeRetainedValue() as String
    }

    nonisolated static func deviceName(forID deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfStr: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &cfStr)
        guard status == noErr, let unmanaged = cfStr else { return nil }
        return unmanaged.takeRetainedValue() as String
    }

    nonisolated static func transportType(forID deviceID: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        return status == noErr ? value : kAudioDeviceTransportTypeUnknown
    }

    nonisolated static func defaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        return (status == noErr && deviceID != kAudioObjectUnknown) ? deviceID : nil
    }

    // MARK: - Listeners

    /// `AVCaptureDevice.DiscoverySession.devices` is a snapshot — to react to
    /// plug/unplug we have to subscribe to the underlying CoreAudio HAL
    /// notifications. Two we care about:
    ///   - `kAudioHardwarePropertyDevices`: device list changed
    ///   - `kAudioHardwarePropertyDefaultInputDevice`: system default changed
    ///     (so the "Default — XYZ" label in the picker can update live)
    private func startListeningForDeviceChanges() {
        var devicesAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddr,
            DispatchQueue.main
        ) { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
        devicesListenerAddress = devicesAddr

        var defaultAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultAddr,
            DispatchQueue.main
        ) { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
        defaultListenerAddress = defaultAddr
    }

    // MARK: - Device-type list

    /// `AVCaptureDevice.DeviceType.external` was renamed from
    /// `.externalUnknown` in macOS 14 and consolidated several legacy types.
    /// We always include `.microphone`; on macOS 14+ we also include
    /// `.external` to catch USB/Thunderbolt audio interfaces that don't
    /// register as a "microphone" subtype.
    private func macosInputDeviceTypes() -> [AVCaptureDevice.DeviceType] {
        var types: [AVCaptureDevice.DeviceType] = [.microphone]
        if #available(macOS 14, *) {
            types.append(.external)
        }
        return types
    }
}
