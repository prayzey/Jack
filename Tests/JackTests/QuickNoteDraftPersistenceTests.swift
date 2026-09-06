import XCTest
@testable import Gilt

@MainActor
final class QuickNoteDraftPersistenceTests: XCTestCase {
    func testDraftFlushTargetsTheNoteThatOwnsTheDraft() {
        let noteID = UUID()
        let note = NoteItem(
            noteID: noteID,
            folderID: NoteFolder.scratchpadsID,
            bodyMarkdown: "Remember the receipt",
            origin: .quickNote
        )

        let draft = QuickNoteDraftPersistence()
        draft.sync(note: note)
        draft.editorDidChange("Remember the receipt\nCall vendor")

        XCTAssertEqual(
            draft.flushRequest,
            QuickNoteDraftFlushRequest(
                noteID: noteID,
                markdown: "Remember the receipt\nCall vendor"
            )
        )
    }

    func testClearedHiddenDraftCannotFlushIntoReopenedNote() {
        let note = NoteItem(
            folderID: NoteFolder.scratchpadsID,
            bodyMarkdown: "Saved text that must survive reopen",
            origin: .quickNote
        )

        let draft = QuickNoteDraftPersistence()
        draft.sync(note: note)
        draft.sync(note: nil)

        XCTAssertNil(draft.flushRequest)
    }

    func testEditorWritesDoNotBumpRevisionButExternalSyncsDo() {
        // The revision is the ONLY tracked field: keystrokes must leave it
        // untouched (or every keypress re-renders QuickNoteView), while
        // external replacements must bump it (or the editor shows stale text).
        let draft = QuickNoteDraftPersistence()
        let initial = draft.revision

        draft.editorDidChange("typing...")
        XCTAssertEqual(draft.revision, initial)
        XCTAssertEqual(draft.markdown, "typing...")

        let note = NoteItem(
            folderID: NoteFolder.scratchpadsID,
            bodyMarkdown: "replaced from outside",
            origin: .quickNote
        )
        draft.sync(note: note)
        XCTAssertEqual(draft.revision, initial + 1)
        XCTAssertEqual(draft.markdown, "replaced from outside")
    }
}
