import SwiftUI

/// Shared visual identity for clip rendering across card, preview, and onboarding mockups.
enum ClipTypePresentation {
    static let customizableTypes: [ClipType] = [.text, .link, .image, .audio, .color]

    static func defaultTheme(for type: ClipType) -> ClipTypeTheme {
        switch type {
        case .text:
            return ClipTypeTheme(accentRaw: "#6685F5", headerRaw: "grad:#4D5CD1,#7A61E6,90")
        case .link:
            return ClipTypeTheme(accentRaw: "#4DC78C", headerRaw: "grad:#2E9E6B,#3DB885,90")
        case .image:
            return ClipTypeTheme(accentRaw: "#ED617A", headerRaw: "grad:#D14361,#E65C70,90")
        case .audio:
            return ClipTypeTheme(accentRaw: "#F59447", headerRaw: "grad:#E07A2E,#F08F3D,90")
        case .color:
            return ClipTypeTheme(accentRaw: "#33CCD1", headerRaw: "grad:#24ADB3,#38D1D6,90")
        }
    }

    /// Compact SF Symbol used for drag previews and drop ghosts.
    static func symbol(for type: ClipType) -> String {
        switch type {
        case .text: return "doc.text"
        case .link: return "link"
        case .image: return "photo"
        case .audio: return "waveform"
        case .color: return "paintpalette"
        }
    }

    static func label(for type: ClipType, linkPlatform: LinkPlatform? = nil) -> String {
        switch type {
        case .text:
            return L10n.string("clipType.text.label", default: "Text")
        case .link:
            return linkPlatform?.displayName ?? L10n.string("clipType.link.label", default: "Link")
        case .image:
            return L10n.string("clipType.image.label", default: "Image")
        case .audio:
            return L10n.string("clipType.audio.label", default: "Audio")
        case .color:
            return L10n.string("clipType.color.label", default: "Color")
        }
    }

    static func accentColor(
        for type: ClipType,
        settings: AppSettings? = nil,
        linkPlatform: LinkPlatform? = nil,
        parsedColor: (r: Double, g: Double, b: Double)? = nil
    ) -> Color {
        // Color clips should reflect their actual sampled color when available.
        if type == .color, let parsedColor {
            return Color(red: parsedColor.r, green: parsedColor.g, blue: parsedColor.b)
        }

        if let theme = settings?.clipTypeThemes[type.rawValue] {
            return theme.resolvedAccentColor.color
        }

        switch type {
        case .text:
            return Color(red: 0.40, green: 0.52, blue: 0.96)
        case .link:
            return linkPlatform?.accentSwiftUIColor ?? Color(red: 0.30, green: 0.78, blue: 0.55)
        case .image:
            return Color(red: 0.93, green: 0.38, blue: 0.48)
        case .audio:
            return Color(red: 0.96, green: 0.58, blue: 0.28)
        case .color:
            return Color(red: 0.20, green: 0.80, blue: 0.82)
        }
    }

    static func headerGradientColors(
        for type: ClipType,
        settings: AppSettings? = nil,
        linkPlatform: LinkPlatform? = nil,
        parsedColor: (r: Double, g: Double, b: Double)? = nil,
        colorHeaderUsesDarkText: Bool = false
    ) -> [Color] {
        // Color clips should reflect their actual sampled color when available.
        if type == .color, let parsedColor {
            let factor1 = colorHeaderUsesDarkText ? 0.92 : 0.65
            let factor2 = colorHeaderUsesDarkText ? 0.98 : 0.80
            return [
                Color(
                    red: parsedColor.r * factor1,
                    green: parsedColor.g * factor1,
                    blue: parsedColor.b * factor1
                ),
                Color(
                    red: parsedColor.r * factor2,
                    green: parsedColor.g * factor2,
                    blue: parsedColor.b * factor2
                ),
            ]
        }

        if let theme = settings?.clipTypeThemes[type.rawValue] {
            switch theme.headerStyle {
            case .gradient(let spec):
                return [Color(hex: spec.color1), Color(hex: spec.color2)]
            case .solid(let color):
                return [color.color, color.color]
            }
        }

        switch type {
        case .text:
            return [Color(red: 0.30, green: 0.36, blue: 0.82), Color(red: 0.48, green: 0.38, blue: 0.90)]
        case .link:
            if let linkPlatform {
                let start = linkPlatform.headerGradient.start
                let end = linkPlatform.headerGradient.end
                return [
                    Color(red: start.0, green: start.1, blue: start.2),
                    Color(red: end.0, green: end.1, blue: end.2),
                ]
            }
            return [Color(red: 0.18, green: 0.62, blue: 0.42), Color(red: 0.24, green: 0.72, blue: 0.52)]
        case .image:
            return [Color(red: 0.82, green: 0.26, blue: 0.38), Color(red: 0.90, green: 0.34, blue: 0.44)]
        case .audio:
            return [Color(red: 0.88, green: 0.48, blue: 0.18), Color(red: 0.94, green: 0.56, blue: 0.24)]
        case .color:
            return [Color(red: 0.14, green: 0.68, blue: 0.70), Color(red: 0.22, green: 0.82, blue: 0.84)]
        }
    }

    static func headerGradient(
        for type: ClipType,
        settings: AppSettings? = nil,
        linkPlatform: LinkPlatform? = nil,
        parsedColor: (r: Double, g: Double, b: Double)? = nil,
        colorHeaderUsesDarkText: Bool = false
    ) -> LinearGradient {
        if type != .color, let theme = settings?.clipTypeThemes[type.rawValue] {
            switch theme.headerStyle {
            case .gradient(let spec):
                return spec.linearGradient
            case .solid(let color):
                return LinearGradient(
                    colors: [color.color, color.color],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }

        return LinearGradient(
            colors: headerGradientColors(
                for: type,
                settings: settings,
                linkPlatform: linkPlatform,
                parsedColor: parsedColor,
                colorHeaderUsesDarkText: colorHeaderUsesDarkText
            ),
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    static func headerLabelColors(
        for type: ClipType,
        settings: AppSettings? = nil,
        parsedColor: (r: Double, g: Double, b: Double)? = nil,
        colorHeaderUsesDarkText: Bool = false
    ) -> (primary: Color, secondary: Color, tertiary: Color) {
        if type == .color, parsedColor != nil, colorHeaderUsesDarkText {
            return (
                primary: .black.opacity(0.85),
                secondary: .black.opacity(0.55),
                tertiary: .black.opacity(0.45)
            )
        }

        if let labelColor = settings?.clipTypeThemes[type.rawValue]?.resolvedLabelColor?.color {
            return (
                primary: labelColor,
                secondary: labelColor.opacity(0.78),
                tertiary: labelColor.opacity(0.66)
            )
        }

        return (
            primary: .white,
            secondary: .white.opacity(0.75),
            tertiary: .white.opacity(0.7)
        )
    }
}
