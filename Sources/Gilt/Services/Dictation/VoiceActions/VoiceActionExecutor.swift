import Foundation
import OSLog

enum VoiceActionResult: Equatable {
    case reminderCreated(title: String)
    case spotify(message: String)
    case permissionDenied(app: String)
    case notRecognized
    case failed(String)
}

/// Runs parsed voice commands against native Mac connectors. Side effects are
/// explicit: reminders always mirror to Apple Reminders when permission allows.
@MainActor
final class VoiceActionExecutor {
    private let log = Logger(subsystem: AppBrand.logSubsystem, category: "VoiceAction")
    private let addReminder: (PulseReminder) -> Void

    init(addReminder: @escaping (PulseReminder) -> Void) {
        self.addReminder = addReminder
    }

    func execute(
        transcript: String,
        connectors: Set<VoiceActionConnector>,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async -> VoiceActionResult {
        let cleaned = TranscriptCleaner
            .clean(transcript)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return .notRecognized }

        if connectors.contains(.reminders),
           let reminderResult = await tryReminder(from: cleaned, now: now, calendar: calendar) {
            return reminderResult
        }

        if connectors.contains(.spotify),
           let command = SpotifyVoiceParser.parse(cleaned) {
            return executeSpotify(command)
        }

        return .notRecognized
    }

    // MARK: - Reminders

    private func tryReminder(
        from transcript: String,
        now: Date,
        calendar: Calendar
    ) async -> VoiceActionResult? {
        guard case .success(let title, let due) = VoiceActionReminderParser.parse(
            transcript,
            now: now,
            calendar: calendar
        ) else {
            return nil
        }

        let ready = await ensureRemindersAccess()
        guard ready else {
            return .permissionDenied(app: "Reminders")
        }

        guard let reminder = JackReminderDraft.makeReminder(
            text: title,
            due: due,
            now: now,
            calendar: calendar
        ) else {
            return .failed("Couldn't build that reminder.")
        }

        addReminder(reminder)
        await RemindersSyncService.shared.mirror(reminder)

        log.info("Voice action created reminder: \(title, privacy: .public)")
        return .reminderCreated(title: title)
    }

    /// Voice actions treat Apple Reminders as first-class: request permission
    /// on first use and turn on sync so the item shows up immediately.
    private func ensureRemindersAccess() async -> Bool {
        if RemindersSyncService.shared.hasAccess {
            if !RemindersSyncService.shared.isSyncEnabled {
                RemindersSyncService.shared.isSyncEnabled = true
            }
            return true
        }
        let granted = await RemindersSyncService.shared.requestAccess()
        if granted {
            RemindersSyncService.shared.isSyncEnabled = true
        }
        return granted
    }

    // MARK: - Spotify

    private func executeSpotify(_ command: SpotifyControlCommand) -> VoiceActionResult {
        switch SpotifyControlService.run(command) {
        case .success(let message):
            return .spotify(message: message)
        case .spotifyNotInstalled:
            return .failed("Install Spotify on your Mac to use playback commands.")
        case .notRunning:
            return .failed("Open Spotify first, then try again.")
        case .scriptFailed(let message):
            return .failed(message)
        }
    }
}