import Foundation

@MainActor
struct WallpaperOffsets: Equatable {
    let x: Double
    let y: Double

    static let centered = Self(x: 0.5, y: 0.5)

    static func clamped(x: Double, y: Double) -> Self {
        Self(x: clamp(x), y: clamp(y))
    }

    static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

/// Keeps high-frequency wallpaper preview updates separate from the main store
/// so slider drags do not invalidate every store-driven view on each frame.
@MainActor
final class WallpaperPreviewState: ObservableObject {
    @Published private(set) var liveOffsets: WallpaperOffsets?

    func update(x: Double, y: Double) {
        let next = WallpaperOffsets.clamped(x: x, y: y)
        guard liveOffsets != next else { return }
        liveOffsets = next
    }

    func resolved(using settings: AppSettings) -> WallpaperOffsets {
        liveOffsets ?? WallpaperOffsets(
            x: settings.wallpaperOffsetX,
            y: settings.wallpaperOffsetY
        )
    }

    func resolved(x: Double, y: Double) -> WallpaperOffsets {
        liveOffsets ?? WallpaperOffsets(x: x, y: y)
    }

    func commit(into settings: inout AppSettings) {
        let resolvedOffsets = resolved(using: settings)
        settings.wallpaperOffsetX = resolvedOffsets.x
        settings.wallpaperOffsetY = resolvedOffsets.y
        clear()
    }

    func clear() {
        guard liveOffsets != nil else { return }
        liveOffsets = nil
    }
}
