import Foundation

/// Read-only lister of subfolder paths inside an Obsidian vault, used to
/// populate the per-note destination picker.
///
/// Pure and side-effect-free: it never creates, moves, or deletes anything on
/// disk. Phase 0 of the vault feature is strictly non-destructive, so this
/// type only ever *reads* directory names — it never opens file contents
/// (important for iCloud/Dropbox vaults whose files may be offline placeholders).
///
/// `FileManager` is injectable so the logic is unit-testable against a temp
/// directory tree.
struct NoteVaultScanner {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Directory names that must never appear as note destinations: Obsidian's
    /// own config/trash and version-control metadata are noise for the picker.
    /// These all start with "." so `.skipsHiddenFiles` already drops them, but
    /// we exclude them explicitly so the rule is obvious and survives any
    /// enumerator option change.
    private static let excludedDirectoryNames: Set<String> = [
        ".obsidian", ".trash", ".git", ".svn", ".hg"
    ]

    /// Relative POSIX paths of every real subdirectory under `root`, sorted
    /// case-insensitively. Excludes hidden/dotted directories, Obsidian/VCS
    /// metadata, files, and symlinked directories (we don't follow links out of
    /// the vault). Bounded by `maxDepth` and `maxResults` so a pathological
    /// vault can't hang the picker.
    ///
    /// Returns `[]` if `root` doesn't exist or isn't a readable directory.
    func subfolderRelativePaths(under root: URL, maxDepth: Int = 8, maxResults: Int = 5000) -> [String] {
        let standardizedRoot = root.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: standardizedRoot.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return []
        }

        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let enumerator = fileManager.enumerator(
            at: standardizedRoot,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var results: [String] = []
        for case let url as URL in enumerator {
            if results.count >= maxResults {
                break
            }

            let name = url.lastPathComponent
            if name.hasPrefix(".") || Self.excludedDirectoryNames.contains(name) {
                enumerator.skipDescendants()
                continue
            }

            let values = try? url.resourceValues(forKeys: Set(keys))
            // Files are skipped silently; symlinked directories are skipped AND
            // pruned so we never traverse a link that points back into or out of
            // the vault.
            if values?.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            guard values?.isDirectory == true else { continue }

            let relative = Self.relativePath(of: url, under: standardizedRoot)
            guard !relative.isEmpty else { continue }
            // APFS can return decomposed (NFD) names; normalize to NFC so typed
            // queries match what we display.
            results.append(relative.precomposedStringWithCanonicalMapping)

            // Depth is the number of path components below the root. Once we hit
            // the cap, include this folder but don't descend into its children.
            let depth = relative.split(separator: "/").count
            if depth >= maxDepth {
                enumerator.skipDescendants()
            }
        }

        return results.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Path of `url` relative to `root` (no leading slash). Empty string when
    /// `url` isn't actually under `root`.
    private static func relativePath(of url: URL, under root: URL) -> String {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        let full = url.standardizedFileURL.path
        guard full.hasPrefix(rootPath) else { return "" }
        return String(full.dropFirst(rootPath.count))
    }
}
