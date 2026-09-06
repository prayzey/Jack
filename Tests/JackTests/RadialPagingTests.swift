import XCTest
@testable import Gilt

final class RadialPagingTests: XCTestCase {
    func testPageCountRoundsUp() {
        XCTAssertEqual(radialPageCount(total: 0, pageSize: 8, maxPages: 6), 1)
        XCTAssertEqual(radialPageCount(total: 8, pageSize: 8, maxPages: 6), 1)
        XCTAssertEqual(radialPageCount(total: 9, pageSize: 8, maxPages: 6), 2)
        XCTAssertEqual(radialPageCount(total: 17, pageSize: 8, maxPages: 6), 3)
    }

    func testPageCountCapsAtMaxPages() {
        XCTAssertEqual(radialPageCount(total: 49, pageSize: 8, maxPages: 6), 6)
        XCTAssertEqual(radialPageCount(total: 200, pageSize: 8, maxPages: 6), 6)
    }

    func testPageIndexIsClamped() {
        XCTAssertEqual(clampedRadialPageIndex(index: -1, total: 20, pageSize: 8, maxPages: 6), 0)
        XCTAssertEqual(clampedRadialPageIndex(index: 0, total: 20, pageSize: 8, maxPages: 6), 0)
        XCTAssertEqual(clampedRadialPageIndex(index: 2, total: 20, pageSize: 8, maxPages: 6), 2)
        XCTAssertEqual(clampedRadialPageIndex(index: 9, total: 20, pageSize: 8, maxPages: 6), 2)
    }

    func testPageIndexClampsToMaxPageCap() {
        XCTAssertEqual(clampedRadialPageIndex(index: 9, total: 100, pageSize: 8, maxPages: 6), 5)
    }

    func testPageSliceReturnsExpectedItems() {
        let values = Array(0..<20)
        XCTAssertEqual(Array(radialPageSlice(values, pageIndex: 0, pageSize: 8, maxPages: 6)), Array(0..<8))
        XCTAssertEqual(Array(radialPageSlice(values, pageIndex: 1, pageSize: 8, maxPages: 6)), Array(8..<16))
        XCTAssertEqual(Array(radialPageSlice(values, pageIndex: 2, pageSize: 8, maxPages: 6)), Array(16..<20))
    }

    func testPageSliceCapsAtFortyEightItems() {
        let values = Array(0..<100)
        XCTAssertEqual(
            Array(radialPageSlice(values, pageIndex: 5, pageSize: 8, maxPages: 6)),
            Array(40..<48)
        )
    }
}
