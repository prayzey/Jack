import Foundation

/// The "when" choice in the Jack reminder composer. Kept separate from the
/// persisted `PulseReminder` so the UI can offer friendly presets plus a custom
/// date/time without leaking picker state into the model.
enum JackReminderDue: Equatable {
    /// No due date — surfaced "next time Jack appears". Mirrors to Apple
    /// Reminders as an undated item (no alarm).
    case anytime
    case inTenMinutes
    case inThirtyMinutes
    case inOneHour
    /// 6pm today, or 6pm tomorrow if it's already past 6pm.
    case thisEvening
    /// 9am the next calendar day.
    case tomorrowMorning
    /// An exact date + time. When Apple Reminders sync is on this becomes an
    /// alarm that fires on the user's devices.
    case custom(Date)
}

/// Pure construction of a `PulseReminder` from composer input. Side-effect-free
/// and `now`-injectable so the due-date math is unit-testable without a clock.
enum JackReminderDraft {
    /// Build a reminder, or `nil` when the text is blank (so the caller can keep
    /// the Add button disabled / no-op on empty input).
    static func makeReminder(
        text: String,
        due: JackReminderDue,
        now: Date,
        calendar: Calendar = .current
    ) -> PulseReminder? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let dueAt: Date?
        switch due {
        case .anytime:
            dueAt = nil
        case .inTenMinutes:
            dueAt = now.addingTimeInterval(10 * 60)
        case .inThirtyMinutes:
            dueAt = now.addingTimeInterval(30 * 60)
        case .inOneHour:
            dueAt = now.addingTimeInterval(60 * 60)
        case .thisEvening:
            // 6pm today; if that's already passed, roll to 6pm tomorrow so
            // "this evening" never lands in the past.
            let sixToday = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now) ?? now
            if sixToday > now {
                dueAt = sixToday
            } else {
                let nextDay = calendar.date(byAdding: .day, value: 1, to: now) ?? now
                dueAt = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: nextDay) ?? nextDay
            }
        case .tomorrowMorning:
            // 9am the next calendar day — a sane default for "tomorrow" that
            // isn't tied to the current minute.
            let nextDay = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            dueAt = calendar.date(
                bySettingHour: 9, minute: 0, second: 0, of: nextDay
            ) ?? nextDay
        case .custom(let date):
            dueAt = date
        }

        return PulseReminder(message: trimmed, createdAt: now, dueAt: dueAt)
    }
}
