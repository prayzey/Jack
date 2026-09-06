import AppKit
import CoreText
import Foundation
import OSLog
import UniformTypeIdentifiers

/// Imports and registers user-supplied Quick Note fonts.
///
/// We copy the picked file into Application Support and register it with
/// CTFontManager process-scoped, so NSFont(name:size:) can resolve the
/// PostScript name on every launch without re-prompting the user.
enum QuickNoteFontRegistry {
    static let allowedExtensions: Set<String> = ["ttf", "otf", "ttc", "otc"]

    private static let logger = Logger(subsystem: AppBrand.logSubsystem, category: "QuickNoteFonts")

    struct ImportedFont {
        let filename: String
        let postScriptName: String
        let displayName: String
    }

    static var directory: URL {
        AppSupportLocator.giltDirectory()
            .appendingPathComponent("quickNoteFonts", isDirectory: true)
    }

    /// Import a user-selected font file: copies it into the fonts directory
    /// and registers it with CTFontManager. Returns the stored filename and
    /// PostScript name so the appearance struct can persist them.
    @MainActor
    static func importFont(from sourceURL: URL) -> ImportedFont? {
        let ext = sourceURL.pathExtension.lowercased()
        guard allowedExtensions.contains(ext) else {
            logger.error("rejected non-font file extension=\(ext, privacy: .public)")
            return nil
        }

        let dir = directory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Use a stable per-source filename so re-importing the same file replaces it.
        let baseStem = sanitize(sourceURL.deletingPathExtension().lastPathComponent)
        let filename = "\(baseStem).\(ext)"
        let destURL = dir.appendingPathComponent(filename)

        if FileManager.default.fileExists(atPath: destURL.path) {
            unregister(at: destURL)
            try? FileManager.default.removeItem(at: destURL)
        }

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
        } catch {
            logger.error("copy failed source=\(sourceURL.path, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            return nil
        }

        guard let metadata = registerAndDescribe(at: destURL) else {
            try? FileManager.default.removeItem(at: destURL)
            return nil
        }

        return ImportedFont(
            filename: filename,
            postScriptName: metadata.postScriptName,
            displayName: metadata.displayName
        )
    }

    /// Register every stored custom font with CTFontManager. Called once during
    /// app startup so persisted appearance settings can resolve their fonts.
    static func registerAllStoredFonts() {
        let dir = directory
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for url in entries where allowedExtensions.contains(url.pathExtension.lowercased()) {
            _ = registerAndDescribe(at: url)
        }
    }

    static func fileURL(for filename: String?) -> URL? {
        guard let filename, !filename.isEmpty else { return nil }
        return directory.appendingPathComponent(filename)
    }

    @MainActor
    static func remove(filename: String?) {
        guard let url = fileURL(for: filename) else { return }
        unregister(at: url)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Private

    @discardableResult
    private static func registerAndDescribe(at url: URL) -> (postScriptName: String, displayName: String)? {
        var registrationError: Unmanaged<CFError>?
        let registered = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &registrationError)

        if !registered {
            if let error = registrationError?.takeRetainedValue() {
                let nsError = error as Error as NSError
                // Already-registered is fine — we still want metadata.
                if nsError.domain != kCTFontManagerErrorDomain as String
                    || nsError.code != CTFontManagerError.alreadyRegistered.rawValue {
                    logger.error("register failed url=\(url.lastPathComponent, privacy: .public) error=\(nsError.localizedDescription, privacy: .public)")
                    return nil
                }
            }
        }

        guard
            let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
            let descriptor = descriptors.first
        else {
            logger.error("no descriptors for url=\(url.lastPathComponent, privacy: .public)")
            return nil
        }

        let postScriptName = (CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String) ?? ""
        let displayName = (CTFontDescriptorCopyAttribute(descriptor, kCTFontDisplayNameAttribute) as? String) ?? postScriptName

        guard !postScriptName.isEmpty else {
            logger.error("missing PostScript name url=\(url.lastPathComponent, privacy: .public)")
            return nil
        }

        return (postScriptName, displayName)
    }

    private static func unregister(at url: URL) {
        var unregisterError: Unmanaged<CFError>?
        _ = CTFontManagerUnregisterFontsForURL(url as CFURL, .process, &unregisterError)
    }

    private static func sanitize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" {
                return Character(scalar)
            }
            return "-"
        }
        let result = String(cleaned)
        return result.isEmpty ? "custom-font" : result
    }
}
