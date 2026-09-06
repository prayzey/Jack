import AppKit
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

/// Computes normalized SHA-256 content fingerprints for duplicate detection.
/// Each clip type has its own normalization strategy so near-identical content
/// (extra whitespace, trailing slashes, tracking params) maps to the same hash.
enum ContentFingerprint {
    private static let currentImageHashPrefix = "imgv4:"
    private static let currentImageFallbackHashPrefix = "imgv4raw:"

    // MARK: - Public API

    /// Compute a fingerprint from a captured clipboard item before it becomes a model.
    static func fingerprint(
        type: ClipType,
        textValue: String?,
        urlValue: String?,
        imageData: Data?
    ) -> String {
        switch type {
        case .image:
            return fingerprintImage(imageData)
        case .link:
            return fingerprintLink(urlValue ?? textValue)
        case .color:
            return fingerprintColor(textValue)
        case .text, .audio:
            return fingerprintText(textValue)
        }
    }

    /// Recompute a fingerprint from an existing ClipItemModel (for backfilling).
    static func fingerprint(for clip: ClipItemModel) -> String {
        fingerprint(
            type: clip.clipType,
            textValue: clip.textValue ?? clip.previewText,
            urlValue: clip.urlValue,
            imageData: clip.imageData
        )
    }

    /// Offload image hashing from hot UI paths while keeping lightweight text/link
    /// hashing synchronous.
    static func fingerprintAsync(
        type: ClipType,
        textValue: String?,
        urlValue: String?,
        imageData: Data?
    ) async -> String {
        guard type == .image else {
            return fingerprint(type: type, textValue: textValue, urlValue: urlValue, imageData: imageData)
        }

        guard let imageData, !imageData.isEmpty else { return "" }
        let textValue = textValue
        let urlValue = urlValue
        return await Task.detached(priority: .utility) {
            fingerprint(type: type, textValue: textValue, urlValue: urlValue, imageData: imageData)
        }.value
    }

    static func isCurrentImageHash(_ hash: String) -> Bool {
        hash.hasPrefix(currentImageHashPrefix) || hash.hasPrefix(currentImageFallbackHashPrefix)
    }

    // MARK: - Type-Specific Strategies

    /// Text: collapse runs of whitespace to single space, trim, lowercase, then hash.
    private static func fingerprintText(_ text: String?) -> String {
        guard let text, !text.isEmpty else { return "" }
        let normalized = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
        return sha256(normalized)
    }

    /// Link: normalize URL (lowercase scheme+host, strip trailing slash,
    /// remove common tracking query params, sort remaining params).
    private static func fingerprintLink(_ rawURL: String?) -> String {
        guard let rawURL, !rawURL.isEmpty else { return "" }

        guard var components = URLComponents(string: rawURL) else {
            // Fallback: treat as text if URL can't be parsed
            return fingerprintText(rawURL)
        }

        // Lowercase scheme and host
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()

        // Strip trailing slash from path
        if components.path.hasSuffix("/") && components.path.count > 1 {
            components.path = String(components.path.dropLast())
        }

        // Remove tracking / analytics query params
        if let queryItems = components.queryItems {
            let filtered = queryItems.filter { item in
                !Self.trackingParams.contains(item.name.lowercased())
            }
            components.queryItems = filtered.isEmpty ? nil : filtered.sorted { $0.name < $1.name }
        }

        // Remove fragment
        components.fragment = nil

        let normalized = components.string ?? rawURL
        // Preserve path/query case; only scheme+host are normalized to lowercase above.
        return sha256(normalized)
    }

    /// Image: hash a normalized low-resolution pixel sample instead of the raw file bytes.
    /// This keeps duplicate detection stable when helper apps re-encode the same image
    /// (for example, clipboard optimizers that rewrite PNG metadata or compression settings).
    private static func fingerprintImage(_ data: Data?) -> String {
        guard let data, !data.isEmpty else { return "" }
        guard let normalized = normalizedImageSample(data) else {
            return currentImageFallbackHashPrefix + sha256(data)
        }
        return currentImageHashPrefix + sha256(normalized)
    }

    /// Color: normalize hex representations to uppercase 6-digit format,
    /// then hash the normalized string.
    private static func fingerprintColor(_ text: String?) -> String {
        guard let text, !text.isEmpty else { return "" }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Try to normalize hex colors: #fff → #ffffff, #FFF → #ffffff
        if trimmed.hasPrefix("#") {
            let hex = String(trimmed.dropFirst())
            if hex.count == 3 {
                // Expand shorthand: #abc → #aabbcc
                let expanded = hex.map { "\($0)\($0)" }.joined()
                return sha256("#\(expanded)")
            } else if hex.count == 6 || hex.count == 8 {
                return sha256("#\(hex)")
            }
        }

        // rgb(), hsl(), named colors — just lowercase and collapse whitespace
        return fingerprintText(trimmed)
    }

    // MARK: - Hashing

    private static func sha256(_ string: String) -> String {
        let data = Data(string.utf8)
        return sha256(data)
    }

    private static func sha256(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Image Normalization

    /// Downsample images into a detailed normalized sample so visually identical images
    /// hash the same even if another app rewrites the clipboard representation.
    private static func normalizedImageSample(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 64,
                  kCGImageSourceShouldCacheImmediately: false,
              ] as CFDictionary) else {
            return nil
        }

        let width = thumbnail.width
        let height = thumbnail.height
        guard width > 0, height > 0 else { return nil }

        let canvasDimension = 64
        let luminanceHashGridSize = 8
        let colorGridSize = 3

        guard let pixels = normalizedCanvasPixels(from: thumbnail, canvasDimension: canvasDimension),
              let visibleBounds = visiblePixelBounds(in: pixels, dimension: canvasDimension) else { return nil }

        let aspectBucket = UInt16(
            max(1, min(65_535, Int(((Double(visibleBounds.width) / Double(visibleBounds.height)) * 1000.0).rounded())))
        )

        var normalized = Data()
        normalized.reserveCapacity(2 + ((luminanceHashGridSize * luminanceHashGridSize) / 8) + (colorGridSize * colorGridSize * 3))
        withUnsafeBytes(of: aspectBucket.bigEndian) { normalized.append(contentsOf: $0) }
        appendAverageLuminanceHash(
            into: &normalized,
            pixels: pixels,
            dimension: canvasDimension,
            bounds: visibleBounds,
            gridSize: luminanceHashGridSize
        )
        appendColorGrid(
            into: &normalized,
            pixels: pixels,
            dimension: canvasDimension,
            bounds: visibleBounds,
            gridSize: colorGridSize
        )
        return normalized
    }

    private static func normalizedCanvasPixels(from image: CGImage, canvasDimension: Int) -> Data? {
        let bytesPerPixel = 4
        let bitsPerComponent = 8
        let bytesPerRow = canvasDimension * bytesPerPixel
        var pixels = Data(count: canvasDimension * canvasDimension * bytesPerPixel)

        let drawn = pixels.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard let baseAddress = rawBuffer.baseAddress,
                  let context = CGContext(
                      data: baseAddress,
                      width: canvasDimension,
                      height: canvasDimension,
                      bitsPerComponent: bitsPerComponent,
                      bytesPerRow: bytesPerRow,
                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else {
                return false
            }

            context.interpolationQuality = .medium
            context.setFillColor(NSColor.clear.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: canvasDimension, height: canvasDimension))
            context.draw(image, in: aspectFitRect(for: image, canvasDimension: canvasDimension))
            return true
        }

        return drawn ? pixels : nil
    }

    private static func aspectFitRect(for image: CGImage, canvasDimension: Int) -> CGRect {
        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)
        let scale = min(CGFloat(canvasDimension) / imageWidth, CGFloat(canvasDimension) / imageHeight)
        let drawWidth = imageWidth * scale
        let drawHeight = imageHeight * scale
        return CGRect(
            x: (CGFloat(canvasDimension) - drawWidth) / 2.0,
            y: (CGFloat(canvasDimension) - drawHeight) / 2.0,
            width: drawWidth,
            height: drawHeight
        )
    }

    private static func visiblePixelBounds(in pixels: Data, dimension: Int) -> CGRect? {
        let bytesPerPixel = 4
        var minX = dimension
        var minY = dimension
        var maxX = -1
        var maxY = -1

        for y in 0..<dimension {
            for x in 0..<dimension {
                let alpha = pixels[((y * dimension) + x) * bytesPerPixel + 3]
                guard alpha > 12 else { continue }
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        guard maxX >= minX, maxY >= minY else {
            return CGRect(x: 0, y: 0, width: dimension, height: dimension)
        }

        return CGRect(
            x: minX,
            y: minY,
            width: max(1, maxX - minX + 1),
            height: max(1, maxY - minY + 1)
        )
    }

    private static func appendAverageLuminanceHash(
        into output: inout Data,
        pixels: Data,
        dimension: Int,
        bounds: CGRect,
        gridSize: Int
    ) {
        let samples = averagedLuminanceSamples(
            pixels: pixels,
            dimension: dimension,
            bounds: bounds,
            gridSize: gridSize
        )
        guard !samples.isEmpty else { return }

        let mean = samples.reduce(0, +) / samples.count
        var currentByte: UInt8 = 0
        var bitCount = 0

        for sample in samples {
            currentByte <<= 1
            if sample >= mean {
                currentByte |= 1
            }
            bitCount += 1

            if bitCount == 8 {
                output.append(currentByte)
                currentByte = 0
                bitCount = 0
            }
        }

        if bitCount > 0 {
            currentByte <<= UInt8(8 - bitCount)
            output.append(currentByte)
        }
    }

    private static func averagedLuminanceSamples(
        pixels: Data,
        dimension: Int,
        bounds: CGRect,
        gridSize: Int
    ) -> [Int] {
        let bytesPerPixel = 4
        var samples: [Int] = []
        samples.reserveCapacity(gridSize * gridSize)

        for gridY in 0..<gridSize {
            let startY = gridBoundaryStart(index: gridY, total: gridSize, origin: Int(bounds.minY), length: Int(bounds.height))
            let endY = gridBoundaryEnd(index: gridY, total: gridSize, origin: Int(bounds.minY), length: Int(bounds.height))

            for gridX in 0..<gridSize {
                let startX = gridBoundaryStart(index: gridX, total: gridSize, origin: Int(bounds.minX), length: Int(bounds.width))
                let endX = gridBoundaryEnd(index: gridX, total: gridSize, origin: Int(bounds.minX), length: Int(bounds.width))
                var luminanceTotal = 0

                for pixelY in startY..<endY {
                    for pixelX in startX..<endX {
                        guard pixelX >= 0, pixelX < dimension, pixelY >= 0, pixelY < dimension else { continue }
                        let pixelIndex = ((pixelY * dimension) + pixelX) * bytesPerPixel

                        let red = Int(pixels[pixelIndex])
                        let green = Int(pixels[pixelIndex + 1])
                        let blue = Int(pixels[pixelIndex + 2])
                        let alpha = Int(pixels[pixelIndex + 3])

                        let compositedRed = (red * alpha + 255 * (255 - alpha)) / 255
                        let compositedGreen = (green * alpha + 255 * (255 - alpha)) / 255
                        let compositedBlue = (blue * alpha + 255 * (255 - alpha)) / 255
                        luminanceTotal += (299 * compositedRed + 587 * compositedGreen + 114 * compositedBlue) / 1000
                    }
                }

                let sampleCount = max(1, (endX - startX) * (endY - startY))
                samples.append(luminanceTotal / sampleCount)
            }
        }

        return samples
    }

    private static func appendColorGrid(
        into output: inout Data,
        pixels: Data,
        dimension: Int,
        bounds: CGRect,
        gridSize: Int
    ) {
        let bytesPerPixel = 4

        for gridY in 0..<gridSize {
            let startY = gridBoundaryStart(index: gridY, total: gridSize, origin: Int(bounds.minY), length: Int(bounds.height))
            let endY = gridBoundaryEnd(index: gridY, total: gridSize, origin: Int(bounds.minY), length: Int(bounds.height))

            for gridX in 0..<gridSize {
                let startX = gridBoundaryStart(index: gridX, total: gridSize, origin: Int(bounds.minX), length: Int(bounds.width))
                let endX = gridBoundaryEnd(index: gridX, total: gridSize, origin: Int(bounds.minX), length: Int(bounds.width))
                var redTotal = 0
                var greenTotal = 0
                var blueTotal = 0

                for pixelY in startY..<endY {
                    for pixelX in startX..<endX {
                        guard pixelX >= 0, pixelX < dimension, pixelY >= 0, pixelY < dimension else { continue }
                        let pixelIndex = ((pixelY * dimension) + pixelX) * bytesPerPixel

                        let red = Int(pixels[pixelIndex])
                        let green = Int(pixels[pixelIndex + 1])
                        let blue = Int(pixels[pixelIndex + 2])
                        let alpha = Int(pixels[pixelIndex + 3])

                        redTotal += (red * alpha + 255 * (255 - alpha)) / 255
                        greenTotal += (green * alpha + 255 * (255 - alpha)) / 255
                        blueTotal += (blue * alpha + 255 * (255 - alpha)) / 255
                    }
                }

                let sampleCount = max(1, (endX - startX) * (endY - startY))
                output.append(quantizeAverage(redTotal, count: sampleCount, step: 64))
                output.append(quantizeAverage(greenTotal, count: sampleCount, step: 64))
                output.append(quantizeAverage(blueTotal, count: sampleCount, step: 64))
            }
        }
    }

    private static func gridBoundaryStart(index: Int, total: Int, origin: Int, length: Int) -> Int {
        origin + ((index * length) / total)
    }

    private static func gridBoundaryEnd(index: Int, total: Int, origin: Int, length: Int) -> Int {
        max(origin + ((index + 1) * length) / total, gridBoundaryStart(index: index, total: total, origin: origin, length: length) + 1)
    }

    private static func quantizeAverage(_ total: Int, count: Int, step: Int) -> UInt8 {
        guard count > 0 else { return 0 }
        let average = total / count
        return UInt8((average / step) * step)
    }

    // MARK: - Tracking Param Blocklist

    /// Common analytics/tracking query parameters stripped during URL normalization.
    private static let trackingParams: Set<String> = [
        // Google Analytics / Ads
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
        "gclid", "gclsrc", "dclid", "gbraid", "wbraid",
        // Facebook / Meta
        "fbclid", "fb_action_ids", "fb_action_types", "fb_source", "fb_ref",
        // Microsoft / Bing
        "msclkid",
        // HubSpot
        "hsa_cam", "hsa_grp", "hsa_mt", "hsa_src", "hsa_ad", "hsa_acc",
        "hsa_net", "hsa_ver", "hsa_la", "hsa_ol", "hsa_kw",
        // Mailchimp
        "mc_cid", "mc_eid",
        // Generic
        "ref", "referrer", "source",
    ]
}
