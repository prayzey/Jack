import SwiftUI

/// Settings section for the "learn from my edits" feature.
///
/// Two halves: a master toggle at the top explaining what the feature does,
/// then a scrollable list of every correction the AI has actually learned.
/// The list is intentionally raw — original, corrected, source app,
/// reinforcement count, when it landed — because during early development
/// the user explicitly wants visibility into what's getting learned, not
/// a curated summary.
///
/// Renders against `CorrectionStore` (injected from the app root). The
/// store handles all CRUD; this view only displays + dispatches.
struct LearnedCorrectionsSection: View {
    @EnvironmentObject private var store: DictationStore
    @EnvironmentObject private var correctionStore: CorrectionStore
    @State private var showClearAllConfirm = false

    var body: some View {
        SettingsSection(L10n.string("ui.learn.from.my.edits", default: "Learn from my edits")) {
            VStack(alignment: .leading, spacing: 0) {
                headerExplainer

                SettingsDivider()

                SettingsToggleRow(
                    title: "Watch what I fix after paste",
                    subtitle: toggleSubtitle,
                    icon: "wand.and.rays",
                    isOn: Binding(
                        get: { store.settings.learnFromEdits },
                        set: { store.settings.learnFromEdits = $0 }
                    )
                )

                SettingsDivider()

                listHeader

                if correctionStore.corrections.isEmpty {
                    if let diagnostic = dormantReason {
                        dormantBanner(diagnostic)
                    }
                    emptyState
                } else {
                    correctionsList
                }
            }
        }
        .alert("Clear all learned corrections?", isPresented: $showClearAllConfirm) {
            Button(L10n.string("ui.cancel", default: "Cancel"), role: .cancel) { }
            Button(L10n.string("ui.clear", default: "Clear"), role: .destructive) {
                correctionStore.clearAll()
            }
        } message: {
            Text("This removes \(correctionStore.correctionCount) learned correction\(correctionStore.correctionCount == 1 ? "" : "s"). The toggle stays on, so future edits can still be learned from.")
        }
    }

    // MARK: - Pieces

    private var headerExplainer: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(SettingsTheme.primaryAccent)
                .frame(width: 32, height: 32)
                .background(Circle().fill(SettingsTheme.primaryAccent.opacity(0.10)))
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.string("ui.gets.better.the.more.you.fix", default: "Gets better the more you fix"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SettingsTheme.textPrimary)
                Text("When Jack pastes a dictation and you correct something, like a misspelled name, the wrong capitalization on \"API\", or \"useeffect\" → \"useEffect\", Jack notices and adds the fixed form to your vocabulary. Future dictations spell it your way the first time.")
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var toggleSubtitle: String {
        if store.settings.learnFromEdits {
            return "Reads the focused text field for up to a minute after each paste. Stops when you switch apps."
        } else {
            return "Off. Jack won't peek at what you type after dictation."
        }
    }

    private var listHeader: some View {
        HStack {
            Text(L10n.string("ui.learned.corrections", default: "LEARNED CORRECTIONS"))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(SettingsTheme.textSecondary)
            Spacer()
            Text("\(correctionStore.correctionCount)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SettingsTheme.textSecondary)
            if !correctionStore.corrections.isEmpty {
                Button(L10n.string("ui.clear.all", default: "Clear all")) {
                    showClearAllConfirm = true
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.red.opacity(0.85))
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    // MARK: - Dormant-state diagnostics

    /// One of the three reasons the learner is silently doing nothing. nil
    /// means "the feature is healthy, it just hasn't seen an edit yet."
    /// Computed each render so toggling Polish or downloading the model
    /// updates the banner without a manual refresh.
    private enum DormantReason: Equatable {
        case learnDisabled
        case polishOff
        case qwenNotCached
    }

    private var dormantReason: DormantReason? {
        if !store.settings.learnFromEdits {
            return .learnDisabled
        }
        if !store.settings.postProcessEnabled {
            return .polishOff
        }
        if !QwenLocalLLM.cachedModelExists(in: store.qwenCacheURL) {
            return .qwenNotCached
        }
        return nil
    }

    @ViewBuilder
    private func dormantBanner(_ reason: DormantReason) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: bannerIcon(for: reason))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(bannerAccent)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(bannerTitle(for: reason))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(SettingsTheme.textPrimary)
                Text(bannerSubtitle(for: reason))
                    .font(.system(size: 11))
                    .foregroundStyle(SettingsTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(bannerAccent.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(bannerAccent.opacity(0.20), lineWidth: 1)
        )
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    /// Warm amber for the dormant banner. SettingsTheme doesn't ship a
    /// warning token yet, and adding one would touch every theme palette —
    /// not worth it for a single banner.
    private var bannerAccent: Color {
        Color(red: 0.78, green: 0.52, blue: 0.13)
    }

    private func bannerIcon(for reason: DormantReason) -> String {
        switch reason {
        case .learnDisabled:  return "moon.zzz"
        case .polishOff:      return "wand.and.stars"
        case .qwenNotCached:  return "arrow.down.circle"
        }
    }

    private func bannerTitle(for reason: DormantReason) -> String {
        switch reason {
        case .learnDisabled:  return "Learning is paused"
        case .polishOff:      return "Turn on Polish to start learning"
        case .qwenNotCached:  return "Download the local AI model to start learning"
        }
    }

    private func bannerSubtitle(for reason: DormantReason) -> String {
        switch reason {
        case .learnDisabled:
            return "Flip the toggle above and Jack will start watching for the fixes you make after each paste."
        case .polishOff:
            return "Learning only runs on Polish-mode dictations. Enable Polish in the Dictate settings tab, then dictate, paste, and fix something."
        case .qwenNotCached:
            return "Jack uses the local AI model to decide whether an edit is a real correction. Open the Models settings to download it (one-time, ~2 GB)."
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 18))
                .foregroundStyle(SettingsTheme.textTertiary)
            Text(L10n.string("ui.nothing.yet", default: "Nothing yet"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(SettingsTheme.textSecondary)
            Text(store.settings.learnFromEdits
                 ? "Dictate, paste, and fix something. Whatever you correct shows up here."
                 : "Turn on the toggle above to start learning from your edits.")
                .font(.system(size: 11))
                .foregroundStyle(SettingsTheme.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 24)
    }

    private var correctionsList: some View {
        VStack(spacing: 0) {
            // Hard cap on the visible rows so the settings tab never grows
            // into a giant scroll. The full list lives in the store; this
            // view shows the top N by reinforcement, which is what users
            // care about anyway. Anything beyond this is still active and
            // still feeds the matcher — it just isn't on this screen.
            let visible = Array(correctionStore.corrections.prefix(60))
            ForEach(Array(visible.enumerated()), id: \.element.correctionID) { index, row in
                CorrectionRowView(row: row, store: correctionStore)
                if index < visible.count - 1 {
                    Divider()
                        .background(SettingsTheme.divider)
                        .padding(.leading, 18)
                }
            }
            if correctionStore.corrections.count > visible.count {
                Text("+ \(correctionStore.corrections.count - visible.count) more in storage")
                    .font(.system(size: 11))
                    .foregroundStyle(SettingsTheme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 10)
            }
        }
        .padding(.bottom, 6)
    }
}

// MARK: - Single row

/// One learned-correction row. Kept as its own View so re-renders stay
/// scoped to the row whose state actually changed (toggle, delete) rather
/// than the entire list.
private struct CorrectionRowView: View {
    let row: LearnedCorrectionModel
    @ObservedObject var store: CorrectionStore

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(row.original)
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundStyle(SettingsTheme.textSecondary)
                        .strikethrough(true, color: SettingsTheme.textTertiary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(SettingsTheme.textTertiary)
                    Text(row.corrected)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(row.isActive ? SettingsTheme.textPrimary : SettingsTheme.textTertiary)
                }

                HStack(spacing: 8) {
                    if let app = row.sourceAppName {
                        Label(app, systemImage: "app.fill")
                            .font(.system(size: 10))
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(SettingsTheme.textTertiary)
                    }
                    Text("seen \(row.reinforcementCount)×")
                        .font(.system(size: 10))
                        .foregroundStyle(SettingsTheme.textTertiary)
                    Text(relativeDate)
                        .font(.system(size: 10))
                        .foregroundStyle(SettingsTheme.textTertiary)
                }
            }

            Spacer(minLength: 12)

            // Toggle vs delete. The toggle is the "pause it but keep it
            // around" affordance; delete is permanent. Two distinct actions
            // because users sometimes want to re-enable a correction later.
            Toggle("", isOn: Binding(
                get: { row.isActive },
                set: { store.setActive(row, isActive: $0) }
            ))
            .toggleStyle(GoldToggleStyle())
            .labelsHidden()
            .help(row.isActive ? "Active. Applied to future dictations." : "Disabled. Kept in storage but not applied.")

            Button {
                store.deleteCorrection(row)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SettingsTheme.textTertiary)
            }
            .buttonStyle(.borderless)
            .help("Delete this correction permanently")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var relativeDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: row.lastReinforcedAt, relativeTo: Date())
    }
}
