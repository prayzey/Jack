import SwiftUI

/// The tabbed popover that opens when the user clicks Jack. Two tabs:
///   - **Chat**: talk to the local Qwen model
///   - **Reminders**: list of upcoming/active reminders
///
/// The view doesn't draw its own background — the controller's `NSView`
/// container provides the dark surface.
struct JackPopoverView: View {
    @Environment(\.locale) private var locale

    let reminders: [PulseReminder]
    /// Currently selected tab. Owned by the *controller*, not the view, so
    /// that live data refreshes (which rebuild the SwiftUI hierarchy via
    /// `NSHostingView.rootView = …`) don't reset the user's pick.
    let selectedTab: JackPopoverTab
    let onSelectTab: (JackPopoverTab) -> Void
    /// Chat thread for the Chat tab.
    let chatStore: JackChatStore
    /// Dismiss Jack entirely (power button). Lets the user turn off an
    /// always-on Jack without opening Settings.
    var onTurnOff: () -> Void = {}
    /// Create a reminder from the composer in the Reminders tab.
    var onAddReminder: (PulseReminder) -> Void = { _ in }
    /// Delete a reminder from the Reminders tab list.
    var onDeleteReminder: (UUID) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            tabStrip
            Divider().background(Color.white.opacity(0.06))
            content
        }
        .background(Color.clear)
    }

    // MARK: - Tab strip

    private var tabStrip: some View {
        HStack(spacing: 6) {
            ForEach(JackPopoverTab.allCases, id: \.self) { tab in
                tabPill(tab)
            }
            Spacer(minLength: 4)
            powerButton
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    /// Power button — turns Jack off so he disappears from the screen.
    private var powerButton: some View {
        Button(action: onTurnOff) {
            Image(systemName: "power")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.6))
                .frame(width: 26, height: 26)
                .background(
                    Circle().fill(Color.white.opacity(0.08))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Turn Jack off")
    }

    private func tabPill(_ tab: JackPopoverTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
                onSelectTab(tab)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(tab.label)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
            }
            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.55))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.14) : Color.clear)
            )
            // Without this, a plain Button only registers taps on the rendered
            // glyphs (icon + text), not the padding/background — so clicking the
            // pill anywhere but dead-center did nothing. contentShape makes the
            // whole padded area the hit target.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .chat:
            JackChatView(store: chatStore)
        case .reminders:
            JackRemindersView(
                reminders: reminders,
                onAddReminder: onAddReminder,
                onDeleteReminder: onDeleteReminder
            )
        }
    }
}

// MARK: - JackPopoverTab presentation

extension JackPopoverTab {
    /// User-facing label. Keep short — these sit in a tight horizontal pill row.
    var label: String {
        switch self {
        case .chat:      return "Chat"
        case .reminders: return "Reminders"
        }
    }

    /// SF Symbol used in the pill row.
    var icon: String {
        switch self {
        case .chat:      return "bubble.left.and.bubble.right"
        case .reminders: return "bell"
        }
    }
}
