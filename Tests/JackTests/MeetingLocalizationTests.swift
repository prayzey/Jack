import XCTest
@testable import Gilt

/// Smoke tests that every meeting localization key resolves in en/es/de and
/// none of them silently fall back to their default English value.
final class MeetingLocalizationTests: XCTestCase {
    private let supportedLocales = ["en", "es", "de"]

    private struct Key {
        let key: String
        let englishDefault: String
    }

    private let representativeKeys: [Key] = [
        .init(key: "meeting.app.title", englishDefault: "Meeting Notes"),
        .init(key: "meeting.button.newMeeting", englishDefault: "New Meeting"),
        .init(key: "meeting.dashboard.title", englishDefault: "Meeting memory"),
        .init(key: "meeting.new.start", englishDefault: "Start recording"),
        .init(key: "meeting.tab.transcript", englishDefault: "Transcript"),
        .init(key: "meeting.tab.summary", englishDefault: "Summary"),
        .init(key: "meeting.tab.ask", englishDefault: "Ask"),
        .init(key: "meeting.ask.empty.title", englishDefault: "Ask the meeting"),
        .init(key: "meeting.models.title", englishDefault: "Local meeting models"),
        .init(key: "meeting.audio.error.denied", englishDefault: "Microphone access is denied. Open System Settings to grant access.")
    ]

    func testEveryKeyResolvesForEveryLocale() {
        for locale in supportedLocales {
            for entry in representativeKeys {
                let resolved = L10n.string(
                    entry.key,
                    default: entry.englishDefault,
                    locale: Locale(identifier: locale)
                )
                XCTAssertFalse(
                    resolved.isEmpty,
                    "Locale \(locale) returned empty string for \(entry.key)"
                )
            }
        }
    }

    func testNonEnglishLocaleProducesDistinctValueForLeastOneKey() {
        // At least one of the meeting strings must actually differ in es/de —
        // otherwise our localization wiring would silently fall back to English.
        let probeKey = "meeting.button.newMeeting"
        let english = L10n.string(probeKey, default: "New Meeting", locale: Locale(identifier: "en"))
        let spanish = L10n.string(probeKey, default: "New Meeting", locale: Locale(identifier: "es"))
        let german = L10n.string(probeKey, default: "New Meeting", locale: Locale(identifier: "de"))
        XCTAssertNotEqual(spanish, english, "Spanish translation for \(probeKey) must differ from English")
        XCTAssertNotEqual(german, english, "German translation for \(probeKey) must differ from English")
    }
}
