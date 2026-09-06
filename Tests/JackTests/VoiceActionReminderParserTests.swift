import XCTest
@testable import Gilt

final class VoiceActionReminderParserTests: XCTestCase {
    private var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private var now: Date {
        utcCalendar.date(
            from: DateComponents(year: 2026, month: 6, day: 9, hour: 12, minute: 0, second: 0)
        )!
    }

    func testRecognizesRemindMePrefix() {
        let result = VoiceActionReminderParser.parse(
            "remind me to call mom tomorrow",
            now: now,
            calendar: utcCalendar
        )
        guard case .success(let title, let due) = result else {
            return XCTFail("Expected success, got \(result)")
        }
        XCTAssertEqual(title, "call mom")
        XCTAssertEqual(due, .tomorrowMorning)
    }

    func testInThirtyMinutes() {
        let result = VoiceActionReminderParser.parse(
            "remind me to stretch in 30 minutes",
            now: now,
            calendar: utcCalendar
        )
        guard case .success(let title, let due) = result else {
            return XCTFail("Expected success")
        }
        XCTAssertEqual(title, "stretch")
        XCTAssertEqual(due, .inThirtyMinutes)
    }

    func testRememberToPhrase() {
        let result = VoiceActionReminderParser.parse(
            "remember to water the plants",
            now: now,
            calendar: utcCalendar
        )
        guard case .success(let title, let due) = result else {
            return XCTFail("Expected success")
        }
        XCTAssertEqual(title, "water the plants")
        XCTAssertEqual(due, .anytime)
    }

    func testNonReminderReturnsNotAReminder() {
        XCTAssertEqual(
            VoiceActionReminderParser.parse("play some music", now: now, calendar: utcCalendar),
            .notAReminder
        )
    }

    func testSpotifyParserPlayPauseSkip() {
        XCTAssertEqual(SpotifyVoiceParser.parse("play"), .play)
        XCTAssertEqual(SpotifyVoiceParser.parse("pause"), .pause)
        XCTAssertEqual(SpotifyVoiceParser.parse("skip this song"), .skip)
        XCTAssertEqual(SpotifyVoiceParser.parse("what's playing"), .currentTrack)
    }
}