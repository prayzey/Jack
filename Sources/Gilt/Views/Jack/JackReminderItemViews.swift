import SwiftUI

/// Shared subtitle / relative-date formatting for a reminder, used by both the
/// list row and the gallery card.
enum JackReminderFormat {
    static func subtitle(for reminder: PulseReminder) -> String {
        if let delivered = reminder.deliveredAt {
            return "Delivered " + relative(delivered)
        }
        if let due = reminder.dueAt {
            return "Due " + relative(due)
        }
        return "Due next time Jack appears"
    }

    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// One reminder as a full-width list row. Truncates long text to two lines;
/// hovering shows the full reminder via the native tooltip.
struct JackReminderRow: View {
    let reminder: PulseReminder
    let onDelete: () -> Void

    var body: some View {
        let delivered = reminder.deliveredAt != nil
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: delivered ? "bell.badge.slash" : "bell")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(delivered ? 0.35 : 0.75))
                .frame(width: 18)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(reminder.message)
                    .font(.system(size: 12.5, weight: delivered ? .regular : .semibold))
                    .foregroundStyle(Color.white.opacity(delivered ? 0.55 : 0.92))
                    .strikethrough(delivered, color: Color.white.opacity(0.5))
                    .lineLimit(2)

                Text(JackReminderFormat.subtitle(for: reminder))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
            JackReminderDeleteButton(size: 22, glyph: 11, onDelete: onDelete)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(delivered ? 0.03 : 0.06)))
        .help(reminder.message)
    }
}

/// Compact fixed-height card for the 2-column gallery. Shows up to three lines;
/// hovering reveals the full reminder via the native tooltip.
struct JackReminderCard: View {
    let reminder: PulseReminder
    let onDelete: () -> Void

    var body: some View {
        let delivered = reminder.deliveredAt != nil
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                Image(systemName: delivered ? "bell.badge.slash" : "bell")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(delivered ? 0.35 : 0.7))
                Spacer(minLength: 0)
                JackReminderDeleteButton(size: 18, glyph: 10, onDelete: onDelete)
            }

            Text(reminder.message)
                .font(.system(size: 12, weight: delivered ? .regular : .semibold))
                .foregroundStyle(Color.white.opacity(delivered ? 0.55 : 0.92))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            Text(JackReminderFormat.subtitle(for: reminder))
                .font(.system(size: 9.5))
                .foregroundStyle(Color.white.opacity(0.45))
                .lineLimit(1)
        }
        .padding(10)
        .frame(height: 98, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(delivered ? 0.03 : 0.06)))
        .help(reminder.message)
    }
}

/// Shared delete button — the whole frame is the hit target (contentShape) so
/// users don't have to land exactly on the glyph.
private struct JackReminderDeleteButton: View {
    let size: CGFloat
    let glyph: CGFloat
    let onDelete: () -> Void

    var body: some View {
        Button(action: onDelete) {
            Image(systemName: "trash")
                .font(.system(size: glyph, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.4))
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Delete reminder")
    }
}
