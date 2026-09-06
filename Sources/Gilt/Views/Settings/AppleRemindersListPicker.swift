import SwiftUI

/// Picker for where Jack mirrors reminders in Apple Reminders. Shown in Jack
/// settings and Dictate → Voice actions once Reminders access is granted.
///
/// One row, one menu: the destination choices (system default, Jack's own
/// list, or any existing list) all live in the dropdown instead of stacking
/// three radio rows in the panel.
struct AppleRemindersListPicker: View {
    @State private var preference = RemindersSyncService.shared.listPreference
    @State private var availableLists: [RemindersListOption] = []
    @State private var resolvedDefaultName = "Default list"

    var body: some View {
        SettingsRow(
            title: "Add reminders to",
            subtitle: "Where spoken reminders are saved.",
            icon: "tray.full"
        ) {
            Menu {
                Button {
                    select(kind: .systemDefault, listID: nil)
                } label: {
                    menuItem("Default (\(resolvedDefaultName))", selected: preference.kind == .systemDefault)
                }
                Button {
                    select(kind: .jackDedicated, listID: nil)
                } label: {
                    menuItem("Jack list", selected: preference.kind == .jackDedicated)
                }

                if !availableLists.isEmpty {
                    Divider()
                    ForEach(availableLists) { list in
                        Button {
                            select(kind: .namedList, listID: list.calendarIdentifier)
                        } label: {
                            menuItem(
                                list.title,
                                selected: preference.kind == .namedList
                                    && preference.namedListCalendarID == list.calendarIdentifier
                            )
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(currentSelectionLabel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(SettingsTheme.textSecondary)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(SettingsTheme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(SettingsTheme.sidebarBackground)
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .onAppear(perform: reloadLists)
        .onChange(of: preference) { _, newValue in
            RemindersSyncService.shared.listPreference = newValue
        }
    }

    private var currentSelectionLabel: String {
        switch preference.kind {
        case .systemDefault:
            return resolvedDefaultName
        case .jackDedicated:
            return "Jack list"
        case .namedList:
            if let id = preference.namedListCalendarID,
               let list = availableLists.first(where: { $0.calendarIdentifier == id }) {
                return list.title
            }
            return "Choose a list"
        }
    }

    @ViewBuilder
    private func menuItem(_ title: String, selected: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            if selected {
                Image(systemName: "checkmark")
            }
        }
    }

    private func select(kind: AppleRemindersListPreference.Kind, listID: String?) {
        var updated = preference
        updated.kind = kind
        updated.namedListCalendarID = kind == .namedList
            ? (listID ?? availableLists.first?.calendarIdentifier)
            : nil
        preference = updated
    }

    private func reloadLists() {
        preference = RemindersSyncService.shared.listPreference
        availableLists = RemindersSyncService.shared.modifiableReminderLists()
        resolvedDefaultName = RemindersSyncService.shared.displayName(
            for: AppleRemindersListPreference(kind: .systemDefault)
        )
    }
}
