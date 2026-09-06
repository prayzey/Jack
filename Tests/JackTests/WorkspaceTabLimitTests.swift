import XCTest
@testable import Gilt

/// Tests for the workspace tab strip's least-recently-used cap. The strip has a
/// hard ceiling (`WorkspaceSession.maxTabCount`); opening past it must evict the
/// tab the user has touched least recently, never a pinned or selected tab.
final class WorkspaceTabLimitTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_000_000)

    /// A clip tab with a distinct id and an explicit recency time.
    private func tab(_ secondsOffset: TimeInterval, pinned: Bool = false) -> WorkspaceTab {
        WorkspaceTab(
            kind: .clip(UUID()),
            title: "Tab",
            isPinned: pinned,
            createdAt: base,
            lastAccessedAt: base.addingTimeInterval(secondsOffset)
        )
    }

    // MARK: - eviction candidate selection

    func testEvictionCandidateIsLeastRecentlyUsed() {
        let oldest = tab(0)
        let middle = tab(10)
        let newest = tab(20)
        let session = WorkspaceSession(tabs: [middle, oldest, newest], selectedTabID: newest.id)

        XCTAssertEqual(session.evictionCandidateID(), oldest.id)
    }

    func testSelectedTabIsNeverEvicted() {
        // The selected tab is the oldest by recency, but it must be protected so
        // the user never loses the surface they're currently looking at.
        let selected = tab(0)
        let other = tab(50)
        let session = WorkspaceSession(tabs: [selected, other], selectedTabID: selected.id)

        XCTAssertEqual(session.evictionCandidateID(), other.id)
    }

    func testPinnedTabIsNeverEvicted() {
        let pinnedOld = tab(0, pinned: true)
        let unpinnedNewer = tab(30)
        let session = WorkspaceSession(tabs: [pinnedOld, unpinnedNewer], selectedTabID: nil)

        XCTAssertEqual(session.evictionCandidateID(), unpinnedNewer.id)
    }

    func testNoCandidateWhenAllTabsProtected() {
        let selected = tab(0)
        let pinned = tab(10, pinned: true)
        let session = WorkspaceSession(tabs: [selected, pinned], selectedTabID: selected.id)

        XCTAssertNil(session.evictionCandidateID())
    }

    /// A tab persisted before recency tracking has `lastAccessedAt == nil`; it
    /// must still order by `createdAt` and be evictable.
    func testLegacyTabWithoutRecencyFallsBackToCreatedAt() {
        let legacy = WorkspaceTab(kind: .clip(UUID()), title: "Legacy", createdAt: base, lastAccessedAt: nil)
        let fresh = tab(100)
        let session = WorkspaceSession(tabs: [fresh, legacy], selectedTabID: fresh.id)

        XCTAssertEqual(session.evictionCandidateID(), legacy.id)
    }

    // MARK: - makeRoomForNewTab

    func testMakeRoomEvictsDownToCapMinusOne() {
        // Fill the strip to the cap, then make room for one more. Result should
        // leave exactly room for the append (count == maxTabCount - 1).
        let tabs = (0..<WorkspaceSession.maxTabCount).map { tab(TimeInterval($0)) }
        var session = WorkspaceSession(tabs: tabs, selectedTabID: tabs.last?.id)

        session.makeRoomForNewTab()

        XCTAssertEqual(session.tabs.count, WorkspaceSession.maxTabCount - 1)
        // The oldest tab (offset 0) is the one that should be gone.
        XCTAssertFalse(session.tabs.contains { $0.id == tabs.first?.id })
        // The selected (newest) tab survives.
        XCTAssertTrue(session.tabs.contains { $0.id == tabs.last?.id })
    }

    func testMakeRoomIsNoOpBelowCap() {
        let tabs = [tab(0), tab(10)]
        var session = WorkspaceSession(tabs: tabs, selectedTabID: tabs[1].id)

        session.makeRoomForNewTab()

        XCTAssertEqual(session.tabs.count, 2)
    }

    func testOpeningManyTabsNeverExceedsCap() {
        // Simulate the real append loop: make room, then append. After many
        // opens the strip must never exceed the cap.
        var session = WorkspaceSession()
        for i in 0..<(WorkspaceSession.maxTabCount * 3) {
            session.makeRoomForNewTab()
            let new = tab(TimeInterval(i))
            session.tabs.append(new)
            session.selectedTabID = new.id
            XCTAssertLessThanOrEqual(session.tabs.count, WorkspaceSession.maxTabCount)
        }
        XCTAssertEqual(session.tabs.count, WorkspaceSession.maxTabCount)
    }
}
