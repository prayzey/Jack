import Foundation

/// Pure derivation of a filesystem-safe `.md` filename for a note in the vault.
/// The note's identity is its `jack-id` frontmatter, NOT the filename — so the
/// filename can follow the title for a readable Obsidian tree while renames are
/// tracked by id.
enum VaultFilename {
    static let maxBaseLength = 80

    /// Characters illegal or awkward in a cross-platform filename.
    private static let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters)

    /// Sanitize a note title into a safe basename (no extension).
    static func sanitize(_ title: String) -> String {
        let collapsed = title
            .components(separatedBy: invalid).joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Leading/trailing dots and spaces are illegal or hidden on disk.
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        let capped = String(trimmed.prefix(maxBaseLength)).trimmingCharacters(in: .whitespaces)
        return capped.isEmpty ? "Untitled Note" : capped
    }

    /// Resolve a non-colliding vault-relative path "<folder>/<base>.md".
    /// `taken` is the set of already-claimed relative paths (lowercased) in this
    /// sync pass; `ownPrevious` lets a note keep its own path when its title
    /// collides only with itself.
    static func resolve(base: String, inFolder folder: String, taken: Set<String>, ownPrevious: String?) -> String {
        let dir = folder.isEmpty ? "" : folder + "/"
        func candidate(_ suffix: String) -> String { "\(dir)\(base)\(suffix).md" }

        let first = candidate("")
        if let ownPrevious, ownPrevious.caseInsensitiveCompare(first) == .orderedSame {
            return first
        }
        if !taken.contains(first.lowercased()) { return first }

        var n = 2
        while taken.contains(candidate(" \(n)").lowercased()) { n += 1 }
        return candidate(" \(n)")
    }
}
