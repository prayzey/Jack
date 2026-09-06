import XCTest
import SwiftUI
@testable import Gilt

/// Tests for the pure matching/limiting rules behind the command palette. These
/// are the rules a user feels every keystroke: forgiving (case/diacritic
/// insensitive substring), keyword-aware for actions, and capped per section.
final class CommandPaletteMatcherTests: XCTestCase {

    private func makeAction(
        _ id: String,
        _ title: String,
        subtitle: String = "",
        keywords: [String] = []
    ) -> CommandAction {
        CommandAction(
            id: id,
            title: title,
            subtitle: subtitle,
            systemImage: "circle",
            accent: .white,
            keywords: keywords,
            shortcutHint: nil,
            run: {}
        )
    }

    // MARK: - matches

    func testEmptyOrWhitespaceQueryMatchesEverything() {
        XCTAssertTrue(CommandPaletteMatcher.matches(query: "", "anything"))
        XCTAssertTrue(CommandPaletteMatcher.matches(query: "   ", "anything"))
    }

    func testMatchIsCaseInsensitive() {
        XCTAssertTrue(CommandPaletteMatcher.matches(query: "MEET", "weekly meeting notes"))
        XCTAssertTrue(CommandPaletteMatcher.matches(query: "meet", "Weekly MEETING notes"))
    }

    func testMatchIsDiacriticInsensitive() {
        XCTAssertTrue(CommandPaletteMatcher.matches(query: "cafe", "Café receipt"))
    }

    func testMatchChecksAllProvidedFields() {
        XCTAssertTrue(CommandPaletteMatcher.matches(query: "safari", "Some title", "Safari"))
        XCTAssertFalse(CommandPaletteMatcher.matches(query: "zzz", "nothing here", "still nothing"))
    }

    // MARK: - filterActions

    func testFilterActionsMatchesKeywords() {
        let actions = [
            makeAction("meetings", "Meetings", subtitle: "Record a meeting", keywords: ["record", "transcribe"]),
            makeAction("notes", "Notes", subtitle: "Open notes"),
        ]
        let result = CommandPaletteMatcher.filterActions(actions, query: "record", limit: 10)
        XCTAssertEqual(result.map(\.id), ["meetings"])
    }

    func testFilterActionsMatchesTitleAndSubtitle() {
        let actions = [
            makeAction("palette", "Command Palette", subtitle: "Search every action"),
            makeAction("notes", "Notes", subtitle: "Open notes"),
        ]
        XCTAssertEqual(CommandPaletteMatcher.filterActions(actions, query: "search", limit: 10).map(\.id), ["palette"])
        XCTAssertEqual(CommandPaletteMatcher.filterActions(actions, query: "command", limit: 10).map(\.id), ["palette"])
    }

    func testFilterActionsRespectsLimit() {
        let actions = (0..<10).map { makeAction("a\($0)", "Action \($0)") }
        XCTAssertEqual(CommandPaletteMatcher.filterActions(actions, query: "", limit: 3).count, 3)
    }

    func testFilterActionsEmptyQueryReturnsAllUpToLimit() {
        let actions = [makeAction("a", "Alpha"), makeAction("b", "Beta")]
        XCTAssertEqual(CommandPaletteMatcher.filterActions(actions, query: "", limit: 10).count, 2)
    }

    // MARK: - generic filter

    func testGenericFilterMatchesFieldsAndCaps() {
        let items = ["apple pie", "banana bread", "apple tart", "cherry cake"]
        let appleOnly = CommandPaletteMatcher.filter(items, query: "apple", limit: 5) { [$0] }
        XCTAssertEqual(appleOnly, ["apple pie", "apple tart"])

        let firstAppleOnly = CommandPaletteMatcher.filter(items, query: "apple", limit: 1) { [$0] }
        XCTAssertEqual(firstAppleOnly, ["apple pie"])
    }

    func testGenericFilterEmptyQueryReturnsEverythingUpToLimit() {
        let items = ["one", "two", "three"]
        XCTAssertEqual(CommandPaletteMatcher.filter(items, query: "", limit: 2) { [$0] }.count, 2)
    }
}
