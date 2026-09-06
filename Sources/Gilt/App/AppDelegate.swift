import AppKit
import Foundation
import OSLog
import Sentry

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let lifecycleLogger = Logger(subsystem: AppBrand.logSubsystem, category: "AppLifecycle")
    private let loggingEnabled = ProcessInfo.processInfo.environment["GILT_DEBUG_LOGS"] == "1"
    private var launchTimestamp: CFAbsoluteTime = 0
    // Tokens for the NSWorkspace sleep/wake observers. We must retain these so
    // they can be removed on terminate — discarding them leaks the registrations
    // (they stay live in the workspace notification center for the process lifetime).
    private var workspaceObservers: [NSObjectProtocol] = []
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    func applicationDidFinishLaunching(_ notification: Notification) {
        launchTimestamp = CFAbsoluteTimeGetCurrent()
        installCrashLogging()
        Breadcrumb.record("applicationDidFinishLaunching")

        logLifecycle("applicationDidFinishLaunching debugLogs=\(loggingEnabled)")
        BundledFontCatalog.registerBundledFonts()
        QuickNoteFontRegistry.registerAllStoredFonts()

        // Read hideFromDock from persisted settings before ClipboardStore initializes
        let policy: NSApplication.ActivationPolicy
        if let data = UserDefaults.standard.data(forKey: "GiltAppSettings"),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data),
           decoded.hideFromDock {
            policy = .accessory
        } else {
            policy = .regular
        }
        NSApp.setActivationPolicy(policy)
        logLifecycle("activationPolicy=\(policy == .accessory ? ".accessory" : ".regular")")
        logLifecycle("Jack hotkey registration delegated to ClipboardStore")
        setAppIcon()
        installSleepWakeObserver()
        installMemoryPressureMonitor()
        // Register ourselves as the macOS Services provider so the
        // "Send to Jack" entry in any app's right-click → Services menu
        // routes selected text into our menu bar item. The NSMessage name
        // in Info.plist's NSServices entry must match the @objc selector
        // below (`sendToJack:userData:error:`).
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()

        // NSStatusBar is only reliable after finish-launching. Settings are
        // hydrated during ClipboardStore init; this catch-up applies the
        // persisted custom-text menu bar item and Jack presence.
        Task { @MainActor in
            MenuBarTextItemController.shared.finishLaunchSetup()
            AppStoreReferences.shared.clipboardStore?.applyInitialJackPresence()
        }
    }

    /// macOS Services handler. Triggered when the user selects text in any
    /// app and chooses "Send to Jack" from the Services menu (or Share sheet).
    /// The selected string arrives on the pasteboard — we hand it off to the
    /// menu bar controller which sets it as the live custom-text label.
    @objc func sendToJack(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let string = pboard.string(forType: .string), !string.isEmpty else {
            error.pointee = "No text selected." as NSString
            return
        }
        Task { @MainActor in
            MenuBarTextItemController.shared.receiveServiceText(string)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Breadcrumb.record("applicationShouldHandleReopen hasVisible=\(flag)")
        logLifecycle("applicationShouldHandleReopen hasVisible=\(flag) uptime=\(uptimeString)")

        // When clicked from the dock, show the correct mode window instead of
        // letting macOS restore the SwiftUI WindowGroup (tray) by default.
        // This prevents a flash where the tray appears briefly before the
        // active mode window (grid/drawer/radial) is shown.
        let manager = AppWindowManager.shared
        manager.toggleWindow(source: "dock-reopen")
        return false  // We handle it — don't let macOS show the default window
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Breadcrumb.record("appDidBecomeActive")
        logLifecycle("applicationDidBecomeActive uptime=\(uptimeString)")
    }

    func applicationDidResignActive(_ notification: Notification) {
        Breadcrumb.record("appDidResignActive")
        logLifecycle("applicationDidResignActive uptime=\(uptimeString)")
    }

    func applicationDidHide(_ notification: Notification) {
        Breadcrumb.record("appDidHide")
        logLifecycle("applicationDidHide")
    }

    func applicationDidUnhide(_ notification: Notification) {
        Breadcrumb.record("appDidUnhide")
        logLifecycle("applicationDidUnhide")
    }

    @MainActor private func setAppIcon() {
        guard let pngURL = AppResourceLocator.url(forResource: "AppIcon", withExtension: "png", subdirectory: "Resources"),
              let source = NSImage(contentsOf: pngURL) else {
            logLifecycle("App icon not found in Resources")
            return
        }

        // AppIcon.png is normalized to 1024x1024 with 820x820 centered artwork
        // (10% transparent padding). Clip the padded content rect so the Dock
        // shows a proper squircle at the expected visual size — masking the
        // full canvas would render the icon oversized next to native apps.
        let size = NSSize(width: 1024, height: 1024)
        let icon = NSImage(size: size, flipped: false) { rect in
            let contentInset = rect.width * 0.10
            let contentRect = rect.insetBy(dx: contentInset, dy: contentInset)
            let cornerRadius = min(contentRect.width, contentRect.height) * 0.2237
            let path = NSBezierPath(roundedRect: contentRect, xRadius: cornerRadius, yRadius: cornerRadius)
            NSGraphicsContext.current?.shouldAntialias = true
            NSGraphicsContext.current?.imageInterpolation = .high
            path.addClip()
            source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
            return true
        }
        icon.isTemplate = false
        NSApp.applicationIconImage = icon
        logLifecycle("App icon set with native squircle mask")
    }

    func applicationWillTerminate(_ notification: Notification) {
        Breadcrumb.record("applicationWillTerminate")
        logLifecycle("applicationWillTerminate uptime=\(uptimeString)")
        removeWorkspaceObservers()
        memoryPressureSource?.cancel()
        memoryPressureSource = nil
        TrackpadRevealGestureMonitor.shared.stop()
        GlobalHotKeyManager.shared.unregister()
    }

    // MARK: - Crash Logging with Breadcrumbs

    private func installCrashLogging() {
        NSSetUncaughtExceptionHandler { exception in
            let message = """
            [Crash] Uncaught NSException: \(exception.name.rawValue)
            [Crash] CallStack:
            \(exception.callStackSymbols.joined(separator: "\n"))
            """

            // Keep crash diagnostics local and minimal to avoid echoing sensitive
            // runtime state into Console/stdout logs.
            let logDir = AppSupportLocator.giltDirectory().appendingPathComponent("Logs", isDirectory: true)
            try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
            let formatter = ISO8601DateFormatter()
            let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let logFile = logDir.appendingPathComponent("crash-\(timestamp).log")
            try? message.write(to: logFile, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Sleep/Wake Monitoring

    private func installSleepWakeObserver() {
        let center = NSWorkspace.shared.notificationCenter
        let logger = lifecycleLogger
        let enabled = loggingEnabled
        workspaceObservers.append(
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
                Breadcrumb.record("systemWillSleep")
                guard enabled else { return }
                logger.debug("systemWillSleep")
            }
        )
        workspaceObservers.append(
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
                Breadcrumb.record("systemDidWake")
                guard enabled else { return }
                logger.debug("systemDidWake")
            }
        )
        workspaceObservers.append(
            center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { _ in
                guard enabled else { return }
                logger.debug("screensDidSleep")
            }
        )
        workspaceObservers.append(
            center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { _ in
                guard enabled else { return }
                logger.debug("screensDidWake")
            }
        )
    }

    private func removeWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            center.removeObserver(observer)
        }
        workspaceObservers.removeAll()
    }

    // MARK: - Memory Pressure Monitoring

    private func installMemoryPressureMonitor() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            let event = source.data
            let level: String
            let isCritical: Bool
            if event.contains(.critical) {
                level = "CRITICAL"
                isCritical = true
            } else if event.contains(.warning) {
                level = "WARNING"
                isCritical = false
            } else {
                level = "NORMAL"
                isCritical = false
            }
            Breadcrumb.record("memoryPressure level=\(level)")
            self?.logLifecycle("memoryPressure level=\(level) appMemory=\(Self.currentMemoryUsageMB())MB")
            Task { @MainActor in
                ThumbnailService.shared.handleMemoryPressure(isCritical: isCritical)
            }
            Task {
                await LinkMetadataService.shared.handleMemoryPressure(isCritical: isCritical)
            }
            Task {
                await ImageTextRecognitionService.shared.handleMemoryPressure(isCritical: isCritical)
            }
        }
        source.resume()
        memoryPressureSource = source
    }

    // MARK: - Helpers

    private var uptimeString: String {
        let seconds = Int(CFAbsoluteTimeGetCurrent() - launchTimestamp)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return "\(hours)h\(minutes)m\(secs)s"
        } else if minutes > 0 {
            return "\(minutes)m\(secs)s"
        } else {
            return "\(secs)s"
        }
    }

    /// Approximate resident memory of this process in MB
    static func currentMemoryUsageMB() -> String {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            return String(format: "%.1f", Double(info.resident_size) / 1_048_576)
        }
        return "?"
    }

    private func logLifecycle(_ message: String) {
        guard loggingEnabled else { return }
        lifecycleLogger.debug("\(message, privacy: .private(mask: .hash))")
    }
}

// MARK: - Breadcrumb Ring Buffer

/// Thread-safe ring buffer of recent app actions for crash diagnostics.
/// Records the last 50 significant events so the crash handler can dump context
/// about what happened before a crash (since stack traces alone often aren't enough).
///
/// Usage: Call `Breadcrumb.record("description")` at significant checkpoints.
/// Breadcrumbs are forwarded to Sentry so hang/crash reports include the trail.
enum Breadcrumb {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var buffer: [(timestamp: Date, event: String)] = []
    private static let maxEntries = 50

    /// Record a breadcrumb event. Thread-safe, lightweight (no allocation if buffer isn't full).
    /// Also forwards to Sentry so hang/crash reports include the trail of events.
    static func record(_ event: String) {
        lock.lock()
        defer { lock.unlock() }
        if buffer.count >= maxEntries {
            buffer.removeFirst()
        }
        buffer.append((Date(), event))

        // Forward to Sentry for inclusion in hang/crash reports
        let crumb = Sentry.Breadcrumb(level: .info, category: "gilt")
        crumb.message = event
        SentrySDK.addBreadcrumb(crumb)
    }
}
