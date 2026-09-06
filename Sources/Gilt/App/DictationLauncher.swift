import Foundation
import OSLog

/// Owns the long-lived dictation infrastructure: the hotkey monitor and the
/// glue that re-installs the monitor when the user changes their shortcut.
/// Also binds the coordinator to the overlay window manager so the floating
/// pill shows up automatically when a session starts.
@MainActor
final class DictationLauncher {
    static let shared = DictationLauncher()

    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "DictationLauncher")
    /// Primary hotkey: fires polish-mode dictation.
    private let monitor = DictationHotkeyMonitor()
    /// Optional secondary hotkey: fires ask-the-screen dictation. Installed
    /// only when the user has bound a shortcut in Settings — otherwise no
    /// second CGEventTap is created at all.
    private let askMonitor = DictationHotkeyMonitor()
    /// Optional third hotkey: fires voice-actions dictation.
    private let actionsMonitor = DictationHotkeyMonitor()
    private weak var coordinator: DictationCoordinator?
    private weak var store: DictationStore?
    private var settingsObservation: Task<Void, Never>?

    private init() {}

    func bootstrap(store: DictationStore, coordinator: DictationCoordinator) {
        self.store = store
        self.coordinator = coordinator

        // Primary hotkey → coordinator in polish mode. Push-to-talk uses
        // press+release; toggle and modifier-double-tap fire through
        // `onToggle`.
        monitor.onPress = { [weak coordinator] in
            coordinator?.startSession(mode: .polish)
        }
        monitor.onRelease = { [weak coordinator] in
            coordinator?.stopSession()
        }
        monitor.onToggle = { [weak coordinator] in
            coordinator?.handleToggle()
        }

        // Optional ask-the-screen hotkey. Same flavors of trigger — the
        // coordinator handles `handleToggle()` internally by checking
        // `isActive`. We pass `.askScreen` so the mode is set before the
        // session starts; stopSession doesn't need a mode argument because
        // it's just "stop whatever's running".
        askMonitor.onPress = { [weak coordinator] in
            coordinator?.startSession(mode: .askScreen)
        }
        askMonitor.onRelease = { [weak coordinator] in
            coordinator?.stopSession()
        }
        askMonitor.onToggle = { [weak coordinator] in
            // For ask mode, treat toggle as "start if idle in ask mode,
            // stop otherwise". We can't reuse handleToggle() because that
            // would start in polish mode on the idle path.
            guard let coordinator else { return }
            if coordinator.isActive {
                coordinator.stopSession()
            } else {
                coordinator.startSession(mode: .askScreen)
            }
        }

        actionsMonitor.onPress = { [weak coordinator] in
            coordinator?.startSession(mode: .actions)
        }
        actionsMonitor.onRelease = { [weak coordinator] in
            coordinator?.stopSession()
        }
        actionsMonitor.onToggle = { [weak coordinator] in
            guard let coordinator else { return }
            if coordinator.isActive {
                coordinator.stopSession()
            } else {
                coordinator.startSession(mode: .actions)
            }
        }

        // Phase + theme → overlay window. The store binding lets the overlay
        // re-skin live when the user picks a different pill color in Settings.
        DictationOverlayWindowManager.shared.bind(coordinator: coordinator, store: store)

        applyCurrentSettings()
        observeSettingsChanges()
    }

    private func applyCurrentSettings() {
        guard let store else { return }
        let settings = store.settings

        if settings.isEnabled {
            let ok = monitor.install(shortcut: settings.shortcut)
            if !ok {
                logger.warning("Failed to install dictation hotkey — Accessibility permission likely missing")
            }
        } else {
            monitor.uninstall()
        }

        // Ask-screen hotkey is opt-in. Install only when (a) dictation is
        // enabled overall, (b) the ask-screen feature is toggled on, and
        // (c) the user has bound a shortcut. Otherwise tear the second event
        // tap down — there's no reason to hold an extra CGEventTap when the
        // feature is dormant.
        if settings.isEnabled, settings.askScreenEnabled, let askShortcut = settings.askScreenShortcut {
            let ok = askMonitor.install(shortcut: askShortcut)
            if !ok {
                logger.warning("Failed to install ask-screen hotkey — Accessibility permission likely missing")
            }
        } else {
            askMonitor.uninstall()
        }

        if settings.isEnabled, settings.voiceActionsEnabled, let actionsShortcut = settings.voiceActionsShortcut {
            let ok = actionsMonitor.install(shortcut: actionsShortcut)
            if !ok {
                logger.warning("Failed to install voice-actions hotkey — Accessibility permission likely missing")
            }
        } else {
            actionsMonitor.uninstall()
        }
    }

    /// Watch the dictation store and re-install the hotkey when the user
    /// edits it in Settings. The store publishes the whole `settings` struct
    /// on each change, so we just diff against the currently installed
    /// shortcut.
    private func observeSettingsChanges() {
        guard let store else { return }
        settingsObservation?.cancel()
        settingsObservation = Task { @MainActor [weak self, weak store] in
            guard let store else { return }
            var lastShortcut = store.settings.shortcut
            var lastEnabled = store.settings.isEnabled
            var lastAskEnabled = store.settings.askScreenEnabled
            var lastAsk = store.settings.askScreenShortcut
            var lastActionsEnabled = store.settings.voiceActionsEnabled
            var lastActions = store.settings.voiceActionsShortcut
            for await _ in store.$settings.values {
                guard let self else { return }
                let current = store.settings
                let shortcutChanged = current.shortcut != lastShortcut
                let enabledChanged = current.isEnabled != lastEnabled
                let askEnabledChanged = current.askScreenEnabled != lastAskEnabled
                let askChanged = current.askScreenShortcut != lastAsk
                let actionsEnabledChanged = current.voiceActionsEnabled != lastActionsEnabled
                let actionsChanged = current.voiceActionsShortcut != lastActions
                if shortcutChanged || enabledChanged || askEnabledChanged || askChanged
                    || actionsEnabledChanged || actionsChanged {
                    lastShortcut = current.shortcut
                    lastEnabled = current.isEnabled
                    lastAskEnabled = current.askScreenEnabled
                    lastAsk = current.askScreenShortcut
                    lastActionsEnabled = current.voiceActionsEnabled
                    lastActions = current.voiceActionsShortcut
                    self.applyCurrentSettings()
                }
            }
        }
    }

    // MARK: - Programmatic triggers

    /// Whether dictation is turned on at all (gates the palette/launchpad actions).
    var isDictationEnabled: Bool {
        store?.settings.isEnabled ?? false
    }

    /// Whether ask-the-screen is available (dictation on + ask-screen toggled on).
    var isAskScreenEnabled: Bool {
        guard let settings = store?.settings else { return false }
        return settings.isEnabled && settings.askScreenEnabled
    }

    /// Whether voice actions are available (dictation on + voice actions on).
    var isVoiceActionsEnabled: Bool {
        guard let settings = store?.settings else { return false }
        return settings.isEnabled && settings.voiceActionsEnabled
    }

    /// Start a polish-mode dictation session, as if the dictation hotkey fired.
    /// Used by the command palette so dictation is reachable from search.
    func startDictation() {
        coordinator?.startSession(mode: .polish)
    }

    /// Start an ask-the-screen dictation session.
    func startAskScreen() {
        coordinator?.startSession(mode: .askScreen)
    }

    /// Start a voice-actions dictation session.
    func startVoiceActions() {
        coordinator?.startSession(mode: .actions)
    }
}