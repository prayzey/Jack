import Foundation

/// File layout helpers for the Meeting feature.
///
/// Mirrors the directory plan in `meeting-notes-local-ai-plan.md`:
/// ```
/// ~/Library/Application Support/Jack/Meetings/
///   models/<engine-id>/
///   sessions/<meeting-id>/
///     meeting.json
///     transcript.jsonl
///     summary.json
///     audio/recording.caf
/// ```
enum MeetingAppSupportLocator {
    private static let rootFolderName = "Meetings"
    private static let modelsFolderName = "models"
    private static let sessionsFolderName = "sessions"
    private static let audioFolderName = "audio"
    private static let audioFileName = "recording.caf"
    private static let meetingFileName = "meeting.json"
    private static let transcriptFileName = "transcript.jsonl"
    private static let summaryFileName = "summary.json"
    private static let askHistoryFileName = "ask-history.json"

    static func meetingsRoot(
        fileManager: FileManager = .default,
        homeDirectory: URL? = nil,
        temporaryDirectory: URL? = nil
    ) -> URL {
        AppSupportLocator
            .giltDirectory(
                fileManager: fileManager,
                homeDirectory: homeDirectory,
                temporaryDirectory: temporaryDirectory
            )
            .appendingPathComponent(rootFolderName, isDirectory: true)
    }

    static func modelsRoot(in meetingsRoot: URL) -> URL {
        meetingsRoot.appendingPathComponent(modelsFolderName, isDirectory: true)
    }

    static func sessionsRoot(in meetingsRoot: URL) -> URL {
        meetingsRoot.appendingPathComponent(sessionsFolderName, isDirectory: true)
    }

    static func sessionFolder(meetingID: UUID, in sessionsRoot: URL) -> URL {
        sessionsRoot.appendingPathComponent(meetingID.uuidString, isDirectory: true)
    }

    static func meetingFile(in sessionFolder: URL) -> URL {
        sessionFolder.appendingPathComponent(meetingFileName)
    }

    static func transcriptFile(in sessionFolder: URL) -> URL {
        sessionFolder.appendingPathComponent(transcriptFileName)
    }

    static func summaryFile(in sessionFolder: URL) -> URL {
        sessionFolder.appendingPathComponent(summaryFileName)
    }

    static func askHistoryFile(in sessionFolder: URL) -> URL {
        sessionFolder.appendingPathComponent(askHistoryFileName)
    }

    static func audioFile(in sessionFolder: URL) -> URL {
        sessionFolder
            .appendingPathComponent(audioFolderName, isDirectory: true)
            .appendingPathComponent(audioFileName)
    }

    static func transcriptionModelFolder(
        engine: MeetingTranscriptionEngine,
        in modelsRoot: URL
    ) -> URL {
        modelsRoot.appendingPathComponent(engine.rawValue, isDirectory: true)
    }

    static func summarizationModelFolder(
        engine: MeetingSummarizationEngine,
        in modelsRoot: URL
    ) -> URL {
        modelsRoot.appendingPathComponent(engine.modelFolderName, isDirectory: true)
    }

    /// Ensures every directory in the layout exists. Safe to call repeatedly.
    @discardableResult
    static func ensureBaseDirectories(
        fileManager: FileManager = .default,
        root: URL? = nil
    ) -> URL {
        let resolvedRoot = root ?? meetingsRoot(fileManager: fileManager)
        let directories = [
            resolvedRoot,
            modelsRoot(in: resolvedRoot),
            sessionsRoot(in: resolvedRoot)
        ]
        for url in directories {
            try? fileManager.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
        return resolvedRoot
    }
}
