import XCTest
@testable import Gilt

/// Locks in the search contract the vault destination picker relies on: it
/// reuses `CommandPaletteMatcher.filter` over relative folder paths, so empty
/// queries show everything (capped), matching is case- and diacritic-insensitive
/// substring, and a no-match returns [] (which is what makes the picker offer
/// the "Use <typed>" create affordance).
final class NoteVaultPickerFilterTests: XCTestCase {
    private let folders = ["Archive", "Projects", "Projects/Q3", "Reading/Books", "Café Notes"]

    private func filter(_ query: String, limit: Int = 200) -> [String] {
        CommandPaletteMatcher.filter(folders, query: query, limit: limit) { [$0] }
    }

    func testEmptyQueryReturnsAll() {
        XCTAssertEqual(filter(""), folders)
        XCTAssertEqual(filter("   "), folders)
    }

    func testCaseInsensitiveSubstring() {
        XCTAssertEqual(filter("projects"), ["Projects", "Projects/Q3"])
    }

    func testMatchesNestedSegment() {
        XCTAssertEqual(filter("books"), ["Reading/Books"])
    }

    func testDiacriticInsensitive() {
        XCTAssertEqual(filter("cafe"), ["Café Notes"])
    }

    func testNoMatchReturnsEmpty() {
        XCTAssertTrue(filter("zzz").isEmpty)
    }

    func testLimitRespected() {
        XCTAssertEqual(filter("", limit: 2).count, 2)
    }
}
