import XCTest
@testable import Gilt

@MainActor
final class ClipDragLifecycleTests: XCTestCase {
    func testBeginPostsClipDragDidStart() {
        let posted = expectation(forNotification: .clipDragDidStart, object: nil)

        ClipDragLifecycle.begin()

        wait(for: [posted], timeout: 1.0)
    }

    func testEndPostsClipDragDidEnd() {
        let posted = expectation(forNotification: .clipDragDidEnd, object: nil)

        ClipDragLifecycle.end()

        wait(for: [posted], timeout: 1.0)
    }

    func testMouseReleaseRecoveryEndsDragWhenDropDoesNotHandleIt() {
        let started = expectation(forNotification: .clipDragDidStart, object: nil)
        let ended = expectation(forNotification: .clipDragDidEnd, object: nil)

        ClipDragLifecycle.beginWithMouseReleaseRecovery(isMousePressed: { false })

        wait(for: [started, ended], timeout: 1.0)
    }
}
