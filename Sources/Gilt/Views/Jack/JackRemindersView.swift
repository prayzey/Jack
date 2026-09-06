import SwiftUI

/// Reminders tab inside the Jack popover. Shows reminders sorted by next-due in
/// either a list or a 2-column gallery, paginated so the popover never overflows,
/// with a composer at the bottom to create new ones (with an optional time).
/// Hovering any reminder reveals its full text via the native tooltip.
struct JackRemindersView: View {
    let reminders: [PulseReminder]
    var onAddReminder: (PulseReminder) -> Void = { _ in }
    var onDeleteReminder: (UUID) -> Void = { _ in }

    @State private var viewType: ViewType = .list
    @State private var page: Int = 0

    private enum ViewType { case list, gallery }

    var body: some View {
        VStack(spacing: 0) {
            if !sorted.isEmpty { header }
            contentArea
            if pageCount > 1 { paginationBar }
            Divider().background(Color.white.opacity(0.06))
            JackReminderComposer(onAdd: onAddReminder)
                .padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Derived data

    private var sorted: [PulseReminder] {
        reminders.sorted { lhs, rhs in
            switch (lhs.deliveredAt, rhs.deliveredAt) {
            case (nil, .some): return true
            case (.some, nil): return false
            default: break
            }
            switch (lhs.dueAt, rhs.dueAt) {
            case (nil, nil):   return lhs.createdAt < rhs.createdAt
            case (nil, .some): return true
            case (.some, nil): return false
            case let (l?, r?): return l < r
            }
        }
    }

    private var pageSize: Int { viewType == .list ? 4 : 6 }
    private var pageCount: Int {
        JackReminderPaginator.pageCount(total: sorted.count, pageSize: pageSize)
    }
    private var pageItems: [PulseReminder] {
        JackReminderPaginator.page(sorted, page: page, pageSize: pageSize)
    }

    // MARK: - Header (count + view toggle)

    private var header: some View {
        HStack {
            Text("^[\(sorted.count) reminder](inflect: true)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.5))
            Spacer()
            viewToggle
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var viewToggle: some View {
        HStack(spacing: 2) {
            toggleButton(.list, icon: "list.bullet")
            toggleButton(.gallery, icon: "square.grid.2x2")
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.06)))
    }

    private func toggleButton(_ type: ViewType, icon: String) -> some View {
        let selected = viewType == type
        return Button {
            viewType = type
            page = 0
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(selected ? 0.95 : 0.5))
                .frame(width: 26, height: 20)
                .background(Capsule().fill(Color.white.opacity(selected ? 0.16 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        if sorted.isEmpty {
            emptyState
        } else if viewType == .list {
            VStack(spacing: 8) {
                ForEach(pageItems) { reminder in
                    JackReminderRow(reminder: reminder) { onDeleteReminder(reminder.id) }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(pageItems) { reminder in
                    JackReminderCard(reminder: reminder) { onDeleteReminder(reminder.id) }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: - Pagination

    private var paginationBar: some View {
        let current = JackReminderPaginator.clampedPage(page, total: sorted.count, pageSize: pageSize)
        return HStack(spacing: 14) {
            pageArrow("chevron.left", enabled: current > 0) { page = current - 1 }
            Text("\(current + 1) / \(pageCount)")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.5))
                .monospacedDigit()
            pageArrow("chevron.right", enabled: current < pageCount - 1) { page = current + 1 }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private func pageArrow(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.white.opacity(enabled ? 0.7 : 0.2))
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bell.slash")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.4))
            Text(L10n.string("ui.no.reminders.yet", default: "No reminders yet"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.9))
            Text(L10n.string("ui.add.one.below.and.jack.will.nudge.yo.d8496b", default: "Add one below and Jack will nudge you. Turn on Apple Reminders sync in Settings to get alerts on your other devices too."))
                .font(.system(size: 11.5))
                .foregroundStyle(Color.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
