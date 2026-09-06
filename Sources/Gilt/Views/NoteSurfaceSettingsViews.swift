import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Live preview of the current Quick Note typography settings, shown above
/// the typography controls so users can judge the effect of each change.
struct QuickNoteTypographyPreviewCard: View {
    let appearance: QuickNoteAppearance

    private let sampleText = "The quick brown fox jumps over the lazy dog."
    private let sampleParagraph = "Type here. Sketch a thought, paste a link, or capture an idea before it slips."

    var body: some View {
        let nsFont = resolveQuickNoteFont(
            family: appearance.fontFamily,
            weight: appearance.fontWeight,
            pointSize: appearance.resolvedFontPointSize,
            customPostScriptName: appearance.customFontPostScriptName
        )

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "eye")
                    .font(.system(size: 10, weight: .semibold))
                Text(L10n.string("ui.live.preview", default: "LIVE PREVIEW"))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(1.1)
            }
            .foregroundStyle(SettingsTheme.textSecondary)

            VStack(alignment: .leading, spacing: max(0, appearance.paragraphSpacing)) {
                Text(sampleText)
                Text(sampleParagraph)
            }
            .font(Font(nsFont as CTFont))
            .kerning(CGFloat(appearance.letterSpacing))
            .lineSpacing(max(0, (appearance.lineHeightMultiplier - 1.0) * Double(nsFont.pointSize)))
            .foregroundStyle(SettingsTheme.textPrimary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: NSColor(white: 0.97, alpha: 1)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(SettingsTheme.border, lineWidth: 0.5)
            )
        }
        .padding(.bottom, 4)
    }
}

/// Grid of font family tiles. The last tile is the custom upload slot,
/// which doubles as the file-picker entry point.
struct QuickNoteFontFamilyGrid: View {
    @Binding var selection: QuickNoteFontFamily
    let customFontLabel: String
    let onPickCustomFont: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(QuickNoteFontFamily.allCases) { family in
                tile(for: family)
            }
        }
    }

    @ViewBuilder
    private func tile(for family: QuickNoteFontFamily) -> some View {
        let isSelected = selection == family
        let isCustom = family == .custom

        Button {
            if isCustom {
                onPickCustomFont()
            } else {
                selection = family
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(isCustom ? "Aa" : "Aa")
                    .font(previewFont(for: family))
                    .foregroundStyle(SettingsTheme.textPrimary)
                Text(displayLabel(for: family))
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? SettingsTheme.textPrimary : SettingsTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(SettingsTheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected ? SettingsTheme.gold : SettingsTheme.border,
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
            .shadow(color: isSelected ? SettingsTheme.gold.opacity(0.12) : .clear, radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func displayLabel(for family: QuickNoteFontFamily) -> String {
        if family == .custom, customFontLabel != "No custom font selected" {
            return customFontLabel
        }
        return family.label
    }

    private func previewFont(for family: QuickNoteFontFamily) -> Font {
        // Use Font (SwiftUI) instead of NSFont so SwiftUI handles caching during grid scrolls.
        switch family {
        case .system: return .system(size: 22, weight: .medium, design: .default)
        case .rounded: return .system(size: 22, weight: .medium, design: .rounded)
        case .serif: return .system(size: 22, weight: .medium, design: .serif)
        case .monospaced: return .system(size: 22, weight: .medium, design: .monospaced)
        case .atkinsonHyperlegible:
            if NSFont(name: "AtkinsonHyperlegible-Regular", size: 22) != nil {
                return .custom("AtkinsonHyperlegible-Regular", size: 22)
            }
            return .system(size: 22, weight: .medium, design: .default)
        case .instrumentSans:
            if NSFont(name: "InstrumentSans-Medium", size: 22) != nil {
                return .custom("InstrumentSans-Medium", size: 22)
            }
            return .system(size: 22, weight: .medium, design: .default)
        case .jetBrainsMono:
            if NSFont(name: "JetBrainsMono-Medium", size: 22) != nil {
                return .custom("JetBrainsMono-Medium", size: 22)
            }
            return .system(size: 22, weight: .medium, design: .monospaced)
        case .custom:
            return .system(size: 22, weight: .medium, design: .default)
        }
    }
}

struct QuickNoteStylePickerView: View {
    @Binding var selection: QuickNoteStyle

    private let columns = [
        GridItem(.adaptive(minimum: 120, maximum: 180), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(QuickNoteStyle.allCases) { style in
                styleTile(for: style)
            }
        }
        .padding(.vertical, 4)
    }

    private func styleTile(for style: QuickNoteStyle) -> some View {
        Button {
            selection = style
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    QuickNoteCardBackground(
                        appearance: QuickNoteAppearance(style: style),
                        cornerRadius: 18
                    )

                    if style == .obsidian {
                        RoundedRectangle(cornerRadius: 999, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.98, green: 0.42, blue: 0.28),
                                        Color(red: 0.78, green: 0.16, blue: 0.14)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 3.5)
                            .padding(.vertical, 12)
                            .padding(.trailing, 8)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 999, style: .continuous)
                            .fill(style.secondaryTextColor)
                            .frame(width: 42, height: 4)
                        RoundedRectangle(cornerRadius: 999, style: .continuous)
                            .fill(style.textColor.opacity(0.8))
                            .frame(width: 78, height: 4)
                        RoundedRectangle(cornerRadius: 999, style: .continuous)
                            .fill(style.textColor.opacity(0.42))
                            .frame(width: 54, height: 4)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 70)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            selection == style ? SettingsTheme.gold : style.cardBorderColor,
                            lineWidth: selection == style ? 2 : 1
                        )
                )
                .shadow(color: selection == style ? SettingsTheme.gold.opacity(0.16) : .clear, radius: 10, y: 6)

                Text(style.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SettingsTheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}

struct WorkspaceThemePickerView: View {
    @Binding var selection: BackgroundTheme
    var onSelectCustomTheme: (() -> Void)? = nil

    private let columns = [GridItem(.adaptive(minimum: 64, maximum: 96), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(BackgroundTheme.allCases, id: \.self) { theme in
                let isSelected = selection == theme

                Button {
                    if theme == .custom {
                        onSelectCustomTheme?()
                    }
                    selection = theme
                } label: {
                    VStack(spacing: 8) {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: theme.previewGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 40, height: 40)
                            .overlay(
                                Circle()
                                    .strokeBorder(isSelected ? SettingsTheme.gold : Color.white.opacity(0.12), lineWidth: isSelected ? 2.5 : 1)
                            )
                            .shadow(color: isSelected ? SettingsTheme.gold.opacity(0.28) : .clear, radius: 8, y: 4)

                        Text(theme.label)
                            .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? SettingsTheme.textPrimary : SettingsTheme.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

struct SurfaceWallpaperSettingsView: View {
    @Binding var wallpaper: BackgroundWallpaper
    @Binding var customFilename: String?
    @Binding var offsetX: Double
    @Binding var offsetY: Double
    @ObservedObject var previewState: WallpaperPreviewState
    let previewAspectRatio: CGFloat
    let previewTint: Color
    let onPickCustom: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(BackgroundWallpaper.allCases, id: \.self) { option in
                        let isSelected = wallpaper == option

                        Button {
                            if option == .custom {
                                onPickCustom()
                            } else {
                                wallpaper = option
                            }
                        } label: {
                            VStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(SettingsTheme.sidebarBackground)
                                    .frame(width: 80, height: 56)
                                    .overlay {
                                        wallpaperPreview(option)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(isSelected ? SettingsTheme.gold : Color.white.opacity(0.10), lineWidth: isSelected ? 2 : 1)
                                    )
                                    .shadow(color: isSelected ? SettingsTheme.gold.opacity(0.16) : .clear, radius: 10, y: 4)

                                Text(option.label)
                                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                                    .foregroundStyle(isSelected ? SettingsTheme.textPrimary : SettingsTheme.textSecondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }

            if wallpaper != .none {
                SurfaceWallpaperPositionPreview(
                    wallpaper: wallpaper,
                    customFilename: customFilename,
                    offsetX: $offsetX,
                    offsetY: $offsetY,
                    previewState: previewState,
                    aspectRatio: previewAspectRatio,
                    overlayTint: previewTint
                )
            }
        }
    }

    @ViewBuilder
    private func wallpaperPreview(_ option: BackgroundWallpaper) -> some View {
        switch option {
        case .none:
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.18))
                .overlay(
                    Image(systemName: "nosign")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SettingsTheme.textTertiary)
                )
        case .custom:
            if let nsImage = option.loadImage(customFilename: customFilename) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.12))
                    .overlay(
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(SettingsTheme.textTertiary)
                    )
            }
        default:
            if let nsImage = option.loadImage(customFilename: customFilename) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(previewTint.opacity(0.22))
            }
        }
    }
}

struct SurfaceWallpaperPositionPreview: View {
    let wallpaper: BackgroundWallpaper
    let customFilename: String?
    @Binding var offsetX: Double
    @Binding var offsetY: Double
    @ObservedObject var previewState: WallpaperPreviewState
    let aspectRatio: CGFloat
    let overlayTint: Color

    @State private var dragStartOffsetX: Double?
    @State private var dragStartOffsetY: Double?
    @State private var isDragging = false

    private var overlayOpacity: Double {
        if wallpaper == .custom {
            return isDragging ? 0.10 : 0.04
        }
        return isDragging ? 0.34 : 0.24
    }

    private var controlChromeOpacity: Double {
        wallpaper == .custom ? 0.22 : (isDragging ? 0.54 : 0.32)
    }

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geometry in
                let resolved = previewState.resolved(x: offsetX, y: offsetY)
                let previewImage = wallpaper.loadImage(customFilename: customFilename)
                let frameWidth = min(geometry.size.width, geometry.size.height * aspectRatio)
                let frameHeight = frameWidth / max(aspectRatio, 0.1)

                ZStack {
                    if let previewImage {
                        wallpaperImagePreview(
                            previewImage: previewImage,
                            frameWidth: frameWidth,
                            frameHeight: frameHeight,
                            offsetX: resolved.x,
                            offsetY: resolved.y
                        )
                    } else {
                        LinearGradient(
                            colors: [
                                overlayTint.opacity(0.34),
                                Color.black.opacity(0.24)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }

                    Color.black.opacity(overlayOpacity)

                    VStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.left")
                            RoundedRectangle(cornerRadius: 999, style: .continuous)
                                .frame(width: 28, height: 4)
                            Image(systemName: "arrow.right")
                        }
                        Image(systemName: "arrow.down")
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(isDragging ? 0.92 : 0.72))
                    .padding(.vertical, 7)
                    .padding(.horizontal, 12)
                    .background(Capsule().fill(.black.opacity(controlChromeOpacity)))
                    .animation(.easeInOut(duration: 0.14), value: isDragging)
                }
                .frame(width: frameWidth, height: frameHeight)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                )
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            updateDrag(
                                value: value,
                                previewImage: previewImage,
                                frameWidth: frameWidth,
                                frameHeight: frameHeight
                            )
                        }
                        .onEnded { _ in
                            commitPreviewOffsets()
                        }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: 170)

            axisSlider(
                title: "Horizontal",
                value: Binding(
                    get: { previewState.resolved(x: offsetX, y: offsetY).x },
                    set: { newValue in
                        let currentY = previewState.liveOffsets?.y ?? offsetY
                        previewState.update(x: newValue, y: currentY)
                    }
                ),
                trailingLabel: "Left/Right"
            )

            axisSlider(
                title: "Vertical",
                value: Binding(
                    get: { previewState.resolved(x: offsetX, y: offsetY).y },
                    set: { newValue in
                        let currentX = previewState.liveOffsets?.x ?? offsetX
                        previewState.update(x: currentX, y: newValue)
                    }
                ),
                trailingLabel: "Up/Down"
            )
        }
    }

    private func wallpaperImagePreview(
        previewImage: NSImage,
        frameWidth: CGFloat,
        frameHeight: CGFloat,
        offsetX: Double,
        offsetY: Double
    ) -> some View {
        let imageSize = previewImage.size
        let imageAspect = imageSize.width / max(imageSize.height, 1)
        let containerAspect = frameWidth / max(frameHeight, 1)
        let scale: CGFloat = imageAspect > containerAspect
            ? frameHeight / max(imageSize.height, 1)
            : frameWidth / max(imageSize.width, 1)
        let scaledWidth = imageSize.width * scale
        let scaledHeight = imageSize.height * scale
        let overflowX = max(scaledWidth - frameWidth, 0)
        let overflowY = max(scaledHeight - frameHeight, 0)

        return Image(nsImage: previewImage)
            .resizable()
            .frame(width: scaledWidth, height: scaledHeight)
            .offset(
                x: (0.5 - offsetX) * overflowX,
                y: (0.5 - offsetY) * overflowY
            )
    }

    private func updateDrag(
        value: DragGesture.Value,
        previewImage: NSImage?,
        frameWidth: CGFloat,
        frameHeight: CGFloat
    ) {
        if dragStartOffsetX == nil || dragStartOffsetY == nil {
            dragStartOffsetX = previewState.resolved(x: offsetX, y: offsetY).x
            dragStartOffsetY = previewState.resolved(x: offsetX, y: offsetY).y
            isDragging = true
        }

        guard let startX = dragStartOffsetX, let startY = dragStartOffsetY else { return }

        let overflow = overflowDistances(
            previewImage: previewImage,
            frameWidth: frameWidth,
            frameHeight: frameHeight
        )
        let fallbackX = Double(value.translation.width / max(frameWidth, 1)) * 0.4
        let fallbackY = Double(value.translation.height / max(frameHeight, 1)) * 0.4
        let deltaX = overflow.x > 0 ? Double(value.translation.width / overflow.x) : fallbackX
        let deltaY = overflow.y > 0 ? Double(value.translation.height / overflow.y) : fallbackY

        previewState.update(
            x: min(max(startX + deltaX, 0), 1),
            y: min(max(startY + deltaY, 0), 1)
        )
    }

    private func overflowDistances(
        previewImage: NSImage?,
        frameWidth: CGFloat,
        frameHeight: CGFloat
    ) -> (x: CGFloat, y: CGFloat) {
        guard let previewImage else { return (0, 0) }

        let imageSize = previewImage.size
        let imageAspect = imageSize.width / max(imageSize.height, 1)
        let containerAspect = frameWidth / max(frameHeight, 1)
        let scale: CGFloat = imageAspect > containerAspect
            ? frameHeight / max(imageSize.height, 1)
            : frameWidth / max(imageSize.width, 1)
        return (
            x: max(imageSize.width * scale - frameWidth, 0),
            y: max(imageSize.height * scale - frameHeight, 0)
        )
    }

    private func commitPreviewOffsets() {
        let resolved = previewState.resolved(x: offsetX, y: offsetY)
        offsetX = resolved.x
        offsetY = resolved.y
        previewState.clear()
        dragStartOffsetX = nil
        dragStartOffsetY = nil
        isDragging = false
    }

    private func axisSlider(title: String, value: Binding<Double>, trailingLabel: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)

            Slider(
                value: value,
                in: 0...1,
                onEditingChanged: { editing in
                    if !editing {
                        commitPreviewOffsets()
                    }
                }
            )
            .tint(SettingsTheme.gold)

            Text(trailingLabel)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .frame(width: 52, alignment: .trailing)
        }
    }
}
