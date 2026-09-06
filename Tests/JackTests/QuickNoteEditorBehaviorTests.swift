import AppKit
import SwiftUI
import XCTest
@testable import Gilt

/// Provides an undo manager to a window-less NSTextView in tests, the same
/// way the host window does in the running app.
@MainActor
private final class UndoProvidingDelegate: NSObject, NSTextViewDelegate {
    let manager = UndoManager()

    func undoManager(for view: NSTextView) -> UndoManager? {
        manager
    }
}

/// Editor-level behavior of the quick note text view: when the "---" to
/// horizontal-rule conversion may fire, how it interacts with undo, and how
/// the coordinator restores state when swapping note content.
@MainActor
final class QuickNoteEditorBehaviorTests: XCTestCase {
    private func makeEditor() -> (QuickNoteEditorTextView, UndoProvidingDelegate) {
        let editor = makeQuickNoteEditorTextView()
        editor.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        editor.isEditable = true
        editor.allowsUndo = true
        let delegate = UndoProvidingDelegate()
        editor.delegate = delegate
        return (editor, delegate)
    }

    private func hasHorizontalRule(_ editor: NSTextView) -> Bool {
        guard let storage = editor.textStorage, storage.length > 0 else { return false }
        var found = false
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, _, stop in
            if value is QuickNoteHorizontalRuleAttachment {
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    // MARK: - Layout / growth

    func testEditorUsesContiguousLayout() {
        // Regression: with non-contiguous layout (TextKit's default for a text
        // view in a scroll view) only the visible rect is laid out and the
        // document view's height stays an estimate, so lines added below the
        // fold — e.g. while pressing Return — clip until a full relayout. The
        // editor must force contiguous layout so its height is always exact.
        let editor = makeQuickNoteEditorTextView()
        XCTAssertEqual(editor.layoutManager?.allowsNonContiguousLayout, false)
    }

    // MARK: - Horizontal-rule conversion triggers

    func testEnterAfterDashLineConvertsToHorizontalRule() {
        let (editor, _) = makeEditor()
        editor.string = "---"
        editor.setSelectedRange(NSRange(location: 3, length: 0))

        editor.insertNewline(nil)

        XCTAssertTrue(hasHorizontalRule(editor))
        XCTAssertEqual(editor.string.suffix(1), "\n")
    }

    func testEnterRuleConversionLaysOutContentBelowRule() {
        // Regression: converting a "---" line to a rule swaps a 3-char text run
        // for a 1-char attachment with a different line height. Before the fix,
        // that raw storage edit under forced contiguous layout left the lines
        // BELOW the new rule unlaid, so they visually disappeared until an
        // unrelated relayout (hide/show, scroll, note switch). The conversion
        // must invalidate + ensure layout across the whole document.
        let (editor, _) = makeEditor()
        editor.string = "---\nkeep me visible"
        editor.setSelectedRange(NSRange(location: 3, length: 0))

        editor.insertNewline(nil)

        XCTAssertTrue(hasHorizontalRule(editor))
        // Data is never lost — the text below the rule is still in storage.
        XCTAssertTrue(editor.string.contains("keep me visible"))

        // And layout is ensured across the whole document, so nothing clips.
        guard let lm = editor.layoutManager, let container = editor.textContainer else {
            return XCTFail("missing layout manager / container")
        }
        let length = editor.textStorage?.length ?? 0
        XCTAssertEqual(
            lm.firstUnlaidCharacterIndex(), length,
            "all characters below the converted rule must be laid out, not left clipped"
        )
        _ = lm.usedRect(for: container)
    }

    func testEnterConvertsAsteriskAndLongDashVariants() {
        for line in ["***", "_____", "-----"] {
            let (editor, _) = makeEditor()
            editor.string = line
            editor.setSelectedRange(NSRange(location: (line as NSString).length, length: 0))
            editor.insertNewline(nil)
            XCTAssertTrue(hasHorizontalRule(editor), "expected conversion for \(line)")
        }
    }

    func testBackspaceAtLineStartBelowDashesDoesNotConvert() {
        // Regression: the conversion used to run on every text change and
        // only checked "is the cursor right after a newline", so deleting a
        // character at the start of the line below a literal "---" made the
        // dashes vanish into a rule mid-deletion.
        let (editor, _) = makeEditor()
        editor.string = "---\nx"
        editor.setSelectedRange(NSRange(location: 5, length: 0))

        editor.deleteBackward(nil)

        XCTAssertFalse(hasHorizontalRule(editor))
        XCTAssertEqual(editor.string, "---\n")
    }

    func testDeletingSelectionEndingAtLineStartDoesNotConvert() {
        let (editor, _) = makeEditor()
        editor.string = "---\nhello"
        editor.setSelectedRange(NSRange(location: 4, length: 5))

        editor.deleteBackward(nil)

        XCTAssertFalse(hasHorizontalRule(editor))
        XCTAssertEqual(editor.string, "---\n")
    }

    func testEnterOnBlankLineBelowDashesDoesNotConvert() {
        let (editor, _) = makeEditor()
        editor.string = "---\n"
        editor.setSelectedRange(NSRange(location: 4, length: 0))

        editor.insertNewline(nil)

        XCTAssertFalse(hasHorizontalRule(editor))
    }

    func testEnterAfterNonRuleLineDoesNotConvert() {
        let (editor, _) = makeEditor()
        editor.string = "---abc"
        editor.setSelectedRange(NSRange(location: 6, length: 0))

        editor.insertNewline(nil)

        XCTAssertFalse(hasHorizontalRule(editor))
        XCTAssertEqual(editor.string, "---abc\n")
    }

    // MARK: - Undo integration

    func testUndoAfterConversionRestoresDashes() {
        // Regression: the conversion used to bypass the undo system entirely,
        // so Cmd+Z afterward replayed stale ranges and corrupted the note.
        // The Return keystroke and the conversion share one undo group (same
        // event), so a single undo restores the dashes exactly as typed.
        let (editor, delegate) = makeEditor()
        editor.string = "---"
        editor.setSelectedRange(NSRange(location: 3, length: 0))

        editor.insertNewline(nil)
        XCTAssertTrue(hasHorizontalRule(editor))

        delegate.manager.undo()

        XCTAssertFalse(hasHorizontalRule(editor))
        XCTAssertEqual(editor.string, "---")
    }

    // MARK: - Coordinator content swaps

    private func makeCoordinator(
        editor: QuickNoteEditorTextView,
        initialText: String
    ) -> QuickNoteTextEditor.Coordinator {
        var captured = initialText
        let coordinator = QuickNoteTextEditor.Coordinator(
            text: Binding(get: { captured }, set: { captured = $0 }),
            noteID: nil,
            attachmentsRoot: URL(fileURLWithPath: NSTemporaryDirectory())
        )
        coordinator.textView = editor
        return coordinator
    }

    func testApplyMarkdownClearsUndoStack() {
        // Regression: swapping in another note's content left the previous
        // note's undo entries alive, so Cmd+Z in note B replayed note A's
        // edits into B at stale ranges.
        let (editor, delegate) = makeEditor()
        let coordinator = makeCoordinator(editor: editor, initialText: "first note")
        coordinator.applyMarkdown(
            "first note",
            style: .cleanCanvas,
            typography: .defaultConfig,
            textColorOverride: nil,
            fallbackWidth: 400
        )

        delegate.manager.registerUndo(withTarget: self) { _ in }
        XCTAssertTrue(delegate.manager.canUndo)

        coordinator.applyMarkdown(
            "second note",
            style: .cleanCanvas,
            typography: .defaultConfig,
            textColorOverride: nil,
            fallbackWidth: 400
        )

        XCTAssertFalse(delegate.manager.canUndo)
    }

    func testApplyMarkdownClampsRestoredSelectionToNewContent() {
        // Regression: the old selection range was restored verbatim against
        // shorter replacement content, jumping the cursor out of bounds.
        let (editor, _) = makeEditor()
        let longText = String(repeating: "x", count: 100)
        let coordinator = makeCoordinator(editor: editor, initialText: longText)
        coordinator.applyMarkdown(
            longText,
            style: .cleanCanvas,
            typography: .defaultConfig,
            textColorOverride: nil,
            fallbackWidth: 400
        )
        editor.setSelectedRange(NSRange(location: 100, length: 0))

        coordinator.applyMarkdown(
            "short",
            style: .cleanCanvas,
            typography: .defaultConfig,
            textColorOverride: nil,
            fallbackWidth: 400
        )

        let selection = editor.selectedRange()
        XCTAssertLessThanOrEqual(selection.location + selection.length, 5)
    }
}
