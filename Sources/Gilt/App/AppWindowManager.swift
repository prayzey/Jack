import AppKit
import AVFoundation
import Foundation
import OSLog
import QuartzCore
import SwiftData
import SwiftUI

/// Borderless window that can still become key (needed for keyboard input).
private class BorderlessKeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

extension Notification.Name {
    static let shelfHeightDidChange = Notification.Name("JackShelfHeightDidChange")
    static let requestSearchFocus = Notification.Name("JackRequestSearchFocus")
    static let requestClipStripSnapToLatest = Notification.Name("JackRequestClipStripSnapToLatest")
    static let radialSizeDidChange = Notification.Name("JackRadialSizeDidChange")
}

@MainActor
final class AppWindowManager {
    static let shared = AppWindowManager()
    static let workspaceMinimumWindowSize = NSSize(width: 960, height: 620)
    static let workspaceMaximumWindowSize = NSSize(width: 1800, height: 1400)
    static let workspaceVisibleInset: CGFloat = 40

    private struct ToggleTrace {
        let id: UInt64
        let source: String
        let requestedAt: CFTimeInterval
        let startedAt: CFTimeInterval
    }

    private var window: NSWindow?
    private var fallbackTrayWindow: NSWindow?
    private var configuredWindowNumber: Int?
    private var isAnimating = false
    private(set) var isInteractiveResizing = false
    private weak var activeStore: ClipboardStore?
    private var workspaceResizeObserver: NSObjectProtocol?

    private let minShelfHeight: CGFloat = 220
    private let maxShelfHeight: CGFloat = 560
    private let collapsedHeight: CGFloat = 220
    private let expandedHeight: CGFloat = 420
    private let resizeLogger = Logger(subsystem: AppBrand.logSubsystem, category: "WindowResize")
    private let windowLogger = Logger(subsystem: AppBrand.logSubsystem, category: "WindowLifecycle")
    private let performanceLogger = Logger(subsystem: AppBrand.logSubsystem, category: "WindowPerformance")
    private let resizeDebugLoggingEnabled = ProcessInfo.processInfo.environment["GILT_DEBUG_LOGS"] == "1"
    private let lifecycleDebugLoggingEnabled = ProcessInfo.processInfo.environment["GILT_DEBUG_LOGS"] == "1"
    private let performanceLoggingEnabled = ProcessInfo.processInfo.environment["GILT_DEBUG_LOGS"] == "1"
    private let showAnimationDuration: CFTimeInterval = 0.30
    private let hideAnimationDuration: CFTimeInterval = 0.24
    private let droppedFrameThresholdMs = 12.0
    private let animationTickCoalescingQueue = DispatchQueue(
        label: "Jack.AppWindowManager.AnimationTickCoalescing",
        qos: .userInteractive
    )
    nonisolated(unsafe) private var animationTickScheduled = false
    private var nextTraceID: UInt64 = 1
    private var didResignActiveObserver: NSObjectProtocol?
    private var didBecomeActiveObserver: NSObjectProtocol?
    private var settingsBecameKeyObserver: NSObjectProtocol?
    private var settingsWillCloseObserver: NSObjectProtocol?
    private var settingsDidResignKeyObserver: NSObjectProtocol?
    private var isInternalDragActive = false
    private var settingsPreviewActive = false
    private var prioritizeActiveModeOverSettings = false
    private var onboardingPreviewActive = false
    private var onboardingPreviewDismissWork: DispatchWorkItem?
    private var onboardingMusicPlayer: AVAudioPlayer?
    private var onboardingMusicFadeTask: Task<Void, Never>?
    private var suppressInitialTrayUntilLaunchDecision = false

    // MARK: – Multi-mode support
    private(set) var activeViewMode: ViewMode = .tray
    private var modeWindows: [ViewMode: NSWindow] = [:]
    private(set) var drawerWidth: CGFloat = 280
    private(set) var radialSize: CGFloat = 400
    private let radialFolderBarHeight: CGFloat = 36
    private var drawerSide: DrawerSide = .right
    private var clickOutsideGlobalMonitor: Any?
    private var clickOutsideLocalMonitor: Any?
    private var lastFocusForInputRequestAt: CFTimeInterval = 0
    private let focusForInputThrottleInterval: CFTimeInterval = 0.12

    private(set) var shelfHeight: CGFloat = 300 {
        didSet {
            NotificationCenter.default.post(name: .shelfHeightDidChange, object: shelfHeight)
        }
    }

    /// Mode windows always float at dock+1, even while Settings preview is active
    /// (Settings then stacks one level above via `settingsPreviewWindowLevel`).
    static let modeWindowLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)

    static func shouldInstallClickOutsideMonitors(settingsPreviewActive: Bool) -> Bool {
        !settingsPreviewActive
    }

    static func shouldSuppressBoundTrayWindow(
        suppressInitialTrayUntilLaunchDecision: Bool,
        onboardingVisible: Bool,
        activeViewMode: ViewMode
    ) -> Bool {
        suppressInitialTrayUntilLaunchDecision || onboardingVisible || activeViewMode != .tray
    }

    static func shouldSuppressInitialTrayWindowOnLaunch(
        shouldShowOnboarding: Bool,
        savedViewMode: ViewMode
    ) -> Bool {
        // SwiftUI restores the WindowGroup (the tray) before Jack finishes deciding
        // whether launch should route into onboarding or a different saved mode.
        // Keep the tray hidden during that launch handoff so it never flashes on-screen.
        shouldShowOnboarding || savedViewMode != .tray
    }

    static func shouldThrottleFocusForInput(
        lastRequestAt: CFTimeInterval,
        now: CFTimeInterval,
        minimumInterval: CFTimeInterval = 0.12
    ) -> Bool {
        now - lastRequestAt < minimumInterval
    }

    static func postTrayDidShowNotifications(window: NSWindow?) {
        NotificationCenter.default.post(name: .requestClipStripSnapToLatest, object: window)
        NotificationCenter.default.post(name: .requestSearchFocus, object: nil)
    }

    static func adjustedAnimationDuration(
        base: CFTimeInterval,
        speed: Double,
        reduceMotion: Bool
    ) -> CFTimeInterval {
        guard !reduceMotion else { return 0 }
        let clampedSpeed = min(max(speed, 0), 1)
        guard clampedSpeed < 0.999 else { return 0 }
        return base * (1 - clampedSpeed)
    }

    static func recoveryModeForMissingToggleWindow(
        activeViewMode: ViewMode,
        savedViewMode: ViewMode,
        hasTrayWindow: Bool,
        hasActiveModeWindow: Bool
    ) -> ViewMode? {
        if activeViewMode == .tray {
            return hasTrayWindow ? nil : savedViewMode
        }
        return hasActiveModeWindow ? nil : activeViewMode
    }

    static func clampedWorkspaceWindowSize(
        preferredWidth: CGFloat,
        preferredHeight: CGFloat,
        visibleFrame: NSRect
    ) -> NSSize {
        let maxWidth = max(visibleFrame.width - (workspaceVisibleInset * 2), 720)
        let maxHeight = max(visibleFrame.height - (workspaceVisibleInset * 2), 520)
        let minWidth = min(workspaceMinimumWindowSize.width, maxWidth)
        let minHeight = min(workspaceMinimumWindowSize.height, maxHeight)
        let width = min(max(preferredWidth, minWidth), min(workspaceMaximumWindowSize.width, maxWidth))
        let height = min(max(preferredHeight, minHeight), min(workspaceMaximumWindowSize.height, maxHeight))
        return NSSize(width: width, height: height)
    }

    static func workspaceFrame(
        preferredWidth: CGFloat,
        preferredHeight: CGFloat,
        visibleFrame: NSRect
    ) -> NSRect {
        let size = clampedWorkspaceWindowSize(
            preferredWidth: preferredWidth,
            preferredHeight: preferredHeight,
            visibleFrame: visibleFrame
        )
        return NSRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private var settingsPreviewWindowLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Self.modeWindowLevel.rawValue + 1)
    }

    private var frontmostModeWindowLevel: NSWindow.Level {
        NSWindow.Level(rawValue: settingsPreviewWindowLevel.rawValue + 1)
    }

    private enum OnboardingMusic {
        static let fileName = "Under The Moonstar"
        static let fileExtension = "mp3"
        static let defaultVolume: Float = 0.7
        static let fadeOutDurationNanoseconds: UInt64 = 1_200_000_000
        static let fadeOutSteps: Int = 18
    }

    private init() {
        installLifecycleObservers()
    }

    func configure(store: ClipboardStore) {
        activeStore = store
    }

    private func installLifecycleObservers() {
        didResignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleAppDidResignActive()
            }
        }

        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleAppDidBecomeActive()
            }
        }

        settingsBecameKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let window = notification.object as? NSWindow
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let window, self.isSettingsWindow(window) {
                    SettingsWindowPolicy.apply(to: window)
                }
                self.refreshSettingsPreviewState(reason: "settings-became-key")
            }
        }

        settingsDidResignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let window = notification.object as? NSWindow
            Task { @MainActor [weak self] in
                if let window, self?.isSettingsWindow(window) == true {
                    SettingsWindowPolicy.apply(to: window)
                }
                self?.refreshSettingsPreviewState(reason: "settings-resign-key")
            }
        }

        settingsWillCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                DispatchQueue.main.async { [weak self] in
                    self?.refreshSettingsPreviewState(reason: "settings-will-close")
                }
            }
        }
    }

    private func handleAppDidResignActive() {
        logLifecycle(windowLifecycleSummary(prefix: "app didResignActive"))
        let visibleWindow = visibleWindowForActiveMode()
        guard let visibleWindow, visibleWindow.isVisible, !isAnimating else { return }
        if isInternalDragActive {
            logLifecycle("skip hide on resign-active (internal drag in progress)")
            return
        }
        if onboardingWindow?.isVisible == true {
            logLifecycle("skip hide on resign-active (onboarding visible)")
            return
        }
        hideModeWindow(
            visibleWindow,
            trace: makeTrace(source: "app-resign-active"),
            reason: "app-resign-active"
        )
    }

    private func handleAppDidBecomeActive() {
        logLifecycle(windowLifecycleSummary(prefix: "app didBecomeActive"))

        suppressTrayAutoShowIfNeeded(context: "didBecomeActive")
    }

    private func visibleWindowForActiveMode() -> NSWindow? {
        if activeViewMode == .tray {
            return window
        }
        return modeWindows[activeViewMode]
    }

    var isActiveModeWindowVisible: Bool {
        visibleWindowForActiveMode()?.isVisible ?? false
    }

    private func windowLifecycleSummary(prefix: String) -> String {
        "\(prefix) appActive=\(NSApp.isActive) windowVisible=\(window?.isVisible ?? false) "
            + "isAnimating=\(isAnimating) internalDrag=\(isInternalDragActive)"
    }

    func setInternalDragActive(_ active: Bool) {
        guard isInternalDragActive != active else { return }
        isInternalDragActive = active
        logLifecycle("internalDragActive=\(active) appActive=\(NSApp.isActive) windowVisible=\(window?.isVisible ?? false)")
    }

    func bind(window: NSWindow) {
        if let fallbackTrayWindow, fallbackTrayWindow !== window {
            fallbackTrayWindow.orderOut(nil)
            fallbackTrayWindow.close()
            self.fallbackTrayWindow = nil
        }
        self.window = window
        logLifecycle("bind windowNumber=\(window.windowNumber) title=\(window.title)")

        // Immediately suppress tray visibility when a non-tray mode is active.
        // This runs before configureWindow so the window never renders a visible
        // frame, preventing the brief "flash" when macOS restores the WindowGroup
        // on dock click while in grid/drawer/radial mode.
        if Self.shouldSuppressBoundTrayWindow(
            suppressInitialTrayUntilLaunchDecision: suppressInitialTrayUntilLaunchDecision,
            onboardingVisible: onboardingWindow != nil,
            activeViewMode: activeViewMode
        ) {
            window.alphaValue = 0
            window.orderOut(nil)
        }

        guard configuredWindowNumber != window.windowNumber else { return }
        configuredWindowNumber = window.windowNumber
        configureWindow(window)
        placeWindowAtBottom(window)
    }

    func configureLaunchPresentation(
        shouldShowOnboarding: Bool,
        savedViewMode: ViewMode
    ) {
        suppressInitialTrayUntilLaunchDecision = Self.shouldSuppressInitialTrayWindowOnLaunch(
            shouldShowOnboarding: shouldShowOnboarding,
            savedViewMode: savedViewMode
        )
        logLifecycle(
            "configureLaunchPresentation shouldShowOnboarding=\(shouldShowOnboarding) "
                + "savedViewMode=\(savedViewMode.rawValue) "
                + "suppressInitialTray=\(suppressInitialTrayUntilLaunchDecision)"
        )
    }

    func resolveLaunchPresentation() {
        guard suppressInitialTrayUntilLaunchDecision else { return }
        suppressInitialTrayUntilLaunchDecision = false
        logLifecycle("resolveLaunchPresentation")
    }

    /// The app that was frontmost before Jack appeared — used to return focus on paste.
    private(set) var previousApp: NSRunningApplication?

    /// Standalone onboarding window — shown centered on screen instead of inside the tray.
    private var onboardingWindow: NSWindow?
    private var theaterModeWindow: NSWindow?
    private var forceUpdateWindow: NSWindow?
    private var retainedDismissedOnboardingWindows: [NSWindow] = []
    private var onboardingDismissInFlight = false
    private var skipNextShowAnimation = false

    func toggleWindow(source: String = "unknown", requestedAt: CFTimeInterval? = nil) {
        Analytics.hotkeyToggled()
        guard isAnimating == false else {
            let trace = makeTrace(source: source, requestedAt: requestedAt)
            logPerf("trace#\(trace.id) toggle ignored reason=animation-in-flight source=\(source)")
            return
        }
        // Don't toggle while onboarding is active
        guard onboardingWindow == nil else {
            let trace = makeTrace(source: source, requestedAt: requestedAt)
            logPerf("trace#\(trace.id) toggle ignored reason=onboarding-active source=\(source)")
            return
        }

        let targetWindow = windowForToggle(source: source)

        guard let targetWindow else {
            let trace = makeTrace(source: source, requestedAt: requestedAt)
            logPerf("trace#\(trace.id) toggle ignored reason=no-window mode=\(activeViewMode.rawValue) source=\(source)")
            return
        }

        let trace = makeTrace(source: source, requestedAt: requestedAt)
        logLifecycle("toggleWindow mode=\(activeViewMode.rawValue) visible=\(targetWindow.isVisible) isAnimating=\(isAnimating)")
        logPerf(
            "trace#\(trace.id) toggle start source=\(trace.source) "
                + "mode=\(activeViewMode.rawValue) "
                + "requestedAtToNow=\(String(format: "%.2f", (trace.startedAt - trace.requestedAt) * 1000))ms "
                + "appActive=\(NSApp.isActive)"
        )

        if targetWindow.isVisible {
            prioritizeActiveModeOverSettings = false
            hideModeWindow(targetWindow, trace: trace, reason: "toggle-visible")
            return
        }

        let captureStart = CACurrentMediaTime()
        if let frontmostApp = NSWorkspace.shared.frontmostApplication,
           frontmostApp.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = frontmostApp
        } else {
            previousApp = nil
        }
        logPerf("trace#\(trace.id) capturePreviousApp duration=\(elapsedMillis(since: captureStart))ms")
        logLifecycle("captured previousApp=\(previousApp?.localizedName ?? "nil")")

        prioritizeActiveModeOverSettings = shouldPrioritizeModeWindowOverSettings(source: trace.source)
        updateModeWindowLevels(reason: "toggle-priority")
        showModeWindow(targetWindow, trace: trace)
    }

    private func windowForToggle(source: String) -> NSWindow? {
        if activeViewMode == .tray, let window {
            return window
        }
        if activeViewMode != .tray, let modeWindow = modeWindows[activeViewMode] {
            return modeWindow
        }

        guard let store = activeStore else {
            windowLogger.error("toggle recovery failed: no active store source=\(source, privacy: .public)")
            return nil
        }

        let recoveryMode = Self.recoveryModeForMissingToggleWindow(
            activeViewMode: activeViewMode,
            savedViewMode: store.settings.viewMode,
            hasTrayWindow: window != nil,
            hasActiveModeWindow: activeViewMode == .tray ? false : modeWindows[activeViewMode] != nil
        )

        guard let recoveryMode else {
            return activeViewMode == .tray ? window : modeWindows[activeViewMode]
        }

        windowLogger.info("recovering missing toggle window source=\(source, privacy: .public) activeMode=\(self.activeViewMode.rawValue, privacy: .public) recoveryMode=\(recoveryMode.rawValue, privacy: .public)")

        if recoveryMode != activeViewMode {
            switchMode(to: recoveryMode, store: store)
        }

        if recoveryMode == .tray {
            return ensureFallbackTrayWindow(store: store)
        }

        if modeWindows[recoveryMode] == nil {
            modeWindows[recoveryMode] = createModeWindow(for: recoveryMode, store: store)
        }
        return modeWindows[recoveryMode]
    }

    private func ensureFallbackTrayWindow(store: ClipboardStore) -> NSWindow? {
        if let window {
            return window
        }
        if let fallbackTrayWindow {
            window = fallbackTrayWindow
            return fallbackTrayWindow
        }

        suppressInitialTrayUntilLaunchDecision = false
        let rootView = ContentView()
            .environmentObject(store)
            .environment(\.locale, store.preferredAppLocale)
            .modelContainer(store.modelContainer)
            .frame(minWidth: 980, minHeight: 220)

        let win = BorderlessKeyWindow(
            contentRect: targetFrame(),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.contentView = NSHostingView(rootView: rootView)
        win.isReleasedWhenClosed = false
        configureWindow(win)
        placeWindowAtBottom(win)

        fallbackTrayWindow = win
        window = win
        windowLogger.info("created fallback tray window windowNumber=\(win.windowNumber, privacy: .public)")
        return win
    }

    /// Prep mode windows for Settings presentation while preserving live preview.
    func prepareForSettingsPresentation(source: String = "settings-link") {
        prioritizeActiveModeOverSettings = false
        if settingsPreviewActive == false {
            settingsPreviewActive = true
            removeClickOutsideMonitors()
        }
        updateModeWindowLevels(reason: source)
        promoteSettingsWindowsToActiveSpace(reason: source)
        DispatchQueue.main.async { [weak self] in
            Task { @MainActor [weak self] in
                self?.promoteSettingsWindowsToActiveSpace(reason: "\(source)-async")
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshSettingsPreviewState(reason: "\(source)-post-open-check")
            }
        }
    }

    /// Override the app the paste pipeline will restore focus to. The command
    /// palette is a separate window, so it captures the user's previous app on
    /// open and sets it here right before pasting — otherwise the paste pipeline's
    /// own `previousApp` (captured on the *main* window's last toggle) would be stale.
    func setPasteRestoreTarget(_ app: NSRunningApplication?) {
        previousApp = app
    }

    /// Hide the window and reactivate the previously-focused app (or an explicit target).
    func hideAndRestoreFocus(targetApp: NSRunningApplication? = nil) {
        guard !isAnimating else { return }
        let targetWindow: NSWindow?
        if activeViewMode == .tray {
            targetWindow = window
        } else {
            targetWindow = modeWindows[activeViewMode]
        }
        guard let targetWindow else { return }
        let appToActivate = targetApp ?? previousApp
        hideModeWindow(targetWindow, trace: makeTrace(source: "hide-and-restore"), reason: "hide-and-restore")
        if let appToActivate {
            let activated = appToActivate.activate(options: [.activateAllWindows])
            logLifecycle(
                "hideAndRestoreFocus activated target=\(appToActivate.localizedName ?? "nil") "
                    + "bundleID=\(appToActivate.bundleIdentifier ?? "nil") "
                    + "success=\(activated)"
            )
        }
    }

    /// Instant hide for paste — skips the 240ms tray animation so double-tap
    /// paste feels immediate. Animated hide was forcing users to wait for the
    /// tray to slide away before Cmd+V could land in the target app.
    func hideImmediatelyForPaste(targetApp: NSRunningApplication? = nil) {
        let targetWindow: NSWindow?
        if activeViewMode == .tray {
            targetWindow = window
        } else {
            targetWindow = modeWindows[activeViewMode]
        }
        guard let targetWindow, targetWindow.isVisible else { return }

        removeClickOutsideMonitors()
        stopDisplayLink()
        animationCompletion = nil
        isAnimating = false

        targetWindow.orderOut(nil)
        targetWindow.alphaValue = 1

        if activeViewMode == .tray, let window {
            let target = targetFrame()
            window.setFrame(target, display: false)
        }

        if let appToActivate = targetApp ?? previousApp {
            let activated = appToActivate.activate(options: [.activateAllWindows])
            logLifecycle(
                "hideImmediatelyForPaste activated target=\(appToActivate.localizedName ?? "nil") "
                    + "bundleID=\(appToActivate.bundleIdentifier ?? "nil") "
                    + "success=\(activated)"
            )
        }
        Breadcrumb.record("windowHidden mode=\(activeViewMode.rawValue) reason=hide-immediately-for-paste")
    }

    func focusForInput() {
        let targetWindow: NSWindow?
        if activeViewMode == .tray {
            targetWindow = window
        } else {
            targetWindow = modeWindows[activeViewMode] ?? window
        }
        guard let targetWindow else { return }

        let now = CACurrentMediaTime()
        if Self.shouldThrottleFocusForInput(
            lastRequestAt: lastFocusForInputRequestAt,
            now: now,
            minimumInterval: focusForInputThrottleInterval
        ) {
            logLifecycle("focusForInput throttled mode=\(activeViewMode.rawValue)")
            return
        }
        lastFocusForInputRequestAt = now

        // Avoid re-activating AppKit when we already own focus. Repeated hotkeys can
        // otherwise trigger back-to-back activation work on the main thread.
        if NSApp.isActive, targetWindow.isKeyWindow {
            suppressTrayAutoShowIfNeeded(context: "focus-for-input-already-key")
            return
        }

        activateAppAndWindow(targetWindow, context: "focus-for-input", forceAppActivation: true)
        suppressTrayAutoShowIfNeeded(context: "focus-for-input")
    }

    private func suppressTrayAutoShowIfNeeded(context: String) {
        guard activeViewMode != .tray,
              let tray = window,
              tray.isVisible else { return }
        tray.alphaValue = 0
        tray.orderOut(nil)
        logLifecycle(
            "suppressed tray auto-show context=\(context) mode=\(activeViewMode.rawValue)"
        )
    }

    private func refreshSettingsPreviewState(reason: String) {
        let hasVisibleSettings = NSApp.windows.contains { self.isSettingsWindow($0) && $0.isVisible }
        settingsPreviewActive = hasVisibleSettings
        if settingsPreviewActive == false {
            prioritizeActiveModeOverSettings = false
        }
        updateModeWindowLevels(reason: reason)

        if settingsPreviewActive {
            removeClickOutsideMonitors()
            return
        }

        if (activeViewMode == .grid || activeViewMode == .radial),
           let visibleModeWindow = modeWindows[activeViewMode],
           visibleModeWindow.isVisible {
            installClickOutsideMonitors(for: visibleModeWindow)
        }
    }

    private func promoteSettingsWindowsToActiveSpace(reason: String) {
        let settingsWindows = NSApp.windows.filter(isSettingsWindow)
        guard settingsWindows.isEmpty == false else { return }

        for settingsWindow in settingsWindows {
            SettingsWindowPolicy.apply(to: settingsWindow)
            settingsWindow.orderFrontRegardless()
            settingsWindow.makeKeyAndOrderFront(nil)
            logLifecycle(
                "promoted settings window to active space reason=\(reason) "
                    + "windowNumber=\(settingsWindow.windowNumber)"
            )
        }
    }

    private func updateModeWindowLevels(reason: String) {
        if let window {
            applyModeWindowLevel(to: window, mode: .tray, label: "tray", reason: reason)
        }

        for (mode, window) in modeWindows {
            applyModeWindowLevel(to: window, mode: mode, label: mode.rawValue, reason: reason)
        }

        updateSettingsWindowLevels(reason: reason)
    }

    private func applyModeWindowLevel(to window: NSWindow, mode: ViewMode, label: String, reason: String) {
        let targetLevel = levelForModeWindow(mode)
        guard window.level != targetLevel else { return }
        window.level = targetLevel
    }

    private func levelForModeWindow(_ mode: ViewMode) -> NSWindow.Level {
        if settingsPreviewActive,
           prioritizeActiveModeOverSettings,
           mode == activeViewMode {
            return frontmostModeWindowLevel
        }
        return Self.modeWindowLevel
    }

    private func shouldPrioritizeModeWindowOverSettings(source: String) -> Bool {
        guard settingsPreviewActive else { return false }
        return source.localizedCaseInsensitiveContains("settings") == false
    }

    private func updateSettingsWindowLevels(reason: String) {
        let targetLevel: NSWindow.Level = settingsPreviewActive ? settingsPreviewWindowLevel : .normal
        for settingsWindow in NSApp.windows where isSettingsWindow(settingsWindow) {
            guard settingsWindow.level != targetLevel else { continue }
            settingsWindow.level = targetLevel
        }
    }

    private func isSettingsWindow(_ candidate: NSWindow) -> Bool {
        guard !isManagedWindow(candidate) else { return false }
        if let identifier = candidate.identifier?.rawValue.lowercased(), identifier.contains("settings") {
            return true
        }
        if candidate.title.localizedCaseInsensitiveContains("settings") {
            return true
        }
        return candidate.styleMask.contains(.titled) && !candidate.styleMask.contains(.borderless)
    }

    private func isManagedWindow(_ candidate: NSWindow) -> Bool {
        if let window, window === candidate {
            return true
        }
        if modeWindows.values.contains(where: { $0 === candidate }) {
            return true
        }
        if let onboardingWindow, onboardingWindow === candidate {
            return true
        }
        if retainedDismissedOnboardingWindows.contains(where: { $0 === candidate }) {
            return true
        }
        return false
    }

    // MARK: – Onboarding window

    /// Present onboarding in a standalone centered window, hiding the main tray.
    // INVARIANT: Onboarding must be a standalone NSWindow, not a .sheet() on the tray.
    // The tray is a narrow dock-level window; sheets/covers would render squashed inside it.
    // Follow this same pattern for any future full-screen modal UI.
    func presentOnboarding(store: ClipboardStore) {
        guard onboardingWindow == nil else { return }
        let presentStart = CACurrentMediaTime()
        let onboardingSize = NSSize(width: 1060, height: 720)
        let preferredScreen = preferredScreenForOnboarding()

        // Hide main tray if it's already visible
        window?.orderOut(nil)

        // Show cinematic theater mode dimming
        if theaterModeWindow == nil, let targetScreen = preferredScreen {
            let theaterWin = BorderlessKeyWindow(
                contentRect: targetScreen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            
            // Create a vibrant dark blurred background
            let visualEffect = NSVisualEffectView(frame: NSRect(origin: .zero, size: targetScreen.frame.size))
            visualEffect.material = .hudWindow
            visualEffect.blendingMode = .behindWindow
            visualEffect.state = .active
            visualEffect.appearance = NSAppearance(named: .vibrantDark)
            
            // Add a dark overlay to dim it further
            let dimmingLayer = CALayer()
            dimmingLayer.backgroundColor = NSColor.black.withAlphaComponent(0.4).cgColor
            visualEffect.wantsLayer = true
            visualEffect.layer?.addSublayer(dimmingLayer)
            dimmingLayer.frame = visualEffect.bounds
            
            theaterWin.contentView = visualEffect
            theaterWin.isReleasedWhenClosed = false
            theaterWin.backgroundColor = .clear
            theaterWin.isOpaque = false
            theaterWin.hasShadow = false
            theaterWin.ignoresMouseEvents = true
            
            // Place it just below the onboarding window (which is elevated)
            theaterWin.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.normalWindow)) + 1)
            theaterWin.collectionBehavior = [.moveToActiveSpace, .stationary, .ignoresCycle]
            
            theaterWin.alphaValue = 0
            theaterWin.makeKeyAndOrderFront(nil)
            
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.6
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                theaterWin.animator().alphaValue = 1.0
            }
            
            theaterModeWindow = theaterWin
        }

        let onboardingView = OnboardingView()
            .environmentObject(store)
            .environment(\.locale, store.preferredAppLocale)

        let hostingView = NSHostingView(rootView: onboardingView)
        hostingView.frame = NSRect(origin: .zero, size: onboardingSize)

        let win = BorderlessKeyWindow(
            contentRect: NSRect(origin: .zero, size: onboardingSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.contentView = hostingView
        win.isReleasedWhenClosed = false
        win.isMovableByWindowBackground = true
        win.backgroundColor = NSColor(white: 0.08, alpha: 1)
        win.hasShadow = true
        win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.normalWindow)) + 2)
        win.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        win.hidesOnDeactivate = false
        // Lock window size — prevent NSHostingView auto-resize during SwiftUI transitions
        win.contentMinSize = onboardingSize
        win.contentMaxSize = onboardingSize
        win.updateConstraintsIfNeeded()
        win.setContentSize(onboardingSize)
        if let targetScreen = preferredScreen {
            centerWindow(win, on: targetScreen, size: onboardingSize)
            logLifecycle(
                "presentOnboarding initial placement screen=\(targetScreen.localizedName) "
                    + "screenFrame=\(targetScreen.frame.debugDescription) "
                    + "windowFrame=\(win.frame.debugDescription)"
            )
        } else {
            win.center()
            logLifecycle("presentOnboarding initial placement using win.center() windowFrame=\(win.frame.debugDescription)")
        }

        onboardingWindow = win
        activateAppAndWindow(win, context: "present-onboarding", forceAppActivation: true)
        startOnboardingMusic()
        DispatchQueue.main.async { [weak self, weak win] in
            guard let self, let win else { return }
            win.updateConstraintsIfNeeded()
            win.setContentSize(onboardingSize)
            if let targetScreen = preferredScreen ?? self.preferredScreenForOnboarding() {
                self.centerWindow(win, on: targetScreen, size: onboardingSize)
                self.logLifecycle(
                    "presentOnboarding async recenter screen=\(targetScreen.localizedName) "
                        + "windowFrame=\(win.frame.debugDescription)"
                )
            } else {
                win.center()
                self.logLifecycle("presentOnboarding async recenter using win.center() windowFrame=\(win.frame.debugDescription)")
            }
            self.activateAppAndWindow(win, context: "present-onboarding-async", forceAppActivation: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self, weak win] in
                guard let self, let win else { return }
                win.setContentSize(onboardingSize)
                if let targetScreen = preferredScreen ?? self.preferredScreenForOnboarding() {
                    self.centerWindow(win, on: targetScreen, size: onboardingSize)
                    self.logLifecycle(
                        "presentOnboarding delayed recenter screen=\(targetScreen.localizedName) "
                            + "windowFrame=\(win.frame.debugDescription)"
                    )
                } else {
                    win.center()
                    self.logLifecycle("presentOnboarding delayed recenter using win.center() windowFrame=\(win.frame.debugDescription)")
                }
            }
        }

        logLifecycle("presentOnboarding centered window")
        logPerf("presentOnboarding duration=\(elapsedMillis(since: presentStart))ms windowNumber=\(win.windowNumber)")
    }

    /// Close the onboarding window and reveal the main tray.
    // MARK: - Force Update Window

    /// Present a blocking force-update window. Hides all other Jack windows.
    func presentForceUpdate(latestVersion: String, message: String, updateURL: String) {
        guard forceUpdateWindow == nil else { return }

        let size = NSSize(width: 460, height: 340)
        let view = ForceUpdateView(
            latestVersion: latestVersion,
            message: message,
            updateURL: updateURL
        )

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: size)

        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.contentView = hostingView
        win.isReleasedWhenClosed = false
        win.isMovableByWindowBackground = true
        win.backgroundColor = .clear
        win.isOpaque = false
        win.hasShadow = true
        win.level = .floating
        win.center()

        // Hide any other Jack windows
        window?.orderOut(nil)
        for (_, modeWin) in modeWindows {
            modeWin.orderOut(nil)
        }

        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        forceUpdateWindow = win
    }

    func dismissOnboarding() {
        stopOnboardingMusic()

        guard onboardingDismissInFlight == false else {
            logLifecycle("dismissOnboarding ignored (already in flight)")
            return
        }
        guard let onboardingWindow else {
            logLifecycle("dismissOnboarding ignored (no onboarding window)")
            return
        }

        // Hide any mode preview that was shown during onboarding style step
        hideOnboardingPreview()

        if let theaterWin = self.theaterModeWindow {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.4
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                theaterWin.animator().alphaValue = 0
            } completionHandler: {
                MainActor.assumeIsolated {
                    theaterWin.orderOut(nil)
                }
            }
            self.theaterModeWindow = nil
        }

        onboardingDismissInFlight = true
        let dismissStart = CACurrentMediaTime()
        let onboardingWindowNumber = onboardingWindow.windowNumber
        logLifecycle("dismissOnboarding requested windowNumber=\(onboardingWindowNumber)")

        // Avoid tearing down the hosting hierarchy immediately. We keep a retained
        // hidden onboarding window for this app session to sidestep release-time crashes.
        onboardingWindow.makeFirstResponder(nil)
        onboardingWindow.orderOut(nil)
        retainedDismissedOnboardingWindows.append(onboardingWindow)
        logLifecycle("dismissOnboarding retained hidden window count=\(retainedDismissedOnboardingWindows.count)")

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onboardingWindow = nil
            self.onboardingDismissInFlight = false
            self.logLifecycle("dismissOnboarding completed windowNumber=\(onboardingWindowNumber)")
            self.logPerf("dismissOnboarding transition duration=\(self.elapsedMillis(since: dismissStart))ms")

            guard let window = self.window else {
                self.logLifecycle("dismissOnboarding complete with no bound tray window")
                return
            }

            self.previousApp = NSWorkspace.shared.runningApplications.first {
                $0.isActive && $0.bundleIdentifier != Bundle.main.bundleIdentifier
            }

            // Show the correct window based on the active view mode.
            // If the user selected a non-tray mode during onboarding, show that instead.
            if self.activeViewMode == .tray {
                self.skipNextShowAnimation = true
                self.show(window: window, trace: self.makeTrace(source: "onboarding-dismiss"))
            } else if let modeWindow = self.modeWindows[self.activeViewMode] {
                self.showModeWindow(modeWindow, trace: self.makeTrace(source: "onboarding-dismiss"))
            } else {
                // Fallback: show tray if mode window doesn't exist yet
                self.skipNextShowAnimation = true
                self.show(window: window, trace: self.makeTrace(source: "onboarding-dismiss"))
            }
        }
    }

    private func startOnboardingMusic() {
        onboardingMusicFadeTask?.cancel()
        onboardingMusicFadeTask = nil

        guard onboardingMusicPlayer == nil else {
            onboardingMusicPlayer?.volume = OnboardingMusic.defaultVolume
            onboardingMusicPlayer?.play()
            return
        }

        guard let musicURL = AppResourceLocator.url(
            forResource: OnboardingMusic.fileName,
            withExtension: OnboardingMusic.fileExtension,
            subdirectory: "Resources"
        ) else {
            logLifecycle(
                "onboardingMusic missing resource="
                    + "\(OnboardingMusic.fileName).\(OnboardingMusic.fileExtension)"
            )
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: musicURL)
            player.numberOfLoops = -1
            player.volume = OnboardingMusic.defaultVolume
            player.prepareToPlay()
            guard player.play() else {
                logLifecycle("onboardingMusic failed to begin playback")
                return
            }
            onboardingMusicPlayer = player
            logLifecycle("onboardingMusic playback started")
        } catch {
            logLifecycle("onboardingMusic failed error=\(error.localizedDescription)")
        }
    }

    private func stopOnboardingMusic() {
        guard let player = onboardingMusicPlayer else { return }
        onboardingMusicFadeTask?.cancel()

        let startVolume = player.volume
        onboardingMusicFadeTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let stepCount = max(1, OnboardingMusic.fadeOutSteps)
            let stepDuration = OnboardingMusic.fadeOutDurationNanoseconds / UInt64(stepCount)

            for step in 1...stepCount {
                if Task.isCancelled { return }
                let progress = Double(step) / Double(stepCount)
                player.volume = Self.onboardingMusicFadeVolume(
                    startVolume: startVolume,
                    progress: progress
                )
                try? await Task.sleep(nanoseconds: stepDuration)
            }

            if Task.isCancelled { return }
            player.stop()
            player.currentTime = 0
            self.onboardingMusicPlayer = nil
            self.onboardingMusicFadeTask = nil
            self.logLifecycle("onboardingMusic playback faded out and stopped")
        }
    }

    static func onboardingMusicFadeVolume(startVolume: Float, progress: Double) -> Float {
        let clampedProgress = min(max(progress, 0), 1)
        return max(0, startVolume * Float(1 - clampedProgress))
    }

    func setShelfHeight(_ newHeight: CGFloat, animated: Bool) {
        // Round to whole points to eliminate subpixel jitter
        let clamped = round(clampHeight(newHeight))
        guard clamped != shelfHeight else { return }
        shelfHeight = clamped
        guard let window else { return }

        let frame = targetFrame()
        if isInteractiveResizing || animated == false {
            window.setFrame(frame, display: true, animate: false)
            return
        }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrame(frame, display: true)
            }
        }
    }

    func beginInteractiveResize() {
        guard isAnimating == false else { return }
        isInteractiveResizing = true
        logResize("beginInteractiveResize shelfHeight=\(shelfHeight)")
    }

    func endInteractiveResize() {
        isInteractiveResizing = false
        guard let window else { return }
        let finalHeight = round(clampHeight(window.frame.height))
        shelfHeight = finalHeight
        window.setFrame(targetFrame(), display: true, animate: false)
        logResize("endInteractiveResize frameHeight=\(window.frame.height) syncedShelfHeight=\(shelfHeight)")
    }

    func snapShelfHeight() {
        let midpoint = (collapsedHeight + expandedHeight) / 2
        let snapped = shelfHeight > midpoint ? expandedHeight : collapsedHeight
        setShelfHeight(snapped, animated: true)
    }

    private func configureWindow(_ window: NSWindow) {
        window.styleMask.insert(.titled)
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbar = nil
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = Self.modeWindowLevel
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.styleMask.remove(.resizable)
        window.isMovable = false
        window.isMovableByWindowBackground = false
        window.hidesOnDeactivate = false
        window.preservesContentDuringLiveResize = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        logLifecycle(
            "configureWindow canBecomeMain=\(window.canBecomeMain) canBecomeKey=\(window.canBecomeKey) level=\(window.level.rawValue)"
        )
    }

    private func placeWindowAtBottom(_ window: NSWindow) {
        window.setFrame(targetFrame(), display: true)
    }

    private func targetFrame() -> NSRect {
        let screen: NSScreen?
        if let w = window, w.isVisible {
            // Window is on-screen (resize / hide) — stay on its current monitor
            screen = w.screen ?? activeScreenForPointer() ?? NSScreen.main
        } else {
            // Window is about to appear — open on whichever monitor has the cursor
            screen = activeScreenForPointer() ?? window?.screen ?? NSScreen.main
        }
        guard let screen else { return .zero }

        let full = screen.frame
        let width = full.width
        let originX = full.minX
        let originY = full.minY

        return NSRect(x: originX, y: originY, width: width, height: shelfHeight)
    }

    private func activeScreenForPointer() -> NSScreen? {
        let mousePoint = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mousePoint) })
    }

    private func preferredScreenForOnboarding() -> NSScreen? {
        if let trayScreen = window?.screen {
            return trayScreen
        }
        if let keyScreen = NSApp.keyWindow?.screen {
            return keyScreen
        }
        if let pointerScreen = activeScreenForPointer() {
            return pointerScreen
        }
        if let mainScreen = NSScreen.main {
            return mainScreen
        }
        return NSScreen.screens.first
    }

    private func centerWindow(_ window: NSWindow, on screen: NSScreen, size: NSSize) {
        let frame = screen.frame
        let origin = NSPoint(
            x: round(frame.midX - size.width / 2),
            y: round(frame.midY - size.height / 2)
        )
        window.setFrameOrigin(origin)
    }

    // MARK: – Manual frame-driven animation for buttery smooth slide

    private var displayLink: CVDisplayLink?
    private var animationStartTime: CFTimeInterval = 0
    private var animationDuration: CFTimeInterval = 0
    private var animationFromFrame: NSRect = .zero
    private var animationToFrame: NSRect = .zero
    private var animationFromAlpha: CGFloat = 0
    private var animationToAlpha: CGFloat = 1
    private var animationCompletion: (() -> Void)?
    private var animationIsShow = true
    private var animationLabel = "unknown"
    private var animationFrameCount = 0
    private var animationTrace: ToggleTrace?
    private var animationFirstFrameLogged = false
    private var animationLastFrameTimestamp: CFTimeInterval?
    private var animationFrameDeltaMinMs = Double.greatestFiniteMagnitude
    private var animationFrameDeltaMaxMs = 0.0
    private var animationFrameDeltaSumMs = 0.0
    private var animationFrameDeltaSamples = 0
    private var animationDroppedFrameCount = 0
    /// The window currently being animated (may differ from self.window for non-tray modes).
    private weak var animationWindow: NSWindow?

    nonisolated private func enqueueDisplayLinkTick() {
        let shouldSchedule = animationTickCoalescingQueue.sync { () -> Bool in
            if animationTickScheduled {
                return false
            }
            animationTickScheduled = true
            return true
        }
        guard shouldSchedule else { return }

        DispatchQueue.main.async { @MainActor in
            AppWindowManager.shared.displayLinkTick()
            AppWindowManager.shared.animationTickCoalescingQueue.sync {
                AppWindowManager.shared.animationTickScheduled = false
            }
        }
    }

    /// Cubic bezier easing helper — evaluates y for a given t using control points.
    private func cubicBezier(t: Double, p1x: Double, p1y: Double, p2x: Double, p2y: Double) -> Double {
        // Newton-Raphson to solve for bezier parameter from t (x-axis)
        var guess = t
        for _ in 0..<8 {
            let x = bezierComponent(guess, p1: p1x, p2: p2x) - t
            let dx = bezierDerivative(guess, p1: p1x, p2: p2x)
            guard abs(dx) > 1e-6 else { break }
            guess -= x / dx
        }
        return bezierComponent(guess, p1: p1y, p2: p2y)
    }

    private func bezierComponent(_ t: Double, p1: Double, p2: Double) -> Double {
        let mt = 1 - t
        return 3 * mt * mt * t * p1 + 3 * mt * t * t * p2 + t * t * t
    }

    private func bezierDerivative(_ t: Double, p1: Double, p2: Double) -> Double {
        let mt = 1 - t
        return 3 * mt * mt * p1 + 6 * mt * t * (p2 - p1) + 3 * t * t * (1 - p2)
    }

    /// Smooth deceleration — glides in and decelerates to a stop.
    private func showEase(_ t: Double) -> Double {
        cubicBezier(t: t, p1x: 0.0, p1y: 0.0, p2x: 0.2, p2y: 1.0)
    }

    /// Ease-in for hide — starts at moderate speed and accelerates off-screen.
    /// Paired with an alpha fade (1→0), this masks macOS frame-constraining artifacts
    /// the same way the show's alpha fade (0→1) does.
    private func hideEase(_ t: Double) -> Double {
        cubicBezier(t: t, p1x: 0.4, p1y: 0.0, p2x: 1.0, p2y: 1.0)
    }

    // INVARIANT: Window animations use a manual CVDisplayLink loop, not NSAnimationContext.
    // NSAnimationContext coalesces frames and introduces unpredictable timing; CVDisplayLink
    // fires at display refresh rate for frame-perfect interpolation with custom cubic bezier
    // easing. Do not replace with NSAnimationContext or SwiftUI withAnimation — they produce
    // visible stutter on the dock-level tray window.
    private func startFrameAnimation(
        window: NSWindow,
        from: NSRect,
        to: NSRect,
        fromAlpha: CGFloat,
        toAlpha: CGFloat,
        duration: CFTimeInterval,
        isShow: Bool,
        trace: ToggleTrace,
        completion: @escaping () -> Void
    ) {
        stopDisplayLink()

        if duration <= 0 {
            window.setFrame(to, display: true)
            window.alphaValue = toAlpha
            completion()
            return
        }

        animationWindow = window
        animationTrace = trace
        animationFromFrame = from
        animationToFrame = to
        animationFromAlpha = fromAlpha
        animationToAlpha = toAlpha
        animationDuration = duration
        animationStartTime = CACurrentMediaTime()
        animationIsShow = isShow
        animationLabel = isShow ? "show" : "hide"
        animationFrameCount = 0
        animationFirstFrameLogged = false
        animationLastFrameTimestamp = nil
        animationFrameDeltaMinMs = Double.greatestFiniteMagnitude
        animationFrameDeltaMaxMs = 0
        animationFrameDeltaSumMs = 0
        animationFrameDeltaSamples = 0
        animationDroppedFrameCount = 0
        animationCompletion = completion
        animationTickCoalescingQueue.sync {
            animationTickScheduled = false
        }

        // Avoid forcing a synchronous draw before the first display-link tick.
        window.setFrame(from, display: false)
        window.alphaValue = fromAlpha

        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let link else {
            // Fallback: just jump to final state
            window.setFrame(to, display: true)
            window.alphaValue = toAlpha
            completion()
            return
        }
        displayLink = link

        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, userInfo -> CVReturn in
            _ = userInfo
            AppWindowManager.shared.enqueueDisplayLinkTick()
            return kCVReturnSuccess
        }

        CVDisplayLinkSetOutputCallback(link, callback, nil)
        CVDisplayLinkStart(link)
        logPerf(
            "trace#\(trace.id) animation start label=\(animationLabel) source=\(trace.source) "
                + "duration=\(String(format: "%.2f", duration * 1000))ms "
                + "from=\(from.debugDescription) to=\(to.debugDescription)"
        )
    }

    private func displayLinkTick() {
        guard let window = animationWindow ?? self.window else { stopDisplayLink(); return }
        let now = CACurrentMediaTime()
        animationFrameCount += 1

        if animationFirstFrameLogged == false {
            animationFirstFrameLogged = true
            if let trace = animationTrace {
                let requestToFirstFrame = (now - trace.requestedAt) * 1000
                let animStartToFirstFrame = (now - animationStartTime) * 1000
                logPerf(
                    "trace#\(trace.id) first-frame latency "
                        + "request->frame=\(String(format: "%.2f", requestToFirstFrame))ms "
                        + "animationStart->frame=\(String(format: "%.2f", animStartToFirstFrame))ms "
                        + "label=\(animationLabel)"
                )
            }
        }

        if let last = animationLastFrameTimestamp {
            let deltaMs = (now - last) * 1000
            animationFrameDeltaMinMs = min(animationFrameDeltaMinMs, deltaMs)
            animationFrameDeltaMaxMs = max(animationFrameDeltaMaxMs, deltaMs)
            animationFrameDeltaSumMs += deltaMs
            animationFrameDeltaSamples += 1
            if deltaMs > droppedFrameThresholdMs {
                animationDroppedFrameCount += 1
                if let trace = animationTrace {
                    logPerf(
                        "trace#\(trace.id) frame pacing spike "
                            + "delta=\(String(format: "%.2f", deltaMs))ms "
                            + "threshold=\(String(format: "%.2f", droppedFrameThresholdMs))ms "
                            + "label=\(animationLabel)"
                    )
                }
            }
        }
        animationLastFrameTimestamp = now

        let elapsed = now - animationStartTime
        let rawT = min(elapsed / animationDuration, 1.0)
        let easedT = animationIsShow ? showEase(rawT) : hideEase(rawT)

        let x = animationFromFrame.origin.x + (animationToFrame.origin.x - animationFromFrame.origin.x) * easedT
        let y = animationFromFrame.origin.y + (animationToFrame.origin.y - animationFromFrame.origin.y) * easedT
        let w = animationFromFrame.width
        let h = animationFromFrame.height
        let alpha = animationFromAlpha + (animationToAlpha - animationFromAlpha) * easedT

        window.setFrame(NSRect(x: x, y: y, width: w, height: h), display: false)
        window.alphaValue = alpha

        if rawT >= 1.0 {
            stopDisplayLink()
            window.setFrame(animationToFrame, display: true)
            window.alphaValue = animationToAlpha
            let elapsedMs = elapsed * 1000
            let avgDelta = animationFrameDeltaSamples > 0 ? animationFrameDeltaSumMs / Double(animationFrameDeltaSamples) : 0
            let minDelta = animationFrameDeltaSamples > 0 ? animationFrameDeltaMinMs : 0
            let avgDeltaString = String(format: "%.2f", avgDelta)
            let minDeltaString = String(format: "%.2f", minDelta)
            let maxDeltaString = String(format: "%.2f", animationFrameDeltaMaxMs)
            if let trace = animationTrace {
                logPerf(
                    "trace#\(trace.id) animation complete label=\(animationLabel) "
                        + "frames=\(animationFrameCount) "
                        + "elapsed=\(String(format: "%.2f", elapsedMs))ms "
                        + "target=\(String(format: "%.2f", animationDuration * 1000))ms "
                        + "pacing(avg/min/max)=\(avgDeltaString)/\(minDeltaString)/\(maxDeltaString)ms "
                        + "droppedFrames=\(animationDroppedFrameCount)"
                )
            } else {
                logPerf(
                    "animation complete label=\(animationLabel) frames=\(animationFrameCount) "
                        + "elapsed=\(String(format: "%.2f", elapsedMs))ms "
                        + "target=\(String(format: "%.2f", animationDuration * 1000))ms "
                        + "pacing(avg/min/max)=\(avgDeltaString)/\(minDeltaString)/\(maxDeltaString)ms "
                        + "droppedFrames=\(animationDroppedFrameCount)"
                )
            }
            animationTrace = nil
            animationCompletion?()
            animationCompletion = nil
        }
    }

    private func stopDisplayLink() {
        if let link = displayLink {
            CVDisplayLinkStop(link)
            displayLink = nil
        }
        animationTickCoalescingQueue.sync {
            animationTickScheduled = false
        }
        animationLastFrameTimestamp = nil
    }

    private func show(window: NSWindow, trace: ToggleTrace) {
        let showStart = CACurrentMediaTime()
        window.level = levelForModeWindow(.tray)
        let targetStart = CACurrentMediaTime()
        let target = targetFrame()
        logPerf("trace#\(trace.id) show targetFrame duration=\(elapsedMillis(since: targetStart))ms")

        if skipNextShowAnimation {
            skipNextShowAnimation = false
            stopDisplayLink()
            isAnimating = false
            // Recreate the same off-screen -> frontmost placement sequence used by the
            // normal tray show path. Jumping directly to the final frame while the window
            // is ordered out lets AppKit clamp the tray above the Dock after onboarding.
            let start = NSRect(
                x: target.origin.x,
                y: target.origin.y - target.height,
                width: target.width,
                height: target.height
            )
            window.alphaValue = 0
            window.setFrame(start, display: false)
            prepareWindowForShow(window, trace: trace)
            window.setFrame(target, display: false)
            window.alphaValue = 1
            activateAppAndWindow(window, context: "show-immediate", trace: trace, forceAppActivation: true)
            Self.postTrayDidShowNotifications(window: window)
            logLifecycle("show immediate (post-onboarding) frame=\(window.frame.debugDescription)")
            let requestToVisible = (CACurrentMediaTime() - trace.requestedAt) * 1000
            logPerf(
                "trace#\(trace.id) show immediate total duration=\(elapsedMillis(since: showStart))ms "
                    + "request->complete=\(String(format: "%.2f", requestToVisible))ms"
            )
            logTimeToPopUp(mode: "tray", ms: requestToVisible, source: trace.source)
            Breadcrumb.record("windowShown mode=tray(immediate) \(String(format: "%.0f", requestToVisible))ms")
            return
        }

        // Start fully below the screen edge
        let start = NSRect(x: target.origin.x, y: target.origin.y - target.height, width: target.width, height: target.height)
        logLifecycle("show start target=\(target.debugDescription)")

        isAnimating = true
        window.alphaValue = 0
        window.setFrame(start, display: false)
        let prepareStart = CACurrentMediaTime()
        prepareWindowForShow(window, trace: trace)
        logPerf("trace#\(trace.id) show prepareWindow duration=\(elapsedMillis(since: prepareStart))ms")

        startFrameAnimation(
            window: window,
            from: start,
            to: target,
            fromAlpha: 0,
            toAlpha: 1,
            duration: Self.adjustedAnimationDuration(
                base: showAnimationDuration,
                speed: activeStore?.settings.trayAnimationSpeed ?? 0,
                reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ),
            isShow: true,
            trace: trace
        ) { [weak self] in
            guard let self else { return }
            self.isAnimating = false
            self.activateAppAndWindow(window, context: "show-complete", trace: trace)
            Self.postTrayDidShowNotifications(window: window)
            self.logLifecycle("show complete frame=\(window.frame.debugDescription)")
            let requestToVisible = (CACurrentMediaTime() - trace.requestedAt) * 1000
            self.logPerf(
                "trace#\(trace.id) show total duration=\(self.elapsedMillis(since: showStart))ms "
                    + "request->complete=\(String(format: "%.2f", requestToVisible))ms"
            )
            self.logTimeToPopUp(mode: "tray", ms: requestToVisible, source: trace.source)
            Breadcrumb.record("windowShown mode=tray \(String(format: "%.0f", requestToVisible))ms")
        }
    }

    private func hide(window: NSWindow, trace: ToggleTrace, reason: String) {
        let hideStart = CACurrentMediaTime()
        let from = window.frame
        let targetStart = CACurrentMediaTime()
        let target = targetFrame()
        let end = NSRect(x: target.origin.x, y: target.origin.y - target.height, width: target.width, height: target.height)
        logPerf("trace#\(trace.id) hide targetFrame duration=\(elapsedMillis(since: targetStart))ms reason=\(reason)")
        logLifecycle("hide start from=\(from.debugDescription) target=\(target.debugDescription)")

        isAnimating = true

        startFrameAnimation(
            window: window,
            from: from,
            to: end,
            fromAlpha: 1,
            toAlpha: 0,
            duration: Self.adjustedAnimationDuration(
                base: hideAnimationDuration,
                speed: activeStore?.settings.trayAnimationSpeed ?? 0,
                reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ),
            isShow: false,
            trace: trace
        ) { [weak self] in
            guard let self else { return }
            window.orderOut(nil)
            window.alphaValue = 1
            window.setFrame(target, display: false)
            self.isAnimating = false
            self.logLifecycle("hide complete frame=\(window.frame.debugDescription)")
            self.logPerf(
                "trace#\(trace.id) hide total duration=\(self.elapsedMillis(since: hideStart))ms "
                    + "request->complete=\(String(format: "%.2f", (CACurrentMediaTime() - trace.requestedAt) * 1000))ms "
                    + "reason=\(reason)"
            )
            Breadcrumb.record("windowHidden mode=tray reason=\(reason)")
        }
    }

    // MARK: – Multi-mode window management

    /// Switch the active view mode. Hides any currently visible mode window instantly.
    /// The next `toggleWindow()` call will show the new mode's window.
    func switchMode(to mode: ViewMode, store: ClipboardStore) {
        activeStore = store
        drawerSide = store.settings.drawerSide
        prioritizeActiveModeOverSettings = false
        guard mode != activeViewMode || modeWindows[mode] == nil else { return }
        logLifecycle("switchMode \(activeViewMode.rawValue) -> \(mode.rawValue)")

        // Hide current mode window if visible
        if activeViewMode == .tray {
            if let w = window, w.isVisible {
                w.alphaValue = 0  // Prevent flash if macOS auto-restores the tray
                w.orderOut(nil)
            }
        } else if let w = modeWindows[activeViewMode], w.isVisible {
            w.orderOut(nil)
            removeClickOutsideMonitors()
        }

        activeViewMode = mode

        // Ensure mode window exists for non-tray modes
        if mode != .tray {
            if modeWindows[mode] == nil {
                modeWindows[mode] = createModeWindow(for: mode, store: store)
            }
        }
    }

    /// Preview a mode window during onboarding. Shows the mode window on top
    /// of the onboarding with its natural show animation (slide-up, slide-in, fade),
    /// then auto-dismisses after a brief display so the user can continue choosing.
    func previewModeForOnboarding(mode: ViewMode, store: ClipboardStore) {
        logLifecycle("previewModeForOnboarding mode=\(mode.rawValue)")

        // Cancel any pending auto-dismiss from a previous preview
        onboardingPreviewDismissWork?.cancel()
        onboardingPreviewDismissWork = nil
        onboardingPreviewActive = true

        // Hide any currently previewing mode window instantly
        if activeViewMode != mode {
            if activeViewMode == .tray {
                if let w = window, w.isVisible {
                    stopDisplayLink()
                    isAnimating = false
                    w.orderOut(nil)
                }
            } else if let w = modeWindows[activeViewMode], w.isVisible {
                stopDisplayLink()
                isAnimating = false
                w.orderOut(nil)
            }
        }

        activeViewMode = mode
        drawerSide = store.settings.drawerSide

        // Ensure mode window exists
        if mode != .tray {
            if modeWindows[mode] == nil {
                modeWindows[mode] = createModeWindow(for: mode, store: store)
            }
        }

        let previewWindow: NSWindow? = mode == .tray ? window : modeWindows[mode]
        guard let previewWindow else {
            logLifecycle("previewModeForOnboarding no window for \(mode.rawValue)")
            return
        }

        // Use the real show animation — window appears on top of onboarding
        let trace = makeTrace(source: "onboarding-preview")
        showModeWindow(previewWindow, trace: trace)

        // Auto-dismiss after a brief preview so the user can continue choosing
        let dismissWork = DispatchWorkItem { [weak self] in
            guard let self, self.onboardingPreviewActive else { return }
            self.logLifecycle("onboarding preview auto-dismiss mode=\(mode.rawValue)")

            // Fade out the preview window
            let fadeWindow: NSWindow? = mode == .tray ? self.window : self.modeWindows[mode]
            guard let fadeWindow, fadeWindow.isVisible else { return }

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                fadeWindow.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    fadeWindow.orderOut(nil)
                    fadeWindow.alphaValue = 1
                    // Re-focus onboarding
                    if let onboarding = self?.onboardingWindow, onboarding.isVisible {
                        self?.activateAppAndWindow(onboarding, context: "onboarding-refocus", forceAppActivation: false)
                    }
                }
            }
        }
        onboardingPreviewDismissWork = dismissWork
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: dismissWork)
    }

    /// Toggle the theater blur and onboarding window level for the permissions step.
    /// When `hidden` is true, the blur fades out and the onboarding drops to normal
    /// window level so System Settings can appear in front. When false, restores both.
    func setTheaterBlurHidden(_ hidden: Bool) {
        if hidden {
            // Fade out theater blur
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                theaterModeWindow?.animator().alphaValue = 0
            }
            // Drop onboarding to normal level so System Settings appears on top
            onboardingWindow?.level = .normal
        } else {
            // Fade theater blur back in
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                theaterModeWindow?.animator().alphaValue = 1
            }
            // Restore elevated level
            let normalBase = Int(CGWindowLevelForKey(.normalWindow))
            onboardingWindow?.level = NSWindow.Level(rawValue: normalBase + 2)
            onboardingWindow?.orderFront(nil)
        }
    }

    /// Hide any mode preview window shown during onboarding.
    func hideOnboardingPreview() {
        onboardingPreviewDismissWork?.cancel()
        onboardingPreviewDismissWork = nil
        onboardingPreviewActive = false
        stopDisplayLink()
        isAnimating = false
        removeClickOutsideMonitors()
        if activeViewMode == .tray {
            if let w = window, w.isVisible { w.orderOut(nil) }
        } else if let w = modeWindows[activeViewMode], w.isVisible {
            w.orderOut(nil)
        }
    }

    /// Create a standalone NSWindow hosting the view for the given mode.
    // INVARIANT: Every mode window must inject ClipboardStore as @EnvironmentObject.
    // Views assume store is available via @EnvironmentObject — a missing injection
    // causes a runtime crash with no compile-time warning.
    func createModeWindow(for mode: ViewMode, store: ClipboardStore) -> NSWindow {
        activeStore = store
        drawerSide = store.settings.drawerSide
        let rootView: AnyView
        switch mode {
        case .tray:
            fatalError("Tray uses the SwiftUI WindowGroup window, not a standalone window")
        case .drawer:
            rootView = AnyView(
                SideDrawerView()
                    .environmentObject(store)
            )
        case .panel:
            rootView = AnyView(
                PanelView()
                    .environmentObject(store)
            )
        case .grid:
            rootView = AnyView(
                FloatingGridView()
                    .environmentObject(store)
            )
        case .radial:
            rootView = AnyView(
                RadialMenuView()
                    .environmentObject(store)
            )
        case .workspace:
            rootView = AnyView(
                WorkspaceView()
                    .environmentObject(store)
            )
        }

        let frame = targetFrameForMode(mode)
        let hostingView = NSHostingView(rootView: rootView)

        // Workspace ships with a real .titled style mask so it gets free
        // edge/corner resize hit-testing, native shadow + corner radius, and
        // a real titlebar drag region — same trick Handy uses. A purely
        // borderless window only resizes via a ~3pt hit zone at the visible
        // frame edges, which is what made the drag feel "off." We keep
        // fullSizeContentView so AuricBackground paints behind the titlebar
        // and titleVisibility .hidden so only the traffic lights show.
        let workspaceStyleMask: NSWindow.StyleMask = [
            .titled,
            .closable,
            .miniaturizable,
            .resizable,
            .fullSizeContentView
        ]
        let win = BorderlessKeyWindow(
            contentRect: frame,
            styleMask: mode == .workspace ? workspaceStyleMask : [.borderless],
            backing: .buffered,
            defer: false
        )
        if mode == .workspace {
            win.minSize = Self.workspaceMinimumWindowSize
            win.maxSize = Self.workspaceMaximumWindowSize
            installWorkspaceResizePersistence(for: win, store: store)
            // Hide the title text + separator so the window background flows
            // edge-to-edge. The 28pt titlebar zone stays as a drag region.
            win.titleVisibility = .hidden
            win.titlebarAppearsTransparent = true
            win.titlebarSeparatorStyle = .none
            // Hide the traffic-light cluster. The workspace draws its own
            // rounded card with shadow padding inside the NSWindow frame,
            // so the OS traffic lights end up floating in the transparent
            // shadow-padding zone (visually detached). The user has the menu
            // bar + Escape + global hotkey to close/minimize this window, so
            // the standard buttons aren't needed. We KEEP `.titled` in the
            // style mask so edge/corner resize hit-testing stays smooth.
            win.standardWindowButton(.closeButton)?.isHidden = true
            win.standardWindowButton(.miniaturizeButton)?.isHidden = true
            win.standardWindowButton(.zoomButton)?.isHidden = true
        }
        win.contentView = hostingView
        win.isReleasedWhenClosed = false
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.hidesOnDeactivate = false
        win.level = levelForModeWindow(mode)
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // No mode window enables background dragging: drawer/panel/grid/workspace
        // host draggable clips, cards, and folder pills, and window-background
        // drags would steal those gestures and move the whole window instead.
        // Borderless NSWindows default isMovableByWindowBackground to false, so
        // only `isMovable` needs configuring. Panel and workspace reposition via
        // a dedicated WindowDragHandle.
        switch mode {
        case .drawer, .radial:
            win.isMovable = false
        case .panel, .workspace:
            win.isMovable = true
        case .grid, .tray:
            break
        }

        logLifecycle("createModeWindow mode=\(mode.rawValue) frame=\(frame.debugDescription)")
        return win
    }

    /// Compute the target frame for a mode window on the active screen.
    func targetFrameForMode(_ mode: ViewMode) -> NSRect {
        // No screen at all (e.g. headless/all-displays-asleep) is not survivable for
        // window placement — fall back to a sane centered default instead of crashing.
        guard let screen = activeScreenForPointer() ?? NSScreen.main ?? NSScreen.screens.first else {
            return NSRect(x: 0, y: 0, width: 580, height: 500)
        }
        let full = screen.frame
        let visible = screen.visibleFrame

        switch mode {
        case .tray:
            return targetFrame()

        case .drawer:
            let width = drawerWidth
            let height = visible.maxY - full.minY
            let x = drawerSide == .left ? full.minX : full.maxX - width
            let y = full.minY
            return NSRect(x: x, y: y, width: width, height: height)

        case .grid:
            let width: CGFloat = 580
            let height: CGFloat = 500
            let x = full.midX - width / 2
            let y = full.midY - height / 2
            return NSRect(x: x, y: y, width: width, height: height)

        case .panel:
            let settings = activeStore?.settings
            let width = CGFloat(settings?.panelWidth ?? 320)
            let height = CGFloat(settings?.panelHeight ?? 520)
            let followCursor = settings?.panelFollowsCursor ?? true
            let origin: (x: CGFloat, y: CGFloat)
            if followCursor {
                // Windows-style: panel's top-left sits just below-right of the cursor tip,
                // so the pointer is visually adjacent to the top-left corner.
                // macOS screen y grows upward, so "below cursor" = smaller y.
                let mouse = NSEvent.mouseLocation
                let cursorOffset: CGFloat = 6
                origin = (mouse.x + cursorOffset, mouse.y - height - cursorOffset)
            } else {
                origin = (visible.midX - width / 2, visible.midY - height / 2)
            }
            // Keep the whole panel on-screen with a small inset.
            let margin: CGFloat = 12
            let clampedX = min(max(origin.x, visible.minX + margin), visible.maxX - width - margin)
            let clampedY = min(max(origin.y, visible.minY + margin), visible.maxY - height - margin)
            return NSRect(x: clampedX, y: clampedY, width: width, height: height)

        case .radial:
            let width = radialSize
            let height = radialSize + radialFolderBarHeight
            let mouse = NSEvent.mouseLocation
            // Clamp to screen edges
            let x = min(max(mouse.x - width / 2, full.minX + 10), full.maxX - width - 10)
            let y = min(max(mouse.y - height / 2, full.minY + 10), full.maxY - height - 10)
            return NSRect(x: x, y: y, width: width, height: height)
        case .workspace:
            let preferredWidth = activeStore?.settings.workspaceWindowWidth ?? 1240
            let preferredHeight = activeStore?.settings.workspaceWindowHeight ?? 760
            return Self.workspaceFrame(
                preferredWidth: preferredWidth,
                preferredHeight: preferredHeight,
                visibleFrame: visible
            )
        }
    }

    /// Show a mode-specific window with per-mode animation.
    private func showModeWindow(_ window: NSWindow, trace: ToggleTrace) {
        switch activeViewMode {
        case .tray:
            show(window: window, trace: trace)

        case .drawer:
            let showStart = CACurrentMediaTime()
            let target = targetFrameForMode(.drawer)
            let startX = drawerSide == .left ? target.minX - target.width : target.maxX
            let start = NSRect(x: startX, y: target.minY, width: target.width, height: target.height)

            window.level = levelForModeWindow(.drawer)
            isAnimating = true
            window.alphaValue = 0
            window.setFrame(start, display: false)
            prepareWindowForShow(window, trace: trace)

            startFrameAnimation(
                window: window,
                from: start,
                to: target,
                fromAlpha: 0,
                toAlpha: 1,
                duration: showAnimationDuration,
                isShow: true,
                trace: trace
            ) { [weak self] in
                guard let self else { return }
                self.isAnimating = false
                self.activateAppAndWindow(window, context: "drawer-show-complete", trace: trace)
                NotificationCenter.default.post(name: .requestSearchFocus, object: nil)
                self.logLifecycle("drawer show complete frame=\(window.frame.debugDescription)")
                let requestToVisible = (CACurrentMediaTime() - trace.requestedAt) * 1000
                self.logPerf("trace#\(trace.id) drawer show total=\(self.elapsedMillis(since: showStart))ms")
                self.logTimeToPopUp(mode: "drawer", ms: requestToVisible, source: trace.source)
                Breadcrumb.record("windowShown mode=drawer \(String(format: "%.0f", requestToVisible))ms")
            }

        case .grid:
            let showStart = CACurrentMediaTime()
            let target = targetFrameForMode(.grid)

            window.level = levelForModeWindow(.grid)
            isAnimating = true
            window.setFrame(target, display: false)
            window.alphaValue = 0
            prepareWindowForShow(window, trace: trace)

            startFrameAnimation(
                window: window,
                from: target,
                to: target,
                fromAlpha: 0,
                toAlpha: 1,
                duration: 0.20,
                isShow: true,
                trace: trace
            ) { [weak self] in
                guard let self else { return }
                self.isAnimating = false
                window.alphaValue = 1
                self.activateAppAndWindow(window, context: "grid-show-complete", trace: trace)
                self.installClickOutsideMonitors(for: window)
                NotificationCenter.default.post(name: .requestSearchFocus, object: nil)
                let requestToVisible = (CACurrentMediaTime() - trace.requestedAt) * 1000
                self.logPerf("trace#\(trace.id) grid show total=\(self.elapsedMillis(since: showStart))ms")
                self.logTimeToPopUp(mode: "grid", ms: requestToVisible, source: trace.source)
                Breadcrumb.record("windowShown mode=grid \(String(format: "%.0f", requestToVisible))ms")
            }

        case .panel:
            // Panel recalculates its frame on every reveal so `panelFollowsCursor`
            // repositions at the current mouse location (frozen for the session).
            let showStart = CACurrentMediaTime()
            let target = targetFrameForMode(.panel)

            window.level = levelForModeWindow(.panel)
            isAnimating = true
            window.setFrame(target, display: false)
            window.alphaValue = 0
            prepareWindowForShow(window, trace: trace)

            startFrameAnimation(
                window: window,
                from: target,
                to: target,
                fromAlpha: 0,
                toAlpha: 1,
                duration: 0.18,
                isShow: true,
                trace: trace
            ) { [weak self] in
                guard let self else { return }
                self.isAnimating = false
                window.alphaValue = 1
                self.activateAppAndWindow(window, context: "panel-show-complete", trace: trace)
                self.installClickOutsideMonitors(for: window)
                NotificationCenter.default.post(name: .requestSearchFocus, object: nil)
                let requestToVisible = (CACurrentMediaTime() - trace.requestedAt) * 1000
                self.logPerf("trace#\(trace.id) panel show total=\(self.elapsedMillis(since: showStart))ms")
                self.logTimeToPopUp(mode: "panel", ms: requestToVisible, source: trace.source)
                Breadcrumb.record("windowShown mode=panel \(String(format: "%.0f", requestToVisible))ms")
            }

        case .radial:
            let showStart = CACurrentMediaTime()
            let target = targetFrameForMode(.radial)

            window.level = levelForModeWindow(.radial)
            isAnimating = true
            window.setFrame(target, display: false)
            window.alphaValue = 0
            prepareWindowForShow(window, trace: trace)

            startFrameAnimation(
                window: window,
                from: target,
                to: target,
                fromAlpha: 0,
                toAlpha: 1,
                duration: 0.15,
                isShow: true,
                trace: trace
            ) { [weak self] in
                guard let self else { return }
                self.isAnimating = false
                window.alphaValue = 1
                self.activateAppAndWindow(window, context: "radial-show-complete", trace: trace)
                self.installClickOutsideMonitors(for: window)
                NotificationCenter.default.post(name: .requestSearchFocus, object: nil)
                let requestToVisible = (CACurrentMediaTime() - trace.requestedAt) * 1000
                self.logPerf("trace#\(trace.id) radial show total=\(self.elapsedMillis(since: showStart))ms")
                self.logTimeToPopUp(mode: "radial", ms: requestToVisible, source: trace.source)
                Breadcrumb.record("windowShown mode=radial \(String(format: "%.0f", requestToVisible))ms")
            }
        case .workspace:
            Analytics.workspaceOpened()
            let showStart = CACurrentMediaTime()
            let target = targetFrameForMode(.workspace)

            window.level = levelForModeWindow(.workspace)
            isAnimating = true
            window.setFrame(target, display: false)
            window.alphaValue = 0
            prepareWindowForShow(window, trace: trace)

            startFrameAnimation(
                window: window,
                from: target,
                to: target,
                fromAlpha: 0,
                toAlpha: 1,
                duration: 0.22,
                isShow: true,
                trace: trace
            ) { [weak self] in
                guard let self else { return }
                self.isAnimating = false
                window.alphaValue = 1
                self.activateAppAndWindow(window, context: "workspace-show-complete", trace: trace)
                let requestToVisible = (CACurrentMediaTime() - trace.requestedAt) * 1000
                self.logPerf("trace#\(trace.id) workspace show total=\(self.elapsedMillis(since: showStart))ms")
                self.logTimeToPopUp(mode: "workspace", ms: requestToVisible, source: trace.source)
            }
        }
    }

    /// Hide a mode-specific window with per-mode animation.
    private func hideModeWindow(
        _ window: NSWindow,
        trace: ToggleTrace,
        reason: String
    ) {
        removeClickOutsideMonitors()

        switch activeViewMode {
        case .tray:
            hide(window: window, trace: trace, reason: reason)

        case .drawer:
            let hideStart = CACurrentMediaTime()
            let from = window.frame
            let endX = drawerSide == .left ? from.minX - from.width : from.maxX
            let end = NSRect(x: endX, y: from.minY, width: from.width, height: from.height)

            isAnimating = true
            startFrameAnimation(
                window: window,
                from: from,
                to: end,
                fromAlpha: 1,
                toAlpha: 0,
                duration: hideAnimationDuration,
                isShow: false,
                trace: trace
            ) { [weak self] in
                guard let self else { return }
                window.orderOut(nil)
                window.alphaValue = 1
                self.isAnimating = false
                self.logPerf("trace#\(trace.id) drawer hide total=\(self.elapsedMillis(since: hideStart))ms reason=\(reason)")
                Breadcrumb.record("windowHidden mode=drawer reason=\(reason)")
            }

        case .grid, .panel, .radial, .workspace:
            let hideStart = CACurrentMediaTime()
            let label: String
            let duration: CFTimeInterval
            switch activeViewMode {
            case .grid:
                label = "grid"
                duration = 0.15
            case .panel:
                label = "panel"
                duration = 0.14
            case .radial:
                label = "radial"
                duration = 0.12
            case .workspace:
                label = "workspace"
                duration = 0.18
            case .tray, .drawer:
                label = "window"
                duration = 0.15
            }

            isAnimating = true

            startFrameAnimation(
                window: window,
                from: window.frame,
                to: window.frame,
                fromAlpha: 1,
                toAlpha: 0,
                duration: duration,
                isShow: false,
                trace: trace
            ) { [weak self] in
                guard let self else { return }
                window.orderOut(nil)
                window.alphaValue = 1
                self.isAnimating = false
                self.logPerf("trace#\(trace.id) \(label) hide total=\(self.elapsedMillis(since: hideStart))ms reason=\(reason)")
                Breadcrumb.record("windowHidden mode=\(label) reason=\(reason)")
            }
        }
    }

    /// Set the drawer width during interactive resize.
    func setDrawerWidth(_ width: CGFloat, animated: Bool = false) {
        let clamped = min(max(width, 220), 500)
        guard clamped != drawerWidth else { return }
        drawerWidth = clamped
        guard let win = modeWindows[.drawer], win.isVisible else { return }
        let frame = targetFrameForMode(.drawer)
        win.setFrame(frame, display: true, animate: animated)
    }

    /// Apply new panel dimensions live while the panel window is visible.
    /// Settings sliders call this so the user can see size changes immediately.
    func setPanelSize(animated: Bool = false) {
        guard let win = modeWindows[.panel], win.isVisible else { return }
        let frame = targetFrameForMode(.panel)
        win.setFrame(frame, display: true, animate: animated)
    }

    /// Set the radial size during scroll-to-resize (clamped 300–600).
    func setRadialSize(_ size: CGFloat) {
        let clamped = min(max(size, 300), 600)
        guard clamped != radialSize else { return }
        radialSize = clamped
        NotificationCenter.default.post(name: .radialSizeDidChange, object: clamped)
        guard let win = modeWindows[.radial], win.isVisible else { return }
        let frame = targetFrameForMode(.radial)
        win.setFrame(frame, display: true, animate: false)
    }

    /// Set the drawer side (left or right) and reposition if visible.
    func setDrawerSide(_ side: DrawerSide, store: ClipboardStore, animated: Bool = true) {
        drawerSide = side
        if modeWindows[.drawer] == nil {
            modeWindows[.drawer] = createModeWindow(for: .drawer, store: store)
        }
        guard let win = modeWindows[.drawer], win.isVisible else { return }
        win.setFrame(targetFrameForMode(.drawer), display: true, animate: animated && !isAnimating)
    }

    // MARK: – Click-outside dismiss (grid / radial)

    private func installClickOutsideMonitors(for window: NSWindow) {
        guard !onboardingPreviewActive else {
            logLifecycle("skip clickOutsideMonitors (onboarding preview active)")
            return
        }
        guard Self.shouldInstallClickOutsideMonitors(settingsPreviewActive: settingsPreviewActive) else {
            logLifecycle("skip clickOutsideMonitors (settings preview active)")
            return
        }

        removeClickOutsideMonitors()

        clickOutsideGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self, !self.isAnimating, !self.settingsPreviewActive else { return }
                let clickPoint = NSEvent.mouseLocation
                if !window.frame.contains(clickPoint) {
                    self.hideModeWindow(window, trace: self.makeTrace(source: "click-outside-global"), reason: "click-outside")
                }
            }
        }

        clickOutsideLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self, !self.isAnimating, !self.settingsPreviewActive else { return event }
            let clickPoint = NSEvent.mouseLocation
            if !window.frame.contains(clickPoint) {
                self.hideModeWindow(window, trace: self.makeTrace(source: "click-outside-local"), reason: "click-outside")
            }
            return event
        }

        logLifecycle("installClickOutsideMonitors for mode=\(activeViewMode.rawValue)")
    }

    private func removeClickOutsideMonitors() {
        if let monitor = clickOutsideGlobalMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideGlobalMonitor = nil
        }
        if let monitor = clickOutsideLocalMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideLocalMonitor = nil
        }
    }

    /// Recreate the mode window when the store changes (e.g., after view mode switch)
    func recreateModeWindow(for mode: ViewMode, store: ClipboardStore) {
        guard mode != .tray else { return }
        if let existing = modeWindows[mode] {
            existing.orderOut(nil)
        }
        if mode == .workspace, let observer = workspaceResizeObserver {
            NotificationCenter.default.removeObserver(observer)
            workspaceResizeObserver = nil
        }
        modeWindows[mode] = createModeWindow(for: mode, store: store)
        logLifecycle("recreateModeWindow mode=\(mode.rawValue)")
    }

    private func installWorkspaceResizePersistence(for window: NSWindow, store: ClipboardStore) {
        if let observer = workspaceResizeObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        // Persist on `didEndLiveResize`, NOT `didResize`. `didResize` fires on
        // every frame — during a user drag, but also during the show/hide
        // slide animation, whose intermediate frames would clobber the saved
        // size and JSON-encode all settings 60x/sec. `didEndLiveResize` fires
        // once at mouse-up and never during a programmatic `setFrame`, so it
        // covers native edge resize cleanly. The custom WorkspaceResizeOverlay
        // handles persist their own end-of-drag via onResizeFinished.
        workspaceResizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didEndLiveResizeNotification,
            object: window,
            queue: .main
        ) { [weak self, weak store] notification in
            guard let resizedWindow = notification.object as? NSWindow else { return }
            Task { @MainActor [weak self, weak store] in
                guard let self, let store else { return }
                self.persistWorkspaceWindowFrame(resizedWindow.frame, on: resizedWindow, store: store)
            }
        }
    }

    private func persistWorkspaceWindowFrame(_ frame: NSRect, on window: NSWindow, store: ClipboardStore) {
        let visibleFrame = window.screen?.visibleFrame
            ?? activeScreenForPointer()?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
            ?? frame
        let clampedSize = Self.clampedWorkspaceWindowSize(
            preferredWidth: frame.width,
            preferredHeight: frame.height,
            visibleFrame: visibleFrame
        )
        guard store.settings.workspaceWindowWidth != clampedSize.width
                || store.settings.workspaceWindowHeight != clampedSize.height else { return }
        store.settings.workspaceWindowWidth = clampedSize.width
        store.settings.workspaceWindowHeight = clampedSize.height
    }

    private func clampHeight(_ value: CGFloat) -> CGFloat {
        min(max(value, minShelfHeight), maxShelfHeight)
    }

    private func logResize(_ message: String) {
        guard resizeDebugLoggingEnabled else { return }
        resizeLogger.debug("\(message, privacy: .public)")
    }

    private func logLifecycle(_ message: String) {
        guard lifecycleDebugLoggingEnabled else { return }
        windowLogger.debug("\(message, privacy: .public)")
    }

    private func logPerf(_ message: String) {
        guard performanceLoggingEnabled else { return }
        performanceLogger.debug("\(message, privacy: .public)")
    }

    /// Dedicated "time to pop up" metric — easy to grep and track over time.
    /// Measures from the moment the hotkey event fired (or toggle was requested)
    /// to the moment the window is fully visible and interactive.
    private func logTimeToPopUp(mode: String, ms: Double, source: String) {
        let msg = "timeToPopUp mode=\(mode) \(String(format: "%.1f", ms))ms source=\(source)"
        performanceLogger.info("\(msg, privacy: .public)")
    }

    private func elapsedMillis(since start: CFTimeInterval) -> String {
        String(format: "%.2f", (CACurrentMediaTime() - start) * 1000)
    }

    private func makeTrace(source: String, requestedAt: CFTimeInterval? = nil) -> ToggleTrace {
        defer { nextTraceID += 1 }
        let now = CACurrentMediaTime()
        return ToggleTrace(
            id: nextTraceID,
            source: source,
            requestedAt: requestedAt ?? now,
            startedAt: now
        )
    }

    private func prepareWindowForShow(_ window: NSWindow, trace: ToggleTrace) {
        let orderFrontStart = CACurrentMediaTime()
        window.orderFrontRegardless()
        logPerf("trace#\(trace.id) prepareWindow orderFront duration=\(elapsedMillis(since: orderFrontStart))ms")
        logPerf("trace#\(trace.id) prepareWindow activation deferred=until-animation-complete")
    }

    private func activateAppAndWindow(
        _ window: NSWindow,
        context: String = "general",
        trace: ToggleTrace? = nil,
        forceAppActivation: Bool = false
    ) {
        let activationStart = CACurrentMediaTime()
        var appActivateDurationMs = 0.0
        if forceAppActivation || NSApp.isActive == false {
            let appActivateStart = CACurrentMediaTime()
            NSApp.activate(ignoringOtherApps: true)
            appActivateDurationMs = (CACurrentMediaTime() - appActivateStart) * 1000
        }
        let orderFrontStart = CACurrentMediaTime()
        window.orderFrontRegardless()
        let orderFrontDurationMs = (CACurrentMediaTime() - orderFrontStart) * 1000
        let makeKeyStart = CACurrentMediaTime()
        var madeKeyWindow = false
        if window.canBecomeKey && window.isKeyWindow == false {
            window.makeKey()
            madeKeyWindow = true
        }
        let makeKeyDurationMs = (CACurrentMediaTime() - makeKeyStart) * 1000
        let totalDurationMs = (CACurrentMediaTime() - activationStart) * 1000

        if let trace {
            logPerf(
                "trace#\(trace.id) activate context=\(context) force=\(forceAppActivation) "
                    + "appActivate=\(String(format: "%.2f", appActivateDurationMs))ms "
                    + "orderFront=\(String(format: "%.2f", orderFrontDurationMs))ms "
                    + "makeKey=\(String(format: "%.2f", makeKeyDurationMs))ms "
                    + "madeKey=\(madeKeyWindow) total=\(String(format: "%.2f", totalDurationMs))ms"
            )
        } else {
            logPerf(
                "activate context=\(context) force=\(forceAppActivation) "
                    + "appActivate=\(String(format: "%.2f", appActivateDurationMs))ms "
                    + "orderFront=\(String(format: "%.2f", orderFrontDurationMs))ms "
                    + "makeKey=\(String(format: "%.2f", makeKeyDurationMs))ms "
                    + "madeKey=\(madeKeyWindow) total=\(String(format: "%.2f", totalDurationMs))ms"
            )
        }

        logLifecycle(
            "activate canBecomeMain=\(window.canBecomeMain) "
                + "canBecomeKey=\(window.canBecomeKey) "
                + "frame=\(window.frame.debugDescription)"
        )
    }
}
