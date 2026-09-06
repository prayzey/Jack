import AppKit
import XCTest
@testable import Gilt

final class TrackpadRevealGestureMonitorTests: XCTestCase {
    func testBottomEdgeZoneMatchesAnywhereAlongBottomWhenEnabled() {
        let configuration = TrackpadRevealConfiguration(bottomEdgeSwipeEnabled: true)
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

        XCTAssertTrue(
            trackpadRevealZoneMatches(
                pointerLocation: CGPoint(x: 80, y: 40),
                screenFrame: screen,
                configuration: configuration
            )
        )
        XCTAssertTrue(
            trackpadRevealZoneMatches(
                pointerLocation: CGPoint(x: 1320, y: 30),
                screenFrame: screen,
                configuration: configuration
            )
        )
    }

    func testBottomCenterZoneRejectsBottomCornerPointer() {
        let configuration = TrackpadRevealConfiguration(bottomCenterSwipeEnabled: true)
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

        XCTAssertFalse(
            trackpadRevealZoneMatches(
                pointerLocation: CGPoint(x: 110, y: 36),
                screenFrame: screen,
                configuration: configuration
            )
        )
    }

    func testBottomCenterZoneAcceptsPointerNearBottomMiddle() {
        let configuration = TrackpadRevealConfiguration(bottomCenterSwipeEnabled: true)
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

        XCTAssertTrue(
            trackpadRevealZoneMatches(
                pointerLocation: CGPoint(x: screen.midX, y: 32),
                screenFrame: screen,
                configuration: configuration
            )
        )
    }

    func testUpwardGestureTriggersOnceThresholdIsReached() {
        var state = TrackpadRevealSwipeState()
        let configuration = TrackpadRevealConfiguration(bottomCenterSwipeEnabled: true)
        let pointer = CGPoint(x: 720, y: 20)
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

        XCTAssertFalse(
            advanceTrackpadRevealGesture(
                state: &state,
                fingerDeltaX: 1,
                fingerDeltaY: 18,
                phase: .began,
                momentumPhase: [],
                pointerLocation: pointer,
                screenFrame: screen,
                configuration: configuration,
                swipeThreshold: 42
            )
        )

        XCTAssertTrue(
            advanceTrackpadRevealGesture(
                state: &state,
                fingerDeltaX: 0.5,
                fingerDeltaY: 26,
                phase: .changed,
                momentumPhase: [],
                pointerLocation: pointer,
                screenFrame: screen,
                configuration: configuration,
                swipeThreshold: 42
            )
        )

        XCTAssertTrue(state.hasTriggered)
    }

    func testHorizontalOrDownwardMotionDoesNotTriggerReveal() {
        var state = TrackpadRevealSwipeState()
        let configuration = TrackpadRevealConfiguration(bottomEdgeSwipeEnabled: true)
        let pointer = CGPoint(x: 300, y: 18)
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

        XCTAssertFalse(
            advanceTrackpadRevealGesture(
                state: &state,
                fingerDeltaX: 12,
                fingerDeltaY: 6,
                phase: .began,
                momentumPhase: [],
                pointerLocation: pointer,
                screenFrame: screen,
                configuration: configuration
            )
        )

        XCTAssertFalse(
            advanceTrackpadRevealGesture(
                state: &state,
                fingerDeltaX: 1,
                fingerDeltaY: -24,
                phase: .changed,
                momentumPhase: [],
                pointerLocation: pointer,
                screenFrame: screen,
                configuration: configuration
            )
        )
    }

    func testMomentumPhaseIsIgnored() {
        var state = TrackpadRevealSwipeState()
        let configuration = TrackpadRevealConfiguration(bottomEdgeSwipeEnabled: true)

        XCTAssertFalse(
            advanceTrackpadRevealGesture(
                state: &state,
                fingerDeltaX: 0,
                fingerDeltaY: 60,
                phase: .changed,
                momentumPhase: .began,
                pointerLocation: CGPoint(x: 640, y: 20),
                screenFrame: CGRect(x: 0, y: 0, width: 1280, height: 800),
                configuration: configuration
            )
        )
    }
}
