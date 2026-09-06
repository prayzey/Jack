import AppKit
import XCTest
@testable import Gilt

/// The quick note editor serializes the text view's content to markdown on
/// every keystroke and re-renders from markdown whenever a note loads. These
/// tests pin the core invariant of that loop: serialization must reproduce
/// the on-screen text verbatim (attachments swapped for their references),
/// and render(serialize(x)) must be stable. Any normalization that breaks
/// this silently desyncs the saved note from what the user sees, and the
/// drift compounds every time the note is reopened.
@MainActor
final class QuickNoteRoundTripStabilityTests: XCTestCase {
    private let base: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 14),
        .foregroundColor: NSColor.white
    ]

    private func render(_ markdown: String) -> NSAttributedString {
        QuickNoteBodyRenderer.attributedString(
            from: markdown,
            noteID: UUID(),
            attachmentsRoot: URL(fileURLWithPath: NSTemporaryDirectory()),
            baseAttributes: base,
            maxImageWidth: 300
        )
    }

    private func imageAttachmentString() -> NSAttributedString {
        NSAttributedString(
            attachment: QuickNoteImageTextAttachment(
                imageID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
                image: NSImage(size: NSSize(width: 120, height: 80)),
                maxWidth: 200
            )
        )
    }

    private var imageRef: String {
        QuickNoteImageMarkdown.imageReference(
            imageID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        )
    }

    // MARK: - Blank-line fidelity

    func testSerializePreservesConsecutiveBlankLines() {
        // Regression: a single-pass "\n\n\n" -> "\n\n" collapse made blank
        // lines silently shrink on every open/edit cycle.
        let source = NSAttributedString(string: "a\n\n\n\nb", attributes: base)
        XCTAssertEqual(QuickNoteBodyRenderer.markdown(from: source), "a\n\n\n\nb")
    }

    func testSerializeIsIdempotentForPlainText() {
        let source = NSAttributedString(string: "a\n\n\n\nb", attributes: base)
        let pass1 = QuickNoteBodyRenderer.markdown(from: source)
        let pass2 = QuickNoteBodyRenderer.markdown(
            from: NSAttributedString(string: pass1, attributes: base)
        )
        XCTAssertEqual(pass1, pass2)
    }

    func testBlankLinesSurviveRenderSerializeCycle() {
        let markdown = "a\n\n\nb"
        XCTAssertEqual(QuickNoteBodyRenderer.markdown(from: render(markdown)), markdown)
    }

    // MARK: - Image attachment serialization

    func testImageSerializationPreservesSurroundingNewlinesExactly() {
        // Regression: the serializer appended its own "\n\n" around the image
        // reference even though the editor already holds those newlines as
        // real characters, so every save/load cycle grew a blank line.
        let source = NSMutableAttributedString(string: "Before\n\n", attributes: base)
        source.append(imageAttachmentString())
        source.append(NSAttributedString(string: "\n\nAfter", attributes: base))

        XCTAssertEqual(
            QuickNoteBodyRenderer.markdown(from: source),
            "Before\n\n\(imageRef)\n\nAfter"
        )
    }

    func testImageSerializationKeepsTightLayoutVerbatim() {
        let singleNewline = NSMutableAttributedString(string: "ab\n", attributes: base)
        singleNewline.append(imageAttachmentString())
        singleNewline.append(NSAttributedString(string: "\ncd", attributes: base))
        XCTAssertEqual(
            QuickNoteBodyRenderer.markdown(from: singleNewline),
            "ab\n\(imageRef)\ncd"
        )

        let midline = NSMutableAttributedString(string: "ab ", attributes: base)
        midline.append(imageAttachmentString())
        midline.append(NSAttributedString(string: " cd", attributes: base))
        XCTAssertEqual(
            QuickNoteBodyRenderer.markdown(from: midline),
            "ab \(imageRef) cd"
        )
    }

    // MARK: - Horizontal rules

    func testHorizontalRuleRoundTripIsStable() {
        let markdown = "a\n---\nb"
        XCTAssertEqual(QuickNoteBodyRenderer.markdown(from: render(markdown)), markdown)
    }

    // MARK: - Transition ghost preview

    func testPlainPreviewTextHidesRawMarkup() {
        let markdown = "Hello\n\n\(imageRef)\n\n<b>bold</b> and \\<i> literal"
        let preview = QuickNoteBodyRenderer.plainPreviewText(from: markdown)

        XCTAssertFalse(preview.contains("jack-image"))
        XCTAssertFalse(preview.contains("!["))
        XCTAssertFalse(preview.contains("<b>"))
        XCTAssertFalse(preview.contains("\\"))
        XCTAssertTrue(preview.contains("Hello"))
        XCTAssertTrue(preview.contains("bold"))
        XCTAssertTrue(preview.contains("<i>"), "escaped tags are the user's literal text and should stay visible")
    }
}
