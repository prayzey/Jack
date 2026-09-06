import AppKit
import Sentry
import SwiftData
import SwiftUI

private struct CheckForUpdatesButton: View {
    var body: some View {
        Button(AppMenuCopy.checkForUpdates()) {
            AppUpdater.shared.checkForUpdates()
        }
        .disabled(!AppUpdater.shared.isConfigured)
    }
}

private struct AboutJackButton: View {
    var body: some View {
        Button(AppMenuCopy.about()) {
            NSApp.orderFrontStandardAboutPanel(options: AppAttribution.aboutPanelOptions)
        }
    }
}

/// Menu bar button that activates the app before opening Settings,
/// so it works even when the main window is in the background.
private struct MenuBarSettingsButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(AppMenuCopy.settingsEllipsis()) {
            NSApp.activate(ignoringOtherApps: true)
            AppWindowManager.shared.prepareForSettingsPresentation(source: "menu-bar-settings")
            openWindow(id: SettingsNavigation.windowID)
        }
        .keyboardShortcut(",", modifiers: .command)
    }
}

private struct JackSettingsCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button(AppMenuCopy.settingsEllipsis()) {
                NSApp.activate(ignoringOtherApps: true)
                AppWindowManager.shared.prepareForSettingsPresentation(source: "command-settings")
                openWindow(id: SettingsNavigation.windowID)
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}

private struct MenuBarPathOnlyIcon: View {
    private static let templateImage: NSImage = {
        let size = NSSize(width: 18, height: 16)
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.black.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 2.6
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        let center = NSPoint(x: size.width * 0.50, y: size.height * 0.52)

        path.move(to: NSPoint(x: size.width * 0.15, y: size.height * 0.58))
        path.line(to: NSPoint(x: size.width * 0.36, y: size.height * 0.57))
        path.line(to: center)

        path.move(to: center)
        path.line(to: NSPoint(x: size.width * 0.56, y: size.height * 0.36))
        path.line(to: NSPoint(x: size.width * 0.60, y: size.height * 0.14))

        path.move(to: center)
        path.line(to: NSPoint(x: size.width * 0.69, y: size.height * 0.63))
        path.line(to: NSPoint(x: size.width * 0.84, y: size.height * 0.76))

        path.stroke()
        image.unlockFocus()

        // Template images let AppKit choose the correct contrasting color
        // in normal, highlighted, and inactive menu bar states.
        image.isTemplate = true
        return image
    }()

    var body: some View {
        Image(nsImage: Self.templateImage)
            .renderingMode(.template)
            .frame(width: 17, height: 15)
            .padding(.vertical, 1)
    }
}

@main
struct JackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store: ClipboardStore
    @StateObject private var dictationStore: DictationStore
    @StateObject private var dictationCoordinator: DictationCoordinator
    // Hotkey monitor stays alive for the app's lifetime via a static
    // reference inside `DictationLauncher` (set at first call site below).

    init() {
        SentrySDK.start { options in
            options.dsn = "https://9161743fda7306aba1cedb60924f5b79@o4511105724252160.ingest.us.sentry.io/4511105727463424"
            options.debug = false
            options.enableAutoSessionTracking = true
            options.tracesSampleRate = 1.0
            options.enableAppHangTracking = true
            options.appHangTimeoutInterval = 2
            // Tag release so dSYMs can be matched
            if let releaseName = AppVersionInfo.current.sentryReleaseName {
                options.releaseName = releaseName
            }
        }

        Analytics.initialize()
        let store = ClipboardStore()
        AppStoreReferences.shared.statsStore = store.transcriptionStatsStore
        AppStoreReferences.shared.clipboardStore = store
        _store = StateObject(wrappedValue: store)
        let dictationStore = DictationStore()
        _dictationStore = StateObject(wrappedValue: dictationStore)
        let coordinator = DictationCoordinator()
        coordinator.attach(store: dictationStore)
        coordinator.attach(statsStore: store.transcriptionStatsStore)
        // The correction learner is a long-lived sibling — reuse the same
        // Qwen cache the meeting summarizer + dictation polish already
        // share, so we never duplicate the model on disk.
        let correctionLearner = CorrectionLearner(
            store: store.correctionStore,
            cacheDirectory: dictationStore.qwenCacheURL
        )
        coordinator.attach(correctionLearner: correctionLearner, correctionStore: store.correctionStore)
        let voiceActionExecutor = VoiceActionExecutor { reminder in
            store.addPulseReminder(reminder)
        }
        coordinator.attach(voiceActionExecutor: voiceActionExecutor)
        MeetingHub.shared.controller.attach(statsStore: store.transcriptionStatsStore)
        // One-time backfill from existing data so users who already have
        // dictation history + saved meetings see a populated card on the very
        // first open. After this, every new session flows through the
        // incremental record API on the coordinator + controller.
        store.transcriptionStatsStore.bootstrapIfNeeded(
            dictationHistory: dictationStore.history,
            meetingSessions: MeetingHub.shared.store.sessions,
            meetingWordCount: { meetingID in
                MeetingHub.shared.store
                    .loadTranscript(for: meetingID)
                    .reduce(0) { $0 + TranscriptionStatsStore.wordCount($1.text) }
            }
        )
        _dictationCoordinator = StateObject(wrappedValue: coordinator)
        DictationLauncher.shared.bootstrap(
            store: dictationStore,
            coordinator: coordinator
        )
        AppWindowManager.shared.configure(store: store)
        QuickNoteWindowManager.shared.configure(store: store)
        DictationComposeWindowManager.shared.configure(coordinator: coordinator, clipboardStore: store)
        CommandPaletteWindowManager.shared.configure(store: store)
        // Audio-file transcription: drop a voice note on the workspace or the
        // custom-text menu bar item, or use the "Transcribe Audio File…"
        // command. The coordinator owns the queue + result clip; the HUD shows
        // progress over any view mode.
        AudioTranscriptionCoordinator.shared.bind(to: store)
        TranscriptionHUDWindowManager.shared.configure(coordinator: .shared)
        // Custom-text menu bar activation is deferred to
        // `AppDelegate.applicationDidFinishLaunching` via
        // `MenuBarTextItemController.finishLaunchSetup()` — NSStatusBar is
        // not reliable when requested from `init`.
        MenuBarTextItemController.shared.bind(to: store)
        AppWindowManager.shared.configureLaunchPresentation(
            shouldShowOnboarding: store.shouldShowOnboarding,
            savedViewMode: store.settings.viewMode
        )
        Analytics.appLaunched(viewMode: store.settings.viewMode.rawValue)
        UpdateCheckService.shared.checkOnLaunch()
    }

    /// MenuBarExtra is only inserted when the user wants the icon mode.
    /// When custom-text mode is on, `MenuBarTextItemController` takes over
    /// and we hide the SwiftUI-managed extra so we never have two competing
    /// status items.
    ///
    /// IMPORTANT: the setter must be a no-op. SwiftUI's `isInserted` is
    /// bidirectional — if we mirrored the derived `false` value back into
    /// `store.settings.showInMenuBar`, toggling text mode on would silently
    /// disable the underlying preference, and the icon would never come back.
    /// `showInMenuBar` is only mutated by the explicit toggle in Settings,
    /// which binds directly to `$store.settings.showInMenuBar`.
    private var menuBarInsertedBinding: Binding<Bool> {
        Binding(
            get: {
                let trimmedText = store.settings.menuBarCustomText
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let textModeActive = store.settings.menuBarShowCustomText && !trimmedText.isEmpty
                return store.settings.showInMenuBar && !textModeActive
            },
            set: { _ in /* no-op: see docstring above */ }
        )
    }

    var body: some Scene {
        WindowGroup(AppBrand.displayName) {
            ContentView()
                .environmentObject(store)
                .environmentObject(store.correctionStore)
                .environment(\.locale, store.preferredAppLocale)
                .modelContainer(store.modelContainer)
                .frame(minWidth: 980, minHeight: 220)
                .onAppear {
                    let shouldShowOnboarding = store.shouldShowOnboarding
                    AppWindowManager.shared.resolveLaunchPresentation()
                    store.presentPersistenceIssueIfNeeded()
                    if shouldShowOnboarding {
                        AppWindowManager.shared.presentOnboarding(store: store)
                    }
                    // Restore saved view mode on launch
                    if store.settings.viewMode != .tray {
                        AppWindowManager.shared.switchMode(to: store.settings.viewMode, store: store)
                    }
                }
                .onReceive(UpdateCheckService.shared.$state) { newState in
                    if case .forceUpdate(let version, let message, let url) = newState {
                        AppWindowManager.shared.presentForceUpdate(
                            latestVersion: version,
                            message: message,
                            updateURL: url
                        )
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                AboutJackButton()
            }

            JackSettingsCommands()

            // Override Edit > Copy so Cmd+C copies selected clips when available,
            // otherwise falls through to standard text field copy.
            CommandGroup(replacing: .pasteboard) {
                Button(CommonCopy.copy()) {
                    if !store.selectedClipIDs.isEmpty {
                        store.copySelectionOnly()
                    } else {
                        NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                    }
                }
                .keyboardShortcut("c", modifiers: .command)

                Button(CommonCopy.paste()) {
                    NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("v", modifiers: .command)

                Button(CommonCopy.cut()) {
                    NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("x", modifiers: .command)

                Button(CommonCopy.selectAll()) {
                    let handledByTextResponder = NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                    if !handledByTextResponder {
                        store.selectAllVisibleClips()
                    }
                }
                .keyboardShortcut("a", modifiers: .command)
            }

            CommandGroup(after: .pasteboard) {
                Button(CommonCopy.delete()) {
                    if !store.selectedClipIDs.isEmpty {
                        store.deleteClips(store.selectedClipIDs)
                    }
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(store.selectedClipIDs.isEmpty)
            }

            CommandMenu(AppBrand.displayName) {
                Button(AppMenuCopy.toggleApp()) {
                    AppWindowManager.shared.toggleWindow(source: "command-menu")
                }

                // No key equivalent here: the global Option+Space hotkey already
                // opens this from anywhere, and a menu shortcut would double-fire
                // (open then immediately close) while Jack is frontmost.
                Button(AppMenuCopy.commandPalette()) {
                    CommandPaletteWindowManager.shared.toggle()
                }

                Button(AppMenuCopy.quickNote()) {
                    QuickNoteWindowManager.shared.toggle()
                }
                .keyboardShortcut("a", modifiers: .option)

                Button(AppMenuCopy.voiceCompose()) {
                    DictationComposeWindowManager.shared.toggle()
                }
                .keyboardShortcut("d", modifiers: [.command, .option])

                Button(AppMenuCopy.openWorkspace()) {
                    store.settings.viewMode = .workspace
                    AppWindowManager.shared.toggleWindow(source: "command-workspace")
                }

                Button(AppMenuCopy.openMeetings()) {
                    store.openMeetingsInWorkspace()
                    store.settings.viewMode = .workspace
                    AppWindowManager.shared.toggleWindow(source: "command-meetings")
                }
                .keyboardShortcut("m", modifiers: [.command, .option])

                Button(AppMenuCopy.transcribeAudioFile()) {
                    AudioTranscriptionCoordinator.shared.presentOpenPanel()
                }

                Button(AppMenuCopy.copyCurrentNote()) {
                    guard let noteID = store.selectedWorkspaceNoteID ?? store.quickNoteActiveNoteID else { return }
                    store.copyNoteToClipboard(noteID)
                }
                .disabled(store.selectedWorkspaceNoteID == nil && store.quickNoteActiveNoteID == nil)

                Button(AppMenuCopy.saveCurrentNoteAsClip()) {
                    guard let noteID = store.selectedWorkspaceNoteID ?? store.quickNoteActiveNoteID else { return }
                    store.saveNoteAsClipSnapshot(noteID)
                }
                .disabled(store.selectedWorkspaceNoteID == nil && store.quickNoteActiveNoteID == nil)

                Divider()

                Button(AppMenuCopy.pasteFirstClip()) {
                    store.quickPaste(index: 0)
                }
                .keyboardShortcut("1", modifiers: .command)

                Button(AppMenuCopy.pasteSecondClip()) {
                    store.quickPaste(index: 1)
                }
                .keyboardShortcut("2", modifiers: .command)

                Button(AppMenuCopy.pasteThirdClip()) {
                    store.quickPaste(index: 2)
                }
                .keyboardShortcut("3", modifiers: .command)

                Divider()

                Button(AppMenuCopy.sendFeedback()) {
                    NSWorkspace.shared.open(AppBrand.feedbackURL)
                }

                Button(AppMenuCopy.reportBug()) {
                    NSWorkspace.shared.open(AppBrand.bugReportURL)
                }

                Button(AppMenuCopy.requestFeature()) {
                    NSWorkspace.shared.open(AppBrand.featureRequestURL)
                }

                Divider()

                CheckForUpdatesButton()
            }
        }

        Window(AppMenuCopy.settingsWindowTitle(), id: SettingsNavigation.windowID) {
            SettingsView()
                .environmentObject(store)
                .environmentObject(store.correctionStore)
                .environmentObject(dictationStore)
                .environment(\.locale, store.preferredAppLocale)
                .frame(
                    minWidth: SettingsWindowPolicy.minimumWidth,
                    maxWidth: .infinity,
                    minHeight: SettingsWindowPolicy.minimumHeight,
                    maxHeight: .infinity
                )
        }
        .defaultSize(
            width: SettingsWindowPolicy.defaultWidth,
            height: SettingsWindowPolicy.defaultHeight
        )
        // The hidden-titlebar look is produced by SettingsWindowPolicy via
        // fullSizeContentView + transparent titlebar. Using .windowStyle(.hiddenTitleBar)
        // here fights with .windowResizability and can strip .resizable from the
        // styleMask, blocking edge/corner drag resize.
        .windowResizability(.contentMinSize)

        MenuBarExtra(isInserted: menuBarInsertedBinding) {
            // MenuBarExtra clicks do NOT activate the app — without forcing
            // activation here, the window we order front comes up *behind*
            // whatever app the user was focused on, then auto-hides ~1s later
            // via `hidesOnDeactivate`. Net effect: clicking "Show Jack" looks
            // like nothing happened. Always activate before toggling.
            Button(AppMenuCopy.showApp(shortcutSymbol: store.settings.globalShortcut.symbolString)) {
                NSApp.activate(ignoringOtherApps: true)
                AppWindowManager.shared.toggleWindow(source: "menu-bar")
            }

            Button(AppMenuCopy.openMeetings()) {
                NSApp.activate(ignoringOtherApps: true)
                store.openMeetingsInWorkspace()
                store.settings.viewMode = .workspace
                AppWindowManager.shared.toggleWindow(source: "menu-bar-meetings")
            }

            Button(AppMenuCopy.transcribeAudioFile()) {
                AudioTranscriptionCoordinator.shared.presentOpenPanel()
            }

            // Jack toggle — flips presence between Always-on and Off so the
            // user can summon or dismiss Jack from the menu bar without
            // diving into Settings. The label reflects current state so the
            // user knows what tapping will do.
            Button(store.settings.jackSettings.isVisible ? AppMenuCopy.hideJack() : AppMenuCopy.summonJack()) {
                if store.settings.jackSettings.isVisible {
                    store.settings.jackSettings.presenceMode = .off
                } else {
                    store.settings.jackSettings.presenceMode = .alwaysOn
                }
            }

            Divider()

            Menu(CommonCopy.viewMode()) {
                ForEach(ViewMode.allCases) { mode in
                    if mode == .drawer {
                        Menu {
                            ForEach(DrawerSide.allCases) { side in
                                Button {
                                    store.settings.viewMode = .drawer
                                    store.settings.drawerSide = side
                                } label: {
                                    if store.settings.viewMode == .drawer && store.settings.drawerSide == side {
                                        Label(side.label, systemImage: "checkmark")
                                    } else {
                                        Text(side.label)
                                    }
                                }
                            }
                        } label: {
                            if store.settings.viewMode == .drawer {
                                Label(mode.label, systemImage: "checkmark")
                            } else {
                                Text(mode.label)
                            }
                        }
                    } else {
                        Button {
                            store.settings.viewMode = mode
                        } label: {
                            if store.settings.viewMode == mode {
                                Label(mode.label, systemImage: "checkmark")
                            } else {
                                Text(mode.label)
                            }
                        }
                    }
                }
            }

            Divider()

            CheckForUpdatesButton()

            Divider()

            MenuBarSettingsButton()

            Divider()

            Button(AppMenuCopy.quitApp()) {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        } label: {
            // Custom text is handled by MenuBarTextItemController (a real
            // NSStatusItem). This MenuBarExtra is only inserted when we are
            // in icon mode — see `menuBarInsertedBinding`.
            MenuBarPathOnlyIcon()
                .accessibilityLabel(AppBrand.displayName)
        }
    }
}
