import AppKit
import CoreText
import Foundation
import SwiftUI

struct BundledFontCatalog {
    struct Asset: Hashable {
        let resourceName: String
        let fileExtension: String
        let subdirectory: String
        let postScriptName: String
    }

    static let assets: [Asset] = [
        Asset(
            resourceName: "AtkinsonHyperlegible-Regular",
            fileExtension: "ttf",
            subdirectory: "Resources/Fonts/Atkinson",
            postScriptName: "AtkinsonHyperlegible-Regular"
        ),
        Asset(
            resourceName: "AtkinsonHyperlegible-Bold",
            fileExtension: "ttf",
            subdirectory: "Resources/Fonts/Atkinson",
            postScriptName: "AtkinsonHyperlegible-Bold"
        ),
        Asset(
            resourceName: "InstrumentSans-Regular",
            fileExtension: "ttf",
            subdirectory: "Resources/Fonts/Instrument",
            postScriptName: "InstrumentSans-Regular"
        ),
        Asset(
            resourceName: "InstrumentSans-Medium",
            fileExtension: "ttf",
            subdirectory: "Resources/Fonts/Instrument",
            postScriptName: "InstrumentSans-Medium"
        ),
        Asset(
            resourceName: "InstrumentSans-SemiBold",
            fileExtension: "ttf",
            subdirectory: "Resources/Fonts/Instrument",
            postScriptName: "InstrumentSans-SemiBold"
        ),
        Asset(
            resourceName: "InstrumentSans-Bold",
            fileExtension: "ttf",
            subdirectory: "Resources/Fonts/Instrument",
            postScriptName: "InstrumentSans-Bold"
        ),
        Asset(
            resourceName: "JetBrainsMono-Regular",
            fileExtension: "ttf",
            subdirectory: "Resources/Fonts/JetBrains",
            postScriptName: "JetBrainsMono-Regular"
        ),
        Asset(
            resourceName: "JetBrainsMono-Medium",
            fileExtension: "ttf",
            subdirectory: "Resources/Fonts/JetBrains",
            postScriptName: "JetBrainsMono-Medium"
        ),
        Asset(
            resourceName: "JetBrainsMono-SemiBold",
            fileExtension: "ttf",
            subdirectory: "Resources/Fonts/JetBrains",
            postScriptName: "JetBrainsMono-SemiBold"
        ),
        Asset(
            resourceName: "JetBrainsMono-Bold",
            fileExtension: "ttf",
            subdirectory: "Resources/Fonts/JetBrains",
            postScriptName: "JetBrainsMono-Bold"
        ),
    ]

    static func registerBundledFonts() {
        for asset in assets {
            guard let url = AppResourceLocator.url(
                forResource: asset.resourceName,
                withExtension: asset.fileExtension,
                subdirectory: asset.subdirectory
            ) else {
                continue
            }

            var registrationError: Unmanaged<CFError>?
            let registered = CTFontManagerRegisterFontsForURL(
                url as CFURL,
                .process,
                &registrationError
            )

            if registered {
                continue
            }

            guard let error = registrationError?.takeRetainedValue() else {
                continue
            }

            let nsError = error as Error as NSError
            // Registering the same font again in a new window/session path is harmless.
            if nsError.domain == kCTFontManagerErrorDomain as String,
               nsError.code == CTFontManagerError.alreadyRegistered.rawValue {
                continue
            }
        }
    }

    static func font(
        for selection: ClipboardFont,
        size: CGFloat,
        weight: Font.Weight = .regular,
        forceMonospaced: Bool = false
    ) -> Font {
        if forceMonospaced {
            switch selection {
            case .sfMono:
                return .system(size: size, weight: weight, design: .monospaced)
            case .jetBrainsMono:
                return resolvedCustomFont(postScriptName(for: .jetBrainsMono, weight: weight), size: size) ??
                    .system(size: size, weight: weight, design: .monospaced)
            default:
                return .system(size: size, weight: weight, design: .monospaced)
            }
        }

        switch selection {
        case .sfPro:
            return .system(size: size, weight: weight, design: .default)
        case .sfRounded:
            return .system(size: size, weight: weight, design: .rounded)
        case .sfMono:
            return .system(size: size, weight: weight, design: .monospaced)
        case .atkinsonHyperlegible, .instrumentSans, .jetBrainsMono:
            return resolvedCustomFont(postScriptName(for: selection, weight: weight), size: size) ??
                .system(size: size, weight: weight, design: .default)
        }
    }

    static func appKitFont(
        for selection: ClipboardFont,
        matching existingFont: NSFont?,
        forceMonospaced: Bool = false
    ) -> NSFont? {
        guard let existingFont else { return nil }

        let size = existingFont.pointSize
        let weight = appKitWeight(for: existingFont)

        if forceMonospaced {
            switch selection {
            case .sfMono:
                return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
            case .jetBrainsMono:
                return NSFont(name: postScriptName(for: .jetBrainsMono, weight: swiftUIWeight(for: weight)), size: size)
                    ?? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
            default:
                return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
            }
        }

        switch selection {
        case .sfPro:
            return NSFont.systemFont(ofSize: size, weight: weight)
        case .sfRounded:
            let base = NSFont.systemFont(ofSize: size, weight: weight)
            if let descriptor = base.fontDescriptor.withDesign(.rounded) {
                return NSFont(descriptor: descriptor, size: size)
            }
            return base
        case .sfMono:
            return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        case .atkinsonHyperlegible, .instrumentSans, .jetBrainsMono:
            return NSFont(
                name: postScriptName(for: selection, weight: swiftUIWeight(for: weight)),
                size: size
            ) ?? NSFont.systemFont(ofSize: size, weight: weight)
        }
    }

    private static func resolvedCustomFont(_ postScriptName: String, size: CGFloat) -> Font? {
        guard NSFont(name: postScriptName, size: size) != nil else { return nil }
        return .custom(postScriptName, size: size)
    }

    private static func postScriptName(for selection: ClipboardFont, weight: Font.Weight) -> String {
        switch selection {
        case .atkinsonHyperlegible:
            switch bucket(for: weight) {
            case .semibold, .bold:
                return "AtkinsonHyperlegible-Bold"
            case .regular, .medium:
                return "AtkinsonHyperlegible-Regular"
            }
        case .instrumentSans:
            switch bucket(for: weight) {
            case .regular:
                return "InstrumentSans-Regular"
            case .medium:
                return "InstrumentSans-Medium"
            case .semibold:
                return "InstrumentSans-SemiBold"
            case .bold:
                return "InstrumentSans-Bold"
            }
        case .jetBrainsMono, .sfMono:
            switch bucket(for: weight) {
            case .regular:
                return "JetBrainsMono-Regular"
            case .medium:
                return "JetBrainsMono-Medium"
            case .semibold:
                return "JetBrainsMono-SemiBold"
            case .bold:
                return "JetBrainsMono-Bold"
            }
        case .sfPro, .sfRounded:
            return ""
        }
    }

    private enum WeightBucket {
        case regular
        case medium
        case semibold
        case bold
    }

    private static func bucket(for weight: Font.Weight) -> WeightBucket {
        switch weight {
        case .medium:
            return .medium
        case .semibold:
            return .semibold
        case .bold, .heavy, .black:
            return .bold
        default:
            return .regular
        }
    }

    private static func swiftUIWeight(for weight: NSFont.Weight) -> Font.Weight {
        let value = weight.rawValue
        switch value {
        case ..<(-0.2):
            return .regular
        case ..<0.15:
            return .medium
        case ..<0.32:
            return .semibold
        default:
            return .bold
        }
    }

    private static func appKitWeight(for font: NSFont) -> NSFont.Weight {
        let rawWeight = NSFontManager.shared.weight(of: font)
        switch rawWeight {
        case ..<6:
            return .regular
        case ..<8:
            return .medium
        case ..<10:
            return .semibold
        default:
            return .bold
        }
    }
}
