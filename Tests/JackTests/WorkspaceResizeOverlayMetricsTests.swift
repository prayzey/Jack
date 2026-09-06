import XCTest
@testable import Gilt

final class WorkspaceResizeOverlayMetricsTests: XCTestCase {
    func testTopEdgeResizeBandStaysNarrowEnoughForComfortableWindowDragging() {
        XCTAssertLessThanOrEqual(WorkspaceResizeOverlayMetrics.topEdgeThickness, 6)
    }

    func testSideAndBottomEdgesUseSharedComfortableGrabThickness() {
        XCTAssertEqual(WorkspaceResizeOverlayMetrics.edgeThickness, WindowResizeHandleMetrics.edgeThickness)
    }

    func testCornerHandlesRemainLargerThanStraightEdgesForEasyCornerResizing() {
        XCTAssertGreaterThan(WorkspaceResizeOverlayMetrics.cornerSize, WorkspaceResizeOverlayMetrics.edgeThickness)
        XCTAssertGreaterThan(WorkspaceResizeOverlayMetrics.cornerSize, WorkspaceResizeOverlayMetrics.topEdgeThickness)
    }
}
