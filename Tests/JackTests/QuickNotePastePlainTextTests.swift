import AppKit
import XCTest
@testable import Gilt

/// Regression coverage for the "dark box behind pasted text" bug: copying from a
/// dark-themed source app (e.g. Cursor) puts rich text on the pasteboard carrying
/// that app's foreground + background colours. Quick Note is Markdown-backed and
/// must paste as plain text so pasted content adopts the note's own typography and
/// never inherits a foreign background colour.
@MainActor
final class QuickNotePastePlainTextTests: XCTestCase {
    private func makeRichTextWithDarkBackground(_ string: String) -> Data {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.white,
            // The hitchhiking attribute that produced the visible dark box.
            .backgroundColor: NSColor(white: 0.12, alpha: 1.0)
        ]
        let attributed = NSAttributedString(string: string, attributes: attributes)
        return attributed.rtf(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [:]
        )!
    }

    func testPasteStripsForeignBackgroundColor() {
        let textView = makeQuickNoteEditorTextView()
        textView.isRichText = true

        // The note's own typography — what pasted text should adopt.
        let noteColor = NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: 16),
            .foregroundColor: noteColor
        ]

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(
            makeRichTextWithDarkBackground("admin@wsf.local"),
            forType: .rtf
        )
        pasteboard.setString("admin@wsf.local", forType: .string)

        textView.paste(nil)

        let storage = textView.textStorage!
        XCTAssertEqual(storage.string, "admin@wsf.local")
        XCTAssertGreaterThan(storage.length, 0)

        // No run may carry a background colour — that was the dark box.
        storage.enumerateAttribute(
            .backgroundColor,
            in: NSRange(location: 0, length: storage.length)
        ) { value, _, _ in
            XCTAssertNil(value, "Pasted text must not carry a foreign background colour")
        }

        // And the text should wear the note's own foreground colour, not Cursor's white.
        let pastedColor = storage.attribute(
            .foregroundColor,
            at: 0,
            effectiveRange: nil
        ) as? NSColor
        XCTAssertEqual(pastedColor, noteColor)
    }
}
