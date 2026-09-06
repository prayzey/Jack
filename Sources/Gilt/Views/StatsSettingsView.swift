import SwiftUI

/// Stats panel inside Settings.
///
/// Design direction:
/// - One card. Everything inside it. No name, no PRO pill, no "member since",
///   no eyebrow wordmark — just the numbers.
/// - Visual language matches the rest of Settings: white card, near-black ink,
///   SF (no serif), the same 14px corner radius + soft shadow that the other
///   `SettingsSection`s use. Nothing about it should read as a separate
///   editorial moment from the rest of the panel.
/// - Three bands, separated by hairline dividers: hero number, metrics 2×2,
///   source breakdown. Read top-to-bottom.
struct StatsSettingsView: View {
    @EnvironmentObject private var store: ClipboardStore
    @ObservedObject private var statsStore: TranscriptionStatsStore

    init() {
        _statsStore = ObservedObject(initialValue: AppStoreReferences.shared.statsStore ?? TranscriptionStatsStore())
    }

    private var stats: TranscriptionStats { statsStore.stats }

    private var ink: Color { SettingsTheme.textPrimary }
    private var inkSecondary: Color { SettingsTheme.textSecondary }
    private var inkTertiary: Color { SettingsTheme.textTertiary }
    private var rule: Color { SettingsTheme.divider }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader

            recordCard
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity, alignment: .leading)

            footerNote
        }
        .padding(.top, 8)
    }

    // MARK: - Page header (above the card)

    private var sectionHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.string("ui.stats", default: "STATS"))
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .tracking(2.6)
                .foregroundStyle(inkTertiary)
            Text(L10n.string("ui.your.speaking.record", default: "Your speaking record"))
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(ink)
            Text(L10n.string("ui.every.word.you.ve.dictated.or.transc.19130e", default: "Every word you've dictated or transcribed in a meeting, kept lifetime."))
                .font(.system(size: 12.5))
                .foregroundStyle(inkSecondary)
        }
    }

    // MARK: - The card

    /// White card matching the rest of Settings. No identity zone — just the
    /// data, read top-to-bottom. Hairline dividers separate the bands the
    /// same way the rest of Settings groups related rows.
    private var recordCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            heroBand
            divider
            metricsBand
            divider
            breakdownBand
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 28)
        .background(SettingsTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(SettingsTheme.border, lineWidth: 0.5)
        )
        .shadow(color: SettingsTheme.cardShadow, radius: 8, x: 0, y: 2)
    }

    private var divider: some View {
        Rectangle()
            .fill(rule)
            .frame(height: 0.5)
            .padding(.vertical, 22)
    }

    // MARK: - Band 1: hero number

    /// The whole point of the card. Caption above so the number doesn't have
    /// to introduce itself. Big SF Rounded numeral. Subtitle below in
    /// secondary ink — plain, no italics.
    private var heroBand: some View {
        VStack(alignment: .leading, spacing: 10) {
            caption("TOTAL WORDS SPOKEN")

            Text(stats.totalWords.formatted())
                .font(.system(size: 76, weight: .bold, design: .rounded))
                .foregroundStyle(ink)
                .tracking(-2.0)
                .lineLimit(1)
                .minimumScaleFactor(0.4)

            Text(heroSubtitle)
                .font(.system(size: 13))
                .foregroundStyle(inkSecondary)
        }
    }

    private var heroSubtitle: String {
        if stats.totalWords <= 0 {
            return "Speak once and Jack starts keeping the ledger."
        }
        return "Jack has saved you \(formattedDuration(stats.timeSavedSeconds)) of typing."
    }

    // MARK: - Band 2: metrics (single row)

    /// Three supporting stats in one row. Time saved lives in the hero
    /// subtitle, so it is not repeated here. No borders, no fills.
    private var metricsBand: some View {
        HStack(alignment: .top, spacing: 20) {
            metricRow(label: "AVERAGE WPM", value: stats.averageWPM > 0 ? "\(stats.averageWPM)" : "0")
            metricRow(label: "CURRENT STREAK", value: streakLabel)
            metricRow(label: "MOST USED IN", value: stats.topAppDisplayName ?? "None yet")
        }
    }

    private func metricRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            caption(label)
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Band 3: breakdown by source

    /// Where the words came from: a proportional split bar (one hue, two
    /// lightness steps, 2px surface gap) with a labeled legend row per
    /// source. Values stay in ink, never in the segment color.
    private var breakdownBand: some View {
        let dictated = stats.totalWordsDictated
        let meetings = stats.totalWordsFromMeetings

        return VStack(alignment: .leading, spacing: 14) {
            caption("WHERE THESE WORDS CAME FROM")

            if dictated + meetings > 0 {
                splitBar(dictated: dictated, meetings: meetings)
            }

            breakdownRow(
                color: dictationColor,
                source: "Voice dictation",
                words: dictated,
                duration: stats.totalDictationDurationSeconds,
                sessions: stats.dictationSessionCount
            )
            breakdownRow(
                color: meetingsColor,
                source: "Meetings",
                words: meetings,
                duration: stats.totalMeetingDurationSeconds,
                sessions: stats.meetingSessionCount
            )
        }
    }

    private var dictationColor: Color { SettingsTheme.primaryAccent }
    private var meetingsColor: Color { SettingsTheme.primaryAccent.opacity(0.32) }

    private func splitBar(dictated: Int, meetings: Int) -> some View {
        GeometryReader { proxy in
            let total = max(1, dictated + meetings)
            let gap: CGFloat = meetings > 0 && dictated > 0 ? 2 : 0
            let usable = max(0, proxy.size.width - gap)
            // A nonzero source always gets a visible sliver, even at 0.1%.
            let minSliver: CGFloat = 4
            var dictatedWidth = usable * CGFloat(dictated) / CGFloat(total)
            var meetingsWidth = usable - dictatedWidth
            if dictated > 0 { dictatedWidth = max(dictatedWidth, minSliver) }
            if meetings > 0 { meetingsWidth = max(meetingsWidth, minSliver) }

            return HStack(spacing: gap) {
                if dictated > 0 {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(dictationColor)
                        .frame(width: min(dictatedWidth, usable - (meetings > 0 ? minSliver : 0)))
                }
                if meetings > 0 {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(meetingsColor)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(height: 10)
    }

    private func breakdownRow(
        color: Color,
        source: String,
        words: Int,
        duration: Double,
        sessions: Int
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(source)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ink)

            Spacer(minLength: 10)

            Text(breakdownValue(words: words, duration: duration, sessions: sessions))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(inkSecondary)
                .lineLimit(1)
        }
    }

    private func breakdownValue(words: Int, duration: Double, sessions: Int) -> String {
        let wordsStr = "\(words.formatted()) words"
        let sessionsStr = "\(sessions.formatted()) \(sessions == 1 ? "session" : "sessions")"
        let durationStr = formattedDuration(duration)
        return "\(wordsStr) · \(sessionsStr) · \(durationStr)"
    }

    // MARK: - Footer note (below the card)

    private var footerNote: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 9, weight: .semibold))
            Text(L10n.string("ui.stats.are.stored.only.on.this.mac.no.1abc8f", default: "Stats are stored only on this Mac. Nothing leaves your device."))
                .font(.system(size: 11))
        }
        .foregroundStyle(inkTertiary)
    }

    // MARK: - Helpers

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy, design: .monospaced))
            .tracking(1.8)
            .foregroundStyle(inkSecondary)
    }

    private var streakLabel: String {
        let count = stats.currentStreak
        if count <= 0 { return "0 days" }
        return "\(count) day\(count == 1 ? "" : "s")"
    }

    private func formattedDuration(_ seconds: Double) -> String {
        let s = max(0, seconds)
        if s < 1 { return "0s" }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        if s >= 86_400 {
            formatter.allowedUnits = [.day, .hour]
        } else if s >= 3_600 {
            formatter.allowedUnits = [.hour, .minute]
        } else {
            formatter.allowedUnits = [.minute, .second]
        }
        return formatter.string(from: s) ?? "0s"
    }
}
