import AppKit
import XCTest
@testable import Gilt

@MainActor
final class TrayShowNotificationTests: XCTestCase {
    func testTrayShowEmitsSnapAndSearchEvents() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let snap = XCTNSNotificationExpectation(name: .requestClipStripSnapToLatest, object: window)
        let search = XCTNSNotificationExpectation(name: .requestSearchFocus)

        AppWindowManager.postTrayDidShowNotifications(window: window)

        wait(for: [snap, search], timeout: 1)
    }
}
