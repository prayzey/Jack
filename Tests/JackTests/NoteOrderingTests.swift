import XCTest
@testable import Gilt

/// Tests for the pure reorder math behind sidebar drag-and-drop.
///
/// The thing we care most about: when the user drags an item *downwards*, the
/// drop slot the UI reports is computed against the pre-removal list, so the
/// insertion index has to shift up by one. Easy to get wrong, hence the
/// dedicated suite.
final class NoteOrderingTests: XCTestCase {

    // MARK: - Downward moves

    func testMoveDownAdjustsTargetByOne() {
        // Dragging "A" (index 0) past "C" to the position that *looks* like
        // index 3 in the pre-removal list should leave A in slot 2 (between
        // C and D), not slot 3 (after D).
        let result = NoteOrdering.reorder(["A", "B", "C", "D"], from: 0, to: 3)
        XCTAssertEqual(result, ["B", "C", "A", "D"])
    }

    func testMoveDownToEndLandsAtTail() {
        let result = NoteOrdering.reorder(["A", "B", "C", "D"], from: 0, to: 4)
        XCTAssertEqual(result, ["B", "C", "D", "A"])
    }

    // MARK: - Upward moves

    func testMoveUpDoesNotAdjust() {
        let result = NoteOrdering.reorder(["A", "B", "C", "D"], from: 3, to: 1)
        XCTAssertEqual(result, ["A", "D", "B", "C"])
    }

    func testMoveUpToHeadLandsAtSlotZero() {
        let result = NoteOrdering.reorder(["A", "B", "C", "D"], from: 2, to: 0)
        XCTAssertEqual(result, ["C", "A", "B", "D"])
    }

    // MARK: - No-op drops

    func testDropOnOwnSlotIsNoOp() {
        let result = NoteOrdering.reorder(["A", "B", "C"], from: 1, to: 1)
        XCTAssertEqual(result, ["A", "B", "C"])
    }

    func testDropOnSlotImmediatelyAfterSelfIsNoOp() {
        // "Drop B at slot 2" while B is at index 1 — after removing B, slot 2
        // becomes slot 1, which is exactly where B started.
        let result = NoteOrdering.reorder(["A", "B", "C"], from: 1, to: 2)
        XCTAssertEqual(result, ["A", "B", "C"])
    }

    // MARK: - Bounds

    func testTargetBelowZeroClampsToHead() {
        let result = NoteOrdering.reorder(["A", "B", "C"], from: 2, to: -5)
        XCTAssertEqual(result, ["C", "A", "B"])
    }

    func testTargetBeyondEndClampsToTail() {
        let result = NoteOrdering.reorder(["A", "B", "C"], from: 0, to: 99)
        XCTAssertEqual(result, ["B", "C", "A"])
    }

    func testCurrentIndexOutOfRangeReturnsInputUnchanged() {
        let result = NoteOrdering.reorder(["A", "B"], from: 5, to: 0)
        XCTAssertEqual(result, ["A", "B"])
    }

    func testEmptyListIsUnchanged() {
        let result = NoteOrdering.reorder([Int](), from: 0, to: 0)
        XCTAssertEqual(result, [])
    }
}
