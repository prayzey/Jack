import XCTest
@testable import Gilt

final class NoteFrontmatterTests: XCTestCase {

    // MARK: - Happy path

    func testParsesSimpleKeyValuePairs() {
        let source = """
        ---
        type: project
        status: active
        ---

        # Title
        body content
        """
        let fm = NoteFrontmatterParser.parse(source)
        XCTAssertEqual(fm.value(for: "type"), "project")
        XCTAssertEqual(fm.value(for: "status"), "active")
        XCTAssertEqual(fm.body, "# Title\nbody content")
    }

    func testKeyLookupIsCaseInsensitive() {
        let source = """
        ---
        Type: Project
        ---
        body
        """
        let fm = NoteFrontmatterParser.parse(source)
        XCTAssertEqual(fm.value(for: "TYPE"), "Project")
        XCTAssertEqual(fm.type, "Project")
    }

    // MARK: - Quoted values

    func testStripsBalancedDoubleQuotes() {
        let source = """
        ---
        title: "Hello, world: a project"
        ---
        body
        """
        let fm = NoteFrontmatterParser.parse(source)
        XCTAssertEqual(fm.value(for: "title"), "Hello, world: a project")
    }

    func testStripsBalancedSingleQuotes() {
        let source = """
        ---
        title: 'quoted'
        ---
        body
        """
        let fm = NoteFrontmatterParser.parse(source)
        XCTAssertEqual(fm.value(for: "title"), "quoted")
    }

    func testKeepsUnbalancedQuotesAsIs() {
        // User typed half a quote — we shouldn't silently rewrite it.
        let source = """
        ---
        title: "still typing
        ---
        body
        """
        let fm = NoteFrontmatterParser.parse(source)
        XCTAssertEqual(fm.value(for: "title"), "\"still typing")
    }

    // MARK: - Edge cases

    func testReturnsEmptyWhenDocumentHasNoFrontmatter() {
        let fm = NoteFrontmatterParser.parse("# Just a heading\nthen body")
        XCTAssertTrue(fm.values.isEmpty)
        XCTAssertEqual(fm.body, "# Just a heading\nthen body")
        XCTAssertNil(fm.blockRange)
    }

    func testUnterminatedFrontmatterFallsBackToFullBody() {
        // No closing `---` => treat the whole document as body, don't swallow
        // user content silently.
        let source = """
        ---
        type: project

        # heading without close
        body
        """
        let fm = NoteFrontmatterParser.parse(source)
        XCTAssertTrue(fm.values.isEmpty)
        XCTAssertEqual(fm.body, source)
    }

    func testIgnoresLinesWithoutColons() {
        let source = """
        ---
        type: project
        not a pair line
        status: active
        ---
        body
        """
        let fm = NoteFrontmatterParser.parse(source)
        XCTAssertEqual(fm.values.count, 2)
        XCTAssertEqual(fm.value(for: "status"), "active")
    }

    func testIgnoresCommentLinesInsideFrontmatter() {
        let source = """
        ---
        # a comment
        type: project
        ---
        body
        """
        let fm = NoteFrontmatterParser.parse(source)
        XCTAssertEqual(fm.values.count, 1)
        XCTAssertEqual(fm.type, "project")
    }

    func testBlankLineBetweenFrontmatterAndBodyIsConsumed() {
        // The conventional separator blank line shouldn't appear at the top
        // of `body` — users don't think of it as note content.
        let source = """
        ---
        type: project
        ---

        first line of body
        """
        let fm = NoteFrontmatterParser.parse(source)
        XCTAssertEqual(fm.body, "first line of body")
    }

    func testHandlesValueContainingColon() {
        let source = """
        ---
        url: https://example.com:8080/path
        ---
        body
        """
        let fm = NoteFrontmatterParser.parse(source)
        XCTAssertEqual(fm.value(for: "url"), "https://example.com:8080/path")
    }

    // MARK: - Block range

    func testBlockRangeCoversDelimitersAndContent() {
        let source = """
        ---
        a: 1
        ---
        rest
        """
        let fm = NoteFrontmatterParser.parse(source)
        guard let range = fm.blockRange else {
            XCTFail("expected blockRange")
            return
        }
        XCTAssertEqual(source[range], "---\na: 1\n---\n")
    }
}
