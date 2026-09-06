import AppKit
import XCTest
@testable import Gilt

@MainActor
final class WindowEdgeResizeChromeTests: XCTestCase {
    private let windowSize = NSSize(width: 560, height: 420)

    private func makeChrome() -> WindowEdgeResizeChromeNSView {
        let chrome = WindowEdgeResizeChromeNSView(frame: NSRect(origin: .zero, size: windowSize))
        chrome.configure(
            minSize: quickNoteMinimumWindowSize,
            edgeThickness: 24,
            topEdgeThickness: 14,
            cornerSize: 36,
            usesDynamicQuickNoteCanvasInset: true,
            usesDynamicTopDragGap: true
        )
        return chrome
    }

    private var canvasInset: CGFloat {
        quickNoteWindowCanvasInset(for: windowSize)
    }

    func testChromeLayerDoesNotTintTransparentWindowMargin() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let chrome = makeChrome()

        window.contentView = chrome

        XCTAssertEqual(chrome.layer?.backgroundColor?.alpha ?? 0, 0, accuracy: 0.0001)
    }

    func testLeftEdgeHitAlignsWithVisibleCard() {
        let chrome = makeChrome()
        let inset = canvasInset

        XCTAssertEqual(chrome.hitTest(NSPoint(x: inset + 8, y: 210)), chrome)
        XCTAssertEqual(chrome.hitTest(NSPoint(x: inset + 20, y: 80)), chrome)
        XCTAssertNil(chrome.hitTest(NSPoint(x: inset + 80, y: 210)))
        XCTAssertEqual(chrome.hitTest(NSPoint(x: 8, y: 210)), chrome)
    }

    func testRightEdgeHitAlignsWithVisibleCard() {
        let chrome = makeChrome()
        let inset = canvasInset
        let rightCardEdge = windowSize.width - inset

        XCTAssertEqual(chrome.hitTest(NSPoint(x: rightCardEdge - 8, y: 210)), chrome)
        XCTAssertEqual(chrome.hitTest(NSPoint(x: rightCardEdge - 20, y: 360)), chrome)
        XCTAssertNil(chrome.hitTest(NSPoint(x: rightCardEdge - 80, y: 210)))
        XCTAssertEqual(chrome.hitTest(NSPoint(x: windowSize.width - 8, y: 210)), chrome)
    }

    func testTopCenterDragGapIsClickThroughOnCard() {
        let chrome = makeChrome()
        let inset = canvasInset
        let cardWidth = windowSize.width - inset * 2
        let centerX = inset + cardWidth / 2

        XCTAssertNil(chrome.hitTest(NSPoint(x: centerX, y: inset + 6)))
        XCTAssertEqual(chrome.hitTest(NSPoint(x: inset + 40, y: inset + 6)), chrome)
        XCTAssertEqual(chrome.hitTest(NSPoint(x: windowSize.width - inset - 40, y: inset + 6)), chrome)
    }

    func testEdgeHitOutsetExtendsBeyondDrawnBand() {
        let chrome = makeChrome()
        let inset = canvasInset

        XCTAssertEqual(chrome.hitTest(NSPoint(x: inset - 4, y: 210)), chrome)
        XCTAssertEqual(
            chrome.hitTest(NSPoint(x: windowSize.width - inset + 4, y: 210)),
            chrome
        )
    }
}
