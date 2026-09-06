import Foundation
import Observation

struct QuickNoteDraftFlushRequest: Equatable {
    var noteID: UUID
    var markdown: String
}

/// In-flight text of the note being edited.
///
/// Held in an `@Observable` object with the hot field UNTRACKED on purpose:
/// when this was a plain `@State` struct, every keystroke wrote
/// `draft.markdown` and re-rendered all of `QuickNoteView` — backdrop,
/// wallpaper, chrome overlays, and the editor bridge — just to store a string
/// the NSTextView was already displaying. Same "isolate the changing state
/// into a leaf" fix as `QuickNoteScrollState`.
///
/// - `markdown` is `@ObservationIgnored`: editor-origin writes must never
///   invalidate the SwiftUI tree.
/// - `revision` is tracked and bumps ONLY when content is replaced from
///   outside the editor (note switch, auto-append, OCR append). Reading it in
///   `QuickNoteView.body` is what schedules the render pass that pushes the
///   replacement text into the NSTextView — without it the editor would keep
///   showing stale text, since nothing else re-renders on an external sync.
@Observable
@MainActor
final class QuickNoteDraftPersistence {
    @ObservationIgnored private(set) var noteID: UUID?
    @ObservationIgnored private(set) var markdown: String = ""
    private(set) var revision = 0

    /// Editor-origin update. No revision bump — the text view already shows
    /// this text; invalidating the view tree here would defeat the isolation.
    func editorDidChange(_ newMarkdown: String) {
        markdown = newMarkdown
    }

    func sync(note: NoteItem?) {
        noteID = note?.noteID
        markdown = note?.bodyMarkdown ?? ""
        revision += 1
    }

    /// Only flush when this local draft still belongs to a concrete note.
    /// Hidden Quick Note views can outlive `quickNoteActiveNoteID`; using the
    /// global active ID during teardown can write an old blank draft over the
    /// note the user just reopened.
    var flushRequest: QuickNoteDraftFlushRequest? {
        guard let noteID else { return nil }
        return QuickNoteDraftFlushRequest(noteID: noteID, markdown: markdown)
    }
}
