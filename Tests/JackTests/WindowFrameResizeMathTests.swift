import AppKit
import XCTest
@testable import Gilt

final class WindowFrameResizeMathTests: XCTestCase {
    private let initial = NSRect(x: 100, y: 100, width: 400, height: 300)
    private let minSize = CGSize(width: 320, height: 220)
    private let maxSize = CGSize(width: 800, height: 600)

    private func resize(
        _ edge: WindowResizeEdge,
        dx: CGFloat,
        dy: CGFloat,
        min: CGSize? = nil,
        max: CGSize? = nil
    ) -> NSRect {
        WindowFrameResizeMath.resizedFrame(
            edge: edge,
            initialFrame: initial,
            startMouse: .zero,
            currentMouse: NSPoint(x: dx, y: dy),
            minSize: min ?? minSize,
            maxSize: max ?? maxSize
        )
    }

    private func assertRect(
        _ rect: NSRect,
        _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(rect.origin.x, x, accuracy: 0.001, "origin.x", file: file, line: line)
        XCTAssertEqual(rect.origin.y, y, accuracy: 0.001, "origin.y", file: file, line: line)
        XCTAssertEqual(rect.size.width, w, accuracy: 0.001, "width", file: file, line: line)
        XCTAssertEqual(rect.size.height, h, accuracy: 0.001, "height", file: file, line: line)
    }

    // MARK: - Straight edges pin the opposite edge

    func testRightEdgeGrowsWidthOriginFixed() {
        assertRect(resize(.right, dx: 50, dy: 0), 100, 100, 450, 300)
    }

    func testLeftEdgeKeepsRightEdgePinned() {
        // Drag left edge leftward: width grows, right edge (x+width=500) holds.
        let r = resize(.left, dx: -30, dy: 0)
        assertRect(r, 70, 100, 430, 300)
        XCTAssertEqual(r.maxX, 500, accuracy: 0.001)
    }

    func testTopEdgeKeepsBottomPinned() {
        // Screen coords: top grows upward, origin.y (the bottom) stays put.
        let r = resize(.top, dx: 0, dy: 40)
        assertRect(r, 100, 100, 400, 340)
        XCTAssertEqual(r.minY, 100, accuracy: 0.001)
    }

    func testBottomEdgeKeepsTopPinned() {
        // Drag bottom edge downward: origin.y drops, top edge (y+height=400) holds.
        let r = resize(.bottom, dx: 0, dy: -25)
        assertRect(r, 100, 75, 400, 325)
        XCTAssertEqual(r.maxY, 400, accuracy: 0.001)
    }

    // MARK: - Corners pin both opposite edges

    func testBottomRightCorner() {
        let r = resize(.bottomRight, dx: 20, dy: -15)
        assertRect(r, 100, 85, 420, 315)
        XCTAssertEqual(r.minX, 100, accuracy: 0.001)
        XCTAssertEqual(r.maxY, 400, accuracy: 0.001)
    }

    func testTopLeftCorner() {
        let r = resize(.topLeft, dx: -10, dy: 10)
        assertRect(r, 90, 100, 410, 310)
        XCTAssertEqual(r.maxX, 500, accuracy: 0.001)
        XCTAssertEqual(r.minY, 100, accuracy: 0.001)
    }

    // MARK: - Minimum size clamps without unpinning the anchored edge

    func testLeftEdgeMinWidthKeepsRightPinned() {
        // Shrink the left edge well past the 320 min; right edge must stay at 500.
        let r = resize(.left, dx: 200, dy: 0)
        assertRect(r, 180, 100, 320, 300)
        XCTAssertEqual(r.maxX, 500, accuracy: 0.001)
    }

    func testBottomEdgeMinHeightKeepsTopPinned() {
        let r = resize(.bottom, dx: 0, dy: 120)
        assertRect(r, 100, 180, 400, 220)
        XCTAssertEqual(r.maxY, 400, accuracy: 0.001)
    }

    // MARK: - Maximum size clamps without unpinning the anchored edge

    func testRightEdgeMaxWidthStopsAtCeilingOriginFixed() {
        let r = resize(.right, dx: 500, dy: 0)
        assertRect(r, 100, 100, 800, 300)
    }

    func testLeftEdgeMaxWidthKeepsRightPinned() {
        // Grow the left edge past the 800 max; right edge must stay at 500.
        let r = resize(.left, dx: -500, dy: 0)
        assertRect(r, -300, 100, 800, 300)
        XCTAssertEqual(r.maxX, 500, accuracy: 0.001)
    }

    func testTopEdgeMaxHeightStopsAtCeilingBottomFixed() {
        let r = resize(.top, dx: 0, dy: 400)
        assertRect(r, 100, 100, 400, 600)
        XCTAssertEqual(r.minY, 100, accuracy: 0.001)
    }
}
