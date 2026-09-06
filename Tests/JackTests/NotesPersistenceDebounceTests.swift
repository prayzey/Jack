import XCTest
@testable import Gilt

@MainActor
final class NotesPersistenceDebounceTests: XCTestCase {
    func testPersistNotesLibraryCoalescesRapidCallsIntoOneScheduledWrite() {
        let store = ClipboardStore()
        // Init may have left a pending launch-time persist behind; clear it so
        // the assertions below only see writes scheduled by this test.
        store.pendingNotesPersistWorkItem?.cancel()
        store.pendingNotesPersistWorkItem = nil

        store.persistNotesLibrary()
        guard let first = store.pendingNotesPersistWorkItem else {
            return XCTFail("persistNotesLibrary should schedule a debounced write")
        }

        store.persistNotesLibrary()
        guard let second = store.pendingNotesPersistWorkItem else {
            return XCTFail("a second call should reschedule the debounced write")
        }
        XCTAssertTrue(first.isCancelled, "the earlier pending write must be cancelled, not stacked")
        XCTAssertFalse(second.isCancelled)

        let debounceElapsed = expectation(description: "debounce window elapsed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { debounceElapsed.fulfill() }
        wait(for: [debounceElapsed], timeout: 2.0)
        XCTAssertNil(store.pendingNotesPersistWorkItem, "the work item should clear itself after the write runs")
    }

    func testAccessibilityPasteAlertPresentsOnlyOncePerSession() {
        let store = ClipboardStore()
        XCTAssertTrue(store.consumeAccessibilityPasteAlertPresentation())
        XCTAssertFalse(store.consumeAccessibilityPasteAlertPresentation())
        XCTAssertFalse(store.consumeAccessibilityPasteAlertPresentation())
    }
}
