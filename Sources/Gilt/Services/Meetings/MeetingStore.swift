import Foundation
import OSLog
import SwiftUI

/// Persists meetings, transcripts, summaries, and ask history to disk.
///
/// Storage layout (see `MeetingAppSupportLocator`):
/// ```
/// ~/Library/Application Support/Jack/Meetings/
///   sessions/<meeting-id>/
///     meeting.json      <- MeetingSession
///     transcript.jsonl  <- one MeetingTranscriptChunk per line
///     summary.json      <- MeetingSummary
///     ask-history.json  <- [MeetingQuestion]
///     audio/recording.caf
/// ```
///
/// JSONL for the transcript means streaming writes are an append, which keeps
/// long meetings cheap and resilient to crashes mid-write.
@MainActor
final class MeetingStore: ObservableObject {
    @Published private(set) var sessions: [MeetingSession] = []
    @Published var settings: MeetingSettings

    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "MeetingStore")
    private let fileManager: FileManager
    private let meetingsRoot: URL
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()
    /// Transcript chunks are stored one-per-line in `transcript.jsonl`. Each
    /// line must be a single JSON value with no embedded newlines — otherwise
    /// the line-based reader splits a single chunk into unreadable fragments.
    /// Keep this encoder distinct from the pretty-printed one used for
    /// session/summary metadata.
    private let lineEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer()
            if let seconds = try? value.decode(Double.self) {
                return Date(timeIntervalSince1970: seconds)
            }
            let string = try value.decode(String.self)
            guard let date = ISO8601DateFormatter().date(from: string) else {
                throw DecodingError.dataCorruptedError(
                    in: value,
                    debugDescription: "Expected a Unix timestamp or ISO 8601 date"
                )
            }
            return date
        }
        return decoder
    }()
    private let settingsDefaultsKey = "GiltMeetingSettings"

    init(fileManager: FileManager = .default, meetingsRoot: URL? = nil) {
        self.fileManager = fileManager
        if let meetingsRoot {
            self.meetingsRoot = MeetingAppSupportLocator.ensureBaseDirectories(
                fileManager: fileManager,
                root: meetingsRoot
            )
        } else {
            self.meetingsRoot = MeetingAppSupportLocator.ensureBaseDirectories(fileManager: fileManager)
        }
        if let data = UserDefaults.standard.data(forKey: settingsDefaultsKey),
           let stored = try? decoder.decode(MeetingSettings.self, from: data) {
            self.settings = stored
        } else {
            self.settings = MeetingSettings()
        }
        reloadSessions()
    }

    // MARK: - Settings

    func persistSettings() {
        if let data = try? encoder.encode(settings) {
            UserDefaults.standard.set(data, forKey: settingsDefaultsKey)
        }
    }

    // MARK: - Session CRUD

    @discardableResult
    func createSession(
        title: String = "",
        language: MeetingLanguage,
        audioSource: MeetingAudioSource = .microphone
    ) -> MeetingSession {
        var session = MeetingSession(
            title: title,
            language: language,
            transcriptionEngine: .recommended(for: language),
            audioSource: audioSource
        )
        session.state = .draft
        save(session: session)
        ensureSessionFolder(meetingID: session.meetingID)
        reloadSessions()
        return session
    }

    /// Renames a meeting. The title is trimmed; an empty result is allowed and
    /// simply restores the date-based fallback (`displayTitle`). Order is kept
    /// stable on purpose — a rename shouldn't bump the row to the top of the
    /// list while the user is still looking at it.
    @discardableResult
    func renameSession(_ meetingID: UUID, to newTitle: String) -> MeetingSession? {
        guard var updated = session(for: meetingID) else { return nil }
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != updated.title else { return updated }
        updated.title = trimmed
        save(session: updated, touchUpdatedAt: false)
        return session(for: meetingID)
    }

    func save(session: MeetingSession, touchUpdatedAt: Bool = true) {
        let folder = ensureSessionFolder(meetingID: session.meetingID)
        let file = MeetingAppSupportLocator.meetingFile(in: folder)
        var updated = session
        if touchUpdatedAt { updated.updatedAt = Date() }
        do {
            let data = try encoder.encode(updated)
            try data.write(to: file, options: .atomic)
        } catch {
            logger.error("Failed to write meeting \(session.meetingID): \(error.localizedDescription)")
        }
        // Update in-memory cache as well.
        if let index = sessions.firstIndex(where: { $0.meetingID == updated.meetingID }) {
            sessions[index] = updated
        } else {
            sessions.append(updated)
        }
        sessions.sort(by: meetingSort)
    }

    func deleteSession(_ meetingID: UUID) {
        let folder = MeetingAppSupportLocator.sessionFolder(
            meetingID: meetingID,
            in: MeetingAppSupportLocator.sessionsRoot(in: meetingsRoot)
        )
        try? fileManager.removeItem(at: folder)
        sessions.removeAll { $0.meetingID == meetingID }
    }

    func session(for meetingID: UUID) -> MeetingSession? {
        sessions.first(where: { $0.meetingID == meetingID })
    }

    // MARK: - Transcript

    func appendTranscriptChunk(_ chunk: MeetingTranscriptChunk, to meetingID: UUID) {
        let folder = ensureSessionFolder(meetingID: meetingID)
        let url = MeetingAppSupportLocator.transcriptFile(in: folder)
        do {
            let line = try lineEncoder.encode(chunk)
            var data = line
            data.append(0x0A) // newline
            if fileManager.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: url, options: .atomic)
            }
        } catch {
            logger.error("Failed to append transcript chunk: \(error.localizedDescription)")
        }
    }

    func loadTranscript(for meetingID: UUID) -> [MeetingTranscriptChunk] {
        let folder = MeetingAppSupportLocator.sessionFolder(
            meetingID: meetingID,
            in: MeetingAppSupportLocator.sessionsRoot(in: meetingsRoot)
        )
        let url = MeetingAppSupportLocator.transcriptFile(in: folder)
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let lines = raw.split(separator: "\n").filter { !$0.isEmpty }
        return lines.compactMap { line in
            try? decoder.decode(MeetingTranscriptChunk.self, from: Data(line.utf8))
        }
    }

    func replaceTranscript(_ chunks: [MeetingTranscriptChunk], for meetingID: UUID) {
        let folder = ensureSessionFolder(meetingID: meetingID)
        let url = MeetingAppSupportLocator.transcriptFile(in: folder)
        do {
            var data = Data()
            for chunk in chunks {
                let line = try lineEncoder.encode(chunk)
                data.append(line)
                data.append(0x0A)
            }
            try data.write(to: url, options: .atomic)
        } catch {
            logger.error("Failed to replace transcript: \(error.localizedDescription)")
        }
    }

    // MARK: - Summary

    func loadSummary(for meetingID: UUID) -> MeetingSummary? {
        let folder = MeetingAppSupportLocator.sessionFolder(
            meetingID: meetingID,
            in: MeetingAppSupportLocator.sessionsRoot(in: meetingsRoot)
        )
        let url = MeetingAppSupportLocator.summaryFile(in: folder)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(MeetingSummary.self, from: data)
    }

    func saveSummary(_ summary: MeetingSummary, for meetingID: UUID) {
        let folder = ensureSessionFolder(meetingID: meetingID)
        let url = MeetingAppSupportLocator.summaryFile(in: folder)
        do {
            let data = try encoder.encode(summary)
            try data.write(to: url, options: .atomic)
        } catch {
            logger.error("Failed to save summary: \(error.localizedDescription)")
        }
    }

    // MARK: - Ask history

    func loadAskHistory(for meetingID: UUID) -> [MeetingQuestion] {
        let folder = MeetingAppSupportLocator.sessionFolder(
            meetingID: meetingID,
            in: MeetingAppSupportLocator.sessionsRoot(in: meetingsRoot)
        )
        let url = MeetingAppSupportLocator.askHistoryFile(in: folder)
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? decoder.decode([MeetingQuestion].self, from: data)) ?? []
    }

    func saveAskHistory(_ history: [MeetingQuestion], for meetingID: UUID) {
        let folder = ensureSessionFolder(meetingID: meetingID)
        let url = MeetingAppSupportLocator.askHistoryFile(in: folder)
        do {
            let data = try encoder.encode(history)
            try data.write(to: url, options: .atomic)
        } catch {
            logger.error("Failed to save ask history: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    var sessionsRoot: URL {
        MeetingAppSupportLocator.sessionsRoot(in: meetingsRoot)
    }

    var modelsRoot: URL {
        MeetingAppSupportLocator.modelsRoot(in: meetingsRoot)
    }

    func audioURL(for meetingID: UUID) -> URL {
        let folder = MeetingAppSupportLocator.sessionFolder(
            meetingID: meetingID,
            in: MeetingAppSupportLocator.sessionsRoot(in: meetingsRoot)
        )
        return MeetingAppSupportLocator.audioFile(in: folder)
    }

    @discardableResult
    private func ensureSessionFolder(meetingID: UUID) -> URL {
        let folder = MeetingAppSupportLocator.sessionFolder(
            meetingID: meetingID,
            in: MeetingAppSupportLocator.sessionsRoot(in: meetingsRoot)
        )
        try? fileManager.createDirectory(
            at: folder,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return folder
    }

    private func reloadSessions() {
        let sessionsRoot = MeetingAppSupportLocator.sessionsRoot(in: meetingsRoot)
        guard let contents = try? fileManager.contentsOfDirectory(
            at: sessionsRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            sessions = []
            return
        }
        var loaded: [MeetingSession] = []
        for url in contents where url.hasDirectoryPath {
            let meetingFile = MeetingAppSupportLocator.meetingFile(in: url)
            guard let data = try? Data(contentsOf: meetingFile) else { continue }
            if let session = try? decoder.decode(MeetingSession.self, from: data) {
                loaded.append(session)
            }
        }
        sessions = loaded.sorted(by: meetingSort)
    }

    private func meetingSort(_ a: MeetingSession, _ b: MeetingSession) -> Bool {
        a.updatedAt > b.updatedAt
    }
}
