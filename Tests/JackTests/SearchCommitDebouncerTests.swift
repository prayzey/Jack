import XCTest
@testable import Gilt

@MainActor
final class SearchCommitDebouncerTests: XCTestCase {
    func testCommitsTrailingValueAfterIdleInterval() async {
        let debouncer = SearchCommitDebouncer(interval: .milliseconds(30))
        var committed: [String] = []

        debouncer.textChanged("s") { committed.append($0) }
        debouncer.textChanged("sw") { committed.append($0) }
        debouncer.textChanged("swift") { committed.append($0) }

        XCTAssertTrue(committed.isEmpty, "Nothing should commit while typing continues")

        try? await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(committed, ["swift"], "Only the final draft should commit once typing pauses")
    }

    func testEmptyTextCommitsImmediately() {
        let debouncer = SearchCommitDebouncer(interval: .seconds(10))
        var committed: [String] = []

        debouncer.textChanged("") { committed.append($0) }

        XCTAssertEqual(committed, [""], "Clearing the field must commit without waiting")
    }

    func testClearCancelsPendingCommit() async {
        let debouncer = SearchCommitDebouncer(interval: .milliseconds(30))
        var committed: [String] = []

        debouncer.textChanged("stale") { committed.append($0) }
        debouncer.textChanged("") { committed.append($0) }

        try? await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(committed, [""], "A pending draft must not resurrect after the field is cleared")
    }

    func testCancelPendingDropsScheduledCommit() async {
        let debouncer = SearchCommitDebouncer(interval: .milliseconds(30))
        var committed: [String] = []

        debouncer.textChanged("stale") { committed.append($0) }
        debouncer.cancelPending()

        try? await Task.sleep(for: .milliseconds(120))
        XCTAssertTrue(committed.isEmpty, "cancelPending must drop the scheduled commit")
    }
}
