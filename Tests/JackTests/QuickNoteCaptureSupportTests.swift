import XCTest
@testable import Gilt

final class QuickNoteCaptureSupportTests: XCTestCase {
    func testQuickNoteMergedBodyUsesBlankLineBetweenEntries() {
        XCTAssertEqual(
            quickNoteMergedBody(existing: "First line", incoming: "Second line"),
            "First line\n\nSecond line"
        )
    }

    func testQuickNoteMergedBodyPreservesExistingTrailingNewlineSpacing() {
        XCTAssertEqual(
            quickNoteMergedBody(existing: "First line\n", incoming: "Second line"),
            "First line\n\nSecond line"
        )
        XCTAssertEqual(
            quickNoteMergedBody(existing: "First line\n\n", incoming: "Second line"),
            "First line\n\nSecond line"
        )
    }

    func testQuickNoteAutoAppendTextUsesCopiedTextAndLinks() {
        let textCapture = CapturedClip(
            type: .text,
            title: "Text",
            previewText: "Preview",
            textValue: "Copied body",
            urlValue: nil,
            imageData: nil
        )
        XCTAssertEqual(
            quickNoteAutoAppendText(from: textCapture, sourceBundleID: "com.apple.Safari", appBundleID: "com.praisedev.gilt"),
            "Copied body"
        )

        let linkCapture = CapturedClip(
            type: .link,
            title: "Link",
            previewText: "example.com",
            textValue: "https://example.com/path",
            urlValue: "https://example.com/path",
            imageData: nil
        )
        XCTAssertEqual(
            quickNoteAutoAppendText(from: linkCapture, sourceBundleID: "com.apple.Safari", appBundleID: "com.praisedev.gilt"),
            "https://example.com/path"
        )
    }

    func testQuickNoteAutoAppendTextSkipsImagesAndSelfOriginatingCopies() {
        let imageCapture = CapturedClip(
            type: .image,
            title: "Image",
            previewText: "Image clip",
            textValue: nil,
            urlValue: nil,
            imageData: Data([0x01, 0x02])
        )
        XCTAssertNil(
            quickNoteAutoAppendText(from: imageCapture, sourceBundleID: "com.apple.Preview", appBundleID: "com.praisedev.gilt")
        )

        let selfCapture = CapturedClip(
            type: .text,
            title: "Text",
            previewText: "Preview",
            textValue: "Copied from Jack",
            urlValue: nil,
            imageData: nil
        )
        XCTAssertNil(
            quickNoteAutoAppendText(from: selfCapture, sourceBundleID: "com.praisedev.gilt", appBundleID: "com.praisedev.gilt")
        )
    }

    func testQuickNoteDroppedImageOCRFollowsSharedImageTextSearchSetting() {
        var settings = AppSettings()
        settings.enableImageTextRecognition = true
        XCTAssertTrue(shouldProcessQuickNoteDroppedImageOCR(settings: settings))

        settings.enableImageTextRecognition = false
        XCTAssertFalse(shouldProcessQuickNoteDroppedImageOCR(settings: settings))
    }

    @MainActor
    func testQuickNoteDroppedImageOCRUsesAccurateRecognitionByDefault() {
        let store = ClipboardStore()
        store.settings.ocrRecognitionLevelRaw = "fast"

        XCTAssertEqual(store.imageOCRConfiguration().recognitionLevelRaw, "fast")
        XCTAssertEqual(store.quickNoteImageOCRConfiguration().recognitionLevelRaw, "accurate")
    }
}
