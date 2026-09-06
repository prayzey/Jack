import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import Gilt

@MainActor
final class ClipDragItemProviderTests: XCTestCase {
    func testTextClipProviderExposesExternalTextAndKeepsInternalTokenPrivate() {
        let clip = makeClip(type: .text, title: "Snippet", previewText: "Hello world")
        let expectedClipID = clip.clipID.uuidString

        let provider = ClipDragItemProvider.makeProvider(for: clip)

        XCTAssertTrue(provider.registeredTypeIdentifiers.contains(ClipDragItemProvider.internalDragType.identifier))
        XCTAssertTrue(registeredTypes(provider).contains(where: { $0.conforms(to: .plainText) }))
        XCTAssertEqual(provider.suggestedName, "Snippet")

        let internalPayloadLoaded = expectation(description: "load internal drag payload")
        provider.loadDataRepresentation(forTypeIdentifier: ClipDragItemProvider.internalDragType.identifier) { data, error in
            XCTAssertNil(error)
            XCTAssertEqual(data.flatMap { String(data: $0, encoding: .utf8) }, expectedClipID)
            internalPayloadLoaded.fulfill()
        }

        let objectLoaded = expectation(description: "load external text")
        provider.loadObject(ofClass: NSString.self) { object, error in
            XCTAssertNil(error)
            XCTAssertEqual(object as? String, "Hello world")
            objectLoaded.fulfill()
        }

        wait(for: [internalPayloadLoaded, objectLoaded], timeout: 5)
    }

    func testImageClipProviderLoadsInternalClipIDAndExternalPNGFile() throws {
        let clip = makeClip(
            type: .image,
            title: "Screenshot / April: 6",
            previewText: "Screenshot",
            imageData: try makeSamplePNGData()
        )
        let provider = ClipDragItemProvider.makeProvider(for: clip)
        let expectedClipID = clip.clipID.uuidString
        let expectedImageData = clip.imageData

        XCTAssertTrue(provider.registeredTypeIdentifiers.contains(ClipDragItemProvider.internalDragType.identifier))
        XCTAssertTrue(provider.registeredTypeIdentifiers.contains(UTType.png.identifier))
        XCTAssertEqual(provider.suggestedName, "Screenshot - April- 6")

        let internalPayloadLoaded = expectation(description: "load internal drag payload")
        provider.loadDataRepresentation(forTypeIdentifier: ClipDragItemProvider.internalDragType.identifier) { data, error in
            XCTAssertNil(error)
            XCTAssertEqual(data.flatMap { String(data: $0, encoding: .utf8) }, expectedClipID)
            internalPayloadLoaded.fulfill()
        }

        let pngFileLoaded = expectation(description: "load png file")
        provider.loadFileRepresentation(forTypeIdentifier: UTType.png.identifier) { fileURL, error in
            XCTAssertNil(error)
            XCTAssertNotNil(fileURL)
            XCTAssertTrue(fileURL?.lastPathComponent.hasSuffix(".png") ?? false)

            if let fileURL {
                let data = try? Data(contentsOf: fileURL)
                XCTAssertEqual(data, expectedImageData)
                XCTAssertNotNil(data.flatMap(NSImage.init(data:)))
            }

            pngFileLoaded.fulfill()
        }

        wait(for: [internalPayloadLoaded, pngFileLoaded], timeout: 5)
    }

    func testSuggestedFilenameFallsBackWhenTitleSanitizesToEmpty() throws {
        let clip = makeClip(type: .image, title: "///", previewText: "   ", imageData: try makeSamplePNGData())

        XCTAssertEqual(ClipDragItemProvider.suggestedFilename(for: clip), "jack-image.png")
    }

    func testSeparatorProviderOnlyUsesInternalDragPayload() {
        let separator = FolderSeparatorModel(label: "Ideas")
        let expectedPayload = "separator:\(separator.separatorID.uuidString)"

        let provider = ClipDragItemProvider.makeProvider(for: separator)

        XCTAssertEqual(provider.suggestedName, "Ideas")
        XCTAssertEqual(provider.registeredTypeIdentifiers, [ClipDragItemProvider.internalDragType.identifier])

        let payloadLoaded = expectation(description: "load separator payload")
        provider.loadDataRepresentation(forTypeIdentifier: ClipDragItemProvider.internalDragType.identifier) { data, error in
            XCTAssertNil(error)
            XCTAssertEqual(data.flatMap { String(data: $0, encoding: .utf8) }, expectedPayload)
            payloadLoaded.fulfill()
        }

        wait(for: [payloadLoaded], timeout: 5)
    }

    func testLinkClipProviderExposesURLStringForTextFields() {
        let clip = ClipItemModel(
            typeRaw: ClipType.link.rawValue,
            title: "Example",
            previewText: "example.com",
            textValue: nil,
            urlValue: "https://example.com/path",
            sourceAppName: "Tests"
        )

        let provider = ClipDragItemProvider.makeProvider(for: clip)

        XCTAssertTrue(provider.registeredTypeIdentifiers.contains(ClipDragItemProvider.internalDragType.identifier))
        XCTAssertTrue(registeredTypes(provider).contains(where: { $0.conforms(to: .plainText) }))
        XCTAssertTrue(registeredTypes(provider).contains(where: { $0.conforms(to: .url) }))

        let objectLoaded = expectation(description: "load external link text")
        provider.loadObject(ofClass: NSString.self) { object, error in
            XCTAssertNil(error)
            XCTAssertEqual(object as? String, "https://example.com/path")
            objectLoaded.fulfill()
        }

        wait(for: [objectLoaded], timeout: 5)
    }

    func testStripDragItemParsesClipPayload() {
        let clipID = UUID()

        XCTAssertEqual(StripDragItem(serializedValue: clipID.uuidString), .clip(clipID))
    }

    func testStripDragItemParsesSeparatorPayload() {
        let separatorID = UUID()

        XCTAssertEqual(
            StripDragItem(serializedValue: "separator:\(separatorID.uuidString)"),
            .separator(separatorID)
        )
    }

    func testStripDragItemRejectsInvalidPayload() {
        XCTAssertNil(StripDragItem(serializedValue: "folder:not-a-real-uuid"))
    }

    private func makeClip(
        type: ClipType,
        title: String,
        previewText: String,
        imageData: Data? = nil
    ) -> ClipItemModel {
        ClipItemModel(
            typeRaw: type.rawValue,
            title: title,
            previewText: previewText,
            textValue: previewText,
            imageData: imageData,
            sourceAppName: "Tests"
        )
    }

    private func makeSamplePNGData() throws -> Data {
        let size = NSSize(width: 20, height: 20)
        let image = NSImage(size: size)

        image.lockFocus()
        NSColor(calibratedRed: 0.23, green: 0.67, blue: 0.92, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()

        return try XCTUnwrap(image.pngData())
    }

    private func registeredTypes(_ provider: NSItemProvider) -> [UTType] {
        provider.registeredTypeIdentifiers.compactMap(UTType.init)
    }
}
