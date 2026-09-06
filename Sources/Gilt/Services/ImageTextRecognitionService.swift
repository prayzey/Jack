import CoreGraphics
import Foundation
import ImageIO
import OSLog
import Vision

struct ImageOCRConfiguration: Sendable {
    var recognitionLevelRaw: String
    var minimumTextHeight: Float
    var maxImageMegapixels: Double
    var maxImageBytes: Int
    var recognitionLanguages: [String]
    var maxDimension: Int = 2_048
    var maxOutputCharacters: Int = 8_000

    var recognitionLevel: VNRequestTextRecognitionLevel {
        recognitionLevelRaw == "accurate" ? .accurate : .fast
    }

    var sanitizedMinimumTextHeight: Float {
        min(max(minimumTextHeight, 0), 1)
    }

    var sanitizedLanguages: [String] {
        let filtered = recognitionLanguages.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return filtered.isEmpty ? ["en-US"] : filtered
    }
}

enum ImageOCROutcome: Sendable {
    case success(String?)
    case skipped(String)
    case failed(String)
}

actor ImageTextRecognitionService {
    static let shared = ImageTextRecognitionService()

    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "ImageOCR")
    private let perfLoggingEnabled = ProcessInfo.processInfo.environment["GILT_DEBUG_LOGS"] == "1"
    private var cooldownUntil: Date?

    func recognize(imageData: Data, configuration: ImageOCRConfiguration) -> ImageOCROutcome {
        if let cooldownUntil, cooldownUntil > Date() {
            return .skipped("memory_pressure_cooldown")
        }

        if imageData.count > configuration.maxImageBytes {
            return .skipped("image_too_large_bytes")
        }

        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else {
            return .failed("decode_failed")
        }

        guard let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = metadata[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = metadata[kCGImagePropertyPixelHeight] as? CGFloat,
              width > 0,
              height > 0 else {
            return .failed("image_metadata_unavailable")
        }

        let megapixels = Double(width * height) / 1_000_000.0
        if megapixels > configuration.maxImageMegapixels {
            return .skipped("image_too_large_pixels")
        }

        guard let cgImage = makeOCRImage(from: source, maxDimension: configuration.maxDimension) else {
            return .failed("cgimage_build_failed")
        }

        do {
            let recognizedText = try recognizeText(
                from: cgImage,
                configuration: configuration
            )
            if recognizedText.isEmpty {
                return .success(nil)
            }
            let clipped = recognizedText.count > configuration.maxOutputCharacters
                ? String(recognizedText.prefix(configuration.maxOutputCharacters))
                : recognizedText
            return .success(clipped)
        } catch {
            logPerf("ocr_failed")
            return .failed("vision_request_failed")
        }
    }

    func handleMemoryPressure(isCritical: Bool) {
        let now = Date()
        cooldownUntil = now.addingTimeInterval(isCritical ? 15 : 5)
        let level = isCritical ? "CRITICAL" : "WARNING"
        logPerf("memory_pressure level=\(level) cooldownUntil=\(cooldownUntil?.description ?? "nil")")
    }

    private func makeOCRImage(from source: CGImageSource, maxDimension: Int) -> CGImage? {
        autoreleasepool {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxDimension,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: false
            ]
            if let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                return thumbnail
            }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
    }

    private func recognizeText(from cgImage: CGImage, configuration: ImageOCRConfiguration) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = configuration.recognitionLevel
        request.recognitionLanguages = configuration.sanitizedLanguages
        request.usesLanguageCorrection = false
        request.minimumTextHeight = configuration.sanitizedMinimumTextHeight

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        let lines = (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return lines.joined(separator: "\n")
    }

    private func logPerf(_ message: String) {
        guard perfLoggingEnabled else { return }
        logger.debug("\(message, privacy: .public)")
    }
}
