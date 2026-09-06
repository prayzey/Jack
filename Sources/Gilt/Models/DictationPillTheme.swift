import SwiftUI

/// A complete color scheme for the dictation pill + caption surface.
///
/// Each theme is a *full look*, not just an accent — it controls the pill
/// background gradient, grid cell colors, caption background, caption text,
/// and accent dot. This lets users pick a theme that matches the app they
/// dictate into most often (dark editors vs light docs vs warm writing apps).
///
/// Mirrors the pattern used by `FolderColorToken` and `QuickNotePaperType`:
/// a small enumerated set of named, opinionated presets.
enum DictationPillTheme: String, Codable, CaseIterable, Identifiable {
    // Dark — neutral
    case obsidian
    case midnight
    case onyx
    case slate
    case graphite
    // Dark — warm
    case cocoa
    case ember
    case wine
    // Dark — accent
    case coral
    case rose
    case mauve
    case plum
    case sunset
    // Dark — cool
    case sapphire
    case cobalt
    case emerald
    case moss
    case teal
    // Light
    case aurora
    case champagne
    case linen
    case mist
    case sage
    case lavender

    var id: String { rawValue }

    /// Loose grouping used by the Settings picker so users scanning swatches
    /// see related options next to each other instead of a random colour mosaic.
    var group: ThemeGroup {
        switch self {
        case .obsidian, .midnight, .onyx, .slate, .graphite: return .darkNeutral
        case .cocoa, .ember, .wine: return .darkWarm
        case .coral, .rose, .mauve, .plum, .sunset: return .darkAccent
        case .sapphire, .cobalt, .emerald, .moss, .teal: return .darkCool
        case .aurora, .champagne, .linen, .mist, .sage, .lavender: return .light
        }
    }

    var displayName: String {
        switch self {
        case .obsidian:  return "Obsidian"
        case .midnight:  return "Midnight"
        case .onyx:      return "Onyx"
        case .slate:     return "Slate"
        case .cocoa:     return "Cocoa"
        case .ember:     return "Ember"
        case .wine:      return "Wine"
        case .coral:     return "Coral"
        case .rose:      return "Rose"
        case .mauve:     return "Mauve"
        case .plum:      return "Plum"
        case .sapphire:  return "Sapphire"
        case .cobalt:    return "Cobalt"
        case .emerald:   return "Emerald"
        case .moss:      return "Moss"
        case .aurora:    return "Aurora"
        case .champagne: return "Champagne"
        case .linen:     return "Linen"
        case .mist:      return "Mist"
        case .graphite:  return "Graphite"
        case .sunset:    return "Sunset"
        case .teal:      return "Teal"
        case .sage:      return "Sage"
        case .lavender:  return "Lavender"
        }
    }

    /// Compact one-line description for tooltips / accessibility.
    var tagline: String {
        switch self {
        case .obsidian:  return "Charcoal with warm gold cells"
        case .midnight:  return "Deepest night, silver cells"
        case .onyx:      return "Jet black with crisp white cells"
        case .slate:     return "Neutral gray, quietest option"
        case .cocoa:     return "Rich brown with warm cream cells"
        case .ember:     return "Burnt orange with cream cells"
        case .wine:      return "Deep burgundy with pale cells"
        case .coral:     return "Warm pink with ivory cells"
        case .rose:      return "Rose-pink with soft cream cells"
        case .mauve:     return "Plum purple with lavender cells"
        case .plum:      return "Deeper plum with violet cells"
        case .sapphire:  return "Deep blue with cool white cells"
        case .cobalt:    return "Vibrant cobalt with sky cells"
        case .emerald:   return "Forest green with pale cells"
        case .moss:      return "Olive sage with cream cells"
        case .aurora:    return "Off-white with aurora glow"
        case .champagne: return "Cream paper with sepia ink"
        case .linen:     return "Warm oat paper, soft brown ink"
        case .mist:      return "Cool gray-blue light surface"
        case .graphite:  return "Warm charcoal with soft amber cells"
        case .sunset:    return "Peach pink with golden cells"
        case .teal:      return "Deep teal with seafoam cells"
        case .sage:      return "Pale green paper with deep moss ink"
        case .lavender:  return "Soft lilac paper with violet ink"
        }
    }

    /// The full palette this theme expands into.
    var palette: DictationPillPalette {
        switch self {
        case .obsidian:  return .obsidian
        case .midnight:  return .midnight
        case .onyx:      return .onyx
        case .slate:     return .slate
        case .cocoa:     return .cocoa
        case .ember:     return .ember
        case .wine:      return .wine
        case .coral:     return .coral
        case .rose:      return .rose
        case .mauve:     return .mauve
        case .plum:      return .plum
        case .sapphire:  return .sapphire
        case .cobalt:    return .cobalt
        case .emerald:   return .emerald
        case .moss:      return .moss
        case .aurora:    return .aurora
        case .champagne: return .champagne
        case .linen:     return .linen
        case .mist:      return .mist
        case .graphite:  return .graphite
        case .sunset:    return .sunset
        case .teal:      return .teal
        case .sage:      return .sage
        case .lavender:  return .lavender
        }
    }
}

/// Used by the Settings picker to render group headings between swatches.
/// Keeps the picker scannable as we add more colours.
enum ThemeGroup: String, CaseIterable, Identifiable {
    case darkNeutral
    case darkWarm
    case darkAccent
    case darkCool
    case light

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .darkNeutral: return "Dark · Neutral"
        case .darkWarm:    return "Dark · Warm"
        case .darkAccent:  return "Dark · Accent"
        case .darkCool:    return "Dark · Cool"
        case .light:       return "Light"
        }
    }
}

extension DictationPillTheme {
    /// All themes ordered by group, so the picker renders a consistent layout
    /// regardless of `allCases` declaration order changes.
    static var orderedForPicker: [DictationPillTheme] {
        ThemeGroup.allCases.flatMap { group in
            allCases.filter { $0.group == group }
        }
    }
}

// MARK: - Palette

/// The concrete colors a theme expands into. Kept as a flat struct of `Color`s
/// so views can pull whichever fields they need without going through the
/// theme enum every time.
struct DictationPillPalette: Equatable {
    /// Whether this is a dark-shelled theme. Drives cancel-button styling and
    /// any auto-contrast decisions in the view.
    let isDarkShell: Bool

    // — Pill surface —
    let pillTop: Color
    let pillBottom: Color
    let pillBorder: Color
    let pillShadow: Color

    // — Grid cells —
    let gridLit: Color
    let gridDim: Color
    /// Glow halo color around lit cells. Use with low opacity; views apply
    /// it as a `shadow(radius:)`. Set to `.clear` to disable the glow.
    let gridGlow: Color

    // — Caption box —
    let captionTop: Color
    let captionBottom: Color
    let captionBorder: Color
    let captionText: Color

    // — Label + accents (used during transcribing/polishing/etc) —
    let labelColor: Color
    let dotColor: Color

    // — Cancel button —
    let cancelBg: Color
    let cancelIcon: Color

    // — Optional decorative aura under the pill (conic-gradient bloom) —
    let auraColor: Color
}

extension DictationPillPalette {
    // MARK: - Dark shell themes

    static let obsidian = DictationPillPalette(
        isDarkShell: true,
        pillTop: Color(red: 0.086, green: 0.086, blue: 0.118),
        pillBottom: Color(red: 0.055, green: 0.055, blue: 0.082),
        pillBorder: Color(red: 0.788, green: 0.663, blue: 0.431, opacity: 0.20),
        pillShadow: Color.black.opacity(0.45),
        gridLit: Color(red: 0.953, green: 0.890, blue: 0.761),
        gridDim: Color(red: 0.953, green: 0.890, blue: 0.761, opacity: 0.10),
        gridGlow: Color(red: 0.953, green: 0.890, blue: 0.761, opacity: 0.55),
        captionTop: Color(red: 0.086, green: 0.086, blue: 0.118),
        captionBottom: Color(red: 0.055, green: 0.055, blue: 0.082),
        captionBorder: Color(red: 0.788, green: 0.663, blue: 0.431, opacity: 0.12),
        captionText: Color(red: 0.894, green: 0.863, blue: 0.780),
        labelColor: Color(red: 0.953, green: 0.890, blue: 0.761),
        dotColor: Color(red: 0.953, green: 0.890, blue: 0.761),
        cancelBg: Color.white.opacity(0.08),
        cancelIcon: Color.white.opacity(0.55),
        auraColor: Color(red: 0.788, green: 0.663, blue: 0.431, opacity: 0.18)
    )

    static let midnight = DictationPillPalette(
        isDarkShell: true,
        pillTop: Color(red: 0.043, green: 0.047, blue: 0.078),
        pillBottom: Color(red: 0.020, green: 0.024, blue: 0.047),
        pillBorder: Color.white.opacity(0.10),
        pillShadow: Color.black.opacity(0.55),
        gridLit: Color(red: 0.929, green: 0.945, blue: 0.973),
        gridDim: Color.white.opacity(0.10),
        gridGlow: Color(red: 0.65, green: 0.78, blue: 0.95, opacity: 0.55),
        captionTop: Color(red: 0.043, green: 0.047, blue: 0.078),
        captionBottom: Color(red: 0.020, green: 0.024, blue: 0.047),
        captionBorder: Color.white.opacity(0.06),
        captionText: Color(red: 0.875, green: 0.890, blue: 0.949),
        labelColor: Color(red: 0.929, green: 0.945, blue: 0.973),
        dotColor: Color(red: 0.70, green: 0.82, blue: 0.98),
        cancelBg: Color.white.opacity(0.08),
        cancelIcon: Color.white.opacity(0.55),
        auraColor: Color(red: 0.40, green: 0.55, blue: 0.95, opacity: 0.18)
    )

    static let coral = DictationPillPalette(
        isDarkShell: true,
        pillTop: Color(red: 0.369, green: 0.161, blue: 0.196),
        pillBottom: Color(red: 0.227, green: 0.094, blue: 0.125),
        pillBorder: Color(red: 1.00, green: 0.55, blue: 0.58, opacity: 0.28),
        pillShadow: Color(red: 0.40, green: 0.10, blue: 0.12, opacity: 0.45),
        gridLit: Color(red: 1.00, green: 0.835, blue: 0.847),
        gridDim: Color(red: 1.00, green: 0.835, blue: 0.847, opacity: 0.12),
        gridGlow: Color(red: 1.00, green: 0.55, blue: 0.58, opacity: 0.55),
        captionTop: Color(red: 0.369, green: 0.161, blue: 0.196),
        captionBottom: Color(red: 0.227, green: 0.094, blue: 0.125),
        captionBorder: Color(red: 1.00, green: 0.55, blue: 0.58, opacity: 0.16),
        captionText: Color(red: 0.984, green: 0.894, blue: 0.902),
        labelColor: Color(red: 1.00, green: 0.835, blue: 0.847),
        dotColor: Color(red: 1.00, green: 0.55, blue: 0.58),
        cancelBg: Color.white.opacity(0.08),
        cancelIcon: Color.white.opacity(0.60),
        auraColor: Color(red: 1.00, green: 0.45, blue: 0.50, opacity: 0.22)
    )

    static let sapphire = DictationPillPalette(
        isDarkShell: true,
        pillTop: Color(red: 0.102, green: 0.173, blue: 0.310),
        pillBottom: Color(red: 0.059, green: 0.102, blue: 0.196),
        pillBorder: Color(red: 0.549, green: 0.706, blue: 1.00, opacity: 0.25),
        pillShadow: Color(red: 0.05, green: 0.08, blue: 0.20, opacity: 0.55),
        gridLit: Color(red: 0.784, green: 0.871, blue: 0.941),
        gridDim: Color(red: 0.784, green: 0.871, blue: 0.941, opacity: 0.12),
        gridGlow: Color(red: 0.55, green: 0.71, blue: 1.00, opacity: 0.55),
        captionTop: Color(red: 0.102, green: 0.173, blue: 0.310),
        captionBottom: Color(red: 0.059, green: 0.102, blue: 0.196),
        captionBorder: Color(red: 0.549, green: 0.706, blue: 1.00, opacity: 0.14),
        captionText: Color(red: 0.847, green: 0.898, blue: 0.961),
        labelColor: Color(red: 0.784, green: 0.871, blue: 0.941),
        dotColor: Color(red: 0.431, green: 0.639, blue: 0.941),
        cancelBg: Color.white.opacity(0.08),
        cancelIcon: Color.white.opacity(0.55),
        auraColor: Color(red: 0.43, green: 0.64, blue: 0.94, opacity: 0.25)
    )

    static let emerald = DictationPillPalette(
        isDarkShell: true,
        pillTop: Color(red: 0.114, green: 0.243, blue: 0.173),
        pillBottom: Color(red: 0.063, green: 0.149, blue: 0.098),
        pillBorder: Color(red: 0.549, green: 0.863, blue: 0.706, opacity: 0.25),
        pillShadow: Color(red: 0.04, green: 0.12, blue: 0.08, opacity: 0.55),
        gridLit: Color(red: 0.784, green: 0.910, blue: 0.831),
        gridDim: Color(red: 0.784, green: 0.910, blue: 0.831, opacity: 0.12),
        gridGlow: Color(red: 0.45, green: 0.85, blue: 0.65, opacity: 0.55),
        captionTop: Color(red: 0.114, green: 0.243, blue: 0.173),
        captionBottom: Color(red: 0.063, green: 0.149, blue: 0.098),
        captionBorder: Color(red: 0.549, green: 0.863, blue: 0.706, opacity: 0.14),
        captionText: Color(red: 0.839, green: 0.918, blue: 0.875),
        labelColor: Color(red: 0.784, green: 0.910, blue: 0.831),
        dotColor: Color(red: 0.373, green: 0.769, blue: 0.533),
        cancelBg: Color.white.opacity(0.08),
        cancelIcon: Color.white.opacity(0.55),
        auraColor: Color(red: 0.37, green: 0.77, blue: 0.53, opacity: 0.22)
    )

    static let mauve = DictationPillPalette(
        isDarkShell: true,
        pillTop: Color(red: 0.180, green: 0.133, blue: 0.251),
        pillBottom: Color(red: 0.110, green: 0.078, blue: 0.157),
        pillBorder: Color(red: 0.784, green: 0.627, blue: 1.00, opacity: 0.25),
        pillShadow: Color(red: 0.12, green: 0.08, blue: 0.22, opacity: 0.55),
        gridLit: Color(red: 0.867, green: 0.816, blue: 0.961),
        gridDim: Color(red: 0.867, green: 0.816, blue: 0.961, opacity: 0.12),
        gridGlow: Color(red: 0.74, green: 0.58, blue: 1.00, opacity: 0.55),
        captionTop: Color(red: 0.180, green: 0.133, blue: 0.251),
        captionBottom: Color(red: 0.110, green: 0.078, blue: 0.157),
        captionBorder: Color(red: 0.784, green: 0.627, blue: 1.00, opacity: 0.14),
        captionText: Color(red: 0.878, green: 0.831, blue: 0.941),
        labelColor: Color(red: 0.867, green: 0.816, blue: 0.961),
        dotColor: Color(red: 0.690, green: 0.561, blue: 0.933),
        cancelBg: Color.white.opacity(0.08),
        cancelIcon: Color.white.opacity(0.55),
        auraColor: Color(red: 0.69, green: 0.56, blue: 0.93, opacity: 0.25)
    )

    static let slate = DictationPillPalette(
        isDarkShell: true,
        pillTop: Color(red: 0.165, green: 0.173, blue: 0.200),
        pillBottom: Color(red: 0.102, green: 0.110, blue: 0.133),
        pillBorder: Color.white.opacity(0.12),
        pillShadow: Color.black.opacity(0.40),
        gridLit: Color(red: 0.945, green: 0.937, blue: 0.922),
        gridDim: Color(red: 0.945, green: 0.937, blue: 0.922, opacity: 0.12),
        gridGlow: Color(red: 0.945, green: 0.937, blue: 0.922, opacity: 0.35),
        captionTop: Color(red: 0.165, green: 0.173, blue: 0.200),
        captionBottom: Color(red: 0.102, green: 0.110, blue: 0.133),
        captionBorder: Color.white.opacity(0.07),
        captionText: Color(red: 0.847, green: 0.839, blue: 0.824),
        labelColor: Color(red: 0.945, green: 0.937, blue: 0.922),
        dotColor: Color(red: 0.847, green: 0.839, blue: 0.824),
        cancelBg: Color.white.opacity(0.08),
        cancelIcon: Color.white.opacity(0.55),
        auraColor: Color.white.opacity(0.08)
    )

    static let ember = DictationPillPalette(
        isDarkShell: true,
        pillTop: Color(red: 0.341, green: 0.184, blue: 0.094),
        pillBottom: Color(red: 0.208, green: 0.110, blue: 0.055),
        pillBorder: Color(red: 1.00, green: 0.682, blue: 0.392, opacity: 0.28),
        pillShadow: Color(red: 0.30, green: 0.10, blue: 0.04, opacity: 0.50),
        gridLit: Color(red: 1.00, green: 0.918, blue: 0.831),
        gridDim: Color(red: 1.00, green: 0.918, blue: 0.831, opacity: 0.12),
        gridGlow: Color(red: 1.00, green: 0.62, blue: 0.30, opacity: 0.55),
        captionTop: Color(red: 0.341, green: 0.184, blue: 0.094),
        captionBottom: Color(red: 0.208, green: 0.110, blue: 0.055),
        captionBorder: Color(red: 1.00, green: 0.682, blue: 0.392, opacity: 0.16),
        captionText: Color(red: 0.984, green: 0.925, blue: 0.851),
        labelColor: Color(red: 1.00, green: 0.918, blue: 0.831),
        dotColor: Color(red: 1.00, green: 0.62, blue: 0.30),
        cancelBg: Color.white.opacity(0.08),
        cancelIcon: Color.white.opacity(0.60),
        auraColor: Color(red: 1.00, green: 0.55, blue: 0.25, opacity: 0.24)
    )

    // MARK: - Light shell themes

    static let aurora = DictationPillPalette(
        isDarkShell: false,
        pillTop: Color.white.opacity(0.96),
        pillBottom: Color.white.opacity(0.92),
        pillBorder: Color.black.opacity(0.06),
        pillShadow: Color.black.opacity(0.18),
        gridLit: Color(red: 0.075, green: 0.075, blue: 0.098),
        gridDim: Color(red: 0.075, green: 0.075, blue: 0.098, opacity: 0.10),
        gridGlow: Color(red: 0.20, green: 0.20, blue: 0.24, opacity: 0.25),
        captionTop: Color.white.opacity(0.94),
        captionBottom: Color.white.opacity(0.90),
        captionBorder: Color.black.opacity(0.06),
        captionText: Color(red: 0.086, green: 0.075, blue: 0.094),
        labelColor: Color(red: 0.075, green: 0.075, blue: 0.098),
        dotColor: Color(red: 0.788, green: 0.663, blue: 0.431),
        cancelBg: Color.black.opacity(0.06),
        cancelIcon: Color.black.opacity(0.45),
        auraColor: Color(red: 0.788, green: 0.663, blue: 0.431, opacity: 0.18)
    )

    // — NEW: Onyx — pure black with crisp white cells (max contrast) —
    static let onyx = DictationPillPalette(
        isDarkShell: true,
        pillTop: Color(red: 0.020, green: 0.020, blue: 0.024),
        pillBottom: Color.black,
        pillBorder: Color.white.opacity(0.14),
        pillShadow: Color.black.opacity(0.65),
        gridLit: Color(red: 0.984, green: 0.984, blue: 0.984),
        gridDim: Color.white.opacity(0.10),
        gridGlow: Color.white.opacity(0.55),
        captionTop: Color(red: 0.020, green: 0.020, blue: 0.024),
        captionBottom: Color.black,
        captionBorder: Color.white.opacity(0.08),
        captionText: Color(red: 0.92, green: 0.92, blue: 0.92),
        labelColor: Color.white,
        dotColor: Color.white,
        cancelBg: Color.white.opacity(0.10),
        cancelIcon: Color.white.opacity(0.60),
        auraColor: Color.white.opacity(0.05)
    )

    // — NEW: Cocoa — warm brown —
    static let cocoa = DictationPillPalette(
        isDarkShell: true,
        pillTop: Color(red: 0.243, green: 0.169, blue: 0.118),
        pillBottom: Color(red: 0.145, green: 0.094, blue: 0.063),
        pillBorder: Color(red: 0.769, green: 0.604, blue: 0.439, opacity: 0.25),
        pillShadow: Color(red: 0.25, green: 0.15, blue: 0.06, opacity: 0.50),
        gridLit: Color(red: 0.965, green: 0.890, blue: 0.804),
        gridDim: Color(red: 0.965, green: 0.890, blue: 0.804, opacity: 0.12),
        gridGlow: Color(red: 0.91, green: 0.71, blue: 0.50, opacity: 0.55),
        captionTop: Color(red: 0.243, green: 0.169, blue: 0.118),
        captionBottom: Color(red: 0.145, green: 0.094, blue: 0.063),
        captionBorder: Color(red: 0.769, green: 0.604, blue: 0.439, opacity: 0.14),
        captionText: Color(red: 0.949, green: 0.890, blue: 0.812),
        labelColor: Color(red: 0.965, green: 0.890, blue: 0.804),
        dotColor: Color(red: 0.91, green: 0.71, blue: 0.50),
        cancelBg: Color.white.opacity(0.08),
        cancelIcon: Color.white.opacity(0.60),
        auraColor: Color(red: 0.91, green: 0.66, blue: 0.40, opacity: 0.22)
    )

    // — NEW: Wine — deep burgundy —
    static let wine = DictationPillPalette(
        isDarkShell: true,
        pillTop: Color(red: 0.243, green: 0.071, blue: 0.114),
        pillBottom: Color(red: 0.149, green: 0.039, blue: 0.067),
        pillBorder: Color(red: 0.847, green: 0.490, blue: 0.553, opacity: 0.25),
        pillShadow: Color(red: 0.20, green: 0.04, blue: 0.08, opacity: 0.55),
        gridLit: Color(red: 0.984, green: 0.882, blue: 0.890),
        gridDim: Color(red: 0.984, green: 0.882, blue: 0.890, opacity: 0.12),
        gridGlow: Color(red: 0.96, green: 0.55, blue: 0.62, opacity: 0.55),
        captionTop: Color(red: 0.243, green: 0.071, blue: 0.114),
        captionBottom: Color(red: 0.149, green: 0.039, blue: 0.067),
        captionBorder: Color(red: 0.847, green: 0.490, blue: 0.553, opacity: 0.14),
        captionText: Color(red: 0.973, green: 0.890, blue: 0.902),
        labelColor: Color(red: 0.984, green: 0.882, blue: 0.890),
        dotColor: Color(red: 0.929, green: 0.404, blue: 0.502),
        cancelBg: Color.white.opacity(0.08),
        cancelIcon: Color.white.opacity(0.60),
        auraColor: Color(red: 0.93, green: 0.40, blue: 0.50, opacity: 0.20)
    )

    // — NEW: Rose — rose pink (softer than Coral) —
    static let rose = DictationPillPalette(
        isDarkShell: true,
        pillTop: Color(red: 0.290, green: 0.176, blue: 0.224),
        pillBottom: Color(red: 0.180, green: 0.106, blue: 0.141),
        pillBorder: Color(red: 1.00, green: 0.690, blue: 0.733, opacity: 0.28),
        pillShadow: Color(red: 0.30, green: 0.10, blue: 0.15, opacity: 0.50),
        gridLit: Color(red: 0.992, green: 0.890, blue: 0.910),
        gridDim: Color(red: 0.992, green: 0.890, blue: 0.910, opacity: 0.12),
        gridGlow: Color(red: 1.00, green: 0.69, blue: 0.73, opacity: 0.55),
        captionTop: Color(red: 0.290, green: 0.176, blue: 0.224),
        captionBottom: Color(red: 0.180, green: 0.106, blue: 0.141),
        captionBorder: Color(red: 1.00, green: 0.690, blue: 0.733, opacity: 0.14),
        captionText: Color(red: 0.980, green: 0.910, blue: 0.929),
        labelColor: Color(red: 0.992, green: 0.890, blue: 0.910),
        dotColor: Color(red: 1.00, green: 0.62, blue: 0.71),
        cancelBg: Color.white.opacity(0.08),
        cancelIcon: Color.white.opacity(0.60),
        auraColor: Color(red: 1.00, green: 0.62, blue: 0.71, opacity: 0.22)
    )

    // — NEW: Plum — deeper purple than Mauve —
    static let plum = DictationPillPalette(
        isDarkShell: true,
        pillTop: Color(red: 0.149, green: 0.090, blue: 0.184),
        pillBottom: Color(red: 0.082, green: 0.043, blue: 0.106),
        pillBorder: Color(red: 0.659, green: 0.439, blue: 0.882, opacity: 0.25),
        pillShadow: Color(red: 0.10, green: 0.04, blue: 0.20, opacity: 0.55),
        gridLit: Color(red: 0.918, green: 0.871, blue: 0.984),
        gridDim: Color(red: 0.918, green: 0.871, blue: 0.984, opacity: 0.12),
        gridGlow: Color(red: 0.66, green: 0.44, blue: 0.88, opacity: 0.55),
        captionTop: Color(red: 0.149, green: 0.090, blue: 0.184),
        captionBottom: Color(red: 0.082, green: 0.043, blue: 0.106),
        captionBorder: Color(red: 0.659, green: 0.439, blue: 0.882, opacity: 0.14),
        captionText: Color(red: 0.918, green: 0.871, blue: 0.949),
        labelColor: Color(red: 0.918, green: 0.871, blue: 0.984),
        dotColor: Color(red: 0.624, green: 0.420, blue: 0.851),
        cancelBg: Color.white.opacity(0.08),
        cancelIcon: Color.white.opacity(0.55),
        auraColor: Color(red: 0.62, green: 0.42, blue: 0.85, opacity: 0.25)
    )

    // — NEW: Cobalt — vibrant electric blue —
    static let cobalt = DictationPillPalette(
        isDarkShell: true,
        pillTop: Color(red: 0.071, green: 0.137, blue: 0.412),
        pillBottom: Color(red: 0.039, green: 0.078, blue: 0.275),
        pillBorder: Color(red: 0.439, green: 0.624, blue: 1.00, opacity: 0.30),
        pillShadow: Color(red: 0.02, green: 0.05, blue: 0.25, opacity: 0.55),
        gridLit: Color(red: 0.882, green: 0.937, blue: 1.00),
        gridDim: Color(red: 0.882, green: 0.937, blue: 1.00, opacity: 0.12),
        gridGlow: Color(red: 0.39, green: 0.58, blue: 1.00, opacity: 0.60),
        captionTop: Color(red: 0.071, green: 0.137, blue: 0.412),
        captionBottom: Color(red: 0.039, green: 0.078, blue: 0.275),
        captionBorder: Color(red: 0.439, green: 0.624, blue: 1.00, opacity: 0.16),
        captionText: Color(red: 0.882, green: 0.918, blue: 0.984),
        labelColor: Color(red: 0.882, green: 0.937, blue: 1.00),
        dotColor: Color(red: 0.353, green: 0.553, blue: 1.00),
        cancelBg: Color.white.opacity(0.08),
        cancelIcon: Color.white.opacity(0.55),
        auraColor: Color(red: 0.35, green: 0.55, blue: 1.00, opacity: 0.30)
    )

    // — NEW: Moss — olive sage green —
    static let moss = DictationPillPalette(
        isDarkShell: true,
        pillTop: Color(red: 0.180, green: 0.212, blue: 0.118),
        pillBottom: Color(red: 0.106, green: 0.133, blue: 0.067),
        pillBorder: Color(red: 0.722, green: 0.792, blue: 0.490, opacity: 0.25),
        pillShadow: Color(red: 0.08, green: 0.10, blue: 0.04, opacity: 0.55),
        gridLit: Color(red: 0.937, green: 0.953, blue: 0.847),
        gridDim: Color(red: 0.937, green: 0.953, blue: 0.847, opacity: 0.12),
        gridGlow: Color(red: 0.72, green: 0.79, blue: 0.49, opacity: 0.55),
        captionTop: Color(red: 0.180, green: 0.212, blue: 0.118),
        captionBottom: Color(red: 0.106, green: 0.133, blue: 0.067),
        captionBorder: Color(red: 0.722, green: 0.792, blue: 0.490, opacity: 0.14),
        captionText: Color(red: 0.929, green: 0.937, blue: 0.871),
        labelColor: Color(red: 0.937, green: 0.953, blue: 0.847),
        dotColor: Color(red: 0.682, green: 0.769, blue: 0.439),
        cancelBg: Color.white.opacity(0.08),
        cancelIcon: Color.white.opacity(0.55),
        auraColor: Color(red: 0.68, green: 0.77, blue: 0.44, opacity: 0.20)
    )

    static let champagne = DictationPillPalette(
        isDarkShell: false,
        pillTop: Color(red: 0.984, green: 0.953, blue: 0.898),
        pillBottom: Color(red: 0.945, green: 0.894, blue: 0.800),
        pillBorder: Color(red: 0.706, green: 0.549, blue: 0.314, opacity: 0.22),
        pillShadow: Color(red: 0.40, green: 0.30, blue: 0.10, opacity: 0.25),
        gridLit: Color(red: 0.353, green: 0.263, blue: 0.129),
        gridDim: Color(red: 0.353, green: 0.263, blue: 0.129, opacity: 0.14),
        gridGlow: Color(red: 0.55, green: 0.40, blue: 0.18, opacity: 0.30),
        captionTop: Color(red: 0.984, green: 0.953, blue: 0.898),
        captionBottom: Color(red: 0.953, green: 0.902, blue: 0.812),
        captionBorder: Color(red: 0.706, green: 0.549, blue: 0.314, opacity: 0.16),
        captionText: Color(red: 0.227, green: 0.173, blue: 0.078),
        labelColor: Color(red: 0.353, green: 0.263, blue: 0.129),
        dotColor: Color(red: 0.541, green: 0.416, blue: 0.196),
        cancelBg: Color.black.opacity(0.06),
        cancelIcon: Color.black.opacity(0.50),
        auraColor: Color(red: 1.00, green: 0.918, blue: 0.784, opacity: 0.50)
    )

    // — NEW: Linen — oat/beige paper, softer than Champagne —
    static let linen = DictationPillPalette(
        isDarkShell: false,
        pillTop: Color(red: 0.961, green: 0.937, blue: 0.886),
        pillBottom: Color(red: 0.918, green: 0.882, blue: 0.808),
        pillBorder: Color(red: 0.451, green: 0.357, blue: 0.220, opacity: 0.18),
        pillShadow: Color(red: 0.30, green: 0.22, blue: 0.10, opacity: 0.22),
        gridLit: Color(red: 0.251, green: 0.196, blue: 0.114),
        gridDim: Color(red: 0.251, green: 0.196, blue: 0.114, opacity: 0.14),
        gridGlow: Color(red: 0.45, green: 0.35, blue: 0.20, opacity: 0.25),
        captionTop: Color(red: 0.961, green: 0.937, blue: 0.886),
        captionBottom: Color(red: 0.929, green: 0.898, blue: 0.831),
        captionBorder: Color(red: 0.451, green: 0.357, blue: 0.220, opacity: 0.14),
        captionText: Color(red: 0.176, green: 0.137, blue: 0.071),
        labelColor: Color(red: 0.251, green: 0.196, blue: 0.114),
        dotColor: Color(red: 0.451, green: 0.357, blue: 0.220),
        cancelBg: Color.black.opacity(0.05),
        cancelIcon: Color.black.opacity(0.50),
        auraColor: Color(red: 0.95, green: 0.86, blue: 0.70, opacity: 0.45)
    )

    // — NEW: Graphite — warm-toned dark neutral, softer than Onyx —
    static let graphite = DictationPillPalette(
        isDarkShell: true,
        pillTop: Color(red: 0.137, green: 0.129, blue: 0.122),
        pillBottom: Color(red: 0.078, green: 0.071, blue: 0.067),
        pillBorder: Color(red: 0.918, green: 0.792, blue: 0.580, opacity: 0.18),
        pillShadow: Color.black.opacity(0.50),
        gridLit: Color(red: 0.973, green: 0.918, blue: 0.812),
        gridDim: Color(red: 0.973, green: 0.918, blue: 0.812, opacity: 0.10),
        gridGlow: Color(red: 0.92, green: 0.79, blue: 0.58, opacity: 0.40),
        captionTop: Color(red: 0.137, green: 0.129, blue: 0.122),
        captionBottom: Color(red: 0.078, green: 0.071, blue: 0.067),
        captionBorder: Color(red: 0.918, green: 0.792, blue: 0.580, opacity: 0.10),
        captionText: Color(red: 0.918, green: 0.890, blue: 0.851),
        labelColor: Color(red: 0.973, green: 0.918, blue: 0.812),
        dotColor: Color(red: 0.918, green: 0.792, blue: 0.580),
        cancelBg: Color.white.opacity(0.08),
        cancelIcon: Color.white.opacity(0.55),
        auraColor: Color(red: 0.92, green: 0.79, blue: 0.58, opacity: 0.14)
    )

    // — NEW: Sunset — peach/coral with golden cells —
    static let sunset = DictationPillPalette(
        isDarkShell: true,
        pillTop: Color(red: 0.388, green: 0.196, blue: 0.169),
        pillBottom: Color(red: 0.231, green: 0.110, blue: 0.094),
        pillBorder: Color(red: 1.00, green: 0.706, blue: 0.486, opacity: 0.30),
        pillShadow: Color(red: 0.35, green: 0.12, blue: 0.08, opacity: 0.50),
        gridLit: Color(red: 1.00, green: 0.886, blue: 0.741),
        gridDim: Color(red: 1.00, green: 0.886, blue: 0.741, opacity: 0.12),
        gridGlow: Color(red: 1.00, green: 0.65, blue: 0.40, opacity: 0.60),
        captionTop: Color(red: 0.388, green: 0.196, blue: 0.169),
        captionBottom: Color(red: 0.231, green: 0.110, blue: 0.094),
        captionBorder: Color(red: 1.00, green: 0.706, blue: 0.486, opacity: 0.16),
        captionText: Color(red: 0.992, green: 0.910, blue: 0.847),
        labelColor: Color(red: 1.00, green: 0.886, blue: 0.741),
        dotColor: Color(red: 1.00, green: 0.62, blue: 0.42),
        cancelBg: Color.white.opacity(0.08),
        cancelIcon: Color.white.opacity(0.60),
        auraColor: Color(red: 1.00, green: 0.55, blue: 0.35, opacity: 0.24)
    )

    // — NEW: Teal — deep teal between blue and green —
    static let teal = DictationPillPalette(
        isDarkShell: true,
        pillTop: Color(red: 0.067, green: 0.220, blue: 0.243),
        pillBottom: Color(red: 0.035, green: 0.133, blue: 0.149),
        pillBorder: Color(red: 0.439, green: 0.831, blue: 0.847, opacity: 0.28),
        pillShadow: Color(red: 0.02, green: 0.10, blue: 0.12, opacity: 0.55),
        gridLit: Color(red: 0.792, green: 0.949, blue: 0.949),
        gridDim: Color(red: 0.792, green: 0.949, blue: 0.949, opacity: 0.12),
        gridGlow: Color(red: 0.44, green: 0.83, blue: 0.85, opacity: 0.55),
        captionTop: Color(red: 0.067, green: 0.220, blue: 0.243),
        captionBottom: Color(red: 0.035, green: 0.133, blue: 0.149),
        captionBorder: Color(red: 0.439, green: 0.831, blue: 0.847, opacity: 0.14),
        captionText: Color(red: 0.847, green: 0.949, blue: 0.949),
        labelColor: Color(red: 0.792, green: 0.949, blue: 0.949),
        dotColor: Color(red: 0.353, green: 0.792, blue: 0.792),
        cancelBg: Color.white.opacity(0.08),
        cancelIcon: Color.white.opacity(0.55),
        auraColor: Color(red: 0.35, green: 0.79, blue: 0.79, opacity: 0.25)
    )

    // — NEW: Sage — light shell pale green —
    static let sage = DictationPillPalette(
        isDarkShell: false,
        pillTop: Color(red: 0.929, green: 0.949, blue: 0.910),
        pillBottom: Color(red: 0.871, green: 0.910, blue: 0.847),
        pillBorder: Color(red: 0.298, green: 0.420, blue: 0.298, opacity: 0.20),
        pillShadow: Color(red: 0.18, green: 0.24, blue: 0.16, opacity: 0.22),
        gridLit: Color(red: 0.122, green: 0.184, blue: 0.122),
        gridDim: Color(red: 0.122, green: 0.184, blue: 0.122, opacity: 0.14),
        gridGlow: Color(red: 0.30, green: 0.45, blue: 0.30, opacity: 0.28),
        captionTop: Color(red: 0.929, green: 0.949, blue: 0.910),
        captionBottom: Color(red: 0.890, green: 0.925, blue: 0.867),
        captionBorder: Color(red: 0.298, green: 0.420, blue: 0.298, opacity: 0.14),
        captionText: Color(red: 0.094, green: 0.149, blue: 0.094),
        labelColor: Color(red: 0.122, green: 0.184, blue: 0.122),
        dotColor: Color(red: 0.337, green: 0.502, blue: 0.337),
        cancelBg: Color.black.opacity(0.05),
        cancelIcon: Color.black.opacity(0.50),
        auraColor: Color(red: 0.78, green: 0.88, blue: 0.74, opacity: 0.45)
    )

    // — NEW: Lavender — light shell soft purple —
    static let lavender = DictationPillPalette(
        isDarkShell: false,
        pillTop: Color(red: 0.945, green: 0.929, blue: 0.973),
        pillBottom: Color(red: 0.898, green: 0.871, blue: 0.949),
        pillBorder: Color(red: 0.420, green: 0.314, blue: 0.612, opacity: 0.20),
        pillShadow: Color(red: 0.22, green: 0.15, blue: 0.32, opacity: 0.22),
        gridLit: Color(red: 0.184, green: 0.118, blue: 0.290),
        gridDim: Color(red: 0.184, green: 0.118, blue: 0.290, opacity: 0.14),
        gridGlow: Color(red: 0.45, green: 0.32, blue: 0.65, opacity: 0.28),
        captionTop: Color(red: 0.945, green: 0.929, blue: 0.973),
        captionBottom: Color(red: 0.910, green: 0.890, blue: 0.953),
        captionBorder: Color(red: 0.420, green: 0.314, blue: 0.612, opacity: 0.14),
        captionText: Color(red: 0.141, green: 0.090, blue: 0.227),
        labelColor: Color(red: 0.184, green: 0.118, blue: 0.290),
        dotColor: Color(red: 0.467, green: 0.353, blue: 0.671),
        cancelBg: Color.black.opacity(0.05),
        cancelIcon: Color.black.opacity(0.50),
        auraColor: Color(red: 0.82, green: 0.76, blue: 0.92, opacity: 0.45)
    )

    // — NEW: Mist — cool gray-blue light surface —
    static let mist = DictationPillPalette(
        isDarkShell: false,
        pillTop: Color(red: 0.949, green: 0.965, blue: 0.980),
        pillBottom: Color(red: 0.890, green: 0.918, blue: 0.949),
        pillBorder: Color(red: 0.349, green: 0.439, blue: 0.541, opacity: 0.20),
        pillShadow: Color(red: 0.15, green: 0.20, blue: 0.30, opacity: 0.22),
        gridLit: Color(red: 0.094, green: 0.137, blue: 0.196),
        gridDim: Color(red: 0.094, green: 0.137, blue: 0.196, opacity: 0.14),
        gridGlow: Color(red: 0.30, green: 0.45, blue: 0.65, opacity: 0.30),
        captionTop: Color(red: 0.949, green: 0.965, blue: 0.980),
        captionBottom: Color(red: 0.910, green: 0.937, blue: 0.965),
        captionBorder: Color(red: 0.349, green: 0.439, blue: 0.541, opacity: 0.14),
        captionText: Color(red: 0.071, green: 0.106, blue: 0.157),
        labelColor: Color(red: 0.094, green: 0.137, blue: 0.196),
        dotColor: Color(red: 0.349, green: 0.494, blue: 0.694),
        cancelBg: Color.black.opacity(0.05),
        cancelIcon: Color.black.opacity(0.50),
        auraColor: Color(red: 0.70, green: 0.82, blue: 0.94, opacity: 0.40)
    )
}
