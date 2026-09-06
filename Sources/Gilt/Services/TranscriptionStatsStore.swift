import AppKit
import Foundation
import OSLog
import SwiftUI

/// Owns `TranscriptionStats` and keeps it up to date as the user dictates or
/// finishes meetings. All mutations are O(1) — there are no scans on render or
/// on every transcript chunk. The one-time bootstrap walks existing dictation
/// history (capped at 100 entries) and meeting sessions once per install to
/// seed the lifetime counters.
@MainActor
final class TranscriptionStatsStore: ObservableObject {
    @Published private(set) var stats: TranscriptionStats

    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "TranscriptionStatsStore")
    private let defaultsKey = "GiltTranscriptionStats"
    private var persistTask: Task<Void, Never>?

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(TranscriptionStats.self, from: data) {
            self.stats = decoded
        } else {
            self.stats = TranscriptionStats()
        }
    }

    // MARK: - Public recording API

    /// Record a finished dictation. Caller passes pre-computed word count so we
    /// don't tokenize the same text twice (the coordinator already has it).
    func recordDictation(
        entryID: UUID,
        words: Int,
        durationSeconds: Double,
        appBundleID: String? = nil,
        appDisplayName: String? = nil,
        at date: Date = Date()
    ) {
        guard words > 0 else { return }
        guard !stats.recordedDictationIDs.contains(entryID) else { return }

        stats.recordedDictationIDs.insert(entryID)
        stats.totalWordsDictated += words
        stats.totalDictationDurationSeconds += max(0, durationSeconds)
        stats.dictationSessionCount += 1
        registerAppUsage(bundleID: appBundleID, displayName: appDisplayName, words: words)
        bumpStreak(on: date)
        schedulePersist()
    }

    /// Record a meeting whose transcription finished. Word count is taken from
    /// the final transcript chunks; the controller computes it once at the end
    /// of `stopAndProcess` so we never re-walk chunks on render.
    func recordMeeting(
        meetingID: UUID,
        words: Int,
        durationSeconds: Double,
        at date: Date = Date()
    ) {
        guard words > 0 else { return }
        guard !stats.recordedMeetingIDs.contains(meetingID) else { return }

        stats.recordedMeetingIDs.insert(meetingID)
        stats.totalWordsFromMeetings += words
        stats.totalMeetingDurationSeconds += max(0, durationSeconds)
        stats.meetingSessionCount += 1
        bumpStreak(on: date)
        schedulePersist()
    }

    // MARK: - Bootstrap

    /// Walk existing dictation history and meeting sessions once per install
    /// so users who already use Jack see a non-zero card on first open. After
    /// this completes, every new dictation/meeting flows through the
    /// incremental API above. Idempotent via `hasBootstrapped`.
    func bootstrapIfNeeded(
        dictationHistory: [DictationHistoryEntry],
        meetingSessions: [MeetingSession],
        meetingWordCount: (UUID) -> Int
    ) {
        guard !stats.hasBootstrapped else { return }
        defer {
            stats.hasBootstrapped = true
            schedulePersist()
        }

        for entry in dictationHistory {
            let words = TranscriptionStatsStore.wordCount(entry.text)
            guard words > 0 else { continue }
            if stats.recordedDictationIDs.contains(entry.entryID) { continue }
            stats.recordedDictationIDs.insert(entry.entryID)
            stats.totalWordsDictated += words
            stats.totalDictationDurationSeconds += max(0, entry.durationSeconds)
            stats.dictationSessionCount += 1
            absorbActivityDate(entry.createdAt)
        }

        for session in meetingSessions {
            // Only count sessions that actually produced content. Drafts and
            // failed runs have no transcript so word count comes back zero.
            let words = meetingWordCount(session.meetingID)
            guard words > 0 else { continue }
            if stats.recordedMeetingIDs.contains(session.meetingID) { continue }
            stats.recordedMeetingIDs.insert(session.meetingID)
            stats.totalWordsFromMeetings += words
            stats.totalMeetingDurationSeconds += max(0, session.durationSeconds)
            stats.meetingSessionCount += 1
            absorbActivityDate(session.endedAt ?? session.updatedAt)
        }

        // Recompute the streak from scratch after bootstrap so an established
        // user doesn't start at zero — we can't reconstruct day-by-day from
        // capped history, but we can at least seed currentStreak = 1 if there
        // was activity today.
        if let last = stats.lastActivityDay,
           Calendar.current.isDate(last, inSameDayAs: Date()) {
            stats.currentStreak = max(stats.currentStreak, 1)
            stats.longestStreak = max(stats.longestStreak, stats.currentStreak)
        }
    }

    // MARK: - Helpers

    static func wordCount(_ text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        return trimmed.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    private func registerAppUsage(bundleID: String?, displayName: String?, words: Int) {
        guard let bundleID, !bundleID.isEmpty else { return }
        stats.perAppWordCounts[bundleID, default: 0] += words
        if let displayName, !displayName.isEmpty {
            stats.perAppDisplayNames[bundleID] = displayName
        } else if stats.perAppDisplayNames[bundleID] == nil {
            // Fall back to a derived name from the bundle ID so the UI never
            // has to render the raw reverse-DNS string.
            stats.perAppDisplayNames[bundleID] = bundleID
                .components(separatedBy: ".")
                .last?
                .capitalized ?? bundleID
        }
    }

    private func bumpStreak(on date: Date) {
        absorbActivityDate(date)
    }

    private func absorbActivityDate(_ date: Date) {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)

        if stats.firstActivityAt == nil || date < (stats.firstActivityAt ?? date) {
            stats.firstActivityAt = date
        }

        guard let last = stats.lastActivityDay else {
            stats.lastActivityDay = day
            stats.currentStreak = 1
            stats.longestStreak = max(stats.longestStreak, 1)
            return
        }

        if cal.isDate(day, inSameDayAs: last) {
            // Already counted today — nothing to do.
            return
        }

        let dayDelta = cal.dateComponents([.day], from: last, to: day).day ?? 0
        if dayDelta == 1 {
            stats.currentStreak += 1
        } else if dayDelta > 1 {
            stats.currentStreak = 1
        } else {
            // Backfill (bootstrap walking older entries) — don't disturb the
            // current streak, just seed it if still zero.
            if stats.currentStreak == 0 { stats.currentStreak = 1 }
        }
        stats.lastActivityDay = day
        stats.longestStreak = max(stats.longestStreak, stats.currentStreak)
    }

    private func schedulePersist() {
        // Debounce — back-to-back dictations shouldn't write the JSON blob
        // five times in 200ms. 250ms feels imperceptible and coalesces bursts.
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self, !Task.isCancelled else { return }
            self.persist()
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(stats)
            UserDefaults.standard.set(data, forKey: defaultsKey)
        } catch {
            logger.error("Failed to persist transcription stats: \(error.localizedDescription)")
        }
    }

    // MARK: - Frontmost app capture

    /// Snapshot of the frontmost app at the moment of paste. Used to attribute
    /// dictated words to "Top App". Returns nil if we can't resolve it.
    static func frontmostAppSnapshot() -> (bundleID: String, displayName: String)? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let bundleID = app.bundleIdentifier ?? ""
        guard !bundleID.isEmpty else { return nil }
        let name = app.localizedName ?? bundleID
        return (bundleID, name)
    }
}
