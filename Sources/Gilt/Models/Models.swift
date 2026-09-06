import AppKit
import Carbon.HIToolbox
import Foundation
import OSLog
import SwiftUI

enum ClipType: String, Codable, CaseIterable {
    case text
    case link
    case image
    case audio
    case color
}

// MARK: - Smart Categorization

enum ContentTag: String, Codable, CaseIterable {
    case code
    case email
    case phoneNumber
    case colorValue
    case credential
    case address
}

enum SmartCategory: String, Codable, CaseIterable {
    case code
    case images
    case links
    case contacts
    case colors
    case addresses
    case sensitive

    var folderName: String {
        switch self {
        case .code: return L10n.string("smartCategory.code.name", default: "Code")
        case .images: return L10n.string("smartCategory.images.name", default: "Images")
        case .links: return L10n.string("smartCategory.links.name", default: "Links")
        case .contacts: return L10n.string("smartCategory.contacts.name", default: "Contacts")
        case .colors: return L10n.string("smartCategory.colors.name", default: "Colors")
        case .addresses: return L10n.string("smartCategory.addresses.name", default: "Addresses")
        case .sensitive: return L10n.string("smartCategory.sensitive.name", default: "Sensitive")
        }
    }

    var folderColor: FolderColorToken {
        switch self {
        case .code: return .sapphire
        case .images: return .coral
        case .links: return .emerald
        case .contacts: return .gold
        case .colors: return .amber
        case .addresses: return .teal
        case .sensitive: return .mauve
        }
    }

    /// Default gradient fill for each smart category — shows users that pill fills are customizable.
    var defaultFillGradient: String {
        switch self {
        case .code:      return "grad:#1A5FBF,#4BA3FF,135.0"
        case .images:    return "grad:#C4362A,#F07060,135.0"
        case .links:     return "grad:#1A8F54,#3CC97E,135.0"
        case .contacts:  return "grad:#C49A1A,#F5D04A,135.0"
        case .colors:    return "grad:#D47518,#F7A64E,135.0"
        case .addresses: return "grad:#1A9E8F,#45E8D4,135.0"
        case .sensitive: return "grad:#7040C0,#B895F5,135.0"
        }
    }

    /// Deterministic UUID per category — survives app restarts
    var folderID: UUID {
        switch self {
        case .code:      return UUID(uuidString: "A1B2C3D4-0001-4000-8000-000000000001")!
        case .images:    return UUID(uuidString: "A1B2C3D4-0002-4000-8000-000000000002")!
        case .links:     return UUID(uuidString: "A1B2C3D4-0003-4000-8000-000000000003")!
        case .contacts:  return UUID(uuidString: "A1B2C3D4-0004-4000-8000-000000000004")!
        case .colors:    return UUID(uuidString: "A1B2C3D4-0005-4000-8000-000000000005")!
        case .addresses: return UUID(uuidString: "A1B2C3D4-0006-4000-8000-000000000006")!
        case .sensitive: return UUID(uuidString: "A1B2C3D4-0007-4000-8000-000000000007")!
        }
    }

    var systemImage: String {
        switch self {
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .images: return "photo"
        case .links: return "link"
        case .contacts: return "person.crop.circle"
        case .colors: return "paintpalette"
        case .addresses: return "mappin.and.ellipse"
        case .sensitive: return "shield.lefthalf.filled"
        }
    }
    
    var settingsDescription: String {
        switch self {
        case .code: return L10n.string("smartCategory.code.description", default: "Detect code blocks and scripts")
        case .images: return L10n.string("smartCategory.images.description", default: "Detect copied images and screenshots")
        case .links: return L10n.string("smartCategory.links.description", default: "Detect URLs and web links")
        case .contacts: return L10n.string("smartCategory.contacts.description", default: "Detect phone numbers and emails")
        case .colors: return L10n.string("smartCategory.colors.description", default: "Detect hex and rgb color codes")
        case .addresses: return L10n.string("smartCategory.addresses.description", default: "Detect physical locations")
        case .sensitive: return L10n.string("smartCategory.sensitive.description", default: "Detect passwords and API keys")
        }
    }
}

enum DetectedLanguage: String, Codable, CaseIterable {
    case swift, python, javascript, typescript, html, css, sql, go, rust, ruby, java, shell, unknown

    var displayName: String {
        switch self {
        case .swift: return "Swift"
        case .python: return "Python"
        case .javascript: return "JavaScript"
        case .typescript: return "TypeScript"
        case .html: return "HTML"
        case .css: return "CSS"
        case .sql: return "SQL"
        case .go: return "Go"
        case .rust: return "Rust"
        case .ruby: return "Ruby"
        case .java: return "Java"
        case .shell: return "Shell"
        case .unknown: return L10n.string("detectedLanguage.unknown.name", default: "Code")
        }
    }
}

enum ClipboardFont: String, Codable, CaseIterable {
    case sfPro
    case sfRounded
    case sfMono
    case atkinsonHyperlegible
    case instrumentSans
    case jetBrainsMono

    var label: String {
        switch self {
        case .sfPro:
            return "SF Pro"
        case .sfRounded:
            return "SF Rounded"
        case .sfMono:
            return "SF Mono"
        case .atkinsonHyperlegible:
            return "Atkinson Hyperlegible"
        case .instrumentSans:
            return "Instrument Sans"
        case .jetBrainsMono:
            return "JetBrains Mono"
        }
    }

    func font(size: CGFloat, weight: Font.Weight = .regular, forceMonospaced: Bool = false) -> Font {
        BundledFontCatalog.font(
            for: self,
            size: size,
            weight: weight,
            forceMonospaced: forceMonospaced
        )
    }
}

enum SensitiveExpiry: String, Codable, CaseIterable {
    case fiveMinutes
    case fifteenMinutes
    case oneHour
    case never

    var label: String {
        switch self {
        case .fiveMinutes: return L10n.string("sensitiveExpiry.fiveMinutes.label", default: "5 Minutes")
        case .fifteenMinutes: return L10n.string("sensitiveExpiry.fifteenMinutes.label", default: "15 Minutes")
        case .oneHour: return L10n.string("sensitiveExpiry.oneHour.label", default: "1 Hour")
        case .never: return L10n.string("sensitiveExpiry.never.label", default: "Never")
        }
    }

    var seconds: TimeInterval? {
        switch self {
        case .fiveMinutes: return 300
        case .fifteenMinutes: return 900
        case .oneHour: return 3600
        case .never: return nil
        }
    }
}

struct SmartCategorySettings: Codable, Equatable {
    var codeEnabled: Bool = true
    var imagesEnabled: Bool = true
    var linksEnabled: Bool = true
    var contactsEnabled: Bool = true
    var colorsEnabled: Bool = true
    var addressesEnabled: Bool = true
    var sensitiveEnabled: Bool = true
    var autoExpireSensitive: Bool = false
    var sensitiveExpiry: SensitiveExpiry = .fifteenMinutes

    func isEnabled(_ category: SmartCategory) -> Bool {
        switch category {
        case .code: return codeEnabled
        case .images: return imagesEnabled
        case .links: return linksEnabled
        case .contacts: return contactsEnabled
        case .colors: return colorsEnabled
        case .addresses: return addressesEnabled
        case .sensitive: return sensitiveEnabled
        }
    }

    mutating func setEnabled(_ category: SmartCategory, _ enabled: Bool) {
        switch category {
        case .code: codeEnabled = enabled
        case .images: imagesEnabled = enabled
        case .links: linksEnabled = enabled
        case .contacts: contactsEnabled = enabled
        case .colors: colorsEnabled = enabled
        case .addresses: addressesEnabled = enabled
        case .sensitive: sensitiveEnabled = enabled
        }
    }

    private enum CodingKeys: String, CodingKey {
        case codeEnabled, imagesEnabled, linksEnabled, contactsEnabled
        case colorsEnabled, addressesEnabled, sensitiveEnabled
        case autoExpireSensitive, sensitiveExpiry
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        codeEnabled = try container.decodeIfPresent(Bool.self, forKey: .codeEnabled) ?? true
        imagesEnabled = try container.decodeIfPresent(Bool.self, forKey: .imagesEnabled) ?? true
        linksEnabled = try container.decodeIfPresent(Bool.self, forKey: .linksEnabled) ?? true
        contactsEnabled = try container.decodeIfPresent(Bool.self, forKey: .contactsEnabled) ?? true
        colorsEnabled = try container.decodeIfPresent(Bool.self, forKey: .colorsEnabled) ?? true
        addressesEnabled = try container.decodeIfPresent(Bool.self, forKey: .addressesEnabled) ?? true
        sensitiveEnabled = try container.decodeIfPresent(Bool.self, forKey: .sensitiveEnabled) ?? true
        autoExpireSensitive = try container.decodeIfPresent(Bool.self, forKey: .autoExpireSensitive) ?? false
        sensitiveExpiry = try container.decodeIfPresent(SensitiveExpiry.self, forKey: .sensitiveExpiry) ?? .fifteenMinutes
    }
}

enum SuggestedActionType: String, Codable {
    case call
    case email
    case openURL
    case openMaps
    case colorSwatch
    case language
}

struct SuggestedAction: Codable {
    let type: SuggestedActionType
    let label: String
    let value: String
}

/// Result of running ContentClassifier on a clip — not persisted directly
struct ContentClassification {
    var matchedCategories: Set<SmartCategory>
    var contentTags: Set<ContentTag>
    var isSensitive: Bool
    var detectedLanguage: DetectedLanguage?
    var suggestedActions: [SuggestedAction]
}

enum FolderColorToken: String, Codable, CaseIterable {
    case gold
    case amber
    case coral
    case emerald
    case teal
    case sapphire
    case mauve
    case slate
    case white

    var color: Color {
        switch self {
        case .gold:
            return Color(red: 0.93, green: 0.74, blue: 0.26)
        case .amber:
            return Color(red: 0.95, green: 0.57, blue: 0.20)
        case .coral:
            return Color(red: 0.93, green: 0.36, blue: 0.30)
        case .emerald:
            return Color(red: 0.18, green: 0.70, blue: 0.44)
        case .teal:
            return Color(red: 0.18, green: 0.83, blue: 0.75)
        case .sapphire:
            return Color(red: 0.16, green: 0.56, blue: 0.92)
        case .mauve:
            return Color(red: 0.62, green: 0.48, blue: 0.92)
        case .slate:
            return Color(red: 0.50, green: 0.53, blue: 0.60)
        case .white:
            return Color.white
        }
    }

    var label: String {
        switch self {
        case .gold: return L10n.string("folderColor.gold.label", default: "Gold")
        case .amber: return L10n.string("folderColor.amber.label", default: "Amber")
        case .coral: return L10n.string("folderColor.coral.label", default: "Coral")
        case .emerald: return L10n.string("folderColor.emerald.label", default: "Emerald")
        case .teal: return L10n.string("folderColor.teal.label", default: "Teal")
        case .sapphire: return L10n.string("folderColor.sapphire.label", default: "Sapphire")
        case .mauve: return L10n.string("folderColor.mauve.label", default: "Mauve")
        case .slate: return L10n.string("folderColor.slate.label", default: "Slate")
        case .white: return L10n.string("folderColor.white.label", default: "White")
        }
    }
}

enum FolderColorMode: String, Codable, CaseIterable {
    case dot         // Dot only
    case text        // Text only
    case fill        // Fill background with text
    case dotAndText  // Dot + text

    var label: String {
        switch self {
        case .dot: return L10n.string("folderColorMode.dot.label", default: "Dot Only")
        case .text: return L10n.string("folderColorMode.text.label", default: "Text Only")
        case .fill: return L10n.string("folderColorMode.fill.label", default: "Fill Background")
        case .dotAndText: return L10n.string("folderColorMode.dotAndText.label", default: "Dot & Text")
        }
    }
}

enum FolderTextColorMode: String, Codable, CaseIterable {
    case auto
    case white
    case accent
    case custom

    var label: String {
        switch self {
        case .auto: return L10n.string("folderTextColorMode.auto.label", default: "Auto")
        case .white: return L10n.string("folderTextColorMode.white.label", default: "White")
        case .accent: return L10n.string("folderTextColorMode.accent.label", default: "Accent")
        case .custom: return L10n.string("folderTextColorMode.custom.label", default: "Custom")
        }
    }

    var helperText: String {
        switch self {
        case .auto:
            return L10n.string(
                "folderTextColorMode.auto.help",
                default: "Matches the folder style automatically: fill uses white text, text and dot & text use the accent color, and dot-only stays white."
            )
        case .white:
            return L10n.string(
                "folderTextColorMode.white.help",
                default: "Forces white text regardless of the folder style."
            )
        case .accent:
            return L10n.string(
                "folderTextColorMode.accent.help",
                default: "Uses the folder accent color for the text."
            )
        case .custom:
            return L10n.string(
                "folderTextColorMode.custom.help",
                default: "Lets you choose a separate text color."
            )
        }
    }
}

enum HistoryRetention: String, Codable, CaseIterable {
    case day
    case week
    case month
    case forever

    var label: String {
        switch self {
        case .day: return L10n.string("historyRetention.day.label", default: "Day")
        case .week: return L10n.string("historyRetention.week.label", default: "Week")
        case .month: return L10n.string("historyRetention.month.label", default: "Month")
        case .forever: return L10n.string("historyRetention.forever.label", default: "Forever")
        }
    }

    var maxAgeSeconds: TimeInterval? {
        switch self {
        case .day:
            return 86_400
        case .week:
            return 604_800
        case .month:
            return 2_592_000
        case .forever:
            return nil
        }
    }
}

struct GlobalShortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let legacyDefault = GlobalShortcut(
        keyCode: UInt32(kVK_ANSI_V),
        modifiers: UInt32(cmdKey | shiftKey)
    )

    /// Temporary safer default used while diagnosing onboarding crash.
    /// Kept for one-time migration back to the product default.
    static let previousDefault = GlobalShortcut(
        keyCode: UInt32(kVK_ANSI_V),
        modifiers: UInt32(controlKey | optionKey)
    )

    static let `default` = GlobalShortcut(
        keyCode: UInt32(kVK_ANSI_V),
        modifiers: UInt32(controlKey)
    )

    static let quickNoteDefault = GlobalShortcut(
        keyCode: UInt32(kVK_ANSI_A),
        modifiers: UInt32(optionKey)
    )

    /// Option+Space. Deliberately not a Cmd-based combo: a global hotkey
    /// intercepts the chord system-wide, so a common combo like Cmd+K would break
    /// it in every other app. Option+Space is rarely bound globally.
    static let commandPaletteDefault = GlobalShortcut(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(optionKey)
    )

    var requiresEventTapFallback: Bool {
        let commandOrControl = UInt32(cmdKey | controlKey)
        let shiftOrOption = UInt32(shiftKey | optionKey)
        return modifiers != 0
            && modifiers & commandOrControl == 0
            && modifiers & ~shiftOrOption == 0
    }

    var displayString: String {
        let parts = modifierDisplayParts + [Self.displayName(for: keyCode)]
        return parts.joined(separator: "+")
    }

    /// macOS-style symbol string (e.g. "⌃V", "⌘⇧V") for menu display.
    var symbolString: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        s += Self.displayName(for: keyCode)
        return s
    }

    private var modifierDisplayParts: [String] {
        var parts: [String] = []
        if modifiers & UInt32(cmdKey) != 0 { parts.append("Cmd") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("Shift") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("Option") }
        if modifiers & UInt32(controlKey) != 0 { parts.append("Ctrl") }
        return parts
    }

    static func displayName(for keyCode: UInt32) -> String {
        switch keyCode {
        case UInt32(kVK_ANSI_A): return "A"
        case UInt32(kVK_ANSI_B): return "B"
        case UInt32(kVK_ANSI_C): return "C"
        case UInt32(kVK_ANSI_D): return "D"
        case UInt32(kVK_ANSI_E): return "E"
        case UInt32(kVK_ANSI_F): return "F"
        case UInt32(kVK_ANSI_G): return "G"
        case UInt32(kVK_ANSI_H): return "H"
        case UInt32(kVK_ANSI_I): return "I"
        case UInt32(kVK_ANSI_J): return "J"
        case UInt32(kVK_ANSI_K): return "K"
        case UInt32(kVK_ANSI_L): return "L"
        case UInt32(kVK_ANSI_M): return "M"
        case UInt32(kVK_ANSI_N): return "N"
        case UInt32(kVK_ANSI_O): return "O"
        case UInt32(kVK_ANSI_P): return "P"
        case UInt32(kVK_ANSI_Q): return "Q"
        case UInt32(kVK_ANSI_R): return "R"
        case UInt32(kVK_ANSI_S): return "S"
        case UInt32(kVK_ANSI_T): return "T"
        case UInt32(kVK_ANSI_U): return "U"
        case UInt32(kVK_ANSI_V): return "V"
        case UInt32(kVK_ANSI_W): return "W"
        case UInt32(kVK_ANSI_X): return "X"
        case UInt32(kVK_ANSI_Y): return "Y"
        case UInt32(kVK_ANSI_Z): return "Z"
        case UInt32(kVK_ANSI_0): return "0"
        case UInt32(kVK_ANSI_1): return "1"
        case UInt32(kVK_ANSI_2): return "2"
        case UInt32(kVK_ANSI_3): return "3"
        case UInt32(kVK_ANSI_4): return "4"
        case UInt32(kVK_ANSI_5): return "5"
        case UInt32(kVK_ANSI_6): return "6"
        case UInt32(kVK_ANSI_7): return "7"
        case UInt32(kVK_ANSI_8): return "8"
        case UInt32(kVK_ANSI_9): return "9"
        case UInt32(kVK_Return): return "Return"
        case UInt32(kVK_Space): return "Space"
        case UInt32(kVK_Tab): return "Tab"
        case UInt32(kVK_Delete): return "Delete"
        case UInt32(kVK_ForwardDelete): return "ForwardDelete"
        case UInt32(kVK_Escape): return "Escape"
        case UInt32(kVK_F1): return "F1"
        case UInt32(kVK_F2): return "F2"
        case UInt32(kVK_F3): return "F3"
        case UInt32(kVK_F4): return "F4"
        case UInt32(kVK_F5): return "F5"
        case UInt32(kVK_F6): return "F6"
        case UInt32(kVK_F7): return "F7"
        case UInt32(kVK_F8): return "F8"
        case UInt32(kVK_F9): return "F9"
        case UInt32(kVK_F10): return "F10"
        case UInt32(kVK_F11): return "F11"
        case UInt32(kVK_F12): return "F12"
        case UInt32(kVK_F13): return "F13"
        case UInt32(kVK_F14): return "F14"
        case UInt32(kVK_F15): return "F15"
        case UInt32(kVK_F16): return "F16"
        case UInt32(kVK_F17): return "F17"
        case UInt32(kVK_F18): return "F18"
        case UInt32(kVK_F19): return "F19"
        case UInt32(kVK_F20): return "F20"
        default: return "Key\(keyCode)"
        }
    }

    static func isFunctionKey(_ keyCode: UInt32) -> Bool {
        switch keyCode {
        case UInt32(kVK_F1),
             UInt32(kVK_F2),
             UInt32(kVK_F3),
             UInt32(kVK_F4),
             UInt32(kVK_F5),
             UInt32(kVK_F6),
             UInt32(kVK_F7),
             UInt32(kVK_F8),
             UInt32(kVK_F9),
             UInt32(kVK_F10),
             UInt32(kVK_F11),
             UInt32(kVK_F12),
             UInt32(kVK_F13),
             UInt32(kVK_F14),
             UInt32(kVK_F15),
             UInt32(kVK_F16),
             UInt32(kVK_F17),
             UInt32(kVK_F18),
             UInt32(kVK_F19),
             UInt32(kVK_F20):
            return true
        default:
            return false
        }
    }
}

enum BackgroundTheme: String, Codable, CaseIterable {
    case scenic
    case auric
    case obsidian
    case midnight
    case forest
    case ember
    case glass
    case vibrancy
    case custom

    var label: String {
        switch self {
        case .auric: return L10n.string("backgroundTheme.auric.label", default: "Auric")
        case .obsidian: return L10n.string("backgroundTheme.obsidian.label", default: "Obsidian")
        case .midnight: return L10n.string("backgroundTheme.midnight.label", default: "Midnight")
        case .forest: return L10n.string("backgroundTheme.forest.label", default: "Forest")
        case .ember: return L10n.string("backgroundTheme.ember.label", default: "Ember")
        case .glass: return L10n.string("backgroundTheme.glass.label", default: "Glass")
        case .vibrancy: return L10n.string("backgroundTheme.vibrancy.label", default: "Vibrancy")
        case .scenic: return L10n.string("backgroundTheme.scenic.label", default: "Normal")
        case .custom: return L10n.string("backgroundTheme.custom.label", default: "Custom")
        }
    }

    /// Whether this theme uses real NSVisualEffectView for desktop blur-through
    var usesNativeVibrancy: Bool {
        self == .vibrancy
    }

    /// Whether this theme shows wallpaper image as the primary background with minimal overlay
    var isImageOnly: Bool {
        self == .scenic
    }

    /// Gradient colors for the main background
    var gradientColors: [Color] {
        switch self {
        case .auric:
            return [
                Color(red: 0.08, green: 0.08, blue: 0.09),
                Color(red: 0.12, green: 0.11, blue: 0.10),
                Color(red: 0.16, green: 0.14, blue: 0.10),
            ]
        case .obsidian:
            return [
                Color(red: 0.07, green: 0.07, blue: 0.08),
                Color(red: 0.10, green: 0.10, blue: 0.11),
                Color(red: 0.13, green: 0.13, blue: 0.14),
            ]
        case .midnight:
            return [
                Color(red: 0.04, green: 0.05, blue: 0.12),
                Color(red: 0.06, green: 0.08, blue: 0.16),
                Color(red: 0.08, green: 0.10, blue: 0.20),
            ]
        case .forest:
            return [
                Color(red: 0.04, green: 0.09, blue: 0.06),
                Color(red: 0.06, green: 0.12, blue: 0.08),
                Color(red: 0.08, green: 0.15, blue: 0.10),
            ]
        case .ember:
            return [
                Color(red: 0.12, green: 0.06, blue: 0.04),
                Color(red: 0.16, green: 0.08, blue: 0.05),
                Color(red: 0.20, green: 0.10, blue: 0.06),
            ]
        case .glass:
            return [
                Color(red: 0.06, green: 0.06, blue: 0.07),
                Color(red: 0.08, green: 0.08, blue: 0.09),
                Color(red: 0.10, green: 0.10, blue: 0.11),
            ]
        case .vibrancy:
            // Minimal tint — the NSVisualEffectView does the heavy lifting
            return [
                Color(red: 0.08, green: 0.08, blue: 0.10),
                Color(red: 0.10, green: 0.10, blue: 0.12),
                Color(red: 0.12, green: 0.12, blue: 0.14),
            ]
        case .scenic:
            // Near-transparent — the wallpaper image is the star
            return [
                Color(red: 0.05, green: 0.05, blue: 0.06),
                Color(red: 0.06, green: 0.06, blue: 0.07),
                Color(red: 0.07, green: 0.07, blue: 0.08),
            ]
        case .custom:
            return [
                Color(red: 0.08, green: 0.06, blue: 0.12),
                Color(red: 0.12, green: 0.08, blue: 0.16),
                Color(red: 0.16, green: 0.10, blue: 0.20),
            ]
        }
    }

    /// Vignette accent color for the radial overlay
    var vignetteColor: Color {
        switch self {
        case .auric:
            return Color(red: 0.24, green: 0.18, blue: 0.10)
        case .obsidian:
            return Color(red: 0.14, green: 0.14, blue: 0.16)
        case .midnight:
            return Color(red: 0.10, green: 0.12, blue: 0.28)
        case .forest:
            return Color(red: 0.08, green: 0.20, blue: 0.12)
        case .ember:
            return Color(red: 0.28, green: 0.12, blue: 0.06)
        case .glass:
            return Color(red: 0.12, green: 0.12, blue: 0.14)
        case .vibrancy:
            return Color(red: 0.14, green: 0.14, blue: 0.18)
        case .scenic:
            return Color.clear
        case .custom:
            return Color.clear
        }
    }

    /// Preview gradient for the theme picker circles
    var previewGradient: [Color] {
        switch self {
        case .auric:    return [Color(red: 0.93, green: 0.74, blue: 0.26), Color(red: 0.16, green: 0.14, blue: 0.10)]
        case .obsidian: return [Color(red: 0.40, green: 0.40, blue: 0.44), Color(red: 0.13, green: 0.13, blue: 0.14)]
        case .midnight: return [Color(red: 0.20, green: 0.30, blue: 0.70), Color(red: 0.04, green: 0.05, blue: 0.12)]
        case .forest:   return [Color(red: 0.18, green: 0.55, blue: 0.30), Color(red: 0.04, green: 0.09, blue: 0.06)]
        case .ember:    return [Color(red: 0.85, green: 0.35, blue: 0.15), Color(red: 0.12, green: 0.06, blue: 0.04)]
        case .glass:    return [Color(red: 0.60, green: 0.60, blue: 0.65), Color(red: 0.20, green: 0.20, blue: 0.22)]
        case .vibrancy: return [Color(red: 0.55, green: 0.55, blue: 0.70), Color(red: 0.30, green: 0.30, blue: 0.40)]
        case .scenic:   return [Color(red: 0.70, green: 0.45, blue: 0.35), Color(red: 0.25, green: 0.20, blue: 0.30)]
        case .custom:   return [Color(red: 0.70, green: 0.40, blue: 0.90), Color(red: 0.20, green: 0.60, blue: 0.80)]
        }
    }

    /// How much the material overlay should show (higher = more glass effect)
    var materialOpacityMultiplier: Double {
        switch self {
        case .glass: return 2.0
        case .vibrancy: return 0.0  // NSVisualEffectView handles blur, no SwiftUI material needed
        case .scenic: return 0.0    // Image-only, no material overlay
        default: return 1.0
        }
    }
}

enum BackgroundWallpaper: String, Codable, CaseIterable {
    case none
    case terra
    case custom

    @MainActor private static let imageCache = NSCache<NSString, NSImage>()
    private static let wallpaperLogger = Logger(subsystem: AppBrand.logSubsystem, category: "Wallpaper")
    private static let wallpaperDebugLoggingEnabled = ProcessInfo.processInfo.environment["GILT_DEBUG_LOGS"] == "1"

    var label: String {
        switch self {
        case .none: return L10n.string("backgroundWallpaper.none.label", default: "None")
        case .terra: return L10n.string("backgroundWallpaper.terra.label", default: "Terra")
        case .custom: return L10n.string("backgroundWallpaper.custom.label", default: "Custom")
        }
    }

    /// Resource filename (without extension) inside Resources/
    var resourceName: String? {
        switch self {
        case .none, .custom: return nil
        case .terra: return "terra"
        }
    }

    /// Directory inside App Support where custom wallpapers are stored
    static var customWallpaperDirectory: URL {
        AppSupportLocator.giltDirectory()
            .appendingPathComponent("wallpapers", isDirectory: true)
    }

    /// Import a user-selected image: copies it to the app support wallpapers directory.
    /// Returns the stored filename on success.
    @MainActor
    static func importCustomImage(from sourceURL: URL, slot: WallpaperSlot = .clipboard) -> String? {
        let dir = customWallpaperDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Use a stable per-surface filename so each surface can keep its own image.
        let ext = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension
        let filename = "\(slot.filenameStem).\(ext)"
        let destURL = dir.appendingPathComponent(filename)

        // Remove any prior image for the same surface slot before copying the
        // new file so the slot never accumulates multiple stale extensions.
        if let existingFiles = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for existingURL in existingFiles where existingURL.deletingPathExtension().lastPathComponent == slot.filenameStem {
                try? FileManager.default.removeItem(at: existingURL)
            }
        }

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            // Different surfaces can each keep their own custom wallpaper, so
            // clear the shared image cache whenever one of those files changes.
            imageCache.removeAllObjects()
            log("imported custom wallpaper from=\(sourceURL.lastPathComponent) to=\(destURL.path)")
            return filename
        } catch {
            log("import failed source=\(sourceURL.path) error=\(error.localizedDescription)")
            return nil
        }
    }

    /// Load the bundled or custom NSImage for this wallpaper
    @MainActor
    func loadImage(customFilename: String? = nil) -> NSImage? {
        if self == .custom {
            return Self.loadCustomImage(filename: customFilename)
        }
        guard let name = resourceName else { return nil }

        let cacheKey = rawValue as NSString
        if let cached = Self.imageCache.object(forKey: cacheKey) {
            return cached
        }

        guard let url = AppResourceLocator.url(forResource: name, withExtension: "png", subdirectory: "Resources")
        else {
            Self.log("load failed wallpaper=\(rawValue) reason=missing-resource")
            return nil
        }
        guard let image = NSImage(contentsOf: url) else {
            Self.log("load failed wallpaper=\(rawValue) reason=decode path=\(url.path)")
            return nil
        }

        Self.imageCache.setObject(image, forKey: cacheKey)
        Self.log(
            "cache-miss loaded wallpaper=\(rawValue) asset=\(url.lastPathComponent) size=\(Int(image.size.width))x\(Int(image.size.height))"
        )
        return image
    }

    @MainActor
    private static func loadCustomImage(filename: String?) -> NSImage? {
        guard let filename, !filename.isEmpty else {
            log("load failed wallpaper=custom reason=no-filename")
            return nil
        }

        let cacheKey = "custom:\(filename)" as NSString
        if let cached = imageCache.object(forKey: cacheKey) {
            return cached
        }

        let url = customWallpaperDirectory.appendingPathComponent(filename)
        guard let image = NSImage(contentsOf: url) else {
            log("load failed wallpaper=custom reason=decode path=\(url.path)")
            return nil
        }

        imageCache.setObject(image, forKey: cacheKey)
        log("cache-miss loaded wallpaper=custom file=\(filename) size=\(Int(image.size.width))x\(Int(image.size.height))")
        return image
    }

    @MainActor
    private static func log(_ message: String) {
        guard wallpaperDebugLoggingEnabled else { return }
        wallpaperLogger.debug("\(message, privacy: .public)")
    }
}

enum ViewMode: String, Codable, CaseIterable, Identifiable {
    case tray
    case drawer
    case panel
    case grid
    case radial
    case workspace

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tray: return L10n.string("viewMode.tray.label", default: "Tray")
        case .drawer: return L10n.string("viewMode.drawer.label", default: "Drawer")
        case .panel: return L10n.string("viewMode.panel.label", default: "Panel")
        case .grid: return L10n.string("viewMode.grid.label", default: "Grid")
        case .radial: return L10n.string("viewMode.radial.label", default: "Radial")
        case .workspace: return L10n.string("viewMode.workspace.label", default: "Workspace")
        }
    }

    var icon: String {
        switch self {
        case .tray: return "rectangle.bottomhalf.inset.filled"
        case .drawer: return "sidebar.trailing"
        case .panel: return "rectangle.portrait.on.rectangle.portrait"
        case .grid: return "square.grid.2x2"
        case .radial: return "circle.hexagongrid"
        case .workspace: return "rectangle.split.3x1"
        }
    }

    var description: String {
        switch self {
        case .tray: return L10n.string("viewMode.tray.description", default: "Bottom shelf with horizontal scroll")
        case .drawer: return L10n.string("viewMode.drawer.description", default: "Side panel with vertical list")
        case .panel: return L10n.string("viewMode.panel.description", default: "Compact pop-up list at your cursor")
        case .grid: return L10n.string("viewMode.grid.description", default: "Floating window with card grid")
        case .radial: return L10n.string("viewMode.radial.description", default: "Quick-access ring at cursor")
        case .workspace: return L10n.string("viewMode.workspace.description", default: "Large workspace with tabs for clipboard, tasks, pulse, and meetings")
        }
    }
}

enum DrawerSide: String, Codable, CaseIterable, Identifiable {
    case left
    case right

    var id: String { rawValue }

    var label: String {
        switch self {
        case .left: return L10n.string("drawerSide.left.label", default: "Left")
        case .right: return L10n.string("drawerSide.right.label", default: "Right")
        }
    }

    var icon: String {
        switch self {
        case .left: return "sidebar.leading"
        case .right: return "sidebar.trailing"
        }
    }
}

enum RadialSwipeDirection: String, Codable, CaseIterable, Identifiable {
    case natural
    case reversed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .natural: return L10n.string("radialSwipeDirection.natural.label", default: "Natural")
        case .reversed: return L10n.string("radialSwipeDirection.reversed.label", default: "Reversed")
        }
    }

    /// Direction multiplier for horizontal swipe delta.
    /// `natural` keeps the default mapping; `reversed` flips it.
    var multiplier: CGFloat {
        switch self {
        case .natural: return 1
        case .reversed: return -1
        }
    }
}

enum QuickNoteNavigationControlsStyle: String, Codable, CaseIterable, Identifiable {
    case standard
    case minimal
    case hidden

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard:
            return L10n.string(
                "quickNoteNavigationControlsStyle.standard.label",
                default: "Standard"
            )
        case .minimal:
            return L10n.string(
                "quickNoteNavigationControlsStyle.minimal.label",
                default: "Minimal"
            )
        case .hidden:
            return L10n.string(
                "quickNoteNavigationControlsStyle.hidden.label",
                default: "Hidden"
            )
        }
    }
}

enum QuickNoteOpenPosition: String, Codable, CaseIterable, Identifiable {
    case centered
    case mouse

    var id: String { rawValue }

    var label: String {
        switch self {
        case .centered:
            return L10n.string("quickNoteOpenPosition.centered.label", default: "Centered")
        case .mouse:
            return L10n.string("quickNoteOpenPosition.mouse.label", default: "At Mouse")
        }
    }

    var subtitle: String {
        switch self {
        case .centered:
            return L10n.string(
                "quickNoteOpenPosition.centered.subtitle",
                default: "Open in the middle of the current screen"
            )
        case .mouse:
            return L10n.string(
                "quickNoteOpenPosition.mouse.subtitle",
                default: "Open near your pointer like the radial view"
            )
        }
    }
}

enum QuickNoteAnimationStyle: String, Codable, CaseIterable, Identifiable {
    case slide
    case fade
    case pop
    case dropFromTop
    case riseFromBelow
    case slideFromLeft
    case slideFromRight
    case zoomIn

    var id: String { rawValue }

    var label: String {
        switch self {
        case .slide: return "Slide"
        case .fade: return "Fade"
        case .pop: return "Pop"
        case .dropFromTop: return "Drop In"
        case .riseFromBelow: return "Rise Up"
        case .slideFromLeft: return "From Left"
        case .slideFromRight: return "From Right"
        case .zoomIn: return "Zoom"
        }
    }
}

enum QuickNoteStyle: String, Codable, CaseIterable, Identifiable {
    case cleanCanvas
    case paper
    case obsidian
    case midnightGrid
    case prismGlass
    case aurora
    case sunset
    case terminal
    case sakura
    case oceanic
    case parchment
    case cyberpunk
    case sage
    case graphite
    case lavender
    case blueprint

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cleanCanvas:
            return L10n.string("quickNoteStyle.cleanCanvas.label", default: "Canvas")
        case .paper:
            return L10n.string("quickNoteStyle.paper.label", default: "Paper")
        case .obsidian:
            return L10n.string("quickNoteStyle.obsidian.label", default: "Obsidian")
        case .midnightGrid:
            return L10n.string("quickNoteStyle.midnightGrid.label", default: "Midnight")
        case .prismGlass:
            return L10n.string("quickNoteStyle.prismGlass.label", default: "Prism")
        case .aurora:
            return L10n.string("quickNoteStyle.aurora.label", default: "Aurora")
        case .sunset:
            return L10n.string("quickNoteStyle.sunset.label", default: "Sunset")
        case .terminal:
            return L10n.string("quickNoteStyle.terminal.label", default: "Terminal")
        case .sakura:
            return L10n.string("quickNoteStyle.sakura.label", default: "Sakura")
        case .oceanic:
            return L10n.string("quickNoteStyle.oceanic.label", default: "Oceanic")
        case .parchment:
            return L10n.string("quickNoteStyle.parchment.label", default: "Parchment")
        case .cyberpunk:
            return L10n.string("quickNoteStyle.cyberpunk.label", default: "Cyberpunk")
        case .sage:
            return L10n.string("quickNoteStyle.sage.label", default: "Sage")
        case .graphite:
            return L10n.string("quickNoteStyle.graphite.label", default: "Graphite")
        case .lavender:
            return L10n.string("quickNoteStyle.lavender.label", default: "Lavender")
        case .blueprint:
            return L10n.string("quickNoteStyle.blueprint.label", default: "Blueprint")
        }
    }

    var subtitle: String {
        switch self {
        case .cleanCanvas:
            return L10n.string(
                "quickNoteStyle.cleanCanvas.subtitle",
                default: "No decorative skin, so wallpapers stay clear and unobstructed"
            )
        case .paper:
            return L10n.string("quickNoteStyle.paper.subtitle", default: "Soft paper card with a subtle grid")
        case .obsidian:
            return L10n.string("quickNoteStyle.obsidian.subtitle", default: "Dense charcoal note with a strong accent edge")
        case .midnightGrid:
            return L10n.string("quickNoteStyle.midnightGrid.subtitle", default: "Dark grid notebook with neon-style contrast")
        case .prismGlass:
            return L10n.string("quickNoteStyle.prismGlass.subtitle", default: "Frosted glass panel with desktop vibrancy")
        case .aurora:
            return L10n.string(
                "quickNoteStyle.aurora.subtitle",
                default: "Transparent glass with a soft aurora color wash"
            )
        case .sunset:
            return L10n.string(
                "quickNoteStyle.sunset.subtitle",
                default: "Warm coral gradient that glows like dusk"
            )
        case .terminal:
            return L10n.string(
                "quickNoteStyle.terminal.subtitle",
                default: "Matte black panel with phosphor-green text"
            )
        case .sakura:
            return L10n.string("quickNoteStyle.sakura.subtitle", default: "Soft cherry-blossom paper with rose ink")
        case .oceanic:
            return L10n.string("quickNoteStyle.oceanic.subtitle", default: "Deep sea teal with coral highlights")
        case .parchment:
            return L10n.string("quickNoteStyle.parchment.subtitle", default: "Aged parchment with warm sepia ink")
        case .cyberpunk:
            return L10n.string("quickNoteStyle.cyberpunk.subtitle", default: "Neon magenta and cyan on jet black")
        case .sage:
            return L10n.string("quickNoteStyle.sage.subtitle", default: "Earthy sage matte with olive accents")
        case .graphite:
            return L10n.string("quickNoteStyle.graphite.subtitle", default: "Soft pencil gray like a sketchbook page")
        case .lavender:
            return L10n.string("quickNoteStyle.lavender.subtitle", default: "Dreamy lilac wash with violet ink")
        case .blueprint:
            return L10n.string("quickNoteStyle.blueprint.subtitle", default: "Engineering blueprint with cyan grid")
        }
    }

    var isLightSurface: Bool {
        switch self {
        case .paper, .sakura, .parchment:
            return true
        case .cleanCanvas, .obsidian, .midnightGrid, .prismGlass, .aurora, .sunset, .terminal,
             .oceanic, .cyberpunk, .sage, .graphite, .lavender, .blueprint:
            return false
        }
    }

    var isTemplateFree: Bool {
        self == .cleanCanvas
    }

    var usesVibrancy: Bool {
        self == .prismGlass || self == .aurora
    }

    var cardGradient: [Color] {
        switch self {
        case .cleanCanvas:
            return [
                Color(red: 0.11, green: 0.12, blue: 0.14),
                Color(red: 0.11, green: 0.12, blue: 0.14)
            ]
        case .paper:
            return [
                Color(red: 0.988, green: 0.982, blue: 0.964),
                Color(red: 0.972, green: 0.968, blue: 0.948)
            ]
        case .obsidian:
            return [
                Color(red: 0.10, green: 0.10, blue: 0.11),
                Color(red: 0.14, green: 0.13, blue: 0.12)
            ]
        case .midnightGrid:
            return [
                Color(red: 0.07, green: 0.08, blue: 0.16),
                Color(red: 0.05, green: 0.06, blue: 0.12)
            ]
        case .prismGlass:
            return [
                Color(red: 0.11, green: 0.21, blue: 0.42).opacity(0.72),
                Color(red: 0.12, green: 0.45, blue: 0.36).opacity(0.68)
            ]
        case .aurora:
            return [
                Color(red: 0.24, green: 0.30, blue: 0.58).opacity(0.42),
                Color(red: 0.18, green: 0.48, blue: 0.46).opacity(0.38),
                Color(red: 0.42, green: 0.22, blue: 0.52).opacity(0.40)
            ]
        case .sunset:
            return [
                Color(red: 0.98, green: 0.52, blue: 0.36),
                Color(red: 0.92, green: 0.32, blue: 0.46),
                Color(red: 0.56, green: 0.22, blue: 0.58)
            ]
        case .terminal:
            return [
                Color(red: 0.04, green: 0.06, blue: 0.05),
                Color(red: 0.02, green: 0.04, blue: 0.03)
            ]
        case .sakura:
            return [
                Color(red: 0.998, green: 0.948, blue: 0.952),
                Color(red: 0.986, green: 0.902, blue: 0.918)
            ]
        case .oceanic:
            return [
                Color(red: 0.04, green: 0.16, blue: 0.26),
                Color(red: 0.02, green: 0.22, blue: 0.30)
            ]
        case .parchment:
            return [
                Color(red: 0.962, green: 0.918, blue: 0.836),
                Color(red: 0.932, green: 0.874, blue: 0.776)
            ]
        case .cyberpunk:
            return [
                Color(red: 0.05, green: 0.02, blue: 0.10),
                Color(red: 0.10, green: 0.02, blue: 0.14)
            ]
        case .sage:
            return [
                Color(red: 0.22, green: 0.28, blue: 0.24),
                Color(red: 0.16, green: 0.22, blue: 0.18)
            ]
        case .graphite:
            return [
                Color(red: 0.20, green: 0.20, blue: 0.22),
                Color(red: 0.14, green: 0.14, blue: 0.16)
            ]
        case .lavender:
            return [
                Color(red: 0.32, green: 0.24, blue: 0.50),
                Color(red: 0.22, green: 0.18, blue: 0.40)
            ]
        case .blueprint:
            return [
                Color(red: 0.04, green: 0.12, blue: 0.26),
                Color(red: 0.06, green: 0.18, blue: 0.34)
            ]
        }
    }

    var cardBorderColor: Color {
        switch self {
        case .cleanCanvas:
            return Color.white.opacity(0.14)
        case .paper:
            return Color.black.opacity(0.06)
        case .obsidian:
            return Color.white.opacity(0.08)
        case .midnightGrid:
            return Color(red: 0.25, green: 0.34, blue: 0.72).opacity(0.35)
        case .prismGlass:
            return Color.white.opacity(0.16)
        case .aurora:
            return Color.white.opacity(0.26)
        case .sunset:
            return Color.white.opacity(0.22)
        case .terminal:
            return Color(red: 0.24, green: 0.82, blue: 0.42).opacity(0.42)
        case .sakura:
            return Color(red: 0.86, green: 0.52, blue: 0.62).opacity(0.22)
        case .oceanic:
            return Color(red: 0.32, green: 0.86, blue: 0.90).opacity(0.30)
        case .parchment:
            return Color(red: 0.52, green: 0.38, blue: 0.22).opacity(0.18)
        case .cyberpunk:
            return Color(red: 0.96, green: 0.22, blue: 0.82).opacity(0.48)
        case .sage:
            return Color(red: 0.58, green: 0.72, blue: 0.56).opacity(0.32)
        case .graphite:
            return Color.white.opacity(0.12)
        case .lavender:
            return Color(red: 0.78, green: 0.66, blue: 0.98).opacity(0.34)
        case .blueprint:
            return Color(red: 0.38, green: 0.78, blue: 1.0).opacity(0.38)
        }
    }

    /// Perceived brightness of the style's card gradient — used to auto-pick
    /// popover text colour when there is no wallpaper (or as an overlay tint).
    var averageCardLuminance: Double {
        let samples = cardGradient.map { color -> Double in
            guard let rgb = NSColor(color).usingColorSpace(.deviceRGB) else { return 0.5 }
            return 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
        }
        guard !samples.isEmpty else { return 0.5 }
        return samples.reduce(0, +) / Double(samples.count)
    }

    var textColor: Color {
        switch self {
        case .cleanCanvas:
            return Color.white.opacity(0.94)
        case .paper:
            return Color.black.opacity(0.82)
        case .obsidian:
            return Color.white.opacity(0.92)
        case .midnightGrid:
            return Color.white.opacity(0.9)
        case .prismGlass:
            return Color.white.opacity(0.9)
        case .aurora:
            return Color.white.opacity(0.95)
        case .sunset:
            return Color.white.opacity(0.96)
        case .terminal:
            return Color(red: 0.58, green: 0.98, blue: 0.66)
        case .sakura:
            return Color(red: 0.46, green: 0.28, blue: 0.34).opacity(0.92)
        case .oceanic:
            return Color.white.opacity(0.94)
        case .parchment:
            return Color(red: 0.32, green: 0.22, blue: 0.12).opacity(0.88)
        case .cyberpunk:
            return Color(red: 0.98, green: 0.94, blue: 1.0).opacity(0.96)
        case .sage:
            return Color(red: 0.94, green: 0.96, blue: 0.88).opacity(0.92)
        case .graphite:
            return Color.white.opacity(0.88)
        case .lavender:
            return Color(red: 0.98, green: 0.94, blue: 1.0).opacity(0.94)
        case .blueprint:
            return Color(red: 0.88, green: 0.96, blue: 1.0).opacity(0.94)
        }
    }

    var secondaryTextColor: Color {
        switch self {
        case .cleanCanvas:
            return Color.white.opacity(0.58)
        case .paper:
            return Color.black.opacity(0.46)
        case .obsidian:
            return Color.white.opacity(0.46)
        case .midnightGrid:
            return Color(red: 0.43, green: 0.85, blue: 0.88).opacity(0.84)
        case .prismGlass:
            return Color(red: 0.46, green: 0.90, blue: 0.86).opacity(0.84)
        case .aurora:
            return Color(red: 0.62, green: 0.96, blue: 0.82).opacity(0.88)
        case .sunset:
            return Color(red: 1.0, green: 0.92, blue: 0.68).opacity(0.92)
        case .terminal:
            return Color(red: 0.42, green: 0.92, blue: 0.52).opacity(0.68)
        case .sakura:
            return Color(red: 0.64, green: 0.42, blue: 0.50).opacity(0.72)
        case .oceanic:
            return Color(red: 0.58, green: 0.90, blue: 0.94).opacity(0.82)
        case .parchment:
            return Color(red: 0.54, green: 0.40, blue: 0.24).opacity(0.68)
        case .cyberpunk:
            return Color(red: 0.42, green: 0.94, blue: 1.0).opacity(0.86)
        case .sage:
            return Color(red: 0.78, green: 0.86, blue: 0.66).opacity(0.78)
        case .graphite:
            return Color.white.opacity(0.52)
        case .lavender:
            return Color(red: 0.86, green: 0.76, blue: 1.0).opacity(0.82)
        case .blueprint:
            return Color(red: 0.62, green: 0.86, blue: 1.0).opacity(0.80)
        }
    }

    var insertionColor: Color {
        switch self {
        case .cleanCanvas:
            return Color.white.opacity(0.92)
        case .paper:
            return Color(red: 0.26, green: 0.39, blue: 0.82)
        case .obsidian:
            return Color(red: 0.98, green: 0.38, blue: 0.27)
        case .midnightGrid:
            return Color(red: 0.38, green: 0.96, blue: 0.56)
        case .prismGlass:
            return Color(red: 0.46, green: 0.90, blue: 0.86)
        case .aurora:
            return Color(red: 0.58, green: 0.98, blue: 0.82)
        case .sunset:
            return Color(red: 1.0, green: 0.86, blue: 0.46)
        case .terminal:
            return Color(red: 0.52, green: 1.0, blue: 0.58)
        case .sakura:
            return Color(red: 0.86, green: 0.34, blue: 0.52)
        case .oceanic:
            return Color(red: 1.0, green: 0.62, blue: 0.42)
        case .parchment:
            return Color(red: 0.58, green: 0.28, blue: 0.14)
        case .cyberpunk:
            return Color(red: 0.98, green: 0.22, blue: 0.86)
        case .sage:
            return Color(red: 0.86, green: 0.92, blue: 0.62)
        case .graphite:
            return Color(red: 1.0, green: 0.84, blue: 0.42)
        case .lavender:
            return Color(red: 0.98, green: 0.82, blue: 1.0)
        case .blueprint:
            return Color(red: 0.42, green: 0.86, blue: 1.0)
        }
    }

    var gridColor: Color {
        switch self {
        case .cleanCanvas:
            return Color.white.opacity(0.08)
        case .paper:
            return Color(red: 0.75, green: 0.76, blue: 0.80).opacity(0.22)
        case .obsidian:
            return Color.white.opacity(0.04)
        case .midnightGrid:
            return Color(red: 0.25, green: 0.34, blue: 0.72).opacity(0.28)
        case .prismGlass:
            return Color.white.opacity(0.06)
        case .aurora:
            return Color.white.opacity(0.05)
        case .sunset:
            return Color.white.opacity(0.10)
        case .terminal:
            return Color(red: 0.24, green: 0.82, blue: 0.42).opacity(0.12)
        case .sakura:
            return Color(red: 0.86, green: 0.52, blue: 0.64).opacity(0.18)
        case .oceanic:
            return Color(red: 0.32, green: 0.86, blue: 0.92).opacity(0.14)
        case .parchment:
            return Color(red: 0.54, green: 0.38, blue: 0.22).opacity(0.20)
        case .cyberpunk:
            return Color(red: 0.96, green: 0.22, blue: 0.82).opacity(0.18)
        case .sage:
            return Color(red: 0.72, green: 0.82, blue: 0.60).opacity(0.16)
        case .graphite:
            return Color.white.opacity(0.08)
        case .lavender:
            return Color(red: 0.86, green: 0.76, blue: 1.0).opacity(0.14)
        case .blueprint:
            return Color(red: 0.42, green: 0.82, blue: 1.0).opacity(0.22)
        }
    }

    var backdropGradient: [Color] {
        switch self {
        case .cleanCanvas:
            return [
                Color(red: 0.08, green: 0.09, blue: 0.10),
                Color(red: 0.10, green: 0.11, blue: 0.13)
            ]
        case .paper:
            return [
                Color(red: 0.10, green: 0.10, blue: 0.11),
                Color(red: 0.15, green: 0.15, blue: 0.14)
            ]
        case .obsidian:
            return [
                Color(red: 0.04, green: 0.05, blue: 0.06),
                Color(red: 0.08, green: 0.08, blue: 0.10)
            ]
        case .midnightGrid:
            return [
                Color(red: 0.05, green: 0.06, blue: 0.14),
                Color(red: 0.10, green: 0.04, blue: 0.18)
            ]
        case .prismGlass:
            return [
                Color(red: 0.14, green: 0.24, blue: 0.44),
                Color(red: 0.10, green: 0.36, blue: 0.30)
            ]
        case .aurora:
            return [
                Color(red: 0.18, green: 0.22, blue: 0.42),
                Color(red: 0.12, green: 0.40, blue: 0.38),
                Color(red: 0.36, green: 0.18, blue: 0.48)
            ]
        case .sunset:
            return [
                Color(red: 0.38, green: 0.14, blue: 0.28),
                Color(red: 0.20, green: 0.08, blue: 0.22)
            ]
        case .terminal:
            return [
                Color(red: 0.02, green: 0.04, blue: 0.03),
                Color(red: 0.00, green: 0.02, blue: 0.01)
            ]
        case .sakura:
            return [
                Color(red: 0.32, green: 0.16, blue: 0.22),
                Color(red: 0.24, green: 0.12, blue: 0.18)
            ]
        case .oceanic:
            return [
                Color(red: 0.02, green: 0.08, blue: 0.14),
                Color(red: 0.00, green: 0.04, blue: 0.10)
            ]
        case .parchment:
            return [
                Color(red: 0.18, green: 0.12, blue: 0.06),
                Color(red: 0.12, green: 0.08, blue: 0.04)
            ]
        case .cyberpunk:
            return [
                Color(red: 0.04, green: 0.00, blue: 0.10),
                Color(red: 0.08, green: 0.02, blue: 0.16)
            ]
        case .sage:
            return [
                Color(red: 0.08, green: 0.12, blue: 0.10),
                Color(red: 0.04, green: 0.08, blue: 0.06)
            ]
        case .graphite:
            return [
                Color(red: 0.08, green: 0.08, blue: 0.09),
                Color(red: 0.12, green: 0.12, blue: 0.13)
            ]
        case .lavender:
            return [
                Color(red: 0.14, green: 0.10, blue: 0.28),
                Color(red: 0.08, green: 0.06, blue: 0.18)
            ]
        case .blueprint:
            return [
                Color(red: 0.02, green: 0.06, blue: 0.14),
                Color(red: 0.04, green: 0.10, blue: 0.22)
            ]
        }
    }

    var wallpaperDimOpacity: Double {
        switch self {
        case .cleanCanvas:
            return 0.0
        case .paper:
            return 0.18
        case .obsidian:
            return 0.42
        case .midnightGrid:
            return 0.34
        case .prismGlass:
            return 0.26
        case .aurora:
            return 0.20
        case .sunset:
            return 0.36
        case .terminal:
            return 0.52
        case .sakura:
            return 0.14
        case .oceanic:
            return 0.38
        case .parchment:
            return 0.16
        case .cyberpunk:
            return 0.48
        case .sage:
            return 0.36
        case .graphite:
            return 0.40
        case .lavender:
            return 0.32
        case .blueprint:
            return 0.42
        }
    }
}

enum QuickNoteTransparencyMode: String, Codable, CaseIterable, Identifiable {
    case solid
    case material
    case glass

    var id: String { rawValue }

    var label: String {
        switch self {
        case .solid:
            return L10n.string("quickNoteTransparencyMode.solid.label", default: "Solid")
        case .material:
            return L10n.string("quickNoteTransparencyMode.material.label", default: "Material")
        case .glass:
            return L10n.string("quickNoteTransparencyMode.glass.label", default: "Glass")
        }
    }
}

enum QuickNoteFontSize: String, Codable, CaseIterable, Identifiable {
    case xs, s, m, l, xl

    var id: String { rawValue }

    var label: String {
        switch self {
        case .xs: return "XS"
        case .s: return "S"
        case .m: return "M"
        case .l: return "L"
        case .xl: return "XL"
        }
    }

    var basePointSize: CGFloat {
        switch self {
        case .xs: return 12
        case .s: return 14
        case .m: return 16
        case .l: return 18
        case .xl: return 20
        }
    }
}

enum QuickNotePaperType: String, Codable, CaseIterable, Identifiable {
    case blank
    case lined
    case dotted
    case miniSquared
    case squared

    var id: String { rawValue }

    var label: String {
        switch self {
        case .blank: return "Blank"
        case .lined: return "Lined"
        case .dotted: return "Dotted"
        case .miniSquared: return "Mini Squared"
        case .squared: return "Squared"
        }
    }
}

enum QuickNoteFontFamily: String, Codable, CaseIterable, Identifiable {
    case system
    case rounded
    case serif
    case monospaced
    case atkinsonHyperlegible
    case instrumentSans
    case jetBrainsMono
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "SF Pro"
        case .rounded: return "SF Rounded"
        case .serif: return "New York"
        case .monospaced: return "SF Mono"
        case .atkinsonHyperlegible: return "Atkinson"
        case .instrumentSans: return "Instrument"
        case .jetBrainsMono: return "JetBrains Mono"
        case .custom: return "Custom"
        }
    }

    /// Bundled families have a fixed visual identity; the custom case loads a user file.
    var isBundled: Bool { self != .custom }
}

enum QuickNoteFontWeight: String, Codable, CaseIterable, Identifiable {
    case light
    case regular
    case medium
    case semibold
    case bold

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: return "Light"
        case .regular: return "Regular"
        case .medium: return "Medium"
        case .semibold: return "Semibold"
        case .bold: return "Bold"
        }
    }

    var nsFontWeight: NSFont.Weight {
        switch self {
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }
}

struct QuickNoteAppearance: Codable, Equatable {
    var style: QuickNoteStyle = .paper
    var transparencyMode: QuickNoteTransparencyMode = .solid
    var backgroundWallpaper: BackgroundWallpaper = .none
    var customWallpaperFilename: String?
    var wallpaperOffsetX: Double = 0.5
    var wallpaperOffsetY: Double = 0.5
    var surfaceOpacity: Double = 0.94
    /// Opacity of the templated card surface *when a wallpaper is loaded*.
    /// Defaults to 0 so wallpapers shine through cleanly without users having
    /// to discover the existing `surfaceOpacity` slider. The regular
    /// `surfaceOpacity` still drives the no-wallpaper case.
    var cardOpacityOverWallpaper: Double = 0.0
    /// User-chosen text colour as a hex string (e.g. "#FFFFFF"). When nil,
    /// the style's default text colour (or the wallpaper-aware auto pick)
    /// is used.
    var customTextColorHex: String?
    /// When true and a wallpaper is loaded with no `customTextColorHex`,
    /// the editor auto-picks white-or-near-black based on wallpaper luminance
    /// so text stays readable on bright and dark images alike.
    var autoTextColorOnWallpaper: Bool = true
    var fontSize: QuickNoteFontSize = .m
    var paperType: QuickNotePaperType = .dotted
    var fontFamily: QuickNoteFontFamily = .monospaced
    var fontWeight: QuickNoteFontWeight = .regular
    /// Multiplier on the natural line height (1.0 = compact, 2.0 = airy).
    var lineHeightMultiplier: Double = 1.15
    /// Per-character tracking in points (negative tightens, positive opens up).
    var letterSpacing: Double = 0
    /// Extra gap between paragraphs in points.
    var paragraphSpacing: Double = 6
    /// Stored filename inside the custom-fonts directory; only used when `fontFamily == .custom`.
    var customFontFilename: String?
    /// PostScript name resolved at import time so we can build NSFont without re-reading the file.
    var customFontPostScriptName: String?

    var resolvedFontPointSize: CGFloat {
        fontSize.basePointSize
    }

    init(
        style: QuickNoteStyle = .paper,
        transparencyMode: QuickNoteTransparencyMode = .solid,
        backgroundWallpaper: BackgroundWallpaper = .none,
        customWallpaperFilename: String? = nil,
        wallpaperOffsetX: Double = 0.5,
        wallpaperOffsetY: Double = 0.5,
        surfaceOpacity: Double = 0.94,
        cardOpacityOverWallpaper: Double = 0.0,
        customTextColorHex: String? = nil,
        autoTextColorOnWallpaper: Bool = true,
        fontSize: QuickNoteFontSize = .m,
        paperType: QuickNotePaperType = .dotted,
        fontFamily: QuickNoteFontFamily = .monospaced,
        fontWeight: QuickNoteFontWeight = .regular,
        lineHeightMultiplier: Double = 1.15,
        letterSpacing: Double = 0,
        paragraphSpacing: Double = 6,
        customFontFilename: String? = nil,
        customFontPostScriptName: String? = nil
    ) {
        self.style = style
        self.transparencyMode = transparencyMode
        self.backgroundWallpaper = backgroundWallpaper
        self.customWallpaperFilename = customWallpaperFilename
        self.wallpaperOffsetX = wallpaperOffsetX
        self.wallpaperOffsetY = wallpaperOffsetY
        self.surfaceOpacity = surfaceOpacity
        self.cardOpacityOverWallpaper = cardOpacityOverWallpaper
        self.customTextColorHex = customTextColorHex
        self.autoTextColorOnWallpaper = autoTextColorOnWallpaper
        self.fontSize = fontSize
        self.paperType = paperType
        self.fontFamily = fontFamily
        self.fontWeight = fontWeight
        self.lineHeightMultiplier = lineHeightMultiplier
        self.letterSpacing = letterSpacing
        self.paragraphSpacing = paragraphSpacing
        self.customFontFilename = customFontFilename
        self.customFontPostScriptName = customFontPostScriptName
    }

    private enum CodingKeys: String, CodingKey {
        case style, transparencyMode, backgroundWallpaper, customWallpaperFilename
        case wallpaperOffsetX, wallpaperOffsetY, surfaceOpacity
        case cardOpacityOverWallpaper, customTextColorHex, autoTextColorOnWallpaper
        case fontSize, paperType
        case fontFamily, fontWeight
        case lineHeightMultiplier, letterSpacing, paragraphSpacing
        case customFontFilename, customFontPostScriptName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        style = try container.decodeIfPresent(QuickNoteStyle.self, forKey: .style) ?? .paper
        transparencyMode = try container.decodeIfPresent(QuickNoteTransparencyMode.self, forKey: .transparencyMode) ?? .solid
        backgroundWallpaper = try container.decodeIfPresent(BackgroundWallpaper.self, forKey: .backgroundWallpaper) ?? .none
        customWallpaperFilename = try container.decodeIfPresent(String.self, forKey: .customWallpaperFilename)
        wallpaperOffsetX = try container.decodeIfPresent(Double.self, forKey: .wallpaperOffsetX) ?? 0.5
        wallpaperOffsetY = try container.decodeIfPresent(Double.self, forKey: .wallpaperOffsetY) ?? 0.5
        surfaceOpacity = try container.decodeIfPresent(Double.self, forKey: .surfaceOpacity) ?? 0.94
        cardOpacityOverWallpaper = try container.decodeIfPresent(Double.self, forKey: .cardOpacityOverWallpaper) ?? 0.0
        customTextColorHex = try container.decodeIfPresent(String.self, forKey: .customTextColorHex)
        autoTextColorOnWallpaper = try container.decodeIfPresent(Bool.self, forKey: .autoTextColorOnWallpaper) ?? true
        fontSize = try container.decodeIfPresent(QuickNoteFontSize.self, forKey: .fontSize) ?? .m
        paperType = try container.decodeIfPresent(QuickNotePaperType.self, forKey: .paperType) ?? .dotted
        fontFamily = try container.decodeIfPresent(QuickNoteFontFamily.self, forKey: .fontFamily) ?? .monospaced
        fontWeight = try container.decodeIfPresent(QuickNoteFontWeight.self, forKey: .fontWeight) ?? .regular
        lineHeightMultiplier = try container.decodeIfPresent(Double.self, forKey: .lineHeightMultiplier) ?? 1.15
        letterSpacing = try container.decodeIfPresent(Double.self, forKey: .letterSpacing) ?? 0
        paragraphSpacing = try container.decodeIfPresent(Double.self, forKey: .paragraphSpacing) ?? 6
        customFontFilename = try container.decodeIfPresent(String.self, forKey: .customFontFilename)
        customFontPostScriptName = try container.decodeIfPresent(String.self, forKey: .customFontPostScriptName)
    }

    func usesWallpaperAsPrimarySurface(hasLoadedWallpaper: Bool) -> Bool {
        hasLoadedWallpaper && style.isTemplateFree
    }

    func shouldRenderTemplateSurface(hasLoadedWallpaper: Bool) -> Bool {
        !usesWallpaperAsPrimarySurface(hasLoadedWallpaper: hasLoadedWallpaper)
    }

    func shouldRenderMaterialOverlay(hasLoadedWallpaper: Bool) -> Bool {
        shouldRenderTemplateSurface(hasLoadedWallpaper: hasLoadedWallpaper)
            && transparencyMode == .material
    }

    func shouldUseGlassSurface(hasLoadedWallpaper: Bool) -> Bool {
        shouldRenderTemplateSurface(hasLoadedWallpaper: hasLoadedWallpaper)
            && (style.usesVibrancy || transparencyMode == .glass)
    }

    func shouldRenderTemplateChrome(hasLoadedWallpaper: Bool) -> Bool {
        !style.isTemplateFree && shouldRenderTemplateSurface(hasLoadedWallpaper: hasLoadedWallpaper)
    }

    /// Opacity of the templated card surface. When a wallpaper is present we
    /// switch to the wallpaper-specific value so the image isn't muddied by
    /// the style's solid backdrop. The regular `surfaceOpacity` continues to
    /// drive non-wallpaper notes so existing users see no change.
    func resolvedSurfaceOpacity(hasLoadedWallpaper: Bool) -> Double {
        hasLoadedWallpaper ? cardOpacityOverWallpaper : surfaceOpacity
    }

    /// Estimates how bright the popover backdrop is behind the editor content,
    /// blending wallpaper, style card, and overlay opacity the same way
    /// `QuickNoteCardBackground` layers them.
    @MainActor
    func estimatedPopoverBackdropLuminance() -> Double {
        let wallpaperImage = backgroundWallpaper
            .loadImage(customFilename: customWallpaperFilename)
        let hasLoadedWallpaper = wallpaperImage != nil
        let styleLuminance = style.averageCardLuminance

        // Memoized on purpose: this runs inside view bodies that re-evaluate
        // on every keystroke; the uncached region sampler TIFF-encodes the
        // whole wallpaper per call and was a real source of typing lag.
        let wallpaperLuminance: Double? = wallpaperImage.flatMap { image in
            WallpaperLuminanceCache.averageLuminance(
                in: CGRect(x: 0.12, y: 0.08, width: 0.76, height: 0.62),
                of: image
            ) ?? WallpaperLuminanceCache.averageLuminance(of: image)
        }

        if hasLoadedWallpaper {
            let base = wallpaperLuminance ?? styleLuminance
            if usesWallpaperAsPrimarySurface(hasLoadedWallpaper: true) {
                let overlay = resolvedSurfaceOpacity(hasLoadedWallpaper: true)
                guard overlay > 0.001 else { return base }
                return Self.blendBackdropLuminance(base, styleLuminance, surfaceWeight: overlay)
            }
            if shouldRenderTemplateSurface(hasLoadedWallpaper: true) {
                let overlay = resolvedSurfaceOpacity(hasLoadedWallpaper: true)
                guard overlay > 0.001 else { return base }
                return Self.blendBackdropLuminance(base, styleLuminance, surfaceWeight: overlay)
            }
            return base
        }

        if shouldUseGlassSurface(hasLoadedWallpaper: false) {
            return 0.38
        }
        if shouldRenderTemplateSurface(hasLoadedWallpaper: false) {
            return styleLuminance
        }
        return styleLuminance
    }

    private static func blendBackdropLuminance(
        _ backdrop: Double,
        _ surface: Double,
        surfaceWeight: Double
    ) -> Double {
        let weight = min(max(surfaceWeight, 0), 1)
        return backdrop * (1 - weight) + surface * weight
    }

    /// Resolves the colour that text in the editor should render in.
    /// Priority: user override → wallpaper-aware auto pick → style default.
    /// `wallpaperLuminance` is 0 (very dark) ... 1 (very bright), or nil
    /// when no wallpaper is loaded.
    func effectiveTextColor(wallpaperLuminance: Double?) -> Color {
        if let hex = customTextColorHex, !hex.isEmpty {
            return Color(hex: hex)
        }
        if let luminance = wallpaperLuminance, autoTextColorOnWallpaper {
            return ReadableInk.textColor(forBackdropLuminance: luminance)
        }
        return style.textColor
    }
}

/// Shared contrast pick for menu bar popover + Quick Note auto-ink paths.
enum ReadableInk {
    static let brightBackdropThreshold = 0.55

    static func textColor(forBackdropLuminance luminance: Double) -> Color {
        luminance > brightBackdropThreshold
            ? Color(red: 0.10, green: 0.10, blue: 0.12).opacity(0.92)
            : Color.white.opacity(0.96)
    }
}

extension AppSettings {
    /// Resolves ink for the menu bar edit popover — labels, field, hints, footer.
    @MainActor
    func resolvedMenuBarPopoverTextColor(appearance: QuickNoteAppearance) -> Color {
        if let hex = menuBarPopoverTextColorHex, !hex.isEmpty {
            return Color(hex: hex)
        }
        if let hex = appearance.customTextColorHex, !hex.isEmpty {
            return Color(hex: hex)
        }

        if appearance.autoTextColorOnWallpaper {
            let luminance = appearance.estimatedPopoverBackdropLuminance()
            return ReadableInk.textColor(forBackdropLuminance: luminance)
        }

        return appearance.style.textColor
    }
}

struct WorkspaceAppearance: Codable, Equatable {
    var backgroundTheme: BackgroundTheme = .midnight
    var backgroundWallpaper: BackgroundWallpaper = .none
    var customWallpaperFilename: String?
    var wallpaperOffsetX: Double = 0.5
    var wallpaperOffsetY: Double = 0.5
    var backgroundOpacity: Double = 0.72
}

enum WallpaperSlot: String, Codable, CaseIterable {
    case clipboard
    case quickNote
    case workspace

    var filenameStem: String {
        switch self {
        case .clipboard:
            return "custom-wallpaper"
        case .quickNote:
            return "quick-note-wallpaper"
        case .workspace:
            return "workspace-wallpaper"
        }
    }
}

/// How often Pulse refreshes usage data from AI providers.
enum PulseRefreshInterval: String, Codable, CaseIterable {
    case fiveMinutes = "5m"
    case tenMinutes = "10m"
    case fifteenMinutes = "15m"
    case thirtyMinutes = "30m"
    case fortyFiveMinutes = "45m"
    case oneHour = "1h"
    case twoHours = "2h"
    case fourHours = "4h"
    case eightHours = "8h"
    case twelveHours = "12h"
    case oneDay = "1d"

    static let usageRefreshOptions: [PulseRefreshInterval] = [
        .fiveMinutes,
        .tenMinutes,
        .fifteenMinutes,
        .thirtyMinutes,
        .fortyFiveMinutes,
        .oneHour,
        .twoHours
    ]

    static let messageFrequencyOptions: [PulseRefreshInterval] = [
        .fiveMinutes,
        .tenMinutes,
        .fifteenMinutes,
        .thirtyMinutes,
        .fortyFiveMinutes,
        .oneHour,
        .twoHours,
        .fourHours,
        .eightHours,
        .twelveHours,
        .oneDay
    ]

    var seconds: TimeInterval {
        switch self {
        case .fiveMinutes: return 300
        case .tenMinutes: return 600
        case .fifteenMinutes: return 900
        case .thirtyMinutes: return 1800
        case .fortyFiveMinutes: return 2700
        case .oneHour: return 3600
        case .twoHours: return 7200
        case .fourHours: return 14_400
        case .eightHours: return 28_800
        case .twelveHours: return 43_200
        case .oneDay: return 86_400
        }
    }

    var label: String {
        switch self {
        case .fiveMinutes: return L10n.string("pulseRefreshInterval.fiveMinutes.label", default: "5 min")
        case .tenMinutes: return L10n.string("pulseRefreshInterval.tenMinutes.label", default: "10 min")
        case .fifteenMinutes: return L10n.string("pulseRefreshInterval.fifteenMinutes.label", default: "15 min")
        case .thirtyMinutes: return L10n.string("pulseRefreshInterval.thirtyMinutes.label", default: "30 min")
        case .fortyFiveMinutes: return L10n.string("pulseRefreshInterval.fortyFiveMinutes.label", default: "45 min")
        case .oneHour: return L10n.string("pulseRefreshInterval.oneHour.label", default: "1 hour")
        case .twoHours: return L10n.string("pulseRefreshInterval.twoHours.label", default: "2 hours")
        case .fourHours: return L10n.string("pulseRefreshInterval.fourHours.label", default: "4 hours")
        case .eightHours: return L10n.string("pulseRefreshInterval.eightHours.label", default: "8 hours")
        case .twelveHours: return L10n.string("pulseRefreshInterval.twelveHours.label", default: "12 hours")
        case .oneDay: return L10n.string("pulseRefreshInterval.oneDay.label", default: "1 day")
        }
    }
}

enum PulseCharacterTriggerMode: String, Codable, CaseIterable {
    case interval
    case threshold

    var label: String {
        switch self {
        case .interval:
            return L10n.string("pulseCharacterTriggerMode.interval.label", default: "At Refresh")
        case .threshold:
            return L10n.string("pulseCharacterTriggerMode.threshold.label", default: "Every 10%")
        }
    }
}

enum PulseCharacterMessageMode: String, Codable, CaseIterable {
    case usageOnly
    case dailyInspiration
    case custom
    case remindersAndInspiration

    var label: String {
        switch self {
        case .usageOnly: return L10n.string("pulseCharacterMessageMode.usageOnly.label", default: "Usage Only")
        case .dailyInspiration: return L10n.string("pulseCharacterMessageMode.dailyInspiration.label", default: "Inspiration")
        case .custom: return L10n.string("pulseCharacterMessageMode.custom.label", default: "Custom")
        case .remindersAndInspiration: return L10n.string("pulseCharacterMessageMode.remindersAndInspiration.label", default: "Reminders")
        }
    }
}

enum PulseReminderSchedule: String, Codable, CaseIterable {
    case nextPulse
    case thirtyMinutes
    case tomorrow

    var label: String {
        switch self {
        case .nextPulse: return L10n.string("pulseReminderSchedule.nextPulse.label", default: "Next Pulse")
        case .thirtyMinutes: return L10n.string("pulseReminderSchedule.thirtyMinutes.label", default: "In 30 Minutes")
        case .tomorrow: return L10n.string("pulseReminderSchedule.tomorrow.label", default: "Tomorrow")
        }
    }

    func dueDate(from now: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .nextPulse:
            return nil
        case .thirtyMinutes:
            return now.addingTimeInterval(30 * 60)
        case .tomorrow:
            return calendar.date(byAdding: .day, value: 1, to: now)
        }
    }
}

struct PulseReminder: Codable, Identifiable, Equatable {
    var id: UUID
    var message: String
    var sourceTitle: String?
    var createdAt: Date
    var dueAt: Date?
    var deliveredAt: Date?

    init(
        id: UUID = UUID(),
        message: String,
        sourceTitle: String? = nil,
        createdAt: Date = Date(),
        dueAt: Date? = nil,
        deliveredAt: Date? = nil
    ) {
        self.id = id
        self.message = message
        self.sourceTitle = sourceTitle
        self.createdAt = createdAt
        self.dueAt = dueAt
        self.deliveredAt = deliveredAt
    }

    func isDue(at date: Date) -> Bool {
        guard deliveredAt == nil else { return false }
        guard let dueAt else { return true }
        return dueAt <= date
    }
}

struct AppSettings: Codable {
    var appLanguage: AppLanguage = .system
    var historyRetention: HistoryRetention = .week
    var alwaysPlainText: Bool = false
    var pasteToActiveApp: Bool = true
    /// When true, a single click pastes immediately; otherwise requires a double click.
    var singleClickToPaste: Bool = false
    var launchAtLogin: Bool = false
    var showInMenuBar: Bool = true
    /// When true, the menu bar item renders `menuBarCustomText` instead of
    /// the default Jack icon. Empty text falls back to the icon even if the
    /// toggle is on, so users can't end up with an invisible status item.
    var menuBarShowCustomText: Bool = false
    /// User-typed text to display in the menu bar. Trimmed + truncated to a
    /// sensible cap at render time so a runaway string can't blow up the bar.
    var menuBarCustomText: String = ""
    /// Optional hex colour for custom menu bar text (e.g. "#E8A87C"). When nil,
    /// macOS uses the system status-item text colour for the current menu bar.
    var menuBarTextColorHex: String?
    /// Hex colour for text inside the menu bar edit popover — the "Menu bar
    /// text" label, input field, "Press return to save…" hint, and footer.
    /// When nil, the popover picks a readable colour from the wallpaper or style.
    var menuBarPopoverTextColorHex: String?
    /// When true, the menu bar popover replaces its editable text field
    /// with a static, multi-line message (read-only). The menu bar item
    /// itself still reflects `menuBarCustomText` — the message is decoupled
    /// from the menu bar so the user can keep a short label in the bar
    /// and a longer reminder/affirmation/quote in the popover.
    var menuBarPopoverShowMessage: Bool = false
    /// The static message shown in the popover when
    /// `menuBarPopoverShowMessage` is true. Supports markdown (bold, italic,
    /// strikethrough) just like the menu bar text does.
    var menuBarPopoverMessage: String = ""
    /// Independent appearance for the menu bar text editor popover. Reuses
    /// the QuickNoteAppearance struct because the rendering pipeline
    /// (QuickNoteCardBackground) is already built around that type — but
    /// stored separately from `quickNoteAppearance` so the two can be styled
    /// differently. Defaults here use a slightly higher contrast (paper
    /// style + slight transparency) tuned for a small popover surface.
    var menuBarPopoverAppearance: QuickNoteAppearance = {
        var appearance = QuickNoteAppearance()
        appearance.surfaceOpacity = 0.92
        appearance.paperType = .blank
        return appearance
    }()
    var hideFromDock: Bool = false
    var globalShortcut: GlobalShortcut = .default
    /// 0 keeps the original glide; 1 makes tray open/close immediate.
    var trayAnimationSpeed: Double = 0
    var quickNoteShortcut: GlobalShortcut = .quickNoteDefault
    var commandPaletteShortcut: GlobalShortcut = .commandPaletteDefault
    var trackpadRevealBottomEdgeSwipeEnabled: Bool = false
    var trackpadRevealBottomCenterSwipeEnabled: Bool = false
    var backgroundTheme: BackgroundTheme = .scenic
    var clipboardFont: ClipboardFont = .sfPro
    var backgroundOpacity: Double = 0.5
    var backgroundWallpaper: BackgroundWallpaper = .terra
    var hasCompletedOnboarding: Bool = false
    var hasSeenRadialResizeHint: Bool = false
    /// Dev flag: always show onboarding on launch, even if already completed
    var alwaysShowOnboarding: Bool = false
    var smartCategories: SmartCategorySettings = SmartCategorySettings()
    var customBackgroundGradient: GradientSpec?
    var savedColorPresets: [ColorPreset] = []
    var customWallpaperFilename: String?
    var wallpaperOffsetX: Double = 0.5
    var wallpaperOffsetY: Double = 0.5
    var enableImageTextRecognition: Bool = true
    var ocrRecognitionLevelRaw: String = "fast"
    var ocrMinimumTextHeight: Float = 0.02
    var ocrMaxImageMegapixels: Double = 12.0
    var ocrMaxImageBytes: Int = 12 * 1024 * 1024
    var ocrRecognitionLanguages: [String] = ["en-US"]
    var viewMode: ViewMode = .tray
    /// Keeps the tray at its newest edge whenever it opens.
    var scrollToLatestOnShow: Bool = true
    /// Places the newest tray clips at the right edge instead of the left.
    var newestTrayClipsOnRight: Bool = false
    var drawerSide: DrawerSide = .right
    var radialSwipeDirection: RadialSwipeDirection = .natural
    /// Higher means fewer points required per page hop.
    var radialPageSwipeSensitivity: Double = 0.6
    /// Per-type visual overrides for card accents/header gradients. Missing entries use defaults.
    var clipTypeThemes: [String: ClipTypeTheme] = [:]
    /// Legacy UserDefaults-backed trial timestamp retained for migration to Keychain.
    var trialStartedAt: String?
    /// Provider IDs whose skill folders have been linked (e.g. ["claude", "codex"]).
    var linkedSkillProviders: [String] = []
    /// Custom directory paths the user has added manually via folder picker.
    var customSkillPaths: [String] = []
    /// Keep custom-folder tab visibility in settings so the toggle can persist
    /// without forcing a SwiftData schema migration for every folder row.
    var hiddenCustomFolderIDs: [UUID] = []
    var pulseRefreshInterval: PulseRefreshInterval = .fifteenMinutes
    /// Whether dock characters appear on screen.
    var pulseCharactersEnabled: Bool = false
    /// Controls whether Pulse characters speak on scheduled refreshes or only on threshold events.
    var pulseCharacterTriggerMode: PulseCharacterTriggerMode = .interval
    var pulseCharacterMessageMode: PulseCharacterMessageMode = .usageOnly
    var pulseCharacterCustomMessage: String = ""
    var pulseReminders: [PulseReminder] = []
    /// Settings owned by the Jack rebrand. Additive on top of the legacy
    /// `pulseCharacter*` fields above — see `JackSettings.swift`.
    var jackSettings: JackSettings = JackSettings()
    var quickNoteOpenPosition: QuickNoteOpenPosition = .centered
    var quickNoteOpenAnimation: QuickNoteAnimationStyle = .slide
    var quickNoteCloseAnimation: QuickNoteAnimationStyle = .slide
    var reverseQuickNoteSwipeDirection: Bool = false
    /// Top-left previous/next note buttons in Quick Note.
    var quickNoteNavigationControlsStyle: QuickNoteNavigationControlsStyle = .standard
    var quickNoteAppearance: QuickNoteAppearance = QuickNoteAppearance()
    var quickNoteAutoPasteFromClipboard: Bool = false
    /// When true, Quick Note fades to `quickNoteUnfocusedAlpha` whenever the
    /// window resigns key focus, so it feels visually deprioritised while you
    /// work in another app — and snaps back to full opacity when refocused.
    var quickNoteDimWhenUnfocused: Bool = false
    /// Alpha applied to the Quick Note window while unfocused. Clamped 0.15...1
    /// on decode so the window can never become invisible by accident.
    var quickNoteUnfocusedAlpha: Double = 0.55
    var quickNoteWindowWidth: Double = 560
    var quickNoteWindowHeight: Double = 420
    var workspaceAppearance: WorkspaceAppearance = WorkspaceAppearance()
    var workspaceWindowWidth: Double = 1240
    var workspaceWindowHeight: Double = 760
    var mirrorNotesIntoClipboardHistory: Bool = true
    var restoreWorkspaceTabs: Bool = true
    /// User-defined Kanban writing actions (right-click menu + composer chips).
    var kanbanCustomAssistPresets: [KanbanCustomAssistPreset] = []
    /// Panel-mode window width in points. Clamped 260–480 on decode.
    var panelWidth: Double = 320
    /// Panel-mode window height in points. Clamped 320–760 on decode.
    var panelHeight: Double = 520
    /// When true, Panel mode appears centered on the cursor; otherwise it centers on the active screen.
    var panelFollowsCursor: Bool = true

    // MARK: - On-device AI (Apple Intelligence, macOS 26+)
    // These gate Apple's Foundation model features. They are inert on hardware/OS that can't run
    // the model — `OnDeviceAIService` reports the real availability and features hide accordingly.

    /// Master switch for every on-device AI feature. When off, all AI actions hide and the app
    /// behaves exactly as it did before these features existed.
    var aiFeaturesEnabled: Bool = true
    /// Manual, user-triggered per-clip AI actions (summarize, rewrite, retitle, extract).
    var aiClipActionsEnabled: Bool = true
    /// Automatically generate a short title for long text clips as they're captured. Off by default
    /// because it runs on ingest; opt-in so capture stays instant for people who don't want it.
    var aiAutoTitleEnabled: Bool = false
    /// AI-assisted tagging + folder suggestions layered on top of the deterministic
    /// `ContentClassifier`. Off by default (runs on ingest).
    var aiSmartTaggingEnabled: Bool = false
    /// Summarize / rewrite / retitle actions inside Quick Notes and the workspace editor.
    var aiNoteAssistEnabled: Bool = true
    /// Prefer Apple's on-device model for meeting summaries and Q&A when available, falling back to
    /// the bundled Qwen model otherwise. Avoids the multi-gigabyte download when Apple's model works.
    var aiMeetingPreferAppleModel: Bool = true
    /// Detect actionable text in clips and offer to create a Reminder from it.
    var aiReminderExtractionEnabled: Bool = true
    /// Interpret natural-language search queries into structured filters. Off by default because it
    /// adds a model round-trip to searching; opt-in for people who want it.
    var aiNaturalLanguageSearchEnabled: Bool = false

    /// Security-scoped bookmark to the user's chosen Obsidian vault root folder.
    /// `nil` = no vault chosen. Resolved via NoteVaultBookmarkService so access
    /// survives relaunch (and is sandbox/MAS-ready).
    var notesVaultBookmark: Data?
    /// Cosmetic path of the chosen vault (e.g. "~/Vaults/Main"), shown in
    /// Settings and the picker header. Never used to resolve access — the
    /// bookmark is the source of truth for the actual location.
    var notesVaultDisplayPath: String?

    init() {}

    private enum CodingKeys: String, CodingKey {
        case appLanguage
        case historyRetention
        case alwaysPlainText
        case pasteToActiveApp
        case singleClickToPaste
        case launchAtLogin
        case showInMenuBar
        case menuBarShowCustomText
        case menuBarCustomText
        case menuBarTextColorHex
        case menuBarPopoverTextColorHex
        case menuBarPopoverShowMessage
        case menuBarPopoverMessage
        case menuBarPopoverAppearance
        case hideFromDock
        case globalShortcut
        case trayAnimationSpeed
        case quickNoteShortcut
        case commandPaletteShortcut
        case trackpadRevealBottomEdgeSwipeEnabled
        case trackpadRevealBottomCenterSwipeEnabled
        case backgroundTheme
        case clipboardFont
        case backgroundOpacity
        case backgroundWallpaper
        case hasCompletedOnboarding
        case hasSeenRadialResizeHint
        case alwaysShowOnboarding
        case smartCategories
        case customBackgroundGradient
        case savedColorPresets
        case customWallpaperFilename
        case wallpaperOffsetX
        case wallpaperOffsetY
        case enableImageTextRecognition
        case ocrRecognitionLevelRaw
        case ocrMinimumTextHeight
        case ocrMaxImageMegapixels
        case ocrMaxImageBytes
        case ocrRecognitionLanguages
        case viewMode
        case scrollToLatestOnShow
        case newestTrayClipsOnRight
        case drawerSide
        case radialSwipeDirection
        case radialPageSwipeSensitivity
        case clipTypeThemes
        case trialStartedAt
        case linkedSkillProviders
        case customSkillPaths
        case hiddenCustomFolderIDs
        case pulseRefreshInterval
        case pulseCharactersEnabled
        case pulseCharacterTriggerMode
        case pulseCharacterMessageMode
        case pulseCharacterCustomMessage
        case pulseReminders
        case jackSettings
        case quickNoteOpenPosition
        case quickNoteOpenAnimation
        case quickNoteCloseAnimation
        case reverseQuickNoteSwipeDirection
        case quickNoteNavigationControlsStyle
        case quickNoteAppearance
        case quickNoteAutoPasteFromClipboard
        case quickNoteDimWhenUnfocused
        case quickNoteUnfocusedAlpha
        case quickNoteWindowWidth
        case quickNoteWindowHeight
        case workspaceAppearance
        case workspaceWindowWidth
        case workspaceWindowHeight
        case mirrorNotesIntoClipboardHistory
        case restoreWorkspaceTabs
        case kanbanCustomAssistPresets
        case panelWidth
        case panelHeight
        case panelFollowsCursor
        case aiFeaturesEnabled
        case aiClipActionsEnabled
        case aiAutoTitleEnabled
        case aiSmartTaggingEnabled
        case aiNoteAssistEnabled
        case aiMeetingPreferAppleModel
        case aiReminderExtractionEnabled
        case aiNaturalLanguageSearchEnabled
        case notesVaultBookmark
        case notesVaultDisplayPath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appLanguage = try container.decodeIfPresent(AppLanguage.self, forKey: .appLanguage) ?? .system
        historyRetention = try container.decodeIfPresent(HistoryRetention.self, forKey: .historyRetention) ?? .week
        alwaysPlainText = try container.decodeIfPresent(Bool.self, forKey: .alwaysPlainText) ?? false
        pasteToActiveApp = try container.decodeIfPresent(Bool.self, forKey: .pasteToActiveApp) ?? true
        singleClickToPaste = try container.decodeIfPresent(Bool.self, forKey: .singleClickToPaste) ?? false
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        showInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showInMenuBar) ?? true
        menuBarShowCustomText = try container.decodeIfPresent(Bool.self, forKey: .menuBarShowCustomText) ?? false
        menuBarCustomText = try container.decodeIfPresent(String.self, forKey: .menuBarCustomText) ?? ""
        menuBarTextColorHex = try container.decodeIfPresent(String.self, forKey: .menuBarTextColorHex)
        menuBarPopoverTextColorHex = try container.decodeIfPresent(String.self, forKey: .menuBarPopoverTextColorHex)
        menuBarPopoverShowMessage = try container.decodeIfPresent(Bool.self, forKey: .menuBarPopoverShowMessage) ?? false
        menuBarPopoverMessage = try container.decodeIfPresent(String.self, forKey: .menuBarPopoverMessage) ?? ""
        if let decoded = try container.decodeIfPresent(QuickNoteAppearance.self, forKey: .menuBarPopoverAppearance) {
            menuBarPopoverAppearance = decoded
        } else {
            var fallback = QuickNoteAppearance()
            fallback.surfaceOpacity = 0.92
            fallback.paperType = .blank
            menuBarPopoverAppearance = fallback
        }
        // Older builds stored popover ink only on the appearance blob.
        if menuBarPopoverTextColorHex == nil,
           let legacy = menuBarPopoverAppearance.customTextColorHex,
           !legacy.isEmpty {
            menuBarPopoverTextColorHex = legacy
        }
        hideFromDock = try container.decodeIfPresent(Bool.self, forKey: .hideFromDock) ?? false
        globalShortcut = try container.decodeIfPresent(GlobalShortcut.self, forKey: .globalShortcut) ?? .default
        trayAnimationSpeed = min(
            max(try container.decodeIfPresent(Double.self, forKey: .trayAnimationSpeed) ?? 0, 0),
            1
        )
        quickNoteShortcut = try container.decodeIfPresent(GlobalShortcut.self, forKey: .quickNoteShortcut) ?? .quickNoteDefault
        commandPaletteShortcut = try container.decodeIfPresent(GlobalShortcut.self, forKey: .commandPaletteShortcut) ?? .commandPaletteDefault
        trackpadRevealBottomEdgeSwipeEnabled = try container.decodeIfPresent(Bool.self, forKey: .trackpadRevealBottomEdgeSwipeEnabled) ?? false
        trackpadRevealBottomCenterSwipeEnabled = try container.decodeIfPresent(Bool.self, forKey: .trackpadRevealBottomCenterSwipeEnabled) ?? false
        backgroundTheme = try container.decodeIfPresent(BackgroundTheme.self, forKey: .backgroundTheme) ?? .scenic
        clipboardFont = try container.decodeIfPresent(ClipboardFont.self, forKey: .clipboardFont) ?? .sfPro
        backgroundOpacity = try container.decodeIfPresent(Double.self, forKey: .backgroundOpacity) ?? 0.5
        backgroundWallpaper = try container.decodeIfPresent(BackgroundWallpaper.self, forKey: .backgroundWallpaper) ?? .terra
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
        hasSeenRadialResizeHint = try container.decodeIfPresent(Bool.self, forKey: .hasSeenRadialResizeHint) ?? false
        alwaysShowOnboarding = try container.decodeIfPresent(Bool.self, forKey: .alwaysShowOnboarding) ?? false
        smartCategories = try container.decodeIfPresent(SmartCategorySettings.self, forKey: .smartCategories) ?? SmartCategorySettings()
        customBackgroundGradient = try container.decodeIfPresent(GradientSpec.self, forKey: .customBackgroundGradient)
        savedColorPresets = try container.decodeIfPresent([ColorPreset].self, forKey: .savedColorPresets) ?? []
        customWallpaperFilename = try container.decodeIfPresent(String.self, forKey: .customWallpaperFilename)
        wallpaperOffsetX = try container.decodeIfPresent(Double.self, forKey: .wallpaperOffsetX) ?? 0.5
        wallpaperOffsetY = try container.decodeIfPresent(Double.self, forKey: .wallpaperOffsetY) ?? 0.5
        enableImageTextRecognition = try container.decodeIfPresent(Bool.self, forKey: .enableImageTextRecognition) ?? true
        ocrRecognitionLevelRaw = try container.decodeIfPresent(String.self, forKey: .ocrRecognitionLevelRaw) ?? "fast"
        ocrMinimumTextHeight = min(
            max(try container.decodeIfPresent(Float.self, forKey: .ocrMinimumTextHeight) ?? 0.02, 0.0),
            1.0
        )
        ocrMaxImageMegapixels = max(try container.decodeIfPresent(Double.self, forKey: .ocrMaxImageMegapixels) ?? 12.0, 0.5)
        ocrMaxImageBytes = max(try container.decodeIfPresent(Int.self, forKey: .ocrMaxImageBytes) ?? (12 * 1024 * 1024), 256 * 1024)
        ocrRecognitionLanguages = try container.decodeIfPresent([String].self, forKey: .ocrRecognitionLanguages) ?? ["en-US"]
        if ocrRecognitionLanguages.isEmpty {
            ocrRecognitionLanguages = ["en-US"]
        }
        viewMode = try container.decodeIfPresent(ViewMode.self, forKey: .viewMode) ?? .tray
        scrollToLatestOnShow = try container.decodeIfPresent(Bool.self, forKey: .scrollToLatestOnShow) ?? true
        newestTrayClipsOnRight = try container.decodeIfPresent(Bool.self, forKey: .newestTrayClipsOnRight) ?? false
        drawerSide = try container.decodeIfPresent(DrawerSide.self, forKey: .drawerSide) ?? .right
        radialSwipeDirection = try container.decodeIfPresent(RadialSwipeDirection.self, forKey: .radialSwipeDirection) ?? .natural
        radialPageSwipeSensitivity = min(
            max(try container.decodeIfPresent(Double.self, forKey: .radialPageSwipeSensitivity) ?? 0.6, 0.4),
            1.6
        )
        clipTypeThemes = try container.decodeIfPresent([String: ClipTypeTheme].self, forKey: .clipTypeThemes) ?? [:]
        trialStartedAt = try container.decodeIfPresent(String.self, forKey: .trialStartedAt)
        linkedSkillProviders = try container.decodeIfPresent([String].self, forKey: .linkedSkillProviders) ?? []
        customSkillPaths = try container.decodeIfPresent([String].self, forKey: .customSkillPaths) ?? []
        hiddenCustomFolderIDs = try container.decodeIfPresent([UUID].self, forKey: .hiddenCustomFolderIDs) ?? []
        pulseRefreshInterval = try container.decodeIfPresent(PulseRefreshInterval.self, forKey: .pulseRefreshInterval) ?? .fifteenMinutes
        pulseCharactersEnabled = try container.decodeIfPresent(Bool.self, forKey: .pulseCharactersEnabled) ?? false
        pulseCharacterTriggerMode = try container.decodeIfPresent(PulseCharacterTriggerMode.self, forKey: .pulseCharacterTriggerMode) ?? .interval
        pulseCharacterMessageMode = try container.decodeIfPresent(PulseCharacterMessageMode.self, forKey: .pulseCharacterMessageMode) ?? .usageOnly
        pulseCharacterCustomMessage = try container.decodeIfPresent(String.self, forKey: .pulseCharacterCustomMessage) ?? ""
        pulseReminders = try container.decodeIfPresent([PulseReminder].self, forKey: .pulseReminders) ?? []
        // Decode the Jack rebrand settings. If a settings file pre-dates the
        // Jack work it won't have this key — migrate from the legacy
        // `pulseCharactersEnabled` flag so returning users don't lose their
        // existing "characters on/off" preference.
        if let stored = try container.decodeIfPresent(JackSettings.self, forKey: .jackSettings) {
            jackSettings = stored
        } else {
            jackSettings = JackSettings.migrating(fromLegacyPulseCharactersEnabled: pulseCharactersEnabled)
        }
        quickNoteOpenPosition = try container.decodeIfPresent(QuickNoteOpenPosition.self, forKey: .quickNoteOpenPosition) ?? .centered
        quickNoteOpenAnimation = try container.decodeIfPresent(QuickNoteAnimationStyle.self, forKey: .quickNoteOpenAnimation) ?? .slide
        quickNoteCloseAnimation = try container.decodeIfPresent(QuickNoteAnimationStyle.self, forKey: .quickNoteCloseAnimation) ?? .slide
        reverseQuickNoteSwipeDirection = try container.decodeIfPresent(Bool.self, forKey: .reverseQuickNoteSwipeDirection) ?? false
        quickNoteNavigationControlsStyle = try container.decodeIfPresent(
            QuickNoteNavigationControlsStyle.self,
            forKey: .quickNoteNavigationControlsStyle
        ) ?? .standard
        quickNoteAppearance = try container.decodeIfPresent(QuickNoteAppearance.self, forKey: .quickNoteAppearance) ?? QuickNoteAppearance()
        quickNoteAutoPasteFromClipboard = try container.decodeIfPresent(Bool.self, forKey: .quickNoteAutoPasteFromClipboard) ?? false
        quickNoteDimWhenUnfocused = try container.decodeIfPresent(Bool.self, forKey: .quickNoteDimWhenUnfocused) ?? false
        // Clamp so a misconfigured value can never make the window invisible.
        let rawUnfocused = try container.decodeIfPresent(Double.self, forKey: .quickNoteUnfocusedAlpha) ?? 0.55
        quickNoteUnfocusedAlpha = min(max(rawUnfocused, 0.15), 1.0)
        quickNoteWindowWidth = max(try container.decodeIfPresent(Double.self, forKey: .quickNoteWindowWidth) ?? 560, 320)
        quickNoteWindowHeight = max(try container.decodeIfPresent(Double.self, forKey: .quickNoteWindowHeight) ?? 420, 220)
        workspaceAppearance = try container.decodeIfPresent(WorkspaceAppearance.self, forKey: .workspaceAppearance) ?? WorkspaceAppearance()
        workspaceWindowWidth = min(
            max(try container.decodeIfPresent(Double.self, forKey: .workspaceWindowWidth) ?? 1240, 960),
            1800
        )
        workspaceWindowHeight = min(
            max(try container.decodeIfPresent(Double.self, forKey: .workspaceWindowHeight) ?? 760, 620),
            1400
        )
        mirrorNotesIntoClipboardHistory = try container.decodeIfPresent(Bool.self, forKey: .mirrorNotesIntoClipboardHistory) ?? true
        restoreWorkspaceTabs = try container.decodeIfPresent(Bool.self, forKey: .restoreWorkspaceTabs) ?? true
        kanbanCustomAssistPresets = try container.decodeIfPresent(
            [KanbanCustomAssistPreset].self,
            forKey: .kanbanCustomAssistPresets
        ) ?? []
        panelWidth = min(
            max(try container.decodeIfPresent(Double.self, forKey: .panelWidth) ?? 320, 260),
            480
        )
        panelHeight = min(
            max(try container.decodeIfPresent(Double.self, forKey: .panelHeight) ?? 520, 320),
            760
        )
        panelFollowsCursor = try container.decodeIfPresent(Bool.self, forKey: .panelFollowsCursor) ?? true
        aiFeaturesEnabled = try container.decodeIfPresent(Bool.self, forKey: .aiFeaturesEnabled) ?? true
        aiClipActionsEnabled = try container.decodeIfPresent(Bool.self, forKey: .aiClipActionsEnabled) ?? true
        aiAutoTitleEnabled = try container.decodeIfPresent(Bool.self, forKey: .aiAutoTitleEnabled) ?? false
        aiSmartTaggingEnabled = try container.decodeIfPresent(Bool.self, forKey: .aiSmartTaggingEnabled) ?? false
        aiNoteAssistEnabled = try container.decodeIfPresent(Bool.self, forKey: .aiNoteAssistEnabled) ?? true
        aiMeetingPreferAppleModel = try container.decodeIfPresent(Bool.self, forKey: .aiMeetingPreferAppleModel) ?? true
        aiReminderExtractionEnabled = try container.decodeIfPresent(Bool.self, forKey: .aiReminderExtractionEnabled) ?? true
        aiNaturalLanguageSearchEnabled = try container.decodeIfPresent(Bool.self, forKey: .aiNaturalLanguageSearchEnabled) ?? false
        notesVaultBookmark = try container.decodeIfPresent(Data.self, forKey: .notesVaultBookmark)
        notesVaultDisplayPath = try container.decodeIfPresent(String.self, forKey: .notesVaultDisplayPath)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(historyRetention, forKey: .historyRetention)
        try container.encode(alwaysPlainText, forKey: .alwaysPlainText)
        try container.encode(pasteToActiveApp, forKey: .pasteToActiveApp)
        try container.encode(singleClickToPaste, forKey: .singleClickToPaste)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encode(showInMenuBar, forKey: .showInMenuBar)
        try container.encode(menuBarShowCustomText, forKey: .menuBarShowCustomText)
        try container.encode(menuBarCustomText, forKey: .menuBarCustomText)
        try container.encode(menuBarTextColorHex, forKey: .menuBarTextColorHex)
        try container.encode(menuBarPopoverTextColorHex, forKey: .menuBarPopoverTextColorHex)
        try container.encode(menuBarPopoverShowMessage, forKey: .menuBarPopoverShowMessage)
        try container.encode(menuBarPopoverMessage, forKey: .menuBarPopoverMessage)
        try container.encode(menuBarPopoverAppearance, forKey: .menuBarPopoverAppearance)
        try container.encode(hideFromDock, forKey: .hideFromDock)
        try container.encode(globalShortcut, forKey: .globalShortcut)
        try container.encode(min(max(trayAnimationSpeed, 0), 1), forKey: .trayAnimationSpeed)
        try container.encode(quickNoteShortcut, forKey: .quickNoteShortcut)
        try container.encode(commandPaletteShortcut, forKey: .commandPaletteShortcut)
        try container.encode(trackpadRevealBottomEdgeSwipeEnabled, forKey: .trackpadRevealBottomEdgeSwipeEnabled)
        try container.encode(trackpadRevealBottomCenterSwipeEnabled, forKey: .trackpadRevealBottomCenterSwipeEnabled)
        try container.encode(backgroundTheme, forKey: .backgroundTheme)
        try container.encode(clipboardFont, forKey: .clipboardFont)
        try container.encode(backgroundOpacity, forKey: .backgroundOpacity)
        try container.encode(backgroundWallpaper, forKey: .backgroundWallpaper)
        try container.encode(hasCompletedOnboarding, forKey: .hasCompletedOnboarding)
        try container.encode(hasSeenRadialResizeHint, forKey: .hasSeenRadialResizeHint)
        try container.encode(alwaysShowOnboarding, forKey: .alwaysShowOnboarding)
        try container.encode(smartCategories, forKey: .smartCategories)
        try container.encodeIfPresent(customBackgroundGradient, forKey: .customBackgroundGradient)
        try container.encode(savedColorPresets, forKey: .savedColorPresets)
        try container.encodeIfPresent(customWallpaperFilename, forKey: .customWallpaperFilename)
        try container.encode(wallpaperOffsetX, forKey: .wallpaperOffsetX)
        try container.encode(wallpaperOffsetY, forKey: .wallpaperOffsetY)
        try container.encode(enableImageTextRecognition, forKey: .enableImageTextRecognition)
        try container.encode(ocrRecognitionLevelRaw, forKey: .ocrRecognitionLevelRaw)
        try container.encode(min(max(ocrMinimumTextHeight, 0.0), 1.0), forKey: .ocrMinimumTextHeight)
        try container.encode(max(ocrMaxImageMegapixels, 0.5), forKey: .ocrMaxImageMegapixels)
        try container.encode(max(ocrMaxImageBytes, 256 * 1024), forKey: .ocrMaxImageBytes)
        try container.encode(ocrRecognitionLanguages.isEmpty ? ["en-US"] : ocrRecognitionLanguages, forKey: .ocrRecognitionLanguages)
        try container.encode(viewMode, forKey: .viewMode)
        try container.encode(scrollToLatestOnShow, forKey: .scrollToLatestOnShow)
        try container.encode(newestTrayClipsOnRight, forKey: .newestTrayClipsOnRight)
        try container.encode(drawerSide, forKey: .drawerSide)
        try container.encode(radialSwipeDirection, forKey: .radialSwipeDirection)
        try container.encode(
            min(max(radialPageSwipeSensitivity, 0.4), 1.6),
            forKey: .radialPageSwipeSensitivity
        )
        try container.encode(clipTypeThemes, forKey: .clipTypeThemes)
        try container.encodeIfPresent(trialStartedAt, forKey: .trialStartedAt)
        try container.encode(linkedSkillProviders, forKey: .linkedSkillProviders)
        try container.encode(customSkillPaths, forKey: .customSkillPaths)
        try container.encode(hiddenCustomFolderIDs, forKey: .hiddenCustomFolderIDs)
        try container.encode(pulseRefreshInterval, forKey: .pulseRefreshInterval)
        try container.encode(pulseCharactersEnabled, forKey: .pulseCharactersEnabled)
        try container.encode(pulseCharacterTriggerMode, forKey: .pulseCharacterTriggerMode)
        try container.encode(pulseCharacterMessageMode, forKey: .pulseCharacterMessageMode)
        try container.encode(pulseCharacterCustomMessage, forKey: .pulseCharacterCustomMessage)
        try container.encode(pulseReminders, forKey: .pulseReminders)
        try container.encode(jackSettings, forKey: .jackSettings)
        try container.encode(quickNoteOpenPosition, forKey: .quickNoteOpenPosition)
        try container.encode(quickNoteOpenAnimation, forKey: .quickNoteOpenAnimation)
        try container.encode(quickNoteCloseAnimation, forKey: .quickNoteCloseAnimation)
        try container.encode(reverseQuickNoteSwipeDirection, forKey: .reverseQuickNoteSwipeDirection)
        try container.encode(quickNoteNavigationControlsStyle, forKey: .quickNoteNavigationControlsStyle)
        try container.encode(quickNoteAppearance, forKey: .quickNoteAppearance)
        try container.encode(quickNoteAutoPasteFromClipboard, forKey: .quickNoteAutoPasteFromClipboard)
        try container.encode(quickNoteDimWhenUnfocused, forKey: .quickNoteDimWhenUnfocused)
        try container.encode(min(max(quickNoteUnfocusedAlpha, 0.15), 1.0), forKey: .quickNoteUnfocusedAlpha)
        try container.encode(max(quickNoteWindowWidth, 320), forKey: .quickNoteWindowWidth)
        try container.encode(max(quickNoteWindowHeight, 220), forKey: .quickNoteWindowHeight)
        try container.encode(workspaceAppearance, forKey: .workspaceAppearance)
        try container.encode(min(max(workspaceWindowWidth, 960), 1800), forKey: .workspaceWindowWidth)
        try container.encode(min(max(workspaceWindowHeight, 620), 1400), forKey: .workspaceWindowHeight)
        try container.encode(mirrorNotesIntoClipboardHistory, forKey: .mirrorNotesIntoClipboardHistory)
        try container.encode(restoreWorkspaceTabs, forKey: .restoreWorkspaceTabs)
        try container.encode(kanbanCustomAssistPresets, forKey: .kanbanCustomAssistPresets)
        try container.encode(min(max(panelWidth, 260), 480), forKey: .panelWidth)
        try container.encode(min(max(panelHeight, 320), 760), forKey: .panelHeight)
        try container.encode(panelFollowsCursor, forKey: .panelFollowsCursor)
        try container.encode(aiFeaturesEnabled, forKey: .aiFeaturesEnabled)
        try container.encode(aiClipActionsEnabled, forKey: .aiClipActionsEnabled)
        try container.encode(aiAutoTitleEnabled, forKey: .aiAutoTitleEnabled)
        try container.encode(aiSmartTaggingEnabled, forKey: .aiSmartTaggingEnabled)
        try container.encode(aiNoteAssistEnabled, forKey: .aiNoteAssistEnabled)
        try container.encode(aiMeetingPreferAppleModel, forKey: .aiMeetingPreferAppleModel)
        try container.encode(aiReminderExtractionEnabled, forKey: .aiReminderExtractionEnabled)
        try container.encode(aiNaturalLanguageSearchEnabled, forKey: .aiNaturalLanguageSearchEnabled)
        try container.encodeIfPresent(notesVaultBookmark, forKey: .notesVaultBookmark)
        try container.encodeIfPresent(notesVaultDisplayPath, forKey: .notesVaultDisplayPath)
    }
}

extension AppSettings {
    func clipboardUIFont(size: CGFloat, weight: Font.Weight = .regular, forceMonospaced: Bool = false) -> Font {
        clipboardFont.font(size: size, weight: weight, forceMonospaced: forceMonospaced)
    }

    func isCustomFolderVisible(_ folderID: UUID) -> Bool {
        !hiddenCustomFolderIDs.contains(folderID)
    }

    mutating func setCustomFolderVisibility(_ isVisible: Bool, for folderID: UUID) {
        if isVisible {
            hiddenCustomFolderIDs.removeAll { $0 == folderID }
            return
        }

        if !hiddenCustomFolderIDs.contains(folderID) {
            hiddenCustomFolderIDs.append(folderID)
        }
    }

    func isFolderVisibleInTabs(_ folder: ClipFolderModel) -> Bool {
        // The core Clipboard tab is the home folder and can never be hidden.
        if folder.folderID == ClipFolderModel.clipboardID {
            return true
        }
        // Smart folders only exist while their category is enabled, so while
        // present they always show — visibility is governed by Smart Categories.
        if folder.isSmartFolder {
            return true
        }
        // Custom folders AND linked skill folders (which are system folders)
        // honor the hidden set so either can be hidden from the tab bar.
        return isCustomFolderVisible(folder.folderID)
    }

    func clipTypeTheme(for type: ClipType) -> ClipTypeTheme {
        clipTypeThemes[type.rawValue] ?? ClipTypePresentation.defaultTheme(for: type)
    }

    mutating func setClipTypeTheme(_ theme: ClipTypeTheme, for type: ClipType) {
        clipTypeThemes[type.rawValue] = theme
    }

    mutating func resetClipTypeTheme(for type: ClipType) {
        clipTypeThemes.removeValue(forKey: type.rawValue)
    }

    mutating func resetAllClipTypeThemes() {
        clipTypeThemes.removeAll()
    }

}
