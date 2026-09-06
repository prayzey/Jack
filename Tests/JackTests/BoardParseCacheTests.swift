import XCTest
@testable import Gilt

/// The board task/column extraction is memoized (`boardParseCache`) because
/// Kanban re-reads it once per column on every body pass and drag tick. The
/// cache revalidates against the note's current body string — these tests pin
/// the one way that can go wrong: serving stale tasks after the body changed.
@MainActor
final class BoardParseCacheTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Board/note mutations can reach clip-mirroring paths that emit
        // TelemetryDeck signals; the SDK hard-crashes if it was never
        // initialized. Debug-build signals are auto-marked as test signals,
        // so initializing here doesn't pollute production analytics.
        Analytics.initialize()
    }

    func testBoardParseCacheRevalidatesAfterEveryMutation() {
        let store = ClipboardStore()
        let boardID = store.createBoard(name: "Cache Test Board")
        // Remove the board (and its note) even if an assertion fails, so test
        // runs never leave artifacts in the developer's real notes library.
        defer { store.deleteBoard(boardID) }

        // First read parses and caches.
        XCTAssertEqual(store.tasks(for: .todo, inBoard: boardID).count, 0)

        // A mutation rewrites the note body — the next read must reparse,
        // not serve the cached empty list.
        store.createTask(title: "First task", in: .todo, boardID: boardID)
        XCTAssertEqual(store.tasks(for: .todo, inBoard: boardID).map(\.title), ["First task"])

        store.createTask(title: "Second task", in: .todo, boardID: boardID)
        XCTAssertEqual(store.tasks(for: .todo, inBoard: boardID).count, 2)

        // Moving a task across columns is also a body rewrite.
        guard let first = store.extractedTasks(forBoard: boardID).first(where: { $0.title == "First task" }) else {
            return XCTFail("task missing after creation")
        }
        store.moveTask(first, to: .doing)
        XCTAssertEqual(store.tasks(for: .todo, inBoard: boardID).map(\.title), ["Second task"])
        XCTAssertEqual(store.tasks(for: .doing, inBoard: boardID).map(\.title), ["First task"])

        // Columns come from the same cache entry and must stay fresh too.
        store.addKanbanColumn(title: "Review", boardID: boardID)
        XCTAssertTrue(store.boardColumns(forBoard: boardID).contains(where: { $0.displayTitle == "Review" }))

        // Repeated reads with no mutation are cache hits and stay consistent.
        let a = store.extractedTasks(forBoard: boardID)
        let b = store.extractedTasks(forBoard: boardID)
        XCTAssertEqual(a, b)
    }
}
