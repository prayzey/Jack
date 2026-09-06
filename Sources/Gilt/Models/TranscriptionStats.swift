import Foundation

/// Lifetime counters for everything the user has dictated or transcribed in
/// meetings. Persisted as a single JSON blob in UserDefaults so reads/writes
/// are O(1) on the main actor — the view layer never walks history.
///
/// All counters are append-only. Dedupe is by `recordedDictationIDs` /
/// `recordedMeetingIDs` so a re-run of the bootstrap (or a meeting that gets
/// re-processed) can't double-count.
struct TranscriptionStats: Codable, Equatable {
    var totalWordsDictated: Int = 0
    var totalWordsFromMeetings: Int = 0
    var totalDictationDurationSeconds: Double = 0
    var totalMeetingDurationSeconds: Double = 0
    var dictationSessionCount: Int = 0
    var meetingSessionCount: Int = 0

    /// Bundle ID → cumulative dictated words. Used for "Most used in".
    var perAppWordCounts: [String: Int] = [:]
    /// Bundle ID → friendly display name (last seen), so we don't have to
    /// re-resolve via NSWorkspace on render.
    var perAppDisplayNames: [String: String] = [:]

    /// Calendar start-of-day for the last activity, in the user's current
    /// timezone-agnostic UTC bucket. Streak math compares day deltas.
    var lastActivityDay: Date?
    var currentStreak: Int = 0
    var longestStreak: Int = 0

    /// First time we ever recorded anything for this user. Drives the
    /// "member since" date on the card.
    var firstActivityAt: Date?

    /// Dedupe sets so bootstrap + re-processed meetings can't double-count.
    var recordedDictationIDs: Set<UUID> = []
    var recordedMeetingIDs: Set<UUID> = []

    /// One-time guard so we only walk the existing dictation/meeting history
    /// the first time the stats feature runs on this install.
    var hasBootstrapped: Bool = false

    // MARK: - Derived

    var totalWords: Int { totalWordsDictated + totalWordsFromMeetings }
    var totalSpokenSeconds: Double { totalDictationDurationSeconds + totalMeetingDurationSeconds }

    /// Average words per minute across all speaking activity. Falls back to
    /// zero (rendered as "—") when there isn't enough data yet.
    var averageWPM: Int {
        let minutes = totalSpokenSeconds / 60.0
        guard minutes > 0.5 else { return 0 }
        return Int((Double(totalWords) / minutes).rounded())
    }

    /// Seconds saved vs typing the same words by hand at 40 WPM. The "saved"
    /// framing only makes sense when the user actually spent less time
    /// speaking than they would have spent typing.
    var timeSavedSeconds: Double {
        let typingMinutes = Double(totalWords) / 40.0
        let savedMinutes = typingMinutes - (totalSpokenSeconds / 60.0)
        return max(0, savedMinutes * 60.0)
    }

    var topAppBundleID: String? {
        perAppWordCounts.max(by: { $0.value < $1.value })?.key
    }

    var topAppDisplayName: String? {
        guard let id = topAppBundleID else { return nil }
        return perAppDisplayNames[id]
    }
}
