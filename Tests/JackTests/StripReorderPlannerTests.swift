import CoreGraphics
import XCTest
@testable import Gilt

final class StripReorderPlannerTests: XCTestCase {
    func testReversedTrayMapsVisualPlacementBackToStoredOrder() {
        XCTAssertEqual(logicalStripPlacement(.before, newestOnRight: false), .before)
        XCTAssertEqual(logicalStripPlacement(.before, newestOnRight: true), .after)
        XCTAssertEqual(logicalStripPlacement(.after, newestOnRight: true), .before)
    }

    func testPlacementStaysBeforeUntilCursorPassesHalfway() {
        XCTAssertEqual(stripReorderPlacement(locationX: 79, targetWidth: 160), .before)
        XCTAssertEqual(stripReorderPlacement(locationX: 80, targetWidth: 160), .before)
        XCTAssertEqual(stripReorderPlacement(locationX: 81, targetWidth: 160), .after)
    }

    func testReorderedStripIDsMovesDraggedItemBeforeTarget() {
        let ids = [UUID(), UUID(), UUID(), UUID()]

        let reordered = reorderedStripIDs(
            ids: ids,
            draggedID: ids[3],
            targetID: ids[1],
            placement: .before
        )

        XCTAssertEqual(reordered, [ids[0], ids[3], ids[1], ids[2]])
    }

    func testReorderedStripIDsMovesDraggedItemAfterTarget() {
        let ids = [UUID(), UUID(), UUID(), UUID()]

        let reordered = reorderedStripIDs(
            ids: ids,
            draggedID: ids[0],
            targetID: ids[2],
            placement: .after
        )

        XCTAssertEqual(reordered, [ids[1], ids[2], ids[0], ids[3]])
    }

    func testReorderedStripIDsReturnsNilWhenPlacementDoesNotChangeOrder() {
        let ids = [UUID(), UUID(), UUID()]

        XCTAssertNil(
            reorderedStripIDs(
                ids: ids,
                draggedID: ids[0],
                targetID: ids[1],
                placement: .before
            )
        )

        XCTAssertNil(
            reorderedStripIDs(
                ids: ids,
                draggedID: ids[2],
                targetID: ids[1],
                placement: .after
            )
        )
    }

    func testHorizontalReorderTargetAdvancesToNearestNeighborAcrossGap() {
        let ids = [UUID(), UUID(), UUID()]
        let frames: [UUID: CGRect] = [
            ids[0]: CGRect(x: 0, y: 0, width: 100, height: 40),
            ids[1]: CGRect(x: 112, y: 0, width: 100, height: 40),
            ids[2]: CGRect(x: 224, y: 0, width: 100, height: 40),
        ]

        let target = horizontalReorderTarget(
            ids: ids,
            frames: frames,
            draggedID: ids[0],
            locationX: 230
        )

        XCTAssertEqual(target, HorizontalReorderTarget(targetID: ids[2], placement: .before))
    }

    func testNearestHorizontalTargetUsesClosestFrameForFolderHover() {
        let ids = [UUID(), UUID(), UUID()]
        let frames: [UUID: CGRect] = [
            ids[0]: CGRect(x: 0, y: 0, width: 80, height: 30),
            ids[1]: CGRect(x: 90, y: 0, width: 80, height: 30),
            ids[2]: CGRect(x: 180, y: 0, width: 80, height: 30),
        ]

        XCTAssertEqual(nearestHorizontalTargetID(ids: ids, frames: frames, locationX: 175), ids[1])
        XCTAssertEqual(nearestHorizontalTargetID(ids: ids, frames: frames, locationX: 181), ids[2])
    }

    func testReorderedProviderIDsMovesDraggedProviderAfterTarget() {
        let ids = ["claude", "cursor", "codex", "windsurf"]

        let reordered = reorderedProviderIDs(
            ids: ids,
            draggedID: "claude",
            targetID: "codex",
            placement: .after
        )

        XCTAssertEqual(reordered, ["cursor", "codex", "claude", "windsurf"])
    }
}

final class LiveReorderPlannerTests: XCTestCase {
    private let ids = [UUID(), UUID(), UUID(), UUID()]
    private var frames: [UUID: CGRect] {
        // Pills 80 wide with 6 spacing: 0-80, 86-166, 172-252, 258-338
        Dictionary(uniqueKeysWithValues: ids.enumerated().map { index, id in
            (id, CGRect(x: CGFloat(index) * 86, y: 0, width: 80, height: 30))
        })
    }

    func testIndexAdvancesOnceCenterPassesNeighborMidpoint() {
        XCTAssertEqual(liveReorderIndex(ids: ids, frames: frames, draggedID: ids[0], translationX: 0), 0)
        XCTAssertEqual(liveReorderIndex(ids: ids, frames: frames, draggedID: ids[0], translationX: 80), 0)
        XCTAssertEqual(liveReorderIndex(ids: ids, frames: frames, draggedID: ids[0], translationX: 90), 1)
        XCTAssertEqual(liveReorderIndex(ids: ids, frames: frames, draggedID: ids[0], translationX: 400), 3)
    }

    func testIndexRetreatsWhenDraggingLeft() {
        XCTAssertEqual(liveReorderIndex(ids: ids, frames: frames, draggedID: ids[3], translationX: -90), 2)
        XCTAssertEqual(liveReorderIndex(ids: ids, frames: frames, draggedID: ids[3], translationX: -400), 0)
    }

    func testShiftsOpenGapOnlyBetweenDraggedAndTarget() {
        let shifts = liveReorderShifts(ids: ids, frames: frames, draggedID: ids[0], targetIndex: 2, spacing: 6)
        XCTAssertEqual(shifts, [ids[1]: -86, ids[2]: -86])

        let back = liveReorderShifts(ids: ids, frames: frames, draggedID: ids[3], targetIndex: 1, spacing: 6)
        XCTAssertEqual(back, [ids[1]: 86, ids[2]: 86])

        XCTAssertTrue(liveReorderShifts(ids: ids, frames: frames, draggedID: ids[1], targetIndex: 1, spacing: 6).isEmpty)
    }

    func testCommitRoundTripsThroughReorderedStripIDs() {
        let forward = liveReorderCommit(ids: ids, draggedID: ids[0], targetIndex: 2)!
        XCTAssertEqual(
            reorderedStripIDs(ids: ids, draggedID: ids[0], targetID: forward.targetID, placement: forward.placement),
            [ids[1], ids[2], ids[0], ids[3]]
        )

        let backward = liveReorderCommit(ids: ids, draggedID: ids[3], targetIndex: 1)!
        XCTAssertEqual(
            reorderedStripIDs(ids: ids, draggedID: ids[3], targetID: backward.targetID, placement: backward.placement),
            [ids[0], ids[3], ids[1], ids[2]]
        )

        XCTAssertNil(liveReorderCommit(ids: ids, draggedID: ids[2], targetIndex: 2))
    }
}
