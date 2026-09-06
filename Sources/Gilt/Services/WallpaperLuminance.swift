import AppKit
import CoreGraphics
import Foundation

/// Cheap perceptual luminance estimate for an `NSImage`, used by Quick Note
/// to auto-pick a readable text colour over user wallpapers. We scale the
/// image down to a tiny 16x16 thumbnail, average the channels, then apply
/// the BT.709 luminance weights so the result tracks human brightness
/// perception rather than raw RGB.
enum WallpaperLuminance {
    private static let sampleEdge = 16

    /// Returns 0...1 where 0 is pitch black and 1 is pure white, or nil if
    /// the image can't be sampled. Heavy callers should cache the result
    /// per wallpaper rather than re-sampling on every view update.
    static func averageLuminance(of image: NSImage) -> Double? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let width = sampleEdge
        let height = sampleEdge
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8

        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue).rawValue

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var total = 0.0
        var samples = 0.0
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * bytesPerRow) + (x * bytesPerPixel)
                let r = Double(pixels[offset]) / 255.0
                let g = Double(pixels[offset + 1]) / 255.0
                let b = Double(pixels[offset + 2]) / 255.0
                // BT.709 — tracks perceived brightness closely enough for a
                // text-vs-background contrast decision.
                total += 0.2126 * r + 0.7152 * g + 0.0722 * b
                samples += 1
            }
        }

        guard samples > 0 else { return nil }
        return total / samples
    }

    /// Samples a normalized region of the image (0...1 coordinates) so text
    /// contrast can follow what sits behind the popover content, not the
    /// whole wallpaper frame.
    //
    // (See WallpaperLuminanceCache below for the memoized whole-image variant
    // used by the Quick Note editor's redraw-heavy text-colour pick.)
    static func averageLuminance(in normalizedRect: CGRect, of image: NSImage) -> Double? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {
            return nil
        }

        let width = rep.pixelsWide
        let height = rep.pixelsHigh
        guard width > 2, height > 2 else { return nil }

        let clampedMinX = max(0, min(1, normalizedRect.minX))
        let clampedMaxX = max(clampedMinX, min(1, normalizedRect.maxX))
        let clampedMinY = max(0, min(1, normalizedRect.minY))
        let clampedMaxY = max(clampedMinY, min(1, normalizedRect.maxY))

        let minX = Int(clampedMinX * Double(width - 1))
        let maxX = Int(clampedMaxX * Double(width - 1))
        let minY = Int(clampedMinY * Double(height - 1))
        let maxY = Int(clampedMaxY * Double(height - 1))

        let stepX = max(1, (maxX - minX) / 24)
        let stepY = max(1, (maxY - minY) / 24)

        var total = 0.0
        var count = 0.0
        for y in stride(from: minY, through: maxY, by: stepY) {
            for x in stride(from: minX, through: maxX, by: stepX) {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                total += 0.299 * color.redComponent + 0.587 * color.greenComponent + 0.114 * color.blueComponent
                count += 1
            }
        }

        guard count > 0 else { return nil }
        return total / count
    }
}

/// Memoized whole-image luminance for the Quick Note editor.
///
/// `QuickNoteView.noteCard` re-derives the readable text colour on every body
/// pass, and the body re-runs on every keystroke, scroll tick, and swipe
/// frame. Sampling the wallpaper (decode + 16x16 redraw + 256-pixel average)
/// each time was a measurable source of typing/scroll lag — the underlying
/// `WallpaperLuminance` even documents that heavy callers should cache.
///
/// The cache key is the `NSImage`'s object identity. Wallpaper images are
/// themselves cached and reused per wallpaper, and importing a new custom
/// wallpaper clears that image cache (so a fresh instance — and therefore a
/// fresh identity — forces a recompute). That makes identity a correct,
/// invalidation-free key. The wallpaper image stays retained by its cache
/// while in use, so its identity can't be recycled out from under a live note.
@MainActor
enum WallpaperLuminanceCache {
    private static var storage: [ObjectIdentifier: Double] = [:]
    private static var regionStorage: [RegionKey: Double] = [:]
    /// Hard cap so the table can't grow without bound if many distinct custom
    /// wallpapers are sampled over a long session. A handful of entries is the
    /// norm; clearing past the cap just forces a one-off recompute.
    private static let capacity = 32

    private struct RegionKey: Hashable {
        let image: ObjectIdentifier
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }

    static func averageLuminance(of image: NSImage) -> Double? {
        let key = ObjectIdentifier(image)
        if let cached = storage[key] {
            return cached
        }
        guard let value = WallpaperLuminance.averageLuminance(of: image) else {
            return nil
        }
        if storage.count >= capacity {
            storage.removeAll(keepingCapacity: true)
        }
        storage[key] = value
        return value
    }

    /// Memoized region sample. The uncached variant TIFF-encodes the entire
    /// wallpaper (tens of MB for a retina image) and walks pixels via
    /// `colorAt` — fine once, disastrous when a view body re-derives its ink
    /// on every render. Same identity-keyed invalidation story as above.
    static func averageLuminance(in normalizedRect: CGRect, of image: NSImage) -> Double? {
        let key = RegionKey(
            image: ObjectIdentifier(image),
            x: normalizedRect.origin.x,
            y: normalizedRect.origin.y,
            width: normalizedRect.width,
            height: normalizedRect.height
        )
        if let cached = regionStorage[key] {
            return cached
        }
        guard let value = WallpaperLuminance.averageLuminance(in: normalizedRect, of: image) else {
            return nil
        }
        if regionStorage.count >= capacity {
            regionStorage.removeAll(keepingCapacity: true)
        }
        regionStorage[key] = value
        return value
    }
}
