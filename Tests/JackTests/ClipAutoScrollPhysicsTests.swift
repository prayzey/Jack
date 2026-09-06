import CoreGraphics
import XCTest
@testable import Gilt

final class ClipAutoScrollPhysicsTests: XCTestCase {
    func testStateReturnsIdleWhenTargetIsAwayFromEdges() {
        let frame = CGRect(x: 120, y: 0, width: 180, height: 200)
        let state = clipAutoScrollState(frame: frame, viewportWidth: 600, edgeInset: 96)

        XCTAssertEqual(state.direction, 0)
        XCTAssertEqual(state.proximity, 0, accuracy: 0.001)
    }

    func testStateReturnsLeftDirectionWithClampedProximity() {
        let frame = CGRect(x: -20, y: 0, width: 180, height: 200)
        let state = clipAutoScrollState(frame: frame, viewportWidth: 600, edgeInset: 96)

        XCTAssertEqual(state.direction, -1)
        XCTAssertEqual(state.proximity, 1, accuracy: 0.001)
    }

    func testStateReturnsRightDirectionNearTrailingEdge() {
        let frame = CGRect(x: 470, y: 0, width: 150, height: 200)
        let state = clipAutoScrollState(frame: frame, viewportWidth: 600, edgeInset: 96)

        XCTAssertEqual(state.direction, 1)
        XCTAssertGreaterThan(state.proximity, 0)
        XCTAssertLessThanOrEqual(state.proximity, 1)
    }

    func testSpeedClampsToMinAndMax() {
        XCTAssertEqual(
            clipAutoScrollSpeed(proximity: -0.5, minPointsPerSecond: 200, maxPointsPerSecond: 900),
            200,
            accuracy: 0.001
        )
        XCTAssertEqual(
            clipAutoScrollSpeed(proximity: 2, minPointsPerSecond: 200, maxPointsPerSecond: 900),
            900,
            accuracy: 0.001
        )
    }

    func testSpeedIncreasesWithProximity() {
        let slow = clipAutoScrollSpeed(proximity: 0.2)
        let fast = clipAutoScrollSpeed(proximity: 0.8)
        XCTAssertGreaterThan(fast, slow)
    }
}
