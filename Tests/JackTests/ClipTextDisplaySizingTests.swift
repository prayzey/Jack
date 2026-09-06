import XCTest
@testable import Gilt

final class ClipTextDisplaySizingTests: XCTestCase {
    func testShortTextGrowsInTallCardButStaysCapped() {
        XCTAssertEqual(clipTextDisplayFontSize(characterCount: 12, availableWidth: 230, availableHeight: 250), 24)
    }

    func testLongTextKeepsBaseSize() {
        XCTAssertEqual(clipTextDisplayFontSize(characterCount: 400, availableWidth: 180, availableHeight: 170), 13)
    }

    func testMediumTextScalesWithCardSize() {
        let compact = clipTextDisplayFontSize(characterCount: 67, availableWidth: 180, availableHeight: 170)
        let stretched = clipTextDisplayFontSize(characterCount: 67, availableWidth: 230, availableHeight: 250)
        XCTAssertGreaterThan(stretched, compact)
        XCTAssertGreaterThanOrEqual(compact, 13)
    }

    func testEmptyOrDegenerateInputReturnsBase() {
        XCTAssertEqual(clipTextDisplayFontSize(characterCount: 0, availableWidth: 200, availableHeight: 200), 13)
        XCTAssertEqual(clipTextDisplayFontSize(characterCount: 5, availableWidth: 0, availableHeight: 200), 13)
    }
}
