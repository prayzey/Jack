import XCTest
@testable import Gilt

/// Covers the pure pagination math used by the reminders list so a stale page
/// index after a delete can never read out of bounds, and page counts are right.
final class JackReminderPaginatorTests: XCTestCase {

    func testPageCountRoundsUp() {
        XCTAssertEqual(JackReminderPaginator.pageCount(total: 0, pageSize: 4), 1)
        XCTAssertEqual(JackReminderPaginator.pageCount(total: 4, pageSize: 4), 1)
        XCTAssertEqual(JackReminderPaginator.pageCount(total: 5, pageSize: 4), 2)
        XCTAssertEqual(JackReminderPaginator.pageCount(total: 13, pageSize: 6), 3)
    }

    func testPageCountGuardsZeroPageSize() {
        XCTAssertEqual(JackReminderPaginator.pageCount(total: 10, pageSize: 0), 1)
    }

    func testClampedPageStaysInRange() {
        // 5 items, 4 per page -> pages 0...1. A stale page 5 clamps to 1.
        XCTAssertEqual(JackReminderPaginator.clampedPage(5, total: 5, pageSize: 4), 1)
        XCTAssertEqual(JackReminderPaginator.clampedPage(-3, total: 5, pageSize: 4), 0)
        XCTAssertEqual(JackReminderPaginator.clampedPage(0, total: 0, pageSize: 4), 0)
    }

    func testPageReturnsCorrectSlice() {
        let items = Array(0..<10)
        XCTAssertEqual(JackReminderPaginator.page(items, page: 0, pageSize: 4), [0, 1, 2, 3])
        XCTAssertEqual(JackReminderPaginator.page(items, page: 1, pageSize: 4), [4, 5, 6, 7])
        // Last page is partial.
        XCTAssertEqual(JackReminderPaginator.page(items, page: 2, pageSize: 4), [8, 9])
    }

    func testPageClampsStaleIndexToLastPage() {
        let items = Array(0..<5)
        // Page 9 doesn't exist; clamps to the last page (page 1 -> [4]).
        XCTAssertEqual(JackReminderPaginator.page(items, page: 9, pageSize: 4), [4])
    }

    func testPageEmptyList() {
        XCTAssertEqual(JackReminderPaginator.page([Int](), page: 0, pageSize: 4), [])
    }
}
