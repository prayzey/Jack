import SwiftUI

struct QuickNoteBackdropView: View {
    var body: some View {
        Color.clear
    }
}

struct QuickNoteCardBackground: View {
    let appearance: QuickNoteAppearance
    let cornerRadius: CGFloat

    private var style: QuickNoteStyle { appearance.style }
    private var wallpaperImage: NSImage? {
        appearance.backgroundWallpaper.loadImage(customFilename: appearance.customWallpaperFilename)
    }
    private var hasLoadedWallpaper: Bool {
        wallpaperImage != nil
    }

    var body: some View {
        ZStack {
            if let wallpaperImage {
                PositionedWallpaperImage(
                    nsImage: wallpaperImage,
                    offsetX: appearance.wallpaperOffsetX,
                    offsetY: appearance.wallpaperOffsetY
                )
            }

            if appearance.shouldUseGlassSurface(hasLoadedWallpaper: hasLoadedWallpaper) {
                VibrancyBackgroundView(
                    material: .hudWindow,
                    blendingMode: .behindWindow,
                    cornerRadius: cornerRadius
                )
            }

            if appearance.shouldRenderTemplateSurface(hasLoadedWallpaper: hasLoadedWallpaper) {
                let resolvedOpacity = appearance.resolvedSurfaceOpacity(hasLoadedWallpaper: hasLoadedWallpaper)
                // Skip drawing the surface entirely when fully transparent
                // — otherwise the rounded-rect still consumes a draw pass and
                // can wash out the wallpaper at the corners.
                if resolvedOpacity > 0.001 {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: style.cardGradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .opacity(resolvedOpacity)
                }
            }

            if appearance.shouldRenderMaterialOverlay(hasLoadedWallpaper: hasLoadedWallpaper) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(materialOverlayOpacity)
            }

            if appearance.paperType != .blank {
                SurfacePaperOverlay(
                    paperType: appearance.paperType,
                    color: paperOverlayColor
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .opacity(paperOverlayOpacity)
            }
        }
    }

    private var materialOverlayOpacity: Double {
        max(0.12, (1.0 - appearance.surfaceOpacity) * 0.9 + 0.16)
    }

    private var paperOverlayColor: Color {
        // When the wallpaper sits on top without a template surface, grid lines
        // lifted off a light image need a stronger tint than the style default.
        if appearance.usesWallpaperAsPrimarySurface(hasLoadedWallpaper: hasLoadedWallpaper) {
            return Color.white.opacity(0.22)
        }
        return style.gridColor
    }

    private var paperOverlayOpacity: Double {
        switch style {
        case .obsidian: return 0.5
        default: return 0.9
        }
    }
}

struct WorkspaceSurfaceBackground: View {
    let appearance: WorkspaceAppearance
    let cornerRadius: CGFloat

    var body: some View {
        let theme = appearance.backgroundTheme
        let solidOpacity = appearance.backgroundOpacity
        let wallpaper = appearance.backgroundWallpaper
        let wallpaperImage = wallpaper.loadImage(customFilename: appearance.customWallpaperFilename)

        Group {
            if theme == .custom {
                ZStack {
                    if let nsImage = wallpaperImage {
                        PositionedWallpaperImage(
                            nsImage: nsImage,
                            offsetX: appearance.wallpaperOffsetX,
                            offsetY: appearance.wallpaperOffsetY
                        )
                        Color.black.opacity(0.5)
                    }

                    GradientSpec(color1: "#4A2080", color2: "#206080", angle: 135)
                        .linearGradient
                        .opacity(wallpaperImage == nil ? solidOpacity : solidOpacity * 0.6)

                    RadialGradient(
                        colors: [Color.clear, Color.black.opacity(0.15 * solidOpacity)],
                        center: .bottomTrailing,
                        startRadius: 20,
                        endRadius: 500
                    )
                }
                .overlay(.ultraThinMaterial.opacity((1.0 - solidOpacity) * 0.4 + 0.1))
            } else if theme.usesNativeVibrancy {
                ZStack {
                    VibrancyBackgroundView(
                        material: .hudWindow,
                        blendingMode: .behindWindow,
                        cornerRadius: cornerRadius
                    )

                    if let nsImage = wallpaperImage {
                        PositionedWallpaperImage(
                            nsImage: nsImage,
                            offsetX: appearance.wallpaperOffsetX,
                            offsetY: appearance.wallpaperOffsetY
                        )
                        .opacity(0.15)
                    }

                    LinearGradient(
                        colors: theme.gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .opacity(0.25 * solidOpacity)
                }
            } else if theme.isImageOnly {
                ZStack {
                    if let nsImage = wallpaperImage {
                        PositionedWallpaperImage(
                            nsImage: nsImage,
                            offsetX: appearance.wallpaperOffsetX,
                            offsetY: appearance.wallpaperOffsetY
                        )
                    } else {
                        LinearGradient(
                            colors: theme.gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                }
            } else {
                let materialOpacity = (1.0 - solidOpacity) * 0.6 + 0.15 * theme.materialOpacityMultiplier

                ZStack {
                    if let nsImage = wallpaperImage {
                        PositionedWallpaperImage(
                            nsImage: nsImage,
                            offsetX: appearance.wallpaperOffsetX,
                            offsetY: appearance.wallpaperOffsetY
                        )

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
                    .opacity(wallpaperImage == nil ? solidOpacity : solidOpacity * 0.5)

                    RadialGradient(
                        colors: [theme.vignetteColor.opacity(0.3 * solidOpacity), Color.clear],
                        center: .bottomTrailing,
                        startRadius: 20,
                        endRadius: 500
                    )
                }
                .overlay(.ultraThinMaterial.opacity(materialOpacity))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct SurfacePaperOverlay: View {
    let paperType: QuickNotePaperType
    let color: Color

    var body: some View {
        switch paperType {
        case .blank:
            Color.clear
        case .lined:
            SurfaceLinedOverlay(color: color, spacing: 26)
        case .dotted:
            SurfaceDottedOverlay(color: color, spacing: 18)
        case .miniSquared:
            SurfaceGridOverlay(color: color, spacing: 14)
        case .squared:
            SurfaceGridOverlay(color: color, spacing: 26)
        }
    }
}

struct SurfaceLinedOverlay: View {
    let color: Color
    let spacing: CGFloat

    var body: some View {
        Canvas { context, size in
            var path = Path()
            stride(from: spacing, through: size.height, by: spacing).forEach { y in
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(color), lineWidth: 0.7)
        }
        .allowsHitTesting(false)
    }
}

struct SurfaceDottedOverlay: View {
    let color: Color
    let spacing: CGFloat

    var body: some View {
        Canvas { context, size in
            let radius: CGFloat = 0.9
            stride(from: spacing, through: size.height, by: spacing).forEach { y in
                stride(from: spacing, through: size.width, by: spacing).forEach { x in
                    let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(color))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct SurfaceGridOverlay: View {
    let color: Color
    let spacing: CGFloat

    var body: some View {
        Canvas { context, size in
            var path = Path()

            stride(from: spacing, through: size.width, by: spacing).forEach { x in
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }

            stride(from: spacing, through: size.height, by: spacing).forEach { y in
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }

            context.stroke(path, with: .color(color), lineWidth: 0.7)
        }
        .allowsHitTesting(false)
    }
}
