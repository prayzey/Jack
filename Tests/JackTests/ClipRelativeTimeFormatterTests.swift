import Foundation
import XCTest
@testable import Gilt

final class ClipRelativeTimeFormatterTests: XCTestCase {
    func testEnglishRelativeTimeUsesLocaleAwareShortFormat() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let date = now.addingTimeInterval(-60)

        let value = ClipRelativeTimeFormatter.string(
            from: date,
            relativeTo: now,
            locale: Locale(identifier: "en")
        )

        XCTAssertEqual(value, "1 min. ago")
    }

    func testSpanishRelativeTimeUsesSpanishFormatterOutput() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let date = now.addingTimeInterval(-60)

        let value = ClipRelativeTimeFormatter.string(
            from: date,
            relativeTo: now,
            locale: Locale(identifier: "es")
        )

        XCTAssertEqual(value, "hace 1 min")
    }

    func testGermanRelativeTimeUsesGermanFormatterOutput() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let date = now.addingTimeInterval(-7200)

        let value = ClipRelativeTimeFormatter.string(
            from: date,
            relativeTo: now,
            locale: Locale(identifier: "de")
        )

        XCTAssertEqual(value, "vor 2 Std.")
    }
}
