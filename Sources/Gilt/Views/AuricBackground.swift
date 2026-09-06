import AppKit
import SwiftUI

/// Reusable background modifier that renders the themed, layered background
/// shared across all view modes (tray, drawer, grid, radial).
struct AuricBackground: ViewModifier {
    @ObservedObject private var store: ClipboardStore
    @ObservedObject private var wallpaperPreview: WallpaperPreviewState
    var cornerRadius: CGFloat = 16

    init(store: ClipboardStore, cornerRadius: CGFloat = 16) {
        _store = ObservedObject(wrappedValue: store)
        _wallpaperPreview = ObservedObject(wrappedValue: store.wallpaperPreview)
        self.cornerRadius = cornerRadius
    }

    func body(content: Content) -> some View {
        content
            .background(backgroundView)
    }

    @ViewBuilder
    private var backgroundView: some View {
        let theme = store.settings.backgroundTheme
        let solidOpacity = store.liveBackgroundOpacity ?? store.settings.backgroundOpacity
        let wallpaper = store.settings.backgroundWallpaper
        let hasWallpaper = wallpaper != .none
        let wallpaperImage = hasWallpaper ? wallpaper.loadImage(customFilename: store.settings.customWallpaperFilename) : nil
        // INVARIANT: Wallpaper offsets are normalized to 0...1 for both axes.
        // Use liveWallpaper* during Settings drag for instant preview; persisted
        // settings are committed only when the interaction ends.
        let wallpaperOffsets = wallpaperPreview.resolved(using: store.settings)
        let wpOffsetX = wallpaperOffsets.x
        let wpOffsetY = wallpaperOffsets.y

        if theme == .custom {
            let customGrad = store.settings.customBackgroundGradient ?? GradientSpec(
                color1: "#4A2080", color2: "#206080", angle: 135
            )
            ZStack {
                if let nsImage = wallpaperImage {
                    PositionedWallpaperImage(nsImage: nsImage, offsetX: wpOffsetX, offsetY: wpOffsetY)
                    Color.black.opacity(0.5)
                }

                customGrad.linearGradient
                    .opacity(hasWallpaper ? solidOpacity * 0.6 : solidOpacity)

                RadialGradient(
                    colors: [Color.clear, Color.black.opacity(0.15 * solidOpacity)],
                    center: .bottomTrailing,
                    startRadius: 20,
                    endRadius: 400
                )
            }
            .overlay(.ultraThinMaterial.opacity((1.0 - solidOpacity) * 0.4 + 0.1))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        } else if theme.usesNativeVibrancy {
            ZStack {
                VibrancyBackgroundView(
                    material: .hudWindow,
                    blendingMode: .behindWindow,
                    cornerRadius: cornerRadius
                )

                if let nsImage = wallpaperImage {
                    PositionedWallpaperImage(nsImage: nsImage, offsetX: wpOffsetX, offsetY: wpOffsetY)
                        .opacity(0.15)
                }

                LinearGradient(
                    colors: theme.gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .opacity(0.25 * solidOpacity)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        } else if theme.isImageOnly {
            ZStack {
                if let nsImage = wallpaperImage {
                    PositionedWallpaperImage(nsImage: nsImage, offsetX: wpOffsetX, offsetY: wpOffsetY)
                } else {
                    LinearGradient(
                        colors: theme.gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            let materialOpacity = (1.0 - solidOpacity) * 0.6 + 0.15 * theme.materialOpacityMultiplier

            ZStack {
                if let nsImage = wallpaperImage {
                    PositionedWallpaperImage(nsImage: nsImage, offsetX: wpOffsetX, offsetY: wpOffsetY)

                    LinearGradient(
                        colors: theme.gradientColors.map { $0.opacity(0.7) },
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }

                LinearGradient(
                    colors: theme.gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .opacity(hasWallpaper ? solidOpacity * 0.5 : solidOpacity)

                RadialGradient(
                    colors: [theme.vignetteColor.opacity(0.3 * solidOpacity), Color.clear],
                    center: .bottomTrailing,
                    startRadius: 20,
                    endRadius: 400
                )
            }
            .overlay(.ultraThinMaterial.opacity(materialOpacity))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

/// Renders a wallpaper image with configurable pan offset.
/// Offset values are normalized 0.0–1.0 where 0.5 = centered.
struct PositionedWallpaperImage: View {
    let nsImage: NSImage
    let offsetX: Double
    let offsetY: Double

    var body: some View {
        GeometryReader { geo in
            let containerSize = geo.size
            let imageSize = nsImage.size
            guard imageSize.width > 0, imageSize.height > 0 else { return AnyView(EmptyView()) }
            let imageAspect = imageSize.width / imageSize.height
            let containerAspect = containerSize.width / containerSize.height

            let scale: CGFloat
            if imageAspect > containerAspect {
                scale = containerSize.height / imageSize.height
            } else {
                scale = containerSize.width / imageSize.width
            }
            let scaledW = imageSize.width * scale
            let scaledH = imageSize.height * scale
            let overflowX = max(scaledW - containerSize.width, 0)
            let overflowY = max(scaledH - containerSize.height, 0)

            let pixelX = (0.5 - offsetX) * overflowX
            let pixelY = (0.5 - offsetY) * overflowY

            return AnyView(
                Image(nsImage: nsImage)
                    .resizable()
                    .frame(width: scaledW, height: scaledH)
                    .offset(x: pixelX, y: pixelY)
            )
        }
        .clipped()
    }
}
