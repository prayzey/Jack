import AppKit
import XCTest
@testable import Gilt

final class WorkspaceModalPresentationTests: XCTestCase {
    func testAlertLevelFloatsWhenNoParentWindowExists() {
        XCTAssertEqual(WorkspaceModalPresentation.alertLevel(parentLevel: nil), .floating)
    }

    func testAlertLevelSitsAboveHighLevelWorkspaceWindow() {
        let workspaceLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        let alertLevel = WorkspaceModalPresentation.alertLevel(parentLevel: workspaceLevel)

        XCTAssertGreaterThan(alertLevel.rawValue, workspaceLevel.rawValue)
    }

    @MainActor
    func testModalPanelIsRaisedAgainWhenItBecomesKey() {
        let host = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 300, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        host.level = quickNoteWindowLevel()
        host.orderFrontRegardless()
        defer { host.orderOut(nil) }

        let panel = NSPanel()
        panel.level = .modalPanel
        let observer = JackModalPresentation.raiseAboveAppWindowsWhenKey(panel)
        defer { NotificationCenter.default.removeObserver(observer) }

        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: panel)

        XCTAssertGreaterThan(panel.level.rawValue, host.level.rawValue)
    }
}
