import AppKit
import XCTest
@testable import Gilt

final class ContentFingerprintTests: XCTestCase {

    func testImageFingerprintMatchesAcrossReencodedVariants() throws {
        let image = makeReferenceImage(accent: .systemBlue)
        let pngData = try XCTUnwrap(image.pngData())
        let jpegData = try XCTUnwrap(jpegData(for: image))

        XCTAssertNotEqual(pngData, jpegData, "Sanity check: the encoded clipboard payloads should differ")
        XCTAssertEqual(
            ContentFingerprint.fingerprint(type: .image, textValue: nil, urlValue: nil, imageData: pngData),
            ContentFingerprint.fingerprint(type: .image, textValue: nil, urlValue: nil, imageData: jpegData)
        )
    }

    func testImageFingerprintChangesWhenLayoutMeaningfullyMoves() throws {
        let anchored = try XCTUnwrap(makeReferenceImage(accent: .systemBlue).pngData())
        let shifted = try XCTUnwrap(makeReferenceImage(accent: .systemBlue, shiftAccentRow: true).pngData())

        XCTAssertNotEqual(
            ContentFingerprint.fingerprint(type: .image, textValue: nil, urlValue: nil, imageData: anchored),
            ContentFingerprint.fingerprint(type: .image, textValue: nil, urlValue: nil, imageData: shifted)
        )
    }

    func testImageFingerprintFallbackHashesUndecodableDataStably() {
        let invalidData = Data([0x01, 0x02, 0x03, 0x04, 0x05])
        let fingerprint = ContentFingerprint.fingerprint(
            type: .image,
            textValue: nil,
            urlValue: nil,
            imageData: invalidData
        )

        XCTAssertFalse(fingerprint.isEmpty)
        XCTAssertEqual(
            fingerprint,
            ContentFingerprint.fingerprint(type: .image, textValue: nil, urlValue: nil, imageData: invalidData)
        )
        XCTAssertTrue(ContentFingerprint.isCurrentImageHash(fingerprint))
    }

    func testImageFingerprintChangesForMeaningfullyDifferentArtwork() throws {
        let first = try XCTUnwrap(makeReferenceImage(accent: .systemBlue).pngData())
        let second = try XCTUnwrap(makeReferenceImage(accent: .systemBlue, clearBackground: false, reverseSecondaryBars: true).pngData())

        XCTAssertNotEqual(
            ContentFingerprint.fingerprint(type: .image, textValue: nil, urlValue: nil, imageData: first),
            ContentFingerprint.fingerprint(type: .image, textValue: nil, urlValue: nil, imageData: second)
        )
    }

    private func makeReferenceImage(
        accent: NSColor,
        canvasSize: NSSize = NSSize(width: 180, height: 120),
        contentInset: CGSize = .zero,
        clearBackground: Bool = false,
        shiftAccentRow: Bool = false,
        reverseSecondaryBars: Bool = false
    ) -> NSImage {
        let image = NSImage(size: canvasSize)
        let contentRect = NSRect(
            x: contentInset.width,
            y: contentInset.height,
            width: canvasSize.width - (contentInset.width * 2),
            height: canvasSize.height - (contentInset.height * 2)
        )

        image.lockFocus()
        defer { image.unlockFocus() }

        if clearBackground {
            NSColor.clear.setFill()
        } else {
            NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
        }
        NSBezierPath(rect: NSRect(origin: .zero, size: canvasSize)).fill()

        guard contentRect.width > 0, contentRect.height > 0 else { return image }

        let unitX = contentRect.width / 180.0
        let unitY = contentRect.height / 120.0
        let accentY = shiftAccentRow ? 42.0 : 18.0

        NSColor(calibratedRed: 0.15, green: 0.18, blue: 0.28, alpha: 1).setFill()
        NSBezierPath(rect: scaledRect(x: 12, y: 72, width: 156, height: 20, in: contentRect, unitX: unitX, unitY: unitY)).fill()

        accent.setFill()
        NSBezierPath(rect: scaledRect(x: 18, y: accentY, width: 54, height: 38, in: contentRect, unitX: unitX, unitY: unitY)).fill()

        NSColor(calibratedRed: 0.28, green: 0.74, blue: 0.48, alpha: 1).setFill()
        NSBezierPath(rect: scaledRect(x: 88, y: 18, width: 72, height: 38, in: contentRect, unitX: unitX, unitY: unitY)).fill()

        NSColor(calibratedWhite: 0.85, alpha: 1).setFill()
        let firstBar = reverseSecondaryBars
            ? scaledRect(x: 18, y: 48, width: 132, height: 6, in: contentRect, unitX: unitX, unitY: unitY)
            : scaledRect(x: 18, y: 60, width: 112, height: 6, in: contentRect, unitX: unitX, unitY: unitY)
        NSBezierPath(rect: firstBar).fill()

        NSColor(calibratedWhite: 0.78, alpha: 1).setFill()
        let secondBar = reverseSecondaryBars
            ? scaledRect(x: 18, y: 60, width: 112, height: 6, in: contentRect, unitX: unitX, unitY: unitY)
            : scaledRect(x: 18, y: 48, width: 132, height: 6, in: contentRect, unitX: unitX, unitY: unitY)
        NSBezierPath(rect: secondBar).fill()

        return image
    }

    private func scaledRect(
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        in contentRect: NSRect,
        unitX: CGFloat,
        unitY: CGFloat
    ) -> NSRect {
        NSRect(
            x: contentRect.minX + (x * unitX),
            y: contentRect.minY + (y * unitY),
            width: width * unitX,
            height: height * unitY
        )
    }

    private func jpegData(for image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        return bitmap.representation(
            using: .jpeg,
            properties: [.compressionFactor: 0.72]
        )
    }
}
