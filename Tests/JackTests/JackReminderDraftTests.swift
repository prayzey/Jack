import XCTest
@testable import Gilt

/// Covers the pure reminder-construction logic used by the Jack popover
/// composer: blank input is rejected, and each "when" choice maps to the right
/// `dueAt` so Apple Reminders gets the correct alarm time.
final class JackReminderDraftTests: XCTestCase {

    private var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    // A fixed clock so the relative-date math is deterministic: 2026-06-09
    // 12:00:00 UTC, built from components so there's no magic-epoch ambiguity.
    private var now: Date {
        utcCalendar.date(
            from: DateComponents(year: 2026, month: 6, day: 9, hour: 12, minute: 0, second: 0)
        )!
    }

    func testBlankTextProducesNoReminder() {
        XCTAssertNil(JackReminderDraft.makeReminder(text: "   \n ", due: .anytime, now: now))
        XCTAssertNil(JackReminderDraft.makeReminder(text: "", due: .inThirtyMinutes, now: now))
    }

    func testTextIsTrimmed() {
        let reminder = JackReminderDraft.makeReminder(text: "  call mom  ", due: .anytime, now: now)
        XCTAssertEqual(reminder?.message, "call mom")
    }

    func testAnytimeHasNoDueDate() {
        let reminder = JackReminderDraft.makeReminder(text: "water plants", due: .anytime, now: now)
        XCTAssertNotNil(reminder)
        XCTAssertNil(reminder?.dueAt)
    }

    func testRelativeOffsetsAreExact() {
        XCTAssertEqual(
            JackReminderDraft.makeReminder(text: "a", due: .inTenMinutes, now: now)?.dueAt,
            now.addingTimeInterval(10 * 60)
        )
        XCTAssertEqual(
            JackReminderDraft.makeReminder(text: "b", due: .inThirtyMinutes, now: now)?.dueAt,
            now.addingTimeInterval(30 * 60)
        )
        XCTAssertEqual(
            JackReminderDraft.makeReminder(text: "c", due: .inOneHour, now: now)?.dueAt,
            now.addingTimeInterval(60 * 60)
        )
    }

    func testThisEveningIsSixPmTodayWhenStillMorning() {
        // now is 12:00, so 6pm today is in the future.
        let reminder = JackReminderDraft.makeReminder(
            text: "dinner", due: .thisEvening, now: now, calendar: utcCalendar
        )
        let comps = utcCalendar.dateComponents([.day, .hour, .minute], from: reminder!.dueAt!)
        XCTAssertEqual(comps.hour, 18)
        XCTAssertEqual(comps.minute, 0)
        XCTAssertEqual(comps.day, 9) // same day
    }

    func testThisEveningRollsToTomorrowWhenAlreadyEvening() {
        // 8pm — 6pm today has passed, so it should roll to tomorrow 6pm.
        let eightPm = utcCalendar.date(
            from: DateComponents(year: 2026, month: 6, day: 9, hour: 20, minute: 0, second: 0)
        )!
        let reminder = JackReminderDraft.makeReminder(
            text: "dinner", due: .thisEvening, now: eightPm, calendar: utcCalendar
        )
        let comps = utcCalendar.dateComponents([.day, .hour], from: reminder!.dueAt!)
        XCTAssertEqual(comps.hour, 18)
        XCTAssertEqual(comps.day, 10) // next day
    }

    func testTomorrowMorningIsNineAmNextDay() {
        let reminder = JackReminderDraft.makeReminder(
            text: "standup",
            due: .tomorrowMorning,
            now: now,
            calendar: utcCalendar
        )
        let due = try? XCTUnwrap(reminder?.dueAt)
        let comps = utcCalendar.dateComponents([.year, .month, .day, .hour, .minute], from: due ?? now)
        XCTAssertEqual(comps.hour, 9)
        XCTAssertEqual(comps.minute, 0)
        XCTAssertEqual(comps.day, 10) // 2026-06-09 -> next day is the 10th
        XCTAssertEqual(comps.month, 6)
        XCTAssertEqual(comps.year, 2026)
    }

    func testCustomDateIsPreservedExactly() {
        let target = now.addingTimeInterval(3 * 3600)
        let reminder = JackReminderDraft.makeReminder(text: "join call", due: .custom(target), now: now)
        XCTAssertEqual(reminder?.dueAt, target)
    }

    func testCreatedAtUsesInjectedNow() {
        let reminder = JackReminderDraft.makeReminder(text: "x", due: .anytime, now: now)
        XCTAssertEqual(reminder?.createdAt, now)
    }
}
