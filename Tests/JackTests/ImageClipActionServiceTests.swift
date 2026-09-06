import AppKit
import XCTest
@testable import Gilt

@MainActor
final class ImageClipActionServiceTests: XCTestCase {
    func testConvertImageToPNGProducesData() {
        let image = makeSampleImage()

        let data = ImageClipActionService.convert(image: image, to: .png)

        XCTAssertNotNil(data)
        XCTAssertTrue((data?.count ?? 0) > 0)
        XCTAssertNotNil(data.flatMap(NSImage.init(data:)))
    }

    func testConvertImageToJPEGProducesData() {
        let image = makeSampleImage()

        let data = ImageClipActionService.convert(image: image, to: .jpeg)

        XCTAssertNotNil(data)
        XCTAssertTrue((data?.count ?? 0) > 2)
        XCTAssertEqual(data?.prefix(2), Data([0xFF, 0xD8]))
    }

    func testConvertImageToTIFFProducesData() {
        let image = makeSampleImage()

        let data = ImageClipActionService.convert(image: image, to: .tiff)

        XCTAssertNotNil(data)
        XCTAssertTrue((data?.count ?? 0) > 0)
        XCTAssertNotNil(data.flatMap(NSImage.init(data:)))
    }

    func testConvertImageToPDFProducesPDFHeader() {
        let image = makeSampleImage()

        let data = ImageClipActionService.convert(image: image, to: .pdf)

        XCTAssertNotNil(data)
        XCTAssertTrue((data?.count ?? 0) > 4)
        XCTAssertEqual(String(data: data?.prefix(4) ?? Data(), encoding: .ascii), "%PDF")
    }

    private func makeSampleImage() -> NSImage {
        let size = NSSize(width: 48, height: 48)
        let image = NSImage(size: size)

        image.lockFocus()
        NSColor(calibratedRed: 0.93, green: 0.38, blue: 0.48, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: 10, y: 10, width: 28, height: 28)).fill()
        image.unlockFocus()

        return image
    }
}
