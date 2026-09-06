import XCTest
@testable import Gilt

final class WikilinkExtractorTests: XCTestCase {

    // MARK: - Basic extraction

    func testExtractsSimpleWikilink() {
        let targets = WikilinkExtractor.targets(in: "See [[Project Apollo]] for context.")
        XCTAssertEqual(targets, ["Project Apollo"])
    }

    func testAliasedWikilinkYieldsTargetNotAlias() {
        let targets = WikilinkExtractor.targets(in: "Read [[Project Apollo|the moonshot]] later.")
        XCTAssertEqual(targets, ["Project Apollo"])
    }

    func testExtractsMultipleWikilinksInOrder() {
        let body = "[[A]] and [[B]] together with [[C]]"
        XCTAssertEqual(WikilinkExtractor.targets(in: body), ["A", "B", "C"])
    }

    func testIgnoresEmptyWikilink() {
        // `[[]]` should not show up as a hit — empty target is meaningless.
        XCTAssertTrue(WikilinkExtractor.targets(in: "stray [[]] markers").isEmpty)
    }

    func testExtractsAfterUnicodePrefix() {
        // Emoji + non-ASCII before the link exercise UTF-16 offsets in the
        // line-masking path.
        let body = "🚀 hello — see [[São Paulo]] for more"
        XCTAssertEqual(WikilinkExtractor.targets(in: body), ["São Paulo"])
    }

    // MARK: - Code-block exclusions

    func testSkipsWikilinksInsideFencedCode() {
        let body = """
        Outside [[A]]
        ```
        Inside [[B]] should be ignored
        ```
        Outside [[C]]
        """
        XCTAssertEqual(WikilinkExtractor.targets(in: body), ["A", "C"])
    }

    func testSkipsWikilinksInsideInlineCode() {
        let body = "real link [[A]] but `not [[B]]` is escaped"
        XCTAssertEqual(WikilinkExtractor.targets(in: body), ["A"])
    }

    func testFenceWithLanguageTagStillToggles() {
        let body = """
        ```swift
        [[Hidden]]
        ```
        [[Visible]]
        """
        XCTAssertEqual(WikilinkExtractor.targets(in: body), ["Visible"])
    }

    // MARK: - Line boundaries

    func testDoesNotCrossNewlines() {
        // A `[[ \n ]]` across two lines isn't a single link — it shouldn't
        // greedily span the gap.
        let body = "danger [[unterminated\n]] tail"
        XCTAssertTrue(WikilinkExtractor.targets(in: body).isEmpty)
    }

    // MARK: - uniqueTargets

    func testUniqueTargetsAreCaseInsensitive() {
        let body = "[[Apollo]] then [[apollo]] then [[APOLLO]]"
        XCTAssertEqual(WikilinkExtractor.uniqueTargets(in: body).count, 1)
    }

    func testUniqueTargetsPreservesFirstSpelling() {
        let body = "[[Apollo]] and later [[apollo]]"
        XCTAssertEqual(WikilinkExtractor.uniqueTargets(in: body), ["Apollo"])
    }
}
