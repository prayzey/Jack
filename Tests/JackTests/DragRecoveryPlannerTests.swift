import XCTest
@testable import Gilt

final class DragRecoveryPlannerTests: XCTestCase {
    func testStopsWaitingWhenDragAlreadyEnded() {
        let expectedDragID = UUID()

        XCTAssertEqual(
            dragRecoveryAction(
                currentDraggedID: nil as UUID?,
                expectedDraggedID: expectedDragID,
                currentTargetID: nil as UUID?,
                pressedMouseButtons: 0
            ),
            .stopWaiting
        )
    }

    func testStopsWaitingWhenCursorReturnsToTargetZone() {
        let dragID = UUID()

        XCTAssertEqual(
            dragRecoveryAction(
                currentDraggedID: dragID,
                expectedDraggedID: dragID,
                currentTargetID: UUID(),
                pressedMouseButtons: 1
            ),
            .stopWaiting
        )
    }

    func testKeepsWaitingWhileMouseIsStillHeldOutsideDropZone() {
        let dragID = UUID()

        XCTAssertEqual(
            dragRecoveryAction(
                currentDraggedID: dragID,
                expectedDraggedID: dragID,
                currentTargetID: nil as UUID?,
                pressedMouseButtons: 1
            ),
            .keepWaiting
        )
    }

    func testKeepsClipDragAliveWhileCrossingTowardFolderTabs() {
        let draggedClipID = UUID()

        XCTAssertEqual(
            dragRecoveryAction(
                currentDraggedID: draggedClipID,
                expectedDraggedID: draggedClipID,
                currentTargetID: nil as UUID?,
                pressedMouseButtons: 1
            ),
            .keepWaiting
        )
    }

    func testClearsDragStateAfterMouseIsReleasedOutsideDropZone() {
        let dragID = UUID()

        XCTAssertEqual(
            dragRecoveryAction(
                currentDraggedID: dragID,
                expectedDraggedID: dragID,
                currentTargetID: nil as UUID?,
                pressedMouseButtons: 0
            ),
            .clearDragState
        )
    }
}
