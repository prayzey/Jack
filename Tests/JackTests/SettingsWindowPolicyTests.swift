import XCTest
@testable import Gilt

@MainActor
final class SettingsWindowPolicyTests: XCTestCase {
    func testMinimumSizeProtectsCurrentSettingsLayout() {
        XCTAssertEqual(SettingsWindowPolicy.minimumWidth, 600)
        XCTAssertEqual(SettingsWindowPolicy.minimumHeight, 420)
        XCTAssertEqual(SettingsWindowPolicy.leadingTrafficLightClearanceTop, 38)
    }

    func testDefaultSizeStartsLargerThanMinimumForResizableWindow() {
        XCTAssertGreaterThan(SettingsWindowPolicy.defaultWidth, SettingsWindowPolicy.minimumWidth)
        XCTAssertGreaterThan(SettingsWindowPolicy.defaultHeight, SettingsWindowPolicy.minimumHeight)
    }

    func testApplyMakesSettingsWindowResizableAndSetsMinimums() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        SettingsWindowPolicy.apply(to: window)
        let expectedFrameMinimum = SettingsWindowPolicy.frameMinimumSize(for: window)
        let expectedFrameMaximum = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: SettingsWindowPolicy.maximumContentSize)
        ).size

        XCTAssertTrue(window.styleMask.contains(.titled))
        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.titlebarSeparatorStyle, .none)
        XCTAssertNil(window.toolbar)
        assertColorsMatch(window.backgroundColor, SettingsWindowPolicy.windowBackgroundColor)
        XCTAssertEqual(window.contentMinSize.width, SettingsWindowPolicy.minimumWidth)
        XCTAssertGreaterThan(window.contentMinSize.height, 0)
        XCTAssertEqual(window.minSize.width, expectedFrameMinimum.width)
        XCTAssertEqual(window.minSize.height, expectedFrameMinimum.height)
        XCTAssertEqual(window.contentMaxSize.width, SettingsWindowPolicy.maximumWidth)
        XCTAssertEqual(window.contentMaxSize.height, SettingsWindowPolicy.maximumHeight)
        XCTAssertEqual(window.maxSize.width, expectedFrameMaximum.width)
        XCTAssertEqual(window.maxSize.height, expectedFrameMaximum.height)
    }

    func testApplyAddsSpaceBehaviorWithoutDiscardingExistingFlags() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.collectionBehavior = [.stationary]

        SettingsWindowPolicy.apply(to: window)

        XCTAssertTrue(window.collectionBehavior.contains(.stationary))
        XCTAssertTrue(window.collectionBehavior.contains(.moveToActiveSpace))
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenAuxiliary))
    }

    private func assertColorsMatch(_ lhs: NSColor, _ rhs: NSColor, file: StaticString = #filePath, line: UInt = #line) {
        let left = lhs.usingColorSpace(.deviceRGB)
        let right = rhs.usingColorSpace(.deviceRGB)

        XCTAssertNotNil(left, file: file, line: line)
        XCTAssertNotNil(right, file: file, line: line)

        guard let left, let right else { return }

        XCTAssertEqual(left.redComponent, right.redComponent, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(left.greenComponent, right.greenComponent, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(left.blueComponent, right.blueComponent, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(left.alphaComponent, right.alphaComponent, accuracy: 0.001, file: file, line: line)
    }
}
