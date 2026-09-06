import Foundation

extension ClipboardStore {
    // MARK: - Diagnostics

    func elapsedMilliseconds(since startedAt: DispatchTime) -> Double {
        let delta = DispatchTime.now().uptimeNanoseconds - startedAt.uptimeNanoseconds
        return Double(delta) / 1_000_000
    }

    func logPerf(
        _ operation: String,
        startedAt: DispatchTime,
        details: String? = nil,
        thresholdMs: Double? = nil
    ) {
        guard stateDebugLoggingEnabled else { return }
        let elapsedMs = elapsedMilliseconds(since: startedAt)
        let threshold = thresholdMs ?? perfSlowOperationThresholdMs
        guard elapsedMs >= threshold else { return }
        let detailsSuffix = details.map { " \($0)" } ?? ""
        logState("perf \(operation) \(String(format: "%.2f", elapsedMs))ms\(detailsSuffix)")
    }

    func shortClipID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }

    func logState(_ message: String) {
        guard stateDebugLoggingEnabled else { return }
        stateLogger.debug("\(message, privacy: .public)")
    }

    func logSettingsDiff(previous: AppSettings, current: AppSettings) {
        guard stateDebugLoggingEnabled else { return }
        if previous.appLanguage != current.appLanguage {
            logState("settings.appLanguage \(previous.appLanguage.rawValue) -> \(current.appLanguage.rawValue)")
        }
        if previous.historyRetention != current.historyRetention {
            logState("settings.historyRetention \(previous.historyRetention.rawValue) -> \(current.historyRetention.rawValue)")
        }
        if previous.alwaysPlainText != current.alwaysPlainText {
            logState("settings.alwaysPlainText \(previous.alwaysPlainText) -> \(current.alwaysPlainText)")
        }
        if previous.pasteToActiveApp != current.pasteToActiveApp {
            logState("settings.pasteToActiveApp \(previous.pasteToActiveApp) -> \(current.pasteToActiveApp)")
        }
        if previous.singleClickToPaste != current.singleClickToPaste {
            logState("settings.singleClickToPaste \(previous.singleClickToPaste) -> \(current.singleClickToPaste)")
        }
        if previous.launchAtLogin != current.launchAtLogin {
            logState("settings.launchAtLogin \(previous.launchAtLogin) -> \(current.launchAtLogin)")
        }
        if previous.showInMenuBar != current.showInMenuBar {
            logState("settings.showInMenuBar \(previous.showInMenuBar) -> \(current.showInMenuBar)")
        }
        if previous.hideFromDock != current.hideFromDock {
            logState("settings.hideFromDock \(previous.hideFromDock) -> \(current.hideFromDock)")
        }
        if previous.globalShortcut != current.globalShortcut {
            logState("settings.globalShortcut \(previous.globalShortcut.displayString) -> \(current.globalShortcut.displayString)")
        }
        if previous.trackpadRevealBottomEdgeSwipeEnabled != current.trackpadRevealBottomEdgeSwipeEnabled {
            logState(
                "settings.trackpadRevealBottomEdgeSwipeEnabled "
                    + "\(previous.trackpadRevealBottomEdgeSwipeEnabled) -> \(current.trackpadRevealBottomEdgeSwipeEnabled)"
            )
        }
        if previous.trackpadRevealBottomCenterSwipeEnabled != current.trackpadRevealBottomCenterSwipeEnabled {
            logState(
                "settings.trackpadRevealBottomCenterSwipeEnabled "
                    + "\(previous.trackpadRevealBottomCenterSwipeEnabled) -> \(current.trackpadRevealBottomCenterSwipeEnabled)"
            )
        }
        if previous.backgroundTheme != current.backgroundTheme {
            logState("settings.backgroundTheme \(previous.backgroundTheme.rawValue) -> \(current.backgroundTheme.rawValue)")
        }
        if previous.backgroundOpacity != current.backgroundOpacity {
            logState("settings.backgroundOpacity \(previous.backgroundOpacity) -> \(current.backgroundOpacity)")
        }
        if previous.backgroundWallpaper != current.backgroundWallpaper {
            logState("settings.backgroundWallpaper \(previous.backgroundWallpaper.rawValue) -> \(current.backgroundWallpaper.rawValue)")
        }
        if previous.hasCompletedOnboarding != current.hasCompletedOnboarding {
            logState("settings.hasCompletedOnboarding \(previous.hasCompletedOnboarding) -> \(current.hasCompletedOnboarding)")
        }
        if previous.alwaysShowOnboarding != current.alwaysShowOnboarding {
            logState("settings.alwaysShowOnboarding \(previous.alwaysShowOnboarding) -> \(current.alwaysShowOnboarding)")
        }
        if previous.viewMode != current.viewMode {
            logState("settings.viewMode \(previous.viewMode.rawValue) -> \(current.viewMode.rawValue)")
        }
        if previous.drawerSide != current.drawerSide {
            logState("settings.drawerSide \(previous.drawerSide.rawValue) -> \(current.drawerSide.rawValue)")
        }
    }

    func startSessionHealthTimer() {
        let timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.dumpSessionHealth()
            }
        }
        timer.tolerance = 10.0
        sessionHealthTimer = timer
    }

    /// Invalidate the repeating maintenance timers so they stop firing and release
    /// their RunLoop scheduling. Called on app termination — without this the
    /// repeating timers keep ticking for the whole process lifetime.
    func stopMaintenanceTimers() {
        sessionHealthTimer?.invalidate()
        sessionHealthTimer = nil
        sensitiveExpiryTimer?.invalidate()
        sensitiveExpiryTimer = nil
    }

    func dumpSessionHealth() {
        guard stateDebugLoggingEnabled else { return }
        let uptime = Int(Date().timeIntervalSince(sessionStartTime))
        let hours = uptime / 3600
        let minutes = (uptime % 3600) / 60
        let secs = uptime % 60
        let uptimeStr = hours > 0 ? "\(hours)h\(minutes)m\(secs)s" : (minutes > 0 ? "\(minutes)m\(secs)s" : "\(secs)s")

        let appMemory = AppDelegate.currentMemoryUsageMB()
        let accessibility = AccessibilityService.isTrusted()
        let imageClipCount = clips.filter { $0.clipType == .image }.count

        let typeBreakdown = sessionIngestByType.sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")

        let healthMsg = """
        session uptime=\(uptimeStr) memory=\(appMemory)MB accessibility=\(accessibility) \
        clips=\(clips.count) folders=\(folders.count) imageClips=\(imageClipCount) \
        ingests=\(sessionIngestCount) [\(typeBreakdown)] \
        copies=\(sessionCopyCount) pastes=\(sessionPasteCount) pasteOK=\(sessionPasteSuccessCount) pasteFail=\(sessionPasteFailCount) \
        searches=\(sessionSearchCount) deletes=\(sessionDeleteCount) \
        saves=\(sessionSaveCount) saveFails=\(sessionSaveFailCount) \
        missingIcons=\(missingIconBundleIDs.count) \
        smartFolders=\(activeSmartFolderIDs.count) inFlightMetadata=\(inFlightLinkMetadataClipIDs.count)
        """
        sessionLogger.info("\(healthMsg, privacy: .public)")
    }
}
