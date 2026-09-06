import XCTest
@testable import Gilt

@MainActor
final class ClipboardPayloadTests: XCTestCase {
    func testBuildPlainTextPayloadSkipsWhitespaceOnlyItems() {
        let emptyClip = ClipItemModel(
            typeRaw: ClipType.text.rawValue,
            title: "Whitespace",
            previewText: "   ",
            textValue: " \n\t ",
            sourceAppName: "Tests"
        )

        XCTAssertNil(ClipboardStore.buildPlainTextPayload(for: [emptyClip]))
    }

    func testBuildPlainTextPayloadUsesBestAvailableTextInOrder() {
        let textClip = ClipItemModel(
            typeRaw: ClipType.text.rawValue,
            title: "Text",
            previewText: "Preview 1",
            textValue: "Hello",
            sourceAppName: "Tests"
        )
        let urlClip = ClipItemModel(
            typeRaw: ClipType.link.rawValue,
            title: "Link",
            previewText: "Preview 2",
            textValue: nil,
            urlValue: "https://example.com",
            sourceAppName: "Tests"
        )
        let previewClip = ClipItemModel(
            typeRaw: ClipType.text.rawValue,
            title: "Preview",
            previewText: "Fallback Preview",
            textValue: nil,
            urlValue: nil,
            sourceAppName: "Tests"
        )

        let payload = ClipboardStore.buildPlainTextPayload(for: [textClip, urlClip, previewClip])
        XCTAssertEqual(payload, "Hello\nhttps://example.com\nFallback Preview")
    }
}
