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
    var isUsingMic: Bool
    var effect: SoundAppEffect
    /// The speaker this app is sent to, or nil when it follows the system.
    var outputDeviceUID: String?
}

/// Saved per-app settings. Only apps the user changed are stored.
struct SoundAppLevel: Codable, Equatable {
    var volume: Double = 1
    var isMuted = false
    /// Play this app on a specific output instead of the system's.
    var outputDeviceUID: String?

    /// The app's own gain before solo, call mode, or dictation.
    var gain: Float { isMuted ? 0 : Float(volume) }
}

struct SoundScene: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var levels: [String: SoundAppLevel]
}

struct AudioOutputDevice: Identifiable, Equatable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let transport: UInt32

    var symbolName: String {
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: return "laptopcomputer"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "headphones"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return "display"
        case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
        case kAudioDeviceTransportTypeVirtual: return "waveform"
        default: return "hifispeaker"
        }
    }
}

/// Live levels for the meters, kept apart from `SoundMixer` so 24 updates a
/// second redraw only the meters, not the whole panel.
@MainActor
final class SoundMeters: ObservableObject {
    @Published private(set) var levels: [String: Float] = [:]
    /// Everything the Mac plays except Jack, for Jack's dance.
    @Published private(set) var systemLevel: Float = 0

    /// Peaks rise at once and fall gently, like a VU meter, so the bars
    /// don't flicker between buffers.
    func update(appPeaks: [String: Float], systemPeak: Float?) {
        var next: [String: Float] = [:]
        for (appID, peak) in appPeaks {
            next[appID] = Self.smooth(previous: levels[appID] ?? 0, peak: peak)
        }
        if next != levels { levels = next }
        let system = systemPeak.map { Self.smooth(previous: systemLevel, peak: $0) } ?? 0
        if abs(system - systemLevel) > 0.001 { systemLevel = system }
    }

    nonisolated static func smooth(previous: Float, peak: Float) -> Float {
        // Perceived loudness is closer to the square root of amplitude.
        let target = min(1, sqrt(peak))
        let next = target > previous ? target : previous * 0.82
        return next < 0.01 ? 0 : next
    }
}

/// Drives the menu bar sound panel: the default output device's volume, plus
/// a volume, mute, and output for each app that has opened audio. Per-app
/// control works by tapping the app's audio (see `AppVolumeTap`), which needs
/// macOS 14.2.
///
/// A tap exists only while an app is producing output and needs one: it isn't
/// at 100%, is routed to another speaker, is ducked or soloed, or the panel is
/// open and wants its meter. A running tap keeps the output device busy, which
/// would stop the Mac from idle sleeping, so paused apps go untapped.
@MainActor
final class SoundMixer: ObservableObject {
    @Published private(set) var activeApps: [SoundApp] = []
    @Published private(set) var quietApps: [SoundApp] = []
    /// nil when the output device has no software volume (some HDMI and USB
    /// devices); the panel then explains the volume is set on the device.
    @Published private(set) var masterVolume: Double?
    @Published private(set) var isMasterMuted = false
    @Published private(set) var outputDeviceName = ""
    @Published private(set) var outputDeviceUID = ""
    @Published private(set) var outputDevices: [AudioOutputDevice] = []
    @Published private(set) var needsAudioCapturePermission = false
    @Published private(set) var scenes: [SoundScene] = []
    @Published private(set) var rules = SoundMixRules()
    @Published private(set) var showsCrackleFix = false
    @Published private(set) var isRestartingAudio = false

    let meters = SoundMeters()

    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "SoundMixer")
    private let defaults: UserDefaults
    private static let levelsKey = "JackSoundAppLevels"
    private static let scenesKey = "JackSoundScenes"

    private(set) var levels: [String: SoundAppLevel]
    /// Process objects per app bundle ID, which apps are producing output,
    /// and which have the mic open, from the latest refresh.
    private var processObjects: [String: Set<AudioObjectID>] = [:]
    private var producingOutput: Set<String> = []
    private var jackObjects: [AudioObjectID] = []
    /// Live taps keyed by app bundle ID, with the plan each was built for.
    /// Typed `AnyObject` because `AppVolumeTap` only exists on macOS 14.2+
    /// and a stored property can't be availability-gated.
    private var taps: [String: AnyObject] = [:]
    private var tapPlans: [String: TapPlan] = [:]
    private var systemTap: AnyObject?
    /// Apps whose tap failed. Not retried until the user changes their level
    /// or the output device changes, so a failure can't loop.
    private var failedApps: Set<String> = []
    /// True once capture is known to work (TCC says so, or a tap delivered
    /// real audio). Until then taps start listen-only so a missing
    /// permission can't silence an app.
    private var audioCaptureWorks = false
    private var outputDevice = AudioObjectID(kAudioObjectUnknown)
    private var listeners: [PropertyListener] = []
    private var deviceListeners: [PropertyListener] = []
    private var processListeners: [AudioObjectID: [PropertyListener]] = [:]
    private var appInfo: [String: (name: String, icon: NSImage)] = [:]
    private var owners: [pid_t: String] = [:]
    private var safetyTimer: Timer?
    private var meterTimer: Timer?
    private var refreshScheduled = false
    private var probeCheckScheduled = false
    private var pendingDeviceChange: DispatchWorkItem?
    private var isRunning = false
    private var panelVisible = false
    private var callModeLevel: Float?
    private var cancellables: Set<AnyCancellable> = []

    /// Jack's character asks for this while it's on screen so it can dance.
    var wantsSystemLevel = false {
        didSet { if wantsSystemLevel != oldValue { updateSystemTap(); updateMeterTimer() } }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        levels = defaults.data(forKey: Self.levelsKey)
            .flatMap { try? JSONDecoder().decode([String: SoundAppLevel].self, from: $0) } ?? [:]
        scenes = defaults.data(forKey: Self.scenesKey)
            .flatMap { try? JSONDecoder().decode([SoundScene].self, from: $0) } ?? []
    }

    var menuBarSymbol: String {
        guard let volume = masterVolume else { return "speaker.wave.2.fill" }
        if isMasterMuted || volume == 0 { return "speaker.slash.fill" }
        return volume < 0.34 ? "speaker.wave.1.fill" : volume < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
    }

    var isCallModeOn: Bool { callModeLevel != nil }

    // MARK: - Lifecycle

    /// Runs only while the menu bar item is on, so turning it off hands every
    /// app back its normal volume.
    func bind(to store: ClipboardStore) {
        store.$settings
            .map(\.showSoundControlsInMenuBar)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                MainActor.assumeIsolated { if enabled { self?.start() } else { self?.stop() } }
            }
            .store(in: &cancellables)
        store.$settings
            .map { ($0.soundCallModeEnabled ? Float($0.soundCallModeLevel) : nil, $0.soundShowCrackleFix) }
            .removeDuplicates { $0 == $1 }
            .receive(on: RunLoop.main)
            .sink { [weak self] callLevel, crackleFix in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.showsCrackleFix = crackleFix
                    self.callModeLevel = callLevel
                    self.updateRules(ramp: 0.4)
                }
            }
            .store(in: &cancellables)
    }

    func start() {
        guard !isRunning, #available(macOS 14.2, *) else { return }
        isRunning = true
        checkPermission()
        listeners = [
            listen(to: .system, kAudioHardwarePropertyDefaultOutputDevice) { $0.scheduleOutputDeviceChange() },
            listen(to: .system, kAudioHardwarePropertyDevices) { $0.devicesChanged() },
            listen(to: .system, kAudioHardwarePropertyProcessObjectList) { $0.scheduleRefresh() },
        ].compactMap { $0 }
        // Listeners can miss a quick quit-and-relaunch, so re-check now and then.
        safetyTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshApps() }
        }
        refreshDevices()
        outputDeviceChanged()
    }

    /// Removes every tap, so each app plays at its normal volume again.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        (listeners + deviceListeners + processListeners.values.flatMap { $0 }).forEach { $0.remove() }
        listeners = []
        deviceListeners = []
        processListeners = [:]
        safetyTimer?.invalidate()
        safetyTimer = nil
        pendingDeviceChange?.cancel()
        Array(taps.keys).forEach(removeTap)
        removeSystemTap()
        updateMeterTimer()
        // Forget the snapshot so the next start re-applies every saved level.
        processObjects = [:]
        producingOutput = []
        owners = [:]
        failedApps = []
        rules.soloAppID = nil
        rules.micApps = [:]
        activeApps = []
        quietApps = []
    }

    /// The panel shows live meters, so active apps get listen-only taps
    /// while it's open.
    func setPanelVisible(_ visible: Bool) {
        panelVisible = visible
        guard isRunning else { return }
        if visible { checkPermission() }
        reapplyAllTaps(ramp: 0.03)
        updateMeterTimer()
    }

    private func checkPermission() {
        switch AudioCapturePermission.status() {
        case .authorized:
            audioCaptureWorks = true
            needsAudioCapturePermission = false
        case .denied:
            needsAudioCapturePermission = true
        case .unknown:
            break
        }
    }

    // MARK: - Per-app controls

    func setVolume(_ volume: Double, for appID: String) {
        var level = levels[appID] ?? SoundAppLevel()
        // Snap near-full back to exactly 100% so an untouched app needs no tap.
        level.volume = volume > 0.98 ? 1 : max(0, volume)
        save(level, for: appID)
    }

    func toggleMute(for appID: String) {
        var level = levels[appID] ?? SoundAppLevel()
        level.isMuted.toggle()
        save(level, for: appID)
    }

    func setMuted(_ muted: Bool, for appID: String) {
        var level = levels[appID] ?? SoundAppLevel()
        guard level.isMuted != muted else { return }
        level.isMuted = muted
        save(level, for: appID)
    }

    /// nil sends the app back to the system output.
    func setOutput(_ deviceUID: String?, for appID: String) {
        var level = levels[appID] ?? SoundAppLevel()
        level.outputDeviceUID = deviceUID == outputDeviceUID ? nil : deviceUID
        save(level, for: appID)
    }

    func resetApp(_ appID: String) {
        save(SoundAppLevel(), for: appID)
    }

    /// Hear only this app. Again on the same app ends the solo.
    func toggleSolo(_ appID: String) {
        rules.soloAppID = rules.soloAppID == appID ? nil : appID
        reapplyAllTaps(ramp: 0.15)
        publishApps()
    }

    private func save(_ level: SoundAppLevel, for appID: String) {
        levels[appID] = level == SoundAppLevel() ? nil : level
        persistLevels()
        failedApps.remove(appID)
        applyTap(for: appID, ramp: 0.03)
        publishApps()
    }

    private func persistLevels() {
        if let data = try? JSONEncoder().encode(levels) {
            defaults.set(data, forKey: Self.levelsKey)
        }
    }

    // MARK: - Scenes

    func saveScene(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let index = scenes.firstIndex(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            scenes[index].levels = levels
        } else {
            scenes.append(SoundScene(id: UUID(), name: trimmed, levels: levels))
        }
        persistScenes()
    }

    func applyScene(_ id: SoundScene.ID) {
        guard let scene = scenes.first(where: { $0.id == id }) else { return }
        levels = scene.levels
        persistLevels()
        rules.soloAppID = nil
        failedApps = []
        reapplyAllTaps(ramp: 0.3)
        publishApps()
    }

    func deleteScene(_ id: SoundScene.ID) {
        scenes.removeAll { $0.id == id }
        persistScenes()
    }

    /// The scene whose levels match what's set right now, if any.
    var currentSceneID: SoundScene.ID? {
        scenes.first { $0.levels == levels }?.id
    }

    private func persistScenes() {
        if let data = try? JSONEncoder().encode(scenes) {
            defaults.set(data, forKey: Self.scenesKey)
        }
    }

    // MARK: - Dictation

    /// Lowers every app while Jack dictates. Returns false when per-app
    /// control isn't available yet, so the caller can lower the whole Mac.
    func beginDictationDucking(amount: Double) -> Bool {
        guard isRunning, audioCaptureWorks else { return false }
        rules.dictationLevel = Float(max(0, min(1, 1 - amount)))
        reapplyAllTaps(ramp: 0.25)
        publishApps()
        return true
    }

    func endDictationDucking() {
        guard rules.dictationLevel != nil else { return }
        rules.dictationLevel = nil
        reapplyAllTaps(ramp: 0.5)
        publishApps()
    }

    private func updateRules(ramp: Float) {
        rules.callModeLevel = callModeLevel
        reapplyAllTaps(ramp: ramp)
        publishApps()
    }

    // MARK: - Master volume and outputs

    func setMasterVolume(_ volume: Double) {
        var value = Float32(volume)
        outputDevice.write(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioDevicePropertyScopeOutput, &value)
        if isMasterMuted, volume > 0 { toggleMasterMute() }
        masterVolume = volume
    }

    func nudgeMasterVolume(by delta: Double) {
        guard let volume = masterVolume else { return }
        setMasterVolume(max(0, min(1, volume + delta)))
    }

    func toggleMasterMute() {
        var value: UInt32 = isMasterMuted ? 0 : 1
        outputDevice.write(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput, &value)
        readMasterVolume()
    }

    func setSystemOutput(_ deviceUID: String) {
        guard var device = outputDevices.first(where: { $0.uid == deviceUID })?.id else { return }
        AudioObjectID.system.write(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal, &device)
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
        outputDeviceUID = outputDevice.readString(kAudioDevicePropertyDeviceUID) ?? ""
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

    private func devicesChanged() {
        refreshDevices()
        // A routed speaker may have just connected or gone away.
        rebuildTaps()
    }

    private func refreshDevices() {
        let devices = AudioObjectID.system.readArray(kAudioHardwarePropertyDevices).compactMap { id -> AudioOutputDevice? in
            let transport: UInt32 = id.read(kAudioDevicePropertyTransportType) ?? 0
            let hidden: UInt32 = id.read(kAudioDevicePropertyIsHidden) ?? 0
            // Aggregates can't be nested inside Jack's own aggregate, and
            // Jack's private ones would show up here too.
            guard transport != kAudioDeviceTransportTypeAggregate, hidden == 0,
                  !id.readArray(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput).isEmpty,
                  let uid = id.readString(kAudioDevicePropertyDeviceUID),
                  let name = id.readString(kAudioObjectPropertyName)
            else { return nil }
            return AudioOutputDevice(id: id, uid: uid, name: name, transport: transport)
        }
        if devices != outputDevices { outputDevices = devices }
    }

    private func rebuildTaps() {
        Array(taps.keys).forEach(removeTap)
        removeSystemTap()
        failedApps = []
        refreshApps()
        updateSystemTap()
    }

    // MARK: - Crackle fix

    /// Restarts macOS's audio service (`coreaudiod`), which clears the
    /// system-wide crackle the Simulator can cause. macOS asks for an
    /// administrator password; Jack can't avoid that. Every tap dies with the
    /// service, so the mixer restarts once audio is back.
    func restartAudioSystem() {
        guard !isRestartingAudio else { return }
        isRestartingAudio = true
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "do shell script \"/usr/bin/killall coreaudiod\" with administrator privileges"]
        process.terminationHandler = { [weak self] finished in
            let succeeded = finished.terminationStatus == 0
            Task { @MainActor in
                guard let self else { return }
                if succeeded {
                    let wasRunning = self.isRunning
                    self.stop()
                    try? await Task.sleep(for: .seconds(2.5))
                    if wasRunning { self.start() }
                }
                self.isRestartingAudio = false
            }
        }
        do {
            try process.run()
        } catch {
            logger.error("Couldn't run the audio restart: \(error.localizedDescription, privacy: .public)")
            isRestartingAudio = false
        }
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
        let snapshot = Self.readProcesses(owners: &owners)
        var liveObjects: Set<AudioObjectID> = []
        for process in snapshot.processes {
            liveObjects.insert(process.object)
            if processListeners[process.object] == nil {
                processListeners[process.object] = [
                    listen(to: process.object, kAudioProcessPropertyIsRunningOutput) { $0.scheduleRefresh() },
                    listen(to: process.object, kAudioProcessPropertyIsRunningInput) { $0.scheduleRefresh() },
                ].compactMap { $0 }
            }
        }
        for (object, objectListeners) in processListeners where !liveObjects.contains(object) {
            objectListeners.forEach { $0.remove() }
            processListeners[object] = nil
        }

        var objectsByApp: [String: Set<AudioObjectID>] = [:]
        var producing: Set<String> = []
        var micApps: [String: String] = [:]
        for process in snapshot.processes {
            objectsByApp[process.appID, default: []].insert(process.object)
            if process.isOutputting { producing.insert(process.appID) }
            if process.isInputting { micApps[process.appID] = info(for: process.appID)?.name ?? process.appID }
        }
        jackObjects = snapshot.jackObjects

        // A new helper process or a relaunch means the tap no longer covers
        // all of the app's audio, so rebuild it.
        for (appID, objects) in processObjects where objectsByApp[appID] != objects {
            removeTap(for: appID)
        }
        processObjects = objectsByApp
        producingOutput = producing
        owners = owners.filter { snapshot.livePIDs.contains($0.key) }
        if let solo = rules.soloAppID, objectsByApp[solo] == nil { rules.soloAppID = nil }
        let micChanged = micApps != rules.micApps
        if micChanged { rules.micApps = micApps }
        // Call mode fades in and out; everything else follows at once.
        reapplyAllTaps(ramp: micChanged ? 0.5 : 0.03)
        updateSystemTap()
        publishApps()
    }

    private struct ProcessSnapshot {
        struct Process {
            let object: AudioObjectID
            let appID: String
            let isOutputting: Bool
            let isInputting: Bool
        }
        var processes: [Process] = []
        var jackObjects: [AudioObjectID] = []
        var livePIDs: Set<pid_t> = []
    }

    /// Reads Core Audio's process list. Owners are cached per PID because
    /// resolving a helper's app is the expensive part.
    private static func readProcesses(owners: inout [pid_t: String]) -> ProcessSnapshot {
        let myPID = ProcessInfo.processInfo.processIdentifier
        let myBundleID = Bundle.main.bundleIdentifier
        var snapshot = ProcessSnapshot()
        for object in AudioObjectID.system.readArray(kAudioHardwarePropertyProcessObjectList) {
            guard let pid: pid_t = object.read(kAudioProcessPropertyPID) else { continue }
            snapshot.livePIDs.insert(pid)
            let appID: String
            if let cached = owners[pid] {
                appID = cached
            } else {
                appID = owningApp(of: pid)?.bundleIdentifier ?? ""
                owners[pid] = appID
            }
            // Jack's own taps make it "play" and its dictation uses the mic;
            // tapping or ducking around Jack would loop.
            if pid == myPID || appID == myBundleID {
                snapshot.jackObjects.append(object)
                continue
            }
            guard !appID.isEmpty else { continue }
            let output: UInt32 = object.read(kAudioProcessPropertyIsRunningOutput) ?? 0
            let input: UInt32 = object.read(kAudioProcessPropertyIsRunningInput) ?? 0
            snapshot.processes.append(.init(object: object, appID: appID, isOutputting: output != 0, isInputting: input != 0))
        }
        return snapshot
    }

    /// Apps (other than Jack) with the microphone open right now, for
    /// meeting notes to record only the call. Works whether or not the
    /// mixer is running.
    static func appsUsingMicrophone() -> Set<String> {
        guard #available(macOS 14.2, *) else { return [] }
        var owners: [pid_t: String] = [:]
        return Set(readProcesses(owners: &owners).processes.filter(\.isInputting).map(\.appID))
    }

    private func info(for appID: String) -> (name: String, icon: NSImage)? {
        if let cached = appInfo[appID] { return cached }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: appID).first else { return nil }
        let info = (name: app.localizedName ?? appID, icon: app.icon ?? NSWorkspace.shared.icon(for: .application))
        appInfo[appID] = info
        return info
    }

    private func publishApps() {
        let apps = processObjects.keys.compactMap { appID -> SoundApp? in
            guard let info = info(for: appID) else { return nil }
            let level = levels[appID] ?? SoundAppLevel()
            return SoundApp(
                id: appID,
                name: info.name,
                icon: info.icon,
                isActive: producingOutput.contains(appID),
                volume: level.volume,
                isMuted: level.isMuted,
                isUsingMic: rules.micApps[appID] != nil,
                effect: producingOutput.contains(appID) ? rules.effect(for: appID) : .none,
                outputDeviceUID: level.outputDeviceUID
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let active = apps.filter(\.isActive)
        let quiet = apps.filter { !$0.isActive }
        if active != activeApps { activeApps = active }
        if quiet != quietApps { quietApps = quiet }
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

    /// What a tap should look like for an app right now. A rebuild happens
    /// only when this changes; gain changes just ramp the existing tap.
    private struct TapPlan: Equatable {
        var objects: Set<AudioObjectID>
        var device: AudioObjectID
        var listenOnly: Bool
        /// Listen-only because capture isn't proven yet, though the user
        /// wants the volume changed. Silence here hints at a missing permission.
        var wantsControl: Bool
    }

    private func plan(for appID: String) -> TapPlan? {
        guard isRunning, producingOutput.contains(appID), !failedApps.contains(appID),
              let objects = processObjects[appID], !objects.isEmpty,
              outputDevice != kAudioObjectUnknown
        else { return nil }
        let level = levels[appID] ?? SoundAppLevel()
        let device = level.outputDeviceUID.flatMap { uid in outputDevices.first { $0.uid == uid }?.id } ?? outputDevice
        let wantsControl = rules.gain(for: appID, level: level) != 1 || device != outputDevice
        guard wantsControl || panelVisible else { return nil }
        let listenOnly = !wantsControl || !audioCaptureWorks
        return TapPlan(objects: objects, device: device, listenOnly: listenOnly, wantsControl: wantsControl && listenOnly)
    }

    private func reapplyAllTaps(ramp: Float) {
        Set(taps.keys).union(processObjects.keys).forEach { applyTap(for: $0, ramp: ramp) }
    }

    /// Creates, updates, or removes an app's tap to match its plan. Safe to
    /// call any time.
    private func applyTap(for appID: String, ramp: Float) {
        guard #available(macOS 14.2, *) else { return }
        guard let plan = plan(for: appID) else {
            removeTap(for: appID)
            return
        }
        let gain = rules.gain(for: appID, level: levels[appID] ?? SoundAppLevel())
        let existing = taps[appID] as? AppVolumeTap
        if let existing, tapPlans[appID] == plan {
            existing.setGain(gain, rampSeconds: ramp)
            return
        }
        // Start a replacement where the old tap left the app, so a rebuild
        // doesn't blip back to full volume.
        let startGain = existing.map { $0.isListenOnly ? 1 : $0.gain } ?? 1
        removeTap(for: appID)
        let tap = AppVolumeTap(
            source: .processes(Array(plan.objects)),
            outputDevice: plan.device,
            gain: gain,
            startGain: startGain,
            listenOnly: plan.listenOnly
        ) { [weak self] tap, failure in
            Task { @MainActor in self?.tapFailed(tap, for: appID, failure) }
        }
        tap.setGain(gain, rampSeconds: ramp)
        taps[appID] = tap
        tapPlans[appID] = plan
        if plan.listenOnly, !audioCaptureWorks { scheduleProbeCheck() }
    }

    private func removeTap(for appID: String) {
        guard #available(macOS 14.2, *) else { return }
        (taps.removeValue(forKey: appID) as? AppVolumeTap)?.invalidate()
        tapPlans[appID] = nil
    }

    @available(macOS 14.2, *)
    private func tapFailed(_ tap: AppVolumeTap, for appID: String, _ failure: AppVolumeTap.Failure) {
        guard taps[appID] === tap else { return }
        taps[appID] = nil
        tapPlans[appID] = nil
        failedApps.insert(appID)
        logger.error("Couldn't control the audio of \(appID, privacy: .public): \(String(describing: failure), privacy: .public)")
        if failure == .permissionDenied { needsAudioCapturePermission = true }
    }

    /// Watches listen-only taps while capture is unproven. The first real
    /// sample proves it works, so taps that should change the volume are
    /// rebuilt to do so. One that hears only silence for a while most likely
    /// lacks permission (or the app is playing silence), so the panel shows a hint.
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
        guard #available(macOS 14.2, *), !audioCaptureWorks else { return }
        let probes = taps.compactMapValues { $0 as? AppVolumeTap }.filter(\.value.isListenOnly)
        guard !probes.isEmpty else { return }
        if probes.values.contains(where: \.hasHeardAudio) {
            audioCaptureWorks = true
            needsAudioCapturePermission = false
            reapplyAllTaps(ramp: 0.03)
            updateSystemTap()
            return
        }
        let stuck = probes.contains { appID, tap in
            tapPlans[appID]?.wantsControl == true && tap.createdAt.timeIntervalSinceNow < -5
        }
        if stuck { needsAudioCapturePermission = true }
        scheduleProbeCheck()
    }

    // MARK: - Meters and the system level

    private func updateMeterTimer() {
        let wanted = isRunning && (panelVisible || wantsSystemLevel)
        guard wanted != (meterTimer != nil) else { return }
        if wanted {
            meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 24, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateMeters() }
            }
        } else {
            meterTimer?.invalidate()
            meterTimer = nil
            meters.update(appPeaks: [:], systemPeak: nil)
        }
    }

    private func updateMeters() {
        guard #available(macOS 14.2, *) else { return }
        var peaks: [String: Float] = [:]
        if panelVisible {
            for (appID, tap) in taps {
                if let tap = tap as? AppVolumeTap { peaks[appID] = tap.takePeak() }
            }
        }
        meters.update(appPeaks: peaks, systemPeak: (systemTap as? AppVolumeTap)?.takePeak())
    }

    /// One listen-only tap on everything except Jack, only while Jack's
    /// character wants it, capture is allowed (so it never triggers the
    /// permission prompt on its own), and something is playing.
    private func updateSystemTap() {
        guard #available(macOS 14.2, *) else { return }
        let wanted = isRunning && wantsSystemLevel && audioCaptureWorks && !producingOutput.isEmpty
            && outputDevice != kAudioObjectUnknown
        if !wanted {
            removeSystemTap()
        } else if systemTap == nil {
            systemTap = AppVolumeTap(
                source: .everythingExcept(jackObjects),
                outputDevice: outputDevice,
                gain: 1,
                listenOnly: true
            ) { [weak self] tap, _ in
                Task { @MainActor in
                    if self?.systemTap === tap { self?.systemTap = nil }
                }
            }
        }
        updateMeterTimer()
    }

    private func removeSystemTap() {
        guard #available(macOS 14.2, *) else { return }
        (systemTap as? AppVolumeTap)?.invalidate()
        systemTap = nil
    }

    #if DEBUG
    /// Fills the panel with sample state for snapshot tests.
    func loadPreview(
        active: [SoundApp],
        quiet: [SoundApp],
        devices: [AudioOutputDevice],
        output: AudioOutputDevice,
        volume: Double,
        scenes: [SoundScene],
        rules: SoundMixRules
    ) {
        activeApps = active
        quietApps = quiet
        outputDevices = devices
        outputDeviceUID = output.uid
        outputDeviceName = output.name
        masterVolume = volume
        self.scenes = scenes
        self.rules = rules
    }
    #endif

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
