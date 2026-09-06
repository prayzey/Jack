import XCTest
@testable import Gilt

final class TextFrontierMeasurerTests: XCTestCase {
    func testEmptyTextAnchorsAtOrigin() {
        let metrics = TextFrontierMeasurer.measure(text: "", fontSize: 13, maxWidth: 260)
        XCTAssertEqual(metrics.caretTrailingX, 0, accuracy: 0.01)
        XCTAssertGreaterThan(metrics.caretCenterY, 0)
    }

    func testSingleWordAdvancesCaret() {
        let one = TextFrontierMeasurer.measure(text: "Hello", fontSize: 13, maxWidth: 260)
        let two = TextFrontierMeasurer.measure(text: "Hello again", fontSize: 13, maxWidth: 260)
        XCTAssertGreaterThan(two.caretTrailingX, one.caretTrailingX)
    }

    func testWrappedTextKeepsCaretOnLastLine() {
        let wrapped = TextFrontierMeasurer.measure(
            text: "This is a longer phrase that should wrap inside the caption box",
            fontSize: 13,
            maxWidth: 180
        )
        XCTAssertGreaterThan(wrapped.contentHeight, 18)
        XCTAssertGreaterThan(wrapped.caretTrailingX, 0)
    }
}