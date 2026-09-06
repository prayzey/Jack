import XCTest
@testable import Gilt

final class ImageTextRecognitionServiceTests: XCTestCase {
    func testRecognizeSkipsWhenImageDataExceedsByteLimit() async {
        let service = ImageTextRecognitionService()
        let outcome = await service.recognize(
            imageData: Data(repeating: 0xAB, count: 2),
            configuration: ImageOCRConfiguration(
                recognitionLevelRaw: "fast",
                minimumTextHeight: 0.02,
                maxImageMegapixels: 12,
                maxImageBytes: 1,
                recognitionLanguages: ["en-US"]
            )
        )

        guard case .skipped(let code) = outcome else {
            XCTFail("Expected skipped outcome")
            return
        }
        XCTAssertEqual(code, "image_too_large_bytes")
    }

    func testRecognizeSkipsDuringMemoryPressureCooldown() async {
        let service = ImageTextRecognitionService()
        await service.handleMemoryPressure(isCritical: true)
        let outcome = await service.recognize(
            imageData: Data(repeating: 0xAA, count: 16),
            configuration: ImageOCRConfiguration(
                recognitionLevelRaw: "fast",
                minimumTextHeight: 0.02,
                maxImageMegapixels: 12,
                maxImageBytes: 1024,
                recognitionLanguages: ["en-US"]
            )
        )

        guard case .skipped(let code) = outcome else {
            XCTFail("Expected skipped outcome")
            return
        }
        XCTAssertEqual(code, "memory_pressure_cooldown")
    }

    func testRecognizeFailsForInvalidImageData() async {
        let service = ImageTextRecognitionService()
        let outcome = await service.recognize(
            imageData: Data(repeating: 0xCC, count: 64),
            configuration: ImageOCRConfiguration(
                recognitionLevelRaw: "fast",
                minimumTextHeight: 0.02,
                maxImageMegapixels: 12,
                maxImageBytes: 1024,
                recognitionLanguages: ["en-US"]
            )
        )

        guard case .failed(let code) = outcome else {
            XCTFail("Expected failed outcome")
            return
        }
        XCTAssertEqual(code, "image_metadata_unavailable")
    }
}
