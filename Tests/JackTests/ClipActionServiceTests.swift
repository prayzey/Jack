import XCTest
@testable import Gilt

final class ClipActionServiceTests: XCTestCase {

    func testBrowserPlanUsesDirectURLForLinkClip() {
        let clip = makeClip(type: .link, textValue: "https://example.com/docs", urlValue: "https://example.com/docs")

        let plan = ClipActionService.planBrowserAction(for: [clip])

        guard let plan else {
            XCTFail("Expected browser plan")
            return
        }

        switch plan.destination {
        case .openURL(let url):
            XCTAssertEqual(url.absoluteString, "https://example.com/docs")
        case .search:
            XCTFail("Expected direct URL open, got search")
        }
    }

    func testBrowserPlanNormalizesBareDomain() {
        let clip = makeClip(type: .text, textValue: "openai.com/research")

        let plan = ClipActionService.planBrowserAction(for: [clip])

        guard let plan else {
            XCTFail("Expected browser plan")
            return
        }

        switch plan.destination {
        case .openURL(let url):
            XCTAssertEqual(url.absoluteString, "https://openai.com/research")
        case .search:
            XCTFail("Expected URL normalization, got search")
        }
    }

    func testBrowserPlanFallsBackToSearchForPlainText() {
        let clip = makeClip(type: .text, textValue: "best mac clipboard manager")

        let plan = ClipActionService.planBrowserAction(for: [clip])

        guard let plan else {
            XCTFail("Expected browser plan")
            return
        }

        switch plan.destination {
        case .search(let url):
            XCTAssertTrue(url.absoluteString.contains("google.com/search"))
            XCTAssertTrue(url.absoluteString.contains("q=best%20mac%20clipboard%20manager"))
        case .openURL:
            XCTFail("Expected search fallback, got direct URL")
        }
    }

    func testBrowserPlanSkipsImagePlaceholderText() {
        let imageClip = makeClip(type: .image, previewText: "Image clip", textValue: nil, urlValue: nil, imageData: Data([0xFF]))

        let plan = ClipActionService.planBrowserAction(for: [imageClip])

        XCTAssertNil(plan, "Image-only clips should not produce a noisy browser search")
    }

    func testEmailPlanIncludesAttachmentFlagForImage() {
        let imageClip = makeClip(type: .image, previewText: "Image clip", textValue: nil, urlValue: nil, imageData: Data([0x89, 0x50]))

        let plan = ClipActionService.planEmailAction(for: [imageClip])

        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.hasImageAttachments, true)
        XCTAssertEqual(plan?.subject, "Shared Image from Jack")
    }

    func testEmailPlanBuildsCombinedBodyForMultipleClips() {
        let first = makeClip(type: .text, textValue: "First line")
        let second = makeClip(type: .link, textValue: "https://example.com", urlValue: "https://example.com")

        let plan = ClipActionService.planEmailAction(for: [first, second])

        XCTAssertEqual(plan?.subject, "Shared 2 Clips from Jack")
        XCTAssertEqual(plan?.body, "First line\n\nhttps://example.com")
    }

    func testMailtoURLEncodesSubjectAndBody() {
        let url = ClipActionService.makeMailtoURL(subject: "Hello there", body: "Line 1\nLine 2")

        XCTAssertNotNil(url)
        let value = url?.absoluteString ?? ""
        XCTAssertTrue(value.hasPrefix("mailto:?"))
        XCTAssertTrue(value.contains("subject=Hello%20there"))
        XCTAssertTrue(value.contains("body=Line%201%0ALine%202"))
    }

    private func makeClip(
        type: ClipType,
        previewText: String = "Preview",
        textValue: String? = "Preview",
        urlValue: String? = nil,
        imageData: Data? = nil
    ) -> ClipItemModel {
        ClipItemModel(
            typeRaw: type.rawValue,
            title: "Test",
            previewText: previewText,
            textValue: textValue,
            urlValue: urlValue,
            imageData: imageData,
            sourceAppName: "Tests"
        )
    }
}
