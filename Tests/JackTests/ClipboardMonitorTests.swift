import XCTest
@testable import Gilt

@MainActor
final class ClipboardMonitorTests: XCTestCase {
    /// Regression test for the poll-timer leak.
    ///
    /// `start()` is called again on every trial-refresh tick
    /// (evaluateTrialState -> syncMonitorWithAccessState -> monitor.start()),
    /// roughly once a minute. Before the fix, each call created a fresh 0.6s
    /// repeating timer and overwrote `self.timer` WITHOUT invalidating the old
    /// one. Because the timer repeats and is retained by the run loop, every
    /// orphaned timer kept polling the pasteboard forever — thousands
    /// accumulated over days, pegging the main thread arming timers.
    func testRestartingDoesNotLeakPreviousPollTimer() {
        let monitor = ClipboardMonitor { _, _, _ in }

        monitor.start()
        // Hold a strong reference to the first timer so we can inspect whether
        // it was invalidated (the run loop also retains it, so it won't vanish).
        let firstTimer = monitor.timer
        XCTAssertNotNil(firstTimer)
        XCTAssertTrue(firstTimer?.isValid ?? false, "First start() should schedule a valid timer")

        monitor.start()

        XCTAssertFalse(
            firstTimer?.isValid ?? true,
            "Restarting must invalidate the previous poll timer instead of leaking it"
        )
        XCTAssertTrue(monitor.timer?.isValid ?? false, "A fresh timer should be active after restart")
        XCTAssertFalse(firstTimer === monitor.timer, "Restart should replace the timer instance")

        monitor.stop()
    }

    func testStopInvalidatesAndClearsTimer() {
        let monitor = ClipboardMonitor { _, _, _ in }
        monitor.start()
        let timer = monitor.timer
        XCTAssertTrue(timer?.isValid ?? false)

        monitor.stop()

        XCTAssertFalse(timer?.isValid ?? true, "stop() should invalidate the active timer")
        XCTAssertNil(monitor.timer, "stop() should clear the timer reference")
    }
}
