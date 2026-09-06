import AppKit
import XCTest
@testable import Gilt

@MainActor
final class ThumbnailServiceTests: XCTestCase {
    func testDimensionsReadFromMetadataWithoutFullImageDecode() throws {
        ThumbnailService.shared.clearAll()
        let data = try makePNGData(width: 10, height: 20)

        let dimensions = ThumbnailService.shared.dimensions(for: UUID(), data: data)

        XCTAssertEqual(dimensions, "10×20")
    }

    func testThumbnailCachesDimensionsForLaterLookup() throws {
        ThumbnailService.shared.clearAll()
        let clipID = UUID()
        let data = try makePNGData(width: 24, height: 36)

        let thumbnail = ThumbnailService.shared.thumbnail(for: clipID, data: data, maxDimension: 12)

        XCTAssertNotNil(thumbnail)
        XCTAssertEqual(ThumbnailService.shared.dimensions(for: clipID), "24×36")
    }

    private func makePNGData(width: Int, height: Int) throws -> Data {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw NSError(domain: "ThumbnailServiceTests", code: 1)
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.systemPink.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "ThumbnailServiceTests", code: 2)
        }
        return data
    }
}
