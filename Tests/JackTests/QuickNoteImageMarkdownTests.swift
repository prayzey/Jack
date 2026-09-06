import XCTest
@testable import Gilt

@MainActor
final class QuickNoteImageMarkdownTests: XCTestCase {
    func testImageReferenceRoundTrip() {
        let imageID = UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")!
        let reference = QuickNoteImageMarkdown.imageReference(imageID: imageID)
        XCTAssertEqual(
            reference,
            "![image](jack-image:a1b2c3d4-e5f6-7890-abcd-ef1234567890)"
        )
        XCTAssertEqual(QuickNoteImageMarkdown.imageIDs(in: reference), [imageID])
    }

    func testPlainTextReplacingImageReferences() {
        let imageID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let markdown = """
        Hello

        \(QuickNoteImageMarkdown.imageReference(imageID: imageID))

        World
        """
        XCTAssertEqual(
            QuickNoteImageMarkdown.plainTextReplacingImageReferences(markdown),
            "Hello\n\nWorld"
        )
    }

    func testLoadedDisplayImageUsesNonZeroPixelSize() {
        let pngHeader = Data([
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
            0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
            0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
            0x54, 0x08, 0xD7, 0x63, 0x60, 0x00, 0x00, 0x00,
            0x02, 0x00, 0x01, 0xE2, 0x21, 0xBC, 0x33, 0x00,
            0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
            0x42, 0x60, 0x82
        ])
        guard let image = NoteImageAttachmentStore.loadedDisplayImage(from: pngHeader) else {
            return XCTFail("Expected a display image")
        }

        let size = NoteImageAttachmentStore.displaySize(for: image)
        XCTAssertGreaterThanOrEqual(size.width, 1)
        XCTAssertGreaterThanOrEqual(size.height, 1)

        let fitted = NoteImageAttachmentStore.fittedDisplaySize(for: image, maxWidth: 200)
        XCTAssertGreaterThanOrEqual(fitted.width, NoteImageAttachmentStore.minimumDisplayEdge)
        XCTAssertGreaterThanOrEqual(fitted.height, NoteImageAttachmentStore.minimumDisplayEdge)
    }

    func testImageAttachmentBoundsReserveLineHeightBelowBaseline() {
        let image = NSImage(size: NSSize(width: 120, height: 80))
        let attachment = QuickNoteImageTextAttachment(
            imageID: UUID(),
            image: image,
            maxWidth: 200
        )

        XCTAssertGreaterThan(attachment.bounds.height, 0)
        XCTAssertEqual(attachment.bounds.origin.y, -attachment.bounds.height, accuracy: 0.01)
        XCTAssertEqual(
            attachment.attachmentBounds(
                for: nil,
                proposedLineFragment: .zero,
                glyphPosition: .zero,
                characterIndex: 0
            ),
            attachment.bounds
        )
    }

    func testMarkdownSerializationPreservesTextAndImageMarkers() {
        let imageID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.white
        ]
        let source = NSMutableAttributedString(string: "Before\n\n", attributes: baseAttributes)
        source.append(
            NSAttributedString(
                attachment: QuickNoteImageTextAttachment(
                    imageID: imageID,
                    image: NSImage(size: NSSize(width: 120, height: 80)),
                    maxWidth: 200
                )
            )
        )
        source.append(NSAttributedString(string: "\n\nAfter", attributes: baseAttributes))

        let markdown = QuickNoteBodyRenderer.markdown(from: source)
        XCTAssertTrue(markdown.contains(QuickNoteImageMarkdown.imageReference(imageID: imageID)))
        XCTAssertTrue(markdown.contains("Before"))
        XCTAssertTrue(markdown.contains("After"))
    }
}
