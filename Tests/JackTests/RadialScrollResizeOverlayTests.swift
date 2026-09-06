import CoreGraphics
import XCTest
@testable import Gilt

final class RadialScrollResizeOverlayTests: XCTestCase {
    func testHorizontalDominantScrollRoutesToPaging() {
        let action = radialScrollAction(
            deltaX: 9,
            deltaY: 3,
            locationInView: CGPoint(x: 100, y: 100),
            bounds: CGRect(x: 0, y: 0, width: 200, height: 200)
        )
        guard case .page(let deltaX)? = action else {
            return XCTFail("Expected paging action")
        }
        XCTAssertEqual(deltaX, 9, accuracy: 0.001)
    }

    func testIgnoresScrollOutsideCircle() {
        let action = radialScrollAction(
            deltaX: 0,
            deltaY: 6,
            locationInView: CGPoint(x: 5, y: 5),
            bounds: CGRect(x: 0, y: 0, width: 200, height: 200)
        )
        XCTAssertNil(action)
    }

    func testVerticalScrollInsideCircleRoutesToResize() {
        let action = radialScrollAction(
            deltaX: 1,
            deltaY: 8,
            locationInView: CGPoint(x: 100, y: 100),
            bounds: CGRect(x: 0, y: 0, width: 200, height: 200)
        )
        guard case .resize(let deltaY)? = action else {
            return XCTFail("Expected resize action")
        }
        XCTAssertEqual(deltaY, 8, accuracy: 0.001)
    }
}
