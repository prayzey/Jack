import XCTest
@testable import Gilt

@MainActor
final class SpokenEmailFormatterTests: XCTestCase {

    func testDottedLocalWithAtBecomesAddress() {
        XCTAssertEqual(
            SpokenEmailFormatter.apply("send the invoice to john dot smith at gmail dot com before friday"),
            "send the invoice to john.smith@gmail.com before friday"
        )
    }

    func testCueWordConvertsSingleWordLocal() {
        XCTAssertEqual(
            SpokenEmailFormatter.apply("my email is praise at novor dot dev"),
            "my email is praise@novor.dev"
        )
    }

    func testPrepositionalAtStaysAPreposition() {
        // "it at apple.com" is a preposition + website, not an address —
        // the domain converts but no "@" appears.
        XCTAssertEqual(
            SpokenEmailFormatter.apply("you can find it at apple dot com"),
            "you can find it at apple.com"
        )
    }

    func testSubdomainChainConverts() {
        XCTAssertEqual(
            SpokenEmailFormatter.apply("reach support at mail dot example dot co"),
            "reach support@mail.example.co"
        )
    }

    func testUnrelatedDotPhraseUntouched() {
        // No TLD, no conversion.
        XCTAssertEqual(
            SpokenEmailFormatter.apply("the meeting at nine dot thirty"),
            "the meeting at nine dot thirty"
        )
    }
}
