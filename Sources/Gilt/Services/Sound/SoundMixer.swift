import AppKit
import AudioToolbox
import Combine
import CoreAudio
import Foundation
import OSLog

/// One app in the sound panel. Helper processes (Chrome's audio helper,
/// Safari's WebKit GPU process) are folded into the app the user sees.
struct SoundApp: Identifiable, Equatable {
    /// Bundle ID of the user-facing app. Saved volumes are keyed by it, so a
    /// level sticks when the app quits and comes back.
    let id: String
    let name: String
    let icon: NSImage
    var isActive: Bool
    var volume: Double
    var isMuted: Bool
}

/// Saved per-app level. Only apps the user moved away from 100% are stored.
struct SoundAppLevel: Codable, Equatable {
    var volume: Double = 1
    var isMuted = false

    /// Gain the tap applies. 1 means leave the app alone (no tap at all).
    var gain: Float { isMuted ? 0 : Float(volume) }
}

/// Drives the menu bar sound panel: the default output device's volume, plus
/// a volume for each app that has opened audio. Per-app volume works by
/// tapping the app's audio (see `AppVolumeTap`), which needs macOS 14.2.
///
/// A tap exists only while an app is producing output and isn't at 100%.
/// A running tap keeps the output device busy, which would stop the Mac from
/// idle sleeping, so paused apps go untapped until they play again.
@MainActor
final class SoundMixer: ObservableObject {
    @Published private(set) var activeApps: [SoundApp] = []
    @Published private(set) var quietApps: [SoundApp] = []
    /// nil when the output device has no software volume (some HDMI and USB
    /// devices); the panel then explains the volume is set on the device.
    @Published private(set) var masterVolume: Double?
    @Published private(set) var isMasterMuted = false
    @Published private(set) var outputDeviceName = ""
    @Published private(set) var needsAudioCapturePermission = false

    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "SoundMixer")
    private let defaults: UserDefaults
    private static let levelsKey = "JackSoundAppLevels"

    private(set) var levels: [String: SoundAppLevel]
    /// Process objects per app bundle ID, and which apps are producing
    /// output, from the latest refresh.
    private var processObjects: [String: Set<AudioObjectID>] = [:]
    private var producingOutput: Set<String> = []
    /// Live taps keyed by app bundle ID. Typed `AnyObject` because
    /// `AppVolumeTap` only exists on macOS 14.2+ and a stored property can't
    /// be availability-gated.
    private var taps: [String: AnyObject] = [:]
    /// Apps whose tap failed. Not retried until the user changes their level
    /// or the output device changes, so a failure can't loop.
    private var failedApps: Set<String> = []
    /// Set once any tap delivered real audio this run. Until then taps start
    /// as probes so a missing permission can't silence an app.
    private var audioCaptureWorks = false
    private var outputDevice = AudioObjectID(kAudioObjectUnknown)
    private var listeners: [PropertyListener] = []
    private var deviceListeners: [PropertyListener] = []
    private var processListeners: [AudioObjectID: PropertyListener] = [:]
    private var safetyTimer: Timer?
    private var refreshScheduled = false
    private var probeCheckScheduled = false
    private var pendingDeviceChange: DispatchWorkItem?
    private var isRunning = false
    private var settingsCancellable: AnyCancellable?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        levels = (defaults.data(forKey: Self.levelsKey))
            .flatMap { try? JSONDecoder().decode([String: SoundAppLevel].self, from: $0) } ?? [:]
    }

    var menuBarSymbol: String {
        guard let volume = masterVolume else { return "speaker.wave.2.fill" }
        if isMasterMuted || volume == 0 { return "speaker.slash.fill" }
        return volume < 0.34 ? "speaker.wave.1.fill" : volume < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
    }

    // MARK: - Lifecycle

    /// Runs only while the menu bar item is on, so turning it off hands every
    /// app back its normal volume.
    func bind(to store: ClipboardStore) {
        settingsCancellable = store.$settings
            .map(\.showSoundControlsInMenuBar)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                MainActor.assumeIsolated {
                    if enabled { self?.start() } else { self?.stop() }
                }
            }
    }

    func start() {
        guard !isRunning, #available(macOS 14.2, *) else { return }
        isRunning = true
        listeners = [
            listen(to: .system, kAudioHardwarePropertyDefaultOutputDevice) { $0.scheduleOutputDeviceChange() },
            listen(to: .system, kAudioHardwarePropertyProcessObjectList) { $0.scheduleRefresh() },
        ].compactMap { $0 }
        // Listeners can miss a quick quit-and-relaunch, so re-check now and then.
        safetyTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshApps() }
        }
        outputDeviceChanged()
    }

    /// Removes every tap, so each app plays at its normal volume again.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        (listeners + deviceListeners + Array(processListeners.values)).forEach { $0.remove() }
        listeners = []
        deviceListeners = []
        processListeners = [:]
        safetyTimer?.invalidate()
        safetyTimer = nil
        pendingDeviceChange?.cancel()
        Array(taps.keys).forEach(removeTap)
        // Forget the snapshot so the next start re-applies every saved level.
        processObjects = [:]
        producingOutput = []
        failedApps = []
        activeApps = []
        quietApps = []
    }

    // MARK: - Per-app volume

    func setVolume(_ volume: Double, for appID: String) {
        var level = levels[appID] ?? SoundAppLevel()
        // Snap near-full back to exactly 100% so the tap is removed and the
        // app plays untouched, instead of running a tap at 99%.
        level.volume = volume > 0.98 ? 1 : max(0, volume)
        save(level, for: appID)
    }

    func toggleMute(for appID: String) {
        var level = levels[appID] ?? SoundAppLevel()
        level.isMuted.toggle()
        save(level, for: appID)
    }

    private func save(_ level: SoundAppLevel, for appID: String) {
        levels[appID] = level == SoundAppLevel() ? nil : level
        if let data = try? JSONEncoder().encode(levels) {
            defaults.set(data, forKey: Self.levelsKey)
        }
        failedApps.remove(appID)
        applyTap(for: appID)
        publishApps()
    }

    // MARK: - Master volume

    func setMasterVolume(_ volume: Double) {
        var value = Float32(volume)
        outputDevice.write(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioDevicePropertyScopeOutput, &value)
        if isMasterMuted, volume > 0 { toggleMasterMute() }
        masterVolume = volume
    }

    func toggleMasterMute() {
        var value: UInt32 = isMasterMuted ? 0 : 1
        outputDevice.write(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput, &value)
        readMasterVolume()
    }

    private func readMasterVolume() {
        let volume: Float32? = outputDevice.read(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioDevicePropertyScopeOutput)
        masterVolume = volume.map(Double.init)
        let muted: UInt32? = outputDevice.read(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        isMasterMuted = (muted ?? 0) != 0
    }

    /// Connecting Bluetooth headphones fires several default-device changes
    /// in a row, so wait for them to settle before rebuilding taps.
    private func scheduleOutputDeviceChange() {
        pendingDeviceChange?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.outputDeviceChanged() }
        }
        pendingDeviceChange = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func outputDeviceChanged() {
        guard isRunning else { return }
        deviceListeners.forEach { $0.remove() }
        outputDevice = AudioObjectID.system.read(kAudioHardwarePropertyDefaultOutputDevice) ?? AudioObjectID(kAudioObjectUnknown)
        outputDeviceName = outputDevice.readString(kAudioObjectPropertyName) ?? ""
        let output = kAudioDevicePropertyScopeOutput
        deviceListeners = [
            listen(to: outputDevice, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: output) { $0.readMasterVolume() },
            listen(to: outputDevice, kAudioDevicePropertyMute, scope: output) { $0.readMasterVolume() },
            // A running aggregate can't follow a sample rate change.
            listen(to: outputDevice, kAudioDevicePropertyNominalSampleRate) { $0.rebuildTaps() },
        ].compactMap { $0 }
        readMasterVolume()
        // Taps play through an aggregate built on the old output, so rebuild
        // them on the new one or the app would keep playing there.
        rebuildTaps()
    }

    private func rebuildTaps() {
        let tapped = Array(taps.keys)
        tapped.forEach(removeTap)
        failedApps = []
        refreshApps()
    }

    // MARK: - App list

    /// Process and playback changes arrive in bursts; batch them.
    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            MainActor.assumeIsolated {
                self?.refreshScheduled = false
                self?.refreshApps()
            }
        }
    }

    private func refreshApps() {
        guard isRunning, #available(macOS 14.2, *) else { return }
        let myBundleID = Bundle.main.bundleIdentifier
        var objectsByApp: [String: Set<AudioObjectID>] = [:]
        var producing: Set<String> = []
        var liveObjects: Set<AudioObjectID> = []

        for object in AudioObjectID.system.readArray(kAudioHardwarePropertyProcessObjectList) {
            guard let pid: pid_t = object.read(kAudioProcessPropertyPID),
                  let bundleID = Self.owningApp(of: pid)?.bundleIdentifier,
                  // Jack's own taps make it "play", and tapping them would loop.
                  bundleID != myBundleID
            else { continue }
            objectsByApp[bundleID, default: []].insert(object)
            liveObjects.insert(object)
            if let running: UInt32 = object.read(kAudioProcessPropertyIsRunningOutput), running != 0 {
                producing.insert(bundleID)
            }
            if processListeners[object] == nil {
                processListeners[object] = listen(to: object, kAudioProcessPropertyIsRunningOutput) { $0.scheduleRefresh() }
            }
        }
        for (object, listener) in processListeners where !liveObjects.contains(object) {
            listener.remove()
            processListeners[object] = nil
        }

        // A new helper process or a relaunch means the tap no longer covers
        // all of the app's audio, so rebuild it.
        for (appID, objects) in processObjects where objectsByApp[appID] != objects {
            removeTap(for: appID)
        }
        processObjects = objectsByApp
        producingOutput = producing
        Set(taps.keys).union(objectsByApp.keys).forEach(applyTap)
        publishApps()
    }

    private func publishApps() {
        let apps = processObjects.keys.compactMap { bundleID -> SoundApp? in
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return nil }
            let level = levels[bundleID] ?? SoundAppLevel()
            return SoundApp(
                id: bundleID,
                name: app.localizedName ?? bundleID,
                icon: app.icon ?? NSWorkspace.shared.icon(for: .application),
                isActive: producingOutput.contains(bundleID),
                volume: level.volume,
                isMuted: level.isMuted
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        activeApps = apps.filter(\.isActive)
        quietApps = apps.filter { !$0.isActive }
    }

    /// Resolves the app a process plays audio for. Regular apps own their
    /// audio; helpers (Chrome's audio service, Safari's WebKit GPU process)
    /// are attributed to the app macOS holds responsible for them, falling
    /// back to the parent process.
    static func owningApp(of pid: pid_t) -> NSRunningApplication? {
        var current = pid
        for _ in 0..<4 {
            if let app = NSRunningApplication(processIdentifier: current), app.activationPolicy == .regular {
                return app
            }
            let responsible = responsiblePID?(current) ?? -1
            let next = responsible > 1 && responsible != current ? responsible : parentPID(of: current)
            guard next > 1, next != current else { return nil }
            current = next
        }
        return nil
    }

    /// `responsibility_get_pid_responsible_for_pid` is private but long
    /// lived (it's how Activity Monitor groups helpers). Looked up at runtime
    /// so a future macOS without it falls back to the parent-process walk.
    private static let responsiblePID: (@convention(c) (pid_t) -> pid_t)? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (pid_t) -> pid_t).self)
    }()

    private static func parentPID(of pid: pid_t) -> pid_t {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return 0 }
        return info.kp_eproc.e_ppid
    }

    // MARK: - Taps

    /// Creates, updates, or removes an app's tap to match its level and
    /// whether it's playing. Safe to call any time.
    private func applyTap(for appID: String) {
        guard #available(macOS 14.2, *) else { return }
        let gain = (levels[appID] ?? SoundAppLevel()).gain
        guard isRunning, gain != 1, producingOutput.contains(appID), !failedApps.contains(appID),
              let objects = processObjects[appID], !objects.isEmpty,
              outputDevice != kAudioObjectUnknown
        else {
            removeTap(for: appID)
            return
        }
        if let tap = taps[appID] as? AppVolumeTap {
            tap.gain = gain
            return
        }
        let probe = !audioCaptureWorks
        taps[appID] = AppVolumeTap(
            processObjects: Array(objects),
            outputDevice: outputDevice,
            gain: gain,
            probe: probe
        ) { [weak self] tap, failure in
            Task { @MainActor in self?.tapFailed(tap, for: appID, failure) }
        }
        if probe { scheduleProbeCheck() }
    }

    private func removeTap(for appID: String) {
        guard #available(macOS 14.2, *) else { return }
        (taps.removeValue(forKey: appID) as? AppVolumeTap)?.invalidate()
    }

    @available(macOS 14.2, *)
    private func tapFailed(_ tap: AppVolumeTap, for appID: String, _ failure: AppVolumeTap.Failure) {
        guard taps[appID] === tap else { return }
        taps[appID] = nil
        failedApps.insert(appID)
        logger.error("Couldn't change the volume of \(appID, privacy: .public): \(String(describing: failure), privacy: .public)")
        if failure == .permissionDenied { needsAudioCapturePermission = true }
    }

    /// Watches probe taps. The first real sample proves capture works, so
    /// probes are swapped for taps that actually set the volume. A probe
    /// that hears only silence for a while most likely lacks permission
    /// (or the app is playing silence), so the panel shows a hint.
    private func scheduleProbeCheck() {
        guard !probeCheckScheduled else { return }
        probeCheckScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            MainActor.assumeIsolated {
                self?.probeCheckScheduled = false
                self?.checkProbes()
            }
        }
    }

    private func checkProbes() {
        guard #available(macOS 14.2, *) else { return }
        let probes = taps.compactMapValues { $0 as? AppVolumeTap }.filter { $0.value.isProbe }
        guard !probes.isEmpty else { return }
        if probes.values.contains(where: \.hasHeardAudio) {
            audioCaptureWorks = true
            needsAudioCapturePermission = false
            for appID in probes.keys {
                removeTap(for: appID)
                applyTap(for: appID)
            }
            return
        }
        if probes.values.contains(where: { $0.createdAt.timeIntervalSinceNow < -5 }) {
            needsAudioCapturePermission = true
        }
        scheduleProbeCheck()
    }

    // MARK: - Listener plumbing

    private func listen(
        to object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        _ handler: @escaping @MainActor (SoundMixer) -> Void
    ) -> PropertyListener? {
        PropertyListener(object: object, selector: selector, scope: scope) { [weak self] in
            if let self, self.isRunning { handler(self) }
        }
    }
}

/// A Core Audio property listener on the main queue. Removal needs the exact
/// block that was added, so this keeps it.
private struct PropertyListener {
    let object: AudioObjectID
    let address: AudioObjectPropertyAddress
    let block: AudioObjectPropertyListenerBlock

    @MainActor
    init?(object: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope, handler: @escaping @MainActor () -> Void) {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        // Registered on the main queue, so this already runs on the main actor.
        let block: AudioObjectPropertyListenerBlock = { _, _ in MainActor.assumeIsolated(handler) }
        guard AudioObjectAddPropertyListenerBlock(object, &address, .main, block) == noErr else { return nil }
        self.object = object
        self.address = address
        self.block = block
    }

    /// Fails harmlessly when the object (a quit app's process) is already gone.
    func remove() {
        var address = address
        AudioObjectRemovePropertyListenerBlock(object, &address, .main, block)
    }
}

// MARK: - Core Audio property access

extension AudioObjectID {
    static let system = AudioObjectID(kAudioObjectSystemObject)

    func read<T>(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> T? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(self, &address) else { return nil }
        var size = UInt32(MemoryLayout<T>.size)
        let value = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<T>.alignment)
        defer { value.deallocate() }
        guard AudioObjectGetPropertyData(self, &address, 0, nil, &size, value) == noErr else { return nil }
        return value.load(as: T.self)
    }

    func readArray(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(self, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(self, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    /// String properties come back +1 retained, so take ownership.
    func readString(_ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(self, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    @discardableResult
    func write<T>(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope, _ value: inout T) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        return AudioObjectSetPropertyData(self, &address, 0, nil, UInt32(MemoryLayout<T>.size), &value) == noErr
    }
}
