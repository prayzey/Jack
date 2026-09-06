import AppKit
import Foundation
import OSLog

/// Owns the security-scoped bookmark lifecycle for the user's Obsidian vault.
///
/// Why bookmarks: a plain folder URL doesn't grant access after relaunch, and
/// not at all in the sandboxed Mac App Store build. A security-scoped bookmark
/// persists the user's grant across launches.
///
/// Build differences (one code path either way):
/// - Direct-download build (`Jack.entitlements`, not sandboxed): start/stop
///   access are effectively no-ops, and `.withSecurityScope` may be rejected at
///   creation — we fall back to a plain bookmark, which still resolves the path.
/// - Mac App Store build (`Jack-AppStore.entitlements`, sandboxed): start/stop
///   are mandatory or reads throw, and cross-launch resolution will additionally
///   need the `files.bookmarks.app-scope` + read-write entitlements once Phase 1
///   begins writing. Phase 0 only reads, so it works on the direct build today.
enum NoteVaultBookmarkService {
    private static let logger = Logger(subsystem: AppBrand.logSubsystem, category: "NoteVault")

    /// Present an open panel for the user to choose their vault root folder.
    /// Returns nil if they cancel.
    @MainActor
    static func pickVaultFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.title = L10n.string("vault.picker.title", default: "Choose Your Vault Folder")
        panel.message = L10n.string(
            "vault.picker.message",
            default: "Pick your Obsidian vault (or any folder). Notes you assign will be saved here."
        )
        panel.prompt = L10n.string("vault.picker.prompt", default: "Choose")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        guard panel.runModalInFront() == .OK else { return nil }
        return panel.url
    }

    /// Create a security-scoped bookmark for a chosen folder. Falls back to a
    /// plain bookmark if the non-sandboxed build rejects `.withSecurityScope`.
    static func makeBookmark(for url: URL) throws -> Data {
        do {
            return try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            logger.info("security-scoped bookmark unavailable; using plain bookmark (non-sandboxed build)")
            return try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
    }

    /// Resolve a stored bookmark back into a URL. Tries the security-scoped
    /// path first, then a plain resolution (for bookmarks created via the
    /// fallback above).
    static func resolveBookmark(_ data: Data) throws -> (url: URL, isStale: Bool) {
        var isStale = false
        if let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            return (url, isStale)
        }
        let url = try URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return (url, isStale)
    }

    /// Resolve the bookmark, start security-scoped access, run `body` with the
    /// vault URL, and always stop access afterwards. Returns `nil` if the
    /// bookmark can't be resolved (e.g. the folder was moved or deleted) — the
    /// caller treats nil as "vault unavailable" and never crashes or writes.
    static func withVaultAccess<T>(_ data: Data, _ body: (URL) throws -> T) rethrows -> T? {
        guard let resolved = try? resolveBookmark(data) else {
            logger.info("vault bookmark could not be resolved (moved or deleted?)")
            return nil
        }
        let url = resolved.url
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        return try body(url)
    }
}
