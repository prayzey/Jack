import AppKit
import ImageIO
import OSLog

/// Centralized image thumbnail service with memory-budgeted caching.
///
/// Replaces the scattered per-view NSCache instances (ClipCardView, DrawerClipRow,
/// RadialClipNode) with a single cache that:
/// - Downsamples via CGImageSource (ImageIO) instead of fully decoding images
/// - Tracks actual decoded bitmap cost (width × height × 4), not compressed data size
/// - Enforces a hard 60 MB memory ceiling
@MainActor
final class ThumbnailService {
    static let shared = ThumbnailService()

    // MARK: - Cache

    private let cache: NSCache<NSString, CachedImage> = {
        let cache = NSCache<NSString, CachedImage>()
        cache.totalCostLimit = 60 * 1024 * 1024  // 60 MB of decoded bitmap
        cache.countLimit = 200
        return cache
    }()

    /// Dimensions cache — lightweight strings, no eviction pressure.
    private var dimensionsCache: [String: String] = [:]

    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "Thumbnail")
    private let perfLoggingEnabled = ProcessInfo.processInfo.environment["GILT_DEBUG_LOGS"] == "1"

    // Stats for diagnostics
    private var cacheHits = 0
    private var cacheMisses = 0

    // MARK: - Public API

    /// Returns a thumbnail sized for card display. Uses CGImageSource to downsample
    /// without fully decoding the source image — dramatically lower memory than NSImage(data:).
    ///
    /// - Parameters:
    ///   - clipID: Stable clip identifier (used as cache key component)
    ///   - data: Raw image data (PNG/TIFF/JPEG)
    ///   - maxDimension: Maximum width or height in points (doubled for Retina)
    /// - Returns: Downsampled NSImage, or nil if decoding fails
    @available(*, deprecated, message: "Decodes on the main thread, use AsyncClipThumbnail (views) or thumbnailAsync instead. A cache-miss call in a view body stalls the frame.")
    func thumbnail(for clipID: UUID, data: Data, maxDimension: CGFloat) -> NSImage? {
        let pixelDimension = maxDimension * 2  // Retina
        let cacheKey = "\(clipID.uuidString)-\(Int(pixelDimension))" as NSString

        if let cached = cache.object(forKey: cacheKey) {
            cacheHits += 1
            return cached.image
        }

        cacheMisses += 1
        let startedAt = DispatchTime.now()

        guard let image = Self.downsample(data: data, maxPixelDimension: pixelDimension) else {
            logPerf("thumbnail FAILED clip=\(clipID.uuidString.prefix(8)) dataSize=\(data.count)")
            return nil
        }

        let bitmapCost = Self.bitmapCost(for: image)
        let entry = CachedImage(image: image)
        cache.setObject(entry, forKey: cacheKey, cost: bitmapCost)

        let dims = dimensions(for: clipID, data: data) ?? "\(Int(image.size.width))×\(Int(image.size.height))"

        let ms = Self.elapsedMs(since: startedAt)
        logPerf(
            "thumbnail clip=\(clipID.uuidString.prefix(8)) "
            + "maxDim=\(Int(pixelDimension))px decoded=\(dims) "
            + "cost=\(bitmapCost / 1024)KB time=\(String(format: "%.2f", ms))ms "
            + "hits=\(cacheHits) misses=\(cacheMisses)"
        )
        return image
    }

    /// Fast, decode-free cache peek. Returns the thumbnail only if it is already
    /// cached — never blocks. Used by views to render instantly on a layout
    /// toggle and fall back to async decode on a miss.
    func cachedThumbnail(for clipID: UUID, maxDimension: CGFloat) -> NSImage? {
        let pixelDimension = maxDimension * 2
        let cacheKey = "\(clipID.uuidString)-\(Int(pixelDimension))" as NSString
        return cache.object(forKey: cacheKey)?.image
    }

    /// Async thumbnail: returns the cached image immediately, otherwise
    /// downsamples OFF the main thread before caching. This keeps a wall of
    /// image cards from janking the UI when the list/grid layout toggles —
    /// the synchronous `thumbnail(for:)` path decodes on the main thread, so a
    /// screenful of cache-miss decodes there freezes the toggle.
    func thumbnailAsync(for clipID: UUID, data: Data, maxDimension: CGFloat) async -> NSImage? {
        if let cached = cachedThumbnail(for: clipID, maxDimension: maxDimension) {
            return cached
        }
        // A cancelled caller (row scrolled offscreen, .task id superseded) must
        // not still spawn a detached decode, Task.detached severs structured
        // cancellation, so this pre-check is the only place it can be honored.
        guard !Task.isCancelled else { return nil }
        let pixelDimension = maxDimension * 2
        // Decode on a background task so the main thread stays responsive.
        let decoded: CachedImage? = await Task.detached(priority: .userInitiated) {
            guard let image = Self.downsample(data: data, maxPixelDimension: pixelDimension) else {
                return nil
            }
            return CachedImage(image: image)
        }.value
        guard let decoded else { return nil }
        let cacheKey = "\(clipID.uuidString)-\(Int(pixelDimension))" as NSString
        cache.setObject(decoded, forKey: cacheKey, cost: Self.bitmapCost(for: decoded.image))
        return decoded.image
    }

    /// Returns a full-resolution image for preview overlay. Uses the same cache
    /// but with a "full" key tier so it doesn't evict thumbnails.
    @available(*, deprecated, message: "Decodes on the main thread, use AsyncClipThumbnail (views) or fullImageAsync instead. A cache-miss call in a view body stalls the frame.")
    func fullImage(for clipID: UUID, data: Data) -> NSImage? {
        let cacheKey = "\(clipID.uuidString)-full" as NSString

        if let cached = cache.object(forKey: cacheKey) {
            cacheHits += 1
            return cached.image
        }

        cacheMisses += 1
        guard let image = NSImage(data: data) else { return nil }

        let bitmapCost = Self.bitmapCost(for: image)
        let entry = CachedImage(image: image)
        cache.setObject(entry, forKey: cacheKey, cost: bitmapCost)

        recordDimensionsIfAbsent(for: clipID, image: image)

        return image
    }

    /// Store PIXEL dimensions, and only when nothing is cached yet.
    /// `NSImage.size` is point-based, for a Retina screenshot it is half the
    /// pixel value, and unconditionally writing it here used to clobber the
    /// correct metadata-derived dimensions the card footers display.
    private func recordDimensionsIfAbsent(for clipID: UUID, image: NSImage) {
        let key = clipID.uuidString
        guard dimensionsCache[key] == nil else { return }
        if let rep = image.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            dimensionsCache[key] = "\(rep.pixelsWide)×\(rep.pixelsHigh)"
        } else {
            dimensionsCache[key] = "\(Int(image.size.width))×\(Int(image.size.height))"
        }
    }

    /// Decode-free cache peek for the "-full" tier, the full-image counterpart
    /// of `cachedThumbnail(for:maxDimension:)`. Never blocks.
    func cachedFullImage(for clipID: UUID) -> NSImage? {
        cache.object(forKey: "\(clipID.uuidString)-full" as NSString)?.image
    }

    /// Async full-resolution image: cache peek, then `NSImage(data:)` OFF the
    /// main actor. Mirrors `thumbnailAsync`, the synchronous `fullImage(for:)`
    /// decodes on the main thread, which stalls the preview overlay's open
    /// animation on a large screenshot.
    func fullImageAsync(for clipID: UUID, data: Data) async -> NSImage? {
        if let cached = cachedFullImage(for: clipID) {
            return cached
        }
        // Same cancellation pre-check as thumbnailAsync, see comment there.
        guard !Task.isCancelled else { return nil }
        let decoded: CachedImage? = await Task.detached(priority: .userInitiated) {
            guard let image = NSImage(data: data) else { return nil }
            return CachedImage(image: image)
        }.value
        guard let decoded else { return nil }
        let cacheKey = "\(clipID.uuidString)-full" as NSString
        cache.setObject(decoded, forKey: cacheKey, cost: Self.bitmapCost(for: decoded.image))
        recordDimensionsIfAbsent(for: clipID, image: decoded.image)
        return decoded.image
    }

    /// Returns cached dimensions string (e.g. "1920×1080") without decoding.
    func dimensions(for clipID: UUID) -> String? {
        dimensionsCache[clipID.uuidString]
    }

    /// Reads image pixel dimensions from metadata without forcing a full NSImage decode.
    func dimensions(for clipID: UUID, data: Data) -> String? {
        let cacheKey = clipID.uuidString
        if let cached = dimensionsCache[cacheKey] {
            return cached
        }

        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0,
              height > 0 else {
            return nil
        }

        let dimensions = "\(width)×\(height)"
        dimensionsCache[cacheKey] = dimensions
        return dimensions
    }

    /// Respond to system memory pressure.
    func handleMemoryPressure(isCritical: Bool) {
        if isCritical {
            cache.removeAllObjects()
            dimensionsCache.removeAll()
            logPerf("memoryPressure CRITICAL — cleared all")
        } else {
            // Warning: halve the budget temporarily to shed objects
            let currentLimit = cache.totalCostLimit
            cache.totalCostLimit = currentLimit / 2
            cache.totalCostLimit = currentLimit  // Restore — NSCache evicts down to new limit
            logPerf("memoryPressure WARNING — evicted to half budget")
        }
        cacheHits = 0
        cacheMisses = 0
    }

    /// Clear all cached images (e.g. on mode switch or window hide).
    func clearAll() {
        cache.removeAllObjects()
        dimensionsCache.removeAll()
    }

    // MARK: - ImageIO Downsampling

    /// Downsample image data using CGImageSource — decodes only the pixels needed
    /// for the target size, avoiding a full-resolution bitmap in memory.
    ///
    /// `nonisolated static` so it can run inside a detached background task
    /// (see `thumbnailAsync`). It touches no instance/actor state — only the
    /// passed-in `data` and CGImageSource — so it is safe off the main actor.
    nonisolated private static func downsample(data: Data, maxPixelDimension: CGFloat) -> NSImage? {
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false  // Don't cache the full source
        ]

        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            return nil
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,  // Decode at thumbnail size immediately
            kCGImageSourceCreateThumbnailWithTransform: true,  // Respect EXIF orientation
            kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    // MARK: - Cost Calculation

    /// Actual decoded bitmap memory: width × height × 4 bytes (RGBA).
    private static func bitmapCost(for image: NSImage) -> Int {
        guard let rep = image.representations.first else {
            // Fallback: estimate from point size at 2x
            return Int(image.size.width * 2 * image.size.height * 2 * 4)
        }
        return rep.pixelsWide * rep.pixelsHigh * 4
    }

    // MARK: - Helpers

    private static func elapsedMs(since start: DispatchTime) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    }

    private func logPerf(_ message: String) {
        guard perfLoggingEnabled else { return }
        logger.debug("\(message, privacy: .public)")
    }
}

// MARK: - Cache Entry Wrapper

/// NSCache requires object values (not structs). Thin wrapper around NSImage.
///
/// `@unchecked Sendable`: the wrapped `NSImage` is created once during
/// downsampling and never mutated afterward, so handing the immutable box from
/// the background decode task back to the main actor is safe.
private final class CachedImage: NSObject, @unchecked Sendable {
    let image: NSImage
    init(image: NSImage) {
        self.image = image
    }
}
