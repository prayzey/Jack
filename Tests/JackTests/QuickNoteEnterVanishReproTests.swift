import AppKit
import SwiftUI
import XCTest
@testable import Gilt

/// Reproduction harness for "pressing Enter makes the text below disappear
/// until the note is closed and reopened". Builds the editor exactly the way
/// `QuickNoteTextEditor.makeNSView` does — same scroll view, insets, sizing
/// flags, and a real window so layout + display actually run — then presses
/// Enter mid-document and inspects what TextKit believes is laid out and where.
@MainActor
final class QuickNoteEnterVanishReproTests: XCTestCase {
    private var capturedText = ""

    private func makeFullStack(markdown: String) -> (QuickNoteEditorScrollView, QuickNoteEditorTextView, QuickNoteTextEditor.Coordinator, NSWindow) {
        let scrollView = QuickNoteEditorScrollView(frame: NSRect(x: 0, y: 0, width: 520, height: 420))
        let textView = makeQuickNoteEditorTextView()

        capturedText = markdown
        let coordinator = QuickNoteTextEditor.Coordinator(
            text: Binding(get: { self.capturedText }, set: { self.capturedText = $0 }),
            noteID: nil,
            attachmentsRoot: URL(fileURLWithPath: NSTemporaryDirectory())
        )
        textView.delegate = coordinator
        coordinator.textView = textView
        coordinator.applyMarkdown(
            markdown,
            style: .cleanCanvas,
            typography: .defaultConfig,
            textColorOverride: nil,
            fallbackWidth: scrollView.bounds.width
        )
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isRichText = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 34, height: 56)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        if let container = textView.textContainer {
            container.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
            container.widthTracksTextView = true
            container.lineFragmentPadding = 0
        }
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.documentView = textView
        scrollView.quickNoteTextView = textView

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = scrollView
        window.orderFrontRegardless()
        scrollView.layoutSubtreeIfNeeded()
        window.contentView?.displayIfNeeded()

        return (scrollView, textView, coordinator, window)
    }

    private func lineFragmentRect(containing charIndex: Int, in textView: NSTextView) -> NSRect {
        guard let lm = textView.layoutManager else { return .null }
        let glyphIndex = lm.glyphIndexForCharacter(at: charIndex)
        return lm.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
    }

    func testPlainEnterMidDocumentKeepsBelowTextLaidOutAndInsideFrame() {
        let markdown = "first line\nsecond line\nthird line\nfourth line"
        let (_, textView, _, window) = makeFullStack(markdown: markdown)
        defer { window.orderOut(nil) }

        let ns = textView.string as NSString
        let thirdLineLoc = ns.range(of: "third line").location

        // Cursor at the end of "first line", then press Enter.
        textView.setSelectedRange(NSRange(location: 10, length: 0))
        textView.insertNewline(nil)
        window.contentView?.displayIfNeeded()

        guard let lm = textView.layoutManager, let container = textView.textContainer else {
            return XCTFail("missing layout manager / container")
        }

        let length = textView.textStorage?.length ?? 0
        XCTAssertEqual(
            lm.firstUnlaidCharacterIndex(), length,
            "every character below the inserted newline must be laid out"
        )

        // The document view's frame must contain the full used rect (plus the
        // vertical insets) or the bottom lines sit outside the view = invisible.
        let used = lm.usedRect(for: container)
        let requiredHeight = used.maxY + textView.textContainerInset.height * 2
        XCTAssertGreaterThanOrEqual(
            textView.frame.height + 0.5, requiredHeight,
            "text view frame must grow to hold shifted-down content (frame \(textView.frame.height) vs required \(requiredHeight))"
        )

        // The line that was below the cursor must have an actual on-canvas
        // fragment BELOW its pre-Enter position, inside the frame.
        let newNS = textView.string as NSString
        let shiftedThirdLoc = newNS.range(of: "third line").location
        XCTAssertNotEqual(shiftedThirdLoc, NSNotFound)
        let frag = lineFragmentRect(containing: shiftedThirdLoc, in: textView)
        XCTAssertFalse(frag.isNull, "third line has no line fragment — it is not laid out")
        XCTAssertLessThanOrEqual(
            frag.maxY + textView.textContainerInset.height, textView.frame.height + 0.5,
            "third line's fragment lies outside the text view frame — visually clipped"
        )

        _ = thirdLineLoc
    }

    func testHoldEnterManyTimesMidDocumentStaysLaidOut() {
        let markdown = "top\nmiddle\nbottom text that must stay visible"
        let (_, textView, _, window) = makeFullStack(markdown: markdown)
        defer { window.orderOut(nil) }

        textView.setSelectedRange(NSRange(location: 3, length: 0))
        for _ in 0..<25 {
            textView.insertNewline(nil)
        }
        window.contentView?.displayIfNeeded()

        guard let lm = textView.layoutManager, let container = textView.textContainer else {
            return XCTFail("missing layout manager / container")
        }
        let length = textView.textStorage?.length ?? 0
        XCTAssertEqual(lm.firstUnlaidCharacterIndex(), length)

        let used = lm.usedRect(for: container)
        let requiredHeight = used.maxY + textView.textContainerInset.height * 2
        XCTAssertGreaterThanOrEqual(
            textView.frame.height + 0.5, requiredHeight,
            "after 25 Enters the frame must still contain the content (frame \(textView.frame.height) vs required \(requiredHeight))"
        )

        let newNS = textView.string as NSString
        let bottomLoc = newNS.range(of: "bottom text").location
        let frag = lineFragmentRect(containing: bottomLoc, in: textView)
        XCTAssertLessThanOrEqual(
            frag.maxY + textView.textContainerInset.height, textView.frame.height + 0.5,
            "bottom line's fragment lies outside the text view frame — visually clipped"
        )
    }
}
