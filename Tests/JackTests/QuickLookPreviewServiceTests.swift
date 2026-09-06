import AppKit
import XCTest
@testable import Gilt

@MainActor
final class QuickLookPreviewServiceTests: XCTestCase {
    func testPayloadUsesExistingFileURLWhenAvailable() throws {
        let sourceURL = try makeTemporaryFile(named: "existing.txt", contents: Data("hello".utf8))
        let clip = ClipItemModel(
            typeRaw: ClipType.link.rawValue,
            title: "File URL",
            previewText: sourceURL.path,
            textValue: nil,
            urlValue: sourceURL.absoluteString,
            sourceAppName: "Tests"
        )

        let payload = QuickLookPreviewFileBuilder.payload(for: clip)

        XCTAssertEqual(payload?.url, sourceURL)
        XCTAssertEqual(payload?.isTemporary, false)
    }

    func testPayloadCreatesTemporaryTextFileForTextClip() throws {
        let clip = ClipItemModel(
            typeRaw: ClipType.text.rawValue,
            title: "Note",
            previewText: "Fallback",
            textValue: "Line 1\nLine 2",
            sourceAppName: "Tests"
        )

        let payload = try XCTUnwrap(QuickLookPreviewFileBuilder.payload(for: clip))
        let saved = try String(contentsOf: payload.url, encoding: .utf8)

        XCTAssertTrue(payload.isTemporary)
        XCTAssertTrue(FileManager.default.fileExists(atPath: payload.url.path))
        XCTAssertEqual(saved, "Line 1\nLine 2")
    }

    func testPayloadCreatesTemporaryPNGFileForImageClip() throws {
        let image = makeSampleImage()
        let imageData = try XCTUnwrap(ImageClipActionService.convert(image: image, to: .png))
        let clip = ClipItemModel(
            typeRaw: ClipType.image.rawValue,
            title: "Image",
            previewText: "Image clip",
            textValue: nil,
            imageData: imageData,
            sourceAppName: "Tests"
        )

        let payload = try XCTUnwrap(QuickLookPreviewFileBuilder.payload(for: clip))

        XCTAssertTrue(payload.isTemporary)
        XCTAssertEqual(payload.url.pathExtension.lowercased(), "png")
        XCTAssertNotNil(NSImage(contentsOf: payload.url))
    }

    private func makeTemporaryFile(named name: String, contents: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("JackQuickLookTests", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(name)
        try contents.write(to: fileURL, options: .atomic)
        return fileURL
    }

    private func makeSampleImage() -> NSImage {
        let size = NSSize(width: 32, height: 32)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(calibratedRed: 0.30, green: 0.60, blue: 0.88, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        return image
    }
}
