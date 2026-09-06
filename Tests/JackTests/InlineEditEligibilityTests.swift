import XCTest
@testable import Gilt

final class InlineEditEligibilityTests: XCTestCase {
    func testCanInlineEditAllowsTextLinkAndColor() {
        XCTAssertTrue(ClipboardStore.canInlineEdit(.text))
        XCTAssertTrue(ClipboardStore.canInlineEdit(.link))
        XCTAssertTrue(ClipboardStore.canInlineEdit(.color))
    }

    func testCanInlineEditRejectsImageAndAudio() {
        XCTAssertFalse(ClipboardStore.canInlineEdit(.image))
        XCTAssertFalse(ClipboardStore.canInlineEdit(.audio))
    }
}
