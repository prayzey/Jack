import AppKit
import Foundation

extension ClipboardStore {
    // MARK: - Environment

    /// Update opacity for real-time visual feedback without persisting to disk.
    func updateBackgroundOpacityLive(_ value: Double) {
        liveBackgroundOpacity = value
    }

    /// Update wallpaper offset for real-time visual feedback without persisting to disk.
    func updateWallpaperOffsetLive(x: Double, y: Double) {
        wallpaperPreview.update(x: x, y: y)
    }

    func commitWallpaperOffsetLive() {
        wallpaperPreview.commit(into: &settings)
    }

    static func clampWallpaperOffset(_ value: Double) -> Double {
        WallpaperOffsets.clamp(value)
    }

    /// Whether onboarding should be presented on this launch.
    var shouldShowOnboarding: Bool {
        settings.alwaysShowOnboarding || !settings.hasCompletedOnboarding
    }

    func completeOnboarding() {
        settings.hasCompletedOnboarding = true
        Analytics.onboardingCompleted(viewMode: settings.viewMode.rawValue)
    }

    var storageFolderURL: URL {
        AppSupportLocator.giltDirectory()
    }

    var storageFolderPath: String {
        storageFolderURL.path
    }

    var storageDatabasePath: String {
        AppSupportLocator.storeFileURL().path
    }

    /// Shared on-disk folder for the Qwen GGUF (meetings, dictation, Jack, Kanban assist).
    var qwenModelCacheURL: URL {
        MeetingAppSupportLocator.summarizationModelFolder(
            engine: .qwen35_4b_q4,
            in: MeetingAppSupportLocator.modelsRoot(
                in: MeetingAppSupportLocator.meetingsRoot()
            )
        )
    }

    func requestAccessibilityPermission() {
        _ = AccessibilityService.requestPrompt()
    }

    func openAccessibilitySettings() {
        AccessibilityService.openSettings()
    }

    func microphonePermissionStatus() -> MicrophonePermissionStatus {
        MicrophonePermissionService.currentStatus()
    }

    func requestMicrophonePermission() async -> Bool {
        await MicrophonePermissionService.requestAccess()
    }

    func openMicrophoneSettings() {
        MicrophonePermissionService.openSettings()
    }

    func screenRecordingPermissionStatus() -> ScreenRecordingPermissionStatus {
        ScreenRecordingPermissionService.currentStatus()
    }

    @discardableResult
    func requestScreenRecordingPermission() -> Bool {
        ScreenRecordingPermissionService.requestAccess()
    }

    func openScreenRecordingSettings() {
        ScreenRecordingPermissionService.openSettings()
    }

    func presentPersistenceIssueIfNeeded() {
        guard let pendingPersistenceIssueMessage, !hasPresentedPersistenceIssue else { return }
        hasPresentedPersistenceIssue = true

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(AppBrand.displayName) Started in Recovery Mode"
        alert.informativeText = pendingPersistenceIssueMessage
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModalInFront()
    }
}
