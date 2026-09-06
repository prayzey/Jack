import AppKit
import SwiftUI

/// Settings tab for Apple's on-device AI features. Carries the disclaimer that explains, in plain
/// language, when these features can't run (wrong OS, ineligible Mac, Apple Intelligence off) and
/// the toggles for each feature. Toggles disable themselves when the model can't run, so the user
/// always sees what's on offer even if their setup can't use it yet.
struct AISettingsView: View {
    @EnvironmentObject private var store: ClipboardStore
    @ObservedObject private var ai = OnDeviceAIService.shared

    private var modelUsable: Bool { ai.status.isUsable }
    private var featuresOn: Bool { store.settings.aiFeaturesEnabled }
    /// Sub-feature toggles are live only when the model works AND the master switch is on.
    private var subControlsEnabled: Bool { modelUsable && featuresOn }

    var body: some View {
        VStack(spacing: 24) {
            statusCard

            SettingsSection(L10n.string("ai.settings.section.general", default: "On-Device AI")) {
                SettingsToggleRow(
                    title: L10n.string("ai.settings.master.title", default: "Enable AI features"),
                    subtitle: L10n.string("ai.settings.master.subtitle", default: "Use Apple's on-device model for the features below. Everything runs privately on your Mac."),
                    icon: "sparkles",
                    isDisabled: !modelUsable,
                    isOn: $store.settings.aiFeaturesEnabled
                )
            }

            SettingsSection(L10n.string("ai.settings.section.features", default: "Features")) {
                featureToggle(
                    title: L10n.string("ai.settings.clipActions.title", default: "Clip actions"),
                    subtitle: L10n.string("ai.settings.clipActions.subtitle", default: "Summarize, rewrite, fix grammar, and rename clips from the right-click menu."),
                    icon: "text.badge.star",
                    isOn: $store.settings.aiClipActionsEnabled
                )
                SettingsDivider()
                featureToggle(
                    title: L10n.string("ai.settings.autoTitle.title", default: "Auto-title long clips"),
                    subtitle: L10n.string("ai.settings.autoTitle.subtitle", default: "Give long text clips a short title automatically as they're captured."),
                    icon: "character.cursor.ibeam",
                    isOn: $store.settings.aiAutoTitleEnabled
                )
                SettingsDivider()
                featureToggle(
                    title: L10n.string("ai.settings.smartTagging.title", default: "Smart tagging on capture"),
                    subtitle: L10n.string("ai.settings.smartTagging.subtitle", default: "Add topic tags to new clips to make them easier to find later."),
                    icon: "tag",
                    isOn: $store.settings.aiSmartTaggingEnabled
                )
                SettingsDivider()
                featureToggle(
                    title: L10n.string("ai.settings.noteAssist.title", default: "Note assistant"),
                    subtitle: L10n.string("ai.settings.noteAssist.subtitle", default: "Summarize, rewrite, and title your Quick Notes."),
                    icon: "note.text",
                    isOn: $store.settings.aiNoteAssistEnabled
                )
                SettingsDivider()
                featureToggle(
                    title: L10n.string("ai.settings.reminders.title", default: "Reminders from clips"),
                    subtitle: L10n.string("ai.settings.reminders.subtitle", default: "Spot tasks in a clip and turn them into a reminder in one tap."),
                    icon: "bell.badge",
                    isOn: $store.settings.aiReminderExtractionEnabled
                )
                SettingsDivider()
                featureToggle(
                    title: L10n.string("ai.settings.search.title", default: "Natural language search"),
                    subtitle: L10n.string("ai.settings.search.subtitle", default: "Understand searches like \"that link about taxes from last week\"."),
                    icon: "magnifyingglass",
                    isOn: $store.settings.aiNaturalLanguageSearchEnabled
                )
            }

            // Meeting summarization is an engine choice (Apple Intelligence vs the local
            // Qwen download), not an on/off feature, and meetings have their own AI stack
            // independent of the master toggle above. So it gets a pointer to where the
            // choice actually lives — the Models sheet in Meeting memory — instead of a
            // toggle that looks like a feature switch.
            SettingsSection(L10n.string("ai.settings.section.meetings", default: "Meetings")) {
                SettingsRow(
                    title: L10n.string("ai.settings.meetingsPointer.title", default: "Meeting summarization"),
                    subtitle: L10n.string("ai.settings.meetingsPointer.subtitle", default: "Meetings use their own local models. Choose between Apple Intelligence and the Qwen model under Models in Meeting memory."),
                    icon: "person.wave.2"
                ) { EmptyView() }
            }

            privacyFootnote
        }
        .onAppear { ai.refreshStatus() }
    }

    // MARK: - Status / disclaimer

    @ViewBuilder
    private var statusCard: some View {
        let usable = modelUsable
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill((usable ? Color(red: 0.20, green: 0.62, blue: 0.40) : Color(red: 0.85, green: 0.58, blue: 0.20)).opacity(0.14))
                    .frame(width: 38, height: 38)
                Image(systemName: usable ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(usable ? Color(red: 0.18, green: 0.55, blue: 0.36) : Color(red: 0.78, green: 0.52, blue: 0.16))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(ai.status.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SettingsTheme.textPrimary)
                Text(ai.status.message)
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if ai.status == .appleIntelligenceOff {
                    Button {
                        openSystemSettings()
                    } label: {
                        Text(L10n.string("ai.settings.openSettings", default: "Open System Settings"))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(SettingsTheme.primaryAccent)
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(SettingsTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(SettingsTheme.border, lineWidth: 0.5)
        )
        .shadow(color: SettingsTheme.cardShadow, radius: 8, x: 0, y: 2)
    }

    private var privacyFootnote: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(SettingsTheme.textTertiary)
            Text(L10n.string(
                "ai.settings.privacy",
                default: "These features run entirely on your Mac with Apple Intelligence. Your clips are never sent to a server, and there's no cost per use."
            ))
            .font(.system(size: 11))
            .foregroundStyle(SettingsTheme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func featureToggle(title: String, subtitle: String, icon: String, isOn: Binding<Bool>) -> some View {
        SettingsToggleRow(
            title: title,
            subtitle: subtitle,
            icon: icon,
            isDisabled: !subControlsEnabled,
            isOn: isOn
        )
        .opacity(subControlsEnabled ? 1 : 0.5)
    }

    private func openSystemSettings() {
        // Open System Settings; the disclaimer tells the user where to find Apple Intelligence.
        // We avoid a specific deep link because the pane identifier is not stable across releases.
        if let url = URL(string: "x-apple.systempreferences:") {
            NSWorkspace.shared.open(url)
        }
    }
}
