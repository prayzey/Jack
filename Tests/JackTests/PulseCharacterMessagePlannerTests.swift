import XCTest
@testable import Gilt

final class PulseCharacterMessagePlannerTests: XCTestCase {

    func testInspirationResourcesProvideLargeMessageBankForEachSupportedLanguage() {
        for identifier in ["en", "es", "de"] {
            XCTAssertGreaterThanOrEqual(
                PulseInspirationMessageCatalog.messages(localeIdentifier: identifier).count,
                PulseInspirationMessageCatalog.minimumMessageCount,
                "\(identifier) should include a large Pulse message bank"
            )
        }
    }

    func testInspirationResourcesFitCharacterBubbleAndExpandedPopover() {
        for identifier in ["en", "es", "de"] {
            for message in PulseInspirationMessageCatalog.messages(localeIdentifier: identifier) {
                XCTAssertFalse(message.id.isEmpty)
                XCTAssertLessThanOrEqual(message.bubble.count, PulseCharacterMessagePlanner.maxBubbleCharacters)
                XCTAssertFalse(message.expanded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                XCTAssertLessThanOrEqual(message.expanded.count, 220)
            }
        }
    }

    func testInspirationResourceTranslationsShareStableIDs() {
        let englishIDs = PulseInspirationMessageCatalog.messages(localeIdentifier: "en").map(\.id)

        for identifier in ["es", "de"] {
            XCTAssertEqual(
                PulseInspirationMessageCatalog.messages(localeIdentifier: identifier).map(\.id),
                englishIDs,
                "\(identifier) should translate the same Pulse message IDs in the same order"
            )
        }
    }

    func testInspirationSelectionChangesAcrossSameDaySlots() throws {
        let calendar = Calendar(identifier: .gregorian)
        let morning = Date(timeIntervalSince1970: 1_704_067_200)
        let later = morning.addingTimeInterval(60 * 60)
        let first = PulseInspirationMessageCatalog.message(for: morning, localeIdentifier: "en", calendar: calendar)
        let second = PulseInspirationMessageCatalog.message(for: later, localeIdentifier: "en", calendar: calendar)

        XCTAssertNotEqual(first.id, second.id)
    }

    func testUsageOnlyDoesNotCreateAmbientMessage() {
        let planner = PulseCharacterMessagePlanner()
        let message = planner.ambientMessage(
            configuration: PulseCharacterMessageConfiguration(
                mode: .usageOnly,
                customMessage: "Keep going",
                reminders: []
            )
        )

        XCTAssertNil(message)
    }

    func testDueReminderBeatsCustomAndInspiration() throws {
        let planner = PulseCharacterMessagePlanner()
        let reminderID = UUID()
        let now = Date(timeIntervalSince1970: 2_000)
        let reminder = PulseReminder(
            id: reminderID,
            message: "Send the client update",
            createdAt: now.addingTimeInterval(-60),
            dueAt: now.addingTimeInterval(-1)
        )

        let message = try XCTUnwrap(planner.ambientMessage(
            configuration: PulseCharacterMessageConfiguration(
                mode: .remindersAndInspiration,
                customMessage: "Custom line",
                reminders: [reminder]
            ),
            now: now
        ))

        XCTAssertEqual(message.text, "Send the client update")
        XCTAssertEqual(message.source, .reminder(reminderID))
    }

    func testFutureReminderWaitsAndRecurringReminderMessageShows() throws {
        let planner = PulseCharacterMessagePlanner()
        let now = Date(timeIntervalSince1970: 2_000)
        let reminder = PulseReminder(
            message: "Future thing",
            createdAt: now,
            dueAt: now.addingTimeInterval(60)
        )

        let message = try XCTUnwrap(planner.ambientMessage(
            configuration: PulseCharacterMessageConfiguration(
                mode: .remindersAndInspiration,
                customMessage: "Custom line",
                reminders: [reminder]
            ),
            now: now
        ))

        XCTAssertEqual(message.text, "Custom line")
        XCTAssertEqual(message.source, .recurringReminder)
    }

    func testCustomModeMessageStaysCustomInsteadOfNotificationReminder() throws {
        let planner = PulseCharacterMessagePlanner()

        let message = try XCTUnwrap(planner.ambientMessage(
            configuration: PulseCharacterMessageConfiguration(
                mode: .custom,
                customMessage: "Pray",
                reminders: []
            )
        ))

        XCTAssertEqual(message.text, "Pray")
        XCTAssertEqual(message.source, .custom)
    }

    func testLongCustomMessageIsTrimmedForBubble() throws {
        let planner = PulseCharacterMessagePlanner()
        let longMessage = String(repeating: "Focus ", count: 30)

        let message = try XCTUnwrap(planner.ambientMessage(
            configuration: PulseCharacterMessageConfiguration(
                mode: .custom,
                customMessage: longMessage,
                reminders: []
            )
        ))

        XCTAssertLessThanOrEqual(message.text.count, PulseCharacterMessagePlanner.maxBubbleCharacters)
        XCTAssertTrue(message.text.hasSuffix("..."))
        XCTAssertEqual(message.expandedText, longMessage.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func testAmbientMessagesCanReplaceRoutineIntervalUsage() {
        let planner = PulseCharacterMessagePlanner()

        XCTAssertTrue(planner.shouldPreferAmbientMessage(
            configuration: PulseCharacterMessageConfiguration(
                mode: .dailyInspiration,
                customMessage: "",
                reminders: []
            ),
            overRoutineUsage: .interval
        ))
        XCTAssertFalse(planner.shouldPreferAmbientMessage(
            configuration: PulseCharacterMessageConfiguration(
                mode: .dailyInspiration,
                customMessage: "",
                reminders: []
            ),
            overRoutineUsage: .threshold
        ))
    }
}
