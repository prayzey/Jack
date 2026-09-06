import SwiftUI

/// The "Jack" tab content for the Settings window. Owns the new
/// `jackSettings` block on `AppSettings` — appearance, presence, job toggles,
/// default popover tab.
///
/// Designed to slot into the parent `SettingsView` scroll container; it does
/// not provide its own `ScrollView` or page header (the host already renders
/// a greeting + subtitle above the tab content).
///
/// Phase 2 of the Jack rebrand. The view is read-only against the legacy
/// `pulseCharacter*` fields — those still drive runtime behavior. Phase 3+
/// will start routing through `jackSettings`.
struct JackSettingsView: View {
    @EnvironmentObject private var store: ClipboardStore

    // Mirrors the service's opt-in flag. Held locally so the toggle can snap
    // back if the user declines the system permission prompt. Loaded in
    // onAppear (not the initializer) to avoid touching the @MainActor service
    // from a nonisolated default-value context under strict concurrency.
    @State private var appleRemindersSyncOn = false

    var body: some View {
        VStack(spacing: 24) {
            intro
            presenceSection
            if store.settings.jackSettings.isVisible {
                jobsSection
                defaultTabSection
            }
            appleRemindersSection
        }
        .onAppear { appleRemindersSyncOn = store.appleRemindersSyncEnabled }
    }

    // MARK: - Apple Reminders sync (one-way)

    private var appleRemindersSection: some View {
        SettingsSection(L10n.string("ui.apple.reminders", default: "Apple Reminders")) {
            VStack(alignment: .leading, spacing: 0) {
                SettingsToggleRow(
                    title: "Sync reminders to Apple Reminders",
                    subtitle: "Also add reminders you create to Apple Reminders, so they reach your iPhone and iPad and alert you even when Jack is closed.",
                    icon: "bell.and.waves.left.and.right",
                    isOn: Binding(
                        get: { appleRemindersSyncOn },
                        set: { newValue in
                            appleRemindersSyncOn = newValue
                            Task {
                                // Reflect the real outcome: if permission is denied
                                // the effective state comes back false.
                                let effective = await store.setAppleRemindersSync(enabled: newValue)
                                appleRemindersSyncOn = effective
                            }
                        }
                    )
                )

                if appleRemindersSyncOn {
                    SettingsDivider()
                    AppleRemindersListPicker()
                }
            }
        }
    }

    // MARK: - Intro

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.string("ui.jack.is.your.on.screen.companion", default: "Jack is your on-screen companion"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SettingsTheme.textPrimary)
            Text(
                "He walks above the dock, surfaces reminders and AI quota alerts, "
                + "and can chat with you using the local AI model. No internet needed."
            )
            .font(.system(size: 12))
            .foregroundStyle(SettingsTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    // MARK: - Presence (off / on triggers / always on)

    private var presenceSection: some View {
        SettingsSection(L10n.string("ui.presence", default: "Presence")) {
            VStack(spacing: 0) {
                ForEach(JackPresenceMode.allCases, id: \.self) { mode in
                    if mode != JackPresenceMode.allCases.first { SettingsDivider() }
                    presenceRow(mode: mode)
                }
            }
        }
    }

    private func presenceRow(mode: JackPresenceMode) -> some View {
        SelectableSettingsRow(
            title: presenceTitle(mode),
            subtitle: presenceSubtitle(mode),
            icon: presenceIcon(mode),
            isSelected: store.settings.jackSettings.presenceMode == mode,
            onSelect: { store.settings.jackSettings.presenceMode = mode }
        )
    }

    private func presenceTitle(_ mode: JackPresenceMode) -> String {
        switch mode {
        case .off:        return "Off"
        case .onTriggers: return "Appears on triggers"
        case .alwaysOn:   return "Always on (lives above the dock)"
        }
    }

    private func presenceSubtitle(_ mode: JackPresenceMode) -> String {
        switch mode {
        case .off:
            return "Jack stays hidden. You can still summon him from the menu bar."
        case .onTriggers:
            return "Jack walks across the screen when usage hits a threshold or a reminder fires."
        case .alwaysOn:
            return "Jack is permanently visible, idling and occasionally walking. Click him any time."
        }
    }

    private func presenceIcon(_ mode: JackPresenceMode) -> String {
        switch mode {
        case .off:        return "moon.zzz"
        case .onTriggers: return "figure.walk"
        case .alwaysOn:   return "sparkles"
        }
    }

    // MARK: - Jobs (what Jack does)

    private var jobsSection: some View {
        SettingsSection(L10n.string("ui.what.jack.does", default: "What Jack does")) {
            VStack(spacing: 0) {
                ForEach(JackJob.allCases, id: \.self) { job in
                    if job != JackJob.allCases.first { SettingsDivider() }
                    jobRow(job: job)
                }
            }
        }
    }

    private func jobRow(job: JackJob) -> some View {
        SettingsToggleRow(
            title: jobTitle(job),
            subtitle: jobSubtitle(job),
            icon: jobIcon(job),
            isOn: Binding(
                get: { store.settings.jackSettings.jobs.contains(job) },
                set: { isOn in
                    if isOn {
                        store.settings.jackSettings.jobs.insert(job)
                    } else {
                        store.settings.jackSettings.jobs.remove(job)
                    }
                }
            )
        )
    }

    private func jobTitle(_ job: JackJob) -> String {
        switch job {
        case .reminders:   return "Reminders"
        case .chat:        return "Chat"
        }
    }

    private func jobSubtitle(_ job: JackJob) -> String {
        switch job {
        case .reminders:
            return "Deliver scheduled reminders you've set up."
        case .chat:
            return "Click Jack to chat with the local AI model on your Mac."
        }
    }

    private func jobIcon(_ job: JackJob) -> String {
        switch job {
        case .reminders:   return "bell"
        case .chat:        return "bubble.left.and.bubble.right"
        }
    }

    // MARK: - Default popover tab

    private var defaultTabSection: some View {
        SettingsSection(L10n.string("ui.when.you.click.jack", default: "When you click Jack")) {
            VStack(spacing: 0) {
                ForEach(JackPopoverTab.allCases, id: \.self) { tab in
                    if tab != JackPopoverTab.allCases.first { SettingsDivider() }
                    defaultTabRow(tab: tab)
                }
            }
        }
    }

    private func defaultTabRow(tab: JackPopoverTab) -> some View {
        SelectableSettingsRow(
            title: defaultTabTitle(tab),
            subtitle: defaultTabSubtitle(tab),
            icon: defaultTabIcon(tab),
            isSelected: store.settings.jackSettings.defaultPopoverTab == tab,
            onSelect: { store.settings.jackSettings.defaultPopoverTab = tab }
        )
    }

    private func defaultTabTitle(_ tab: JackPopoverTab) -> String {
        switch tab {
        case .chat:      return "Open Chat"
        case .reminders: return "Open Reminders"
        }
    }

    private func defaultTabSubtitle(_ tab: JackPopoverTab) -> String {
        switch tab {
        case .chat:      return "Default to the chat tab on click. Talk to the local AI."
        case .reminders: return "Default to the list of scheduled reminders."
        }
    }

    private func defaultTabIcon(_ tab: JackPopoverTab) -> String {
        switch tab {
        case .chat:      return "bubble.left.and.bubble.right"
        case .reminders: return "bell"
        }
    }

}
