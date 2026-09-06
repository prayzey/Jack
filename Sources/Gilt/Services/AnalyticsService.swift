import Foundation
import TelemetryDeck

/// Lightweight wrapper around TelemetryDeck for Jack analytics.
/// All signals are privacy-first — no personal data, no clipboard content.
enum Analytics {
    static func initialize() {
        let config = TelemetryDeck.Config(appID: "1AFA14EB-9E56-4C47-9520-2B10C84CCCEF")
        TelemetryDeck.initialize(config: config)
    }

    // MARK: - App Lifecycle

    static func appLaunched(viewMode: String) {
        TelemetryDeck.signal("App.launched", parameters: ["viewMode": viewMode])
    }

    // MARK: - Clips

    static func clipCaptured(type: String) {
        TelemetryDeck.signal("Clip.captured", parameters: ["clipType": type])
    }

    static func clipPasted(type: String) {
        TelemetryDeck.signal("Clip.pasted", parameters: ["clipType": type])
    }

    static func clipDeleted() {
        TelemetryDeck.signal("Clip.deleted")
    }

    // MARK: - Folders

    static func folderCreated(totalCount: Int) {
        TelemetryDeck.signal("Folder.created", parameters: ["totalCount": "\(totalCount)"])
    }

    // MARK: - Features

    static func viewModeSwitched(to mode: String) {
        TelemetryDeck.signal("ViewMode.switched", parameters: ["mode": mode])
    }

    static func searchUsed() {
        TelemetryDeck.signal("Search.used")
    }

    static func hotkeyToggled() {
        TelemetryDeck.signal("Hotkey.toggled")
    }

    static func feedbackTapped() {
        TelemetryDeck.signal("Feedback.tapped")
    }

    // MARK: - Dictation & Meetings

    static func dictationCompleted(mode: String, durationSeconds: Double) {
        TelemetryDeck.signal(
            "Dictation.completed",
            parameters: ["mode": mode],
            floatValue: durationSeconds
        )
    }

    static func meetingCompleted(engine: String, durationSeconds: Double, words: Int) {
        TelemetryDeck.signal(
            "Meeting.completed",
            parameters: ["engine": engine, "words": "\(words)"],
            floatValue: durationSeconds
        )
    }

    // MARK: - Notes & Workspace

    static func noteCreated(origin: String) {
        TelemetryDeck.signal("Note.created", parameters: ["origin": origin])
    }

    static func kanbanBoardOpened(totalBoards: Int) {
        TelemetryDeck.signal("Kanban.boardOpened", parameters: ["totalBoards": "\(totalBoards)"])
    }

    static func workspaceOpened() {
        TelemetryDeck.signal("Workspace.opened")
    }

    static func commandPaletteOpened() {
        TelemetryDeck.signal("CommandPalette.opened")
    }

    // MARK: - Funnel

    static func onboardingCompleted(viewMode: String) {
        TelemetryDeck.signal("Onboarding.completed", parameters: ["viewMode": viewMode])
    }

    static func trialStarted() {
        TelemetryDeck.signal("Trial.started")
    }

    static func licenseActivated() {
        TelemetryDeck.signal("License.activated")
    }
}
