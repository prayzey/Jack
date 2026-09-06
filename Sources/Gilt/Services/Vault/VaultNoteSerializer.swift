import CryptoKit
import Foundation

/// Pure conversion between a note's in-app markdown and the exact `.md` text
/// that lands in the vault. No filesystem access — the writer supplies/consumes
/// bytes. Fully unit-testable and round-trip stable.
///
/// Two representations differ only in two ways:
///  - Frontmatter: vault files carry a `---` block with a hidden `jack-id` (the
///    stable identity that survives Obsidian renames/moves) plus created/updated
///    timestamps. Any user-authored frontmatter keys are preserved verbatim.
///  - Images: in-app `![..](jack-image:<uuid>)` <-> Obsidian embed
///    `![[<uuid>.png]]`. The image UUID is the filename, so the mapping is exact
///    and reversible with no side table.
enum VaultNoteSerializer {
    static let jackIDKey = "jack-id"
    /// Pre-rename builds wrote the identity under `gilt-id`. We still read it as a
    /// fallback so legacy vault files keep their identity; serialization always
    /// writes `jack-id`, so files self-heal on their next save.
    static let legacyIDKey = "gilt-id"
    static let createdKey = "jack-created"
    static let updatedKey = "jack-updated"
    private static let reservedKeys: Set<String> = [jackIDKey, legacyIDKey, createdKey, updatedKey]

    private static let vaultEmbedPattern = #"!\[\[([0-9a-fA-F-]{36})\.png\]\]"#

    struct Frontmatter: Equatable {
        var jackID: UUID
        var created: Date
        var updated: Date
    }

    // MARK: - Image link rewriting

    /// app body -> vault body. Returns the referenced image IDs (for copying).
    static func vaultBody(fromAppBody appBody: String) -> (body: String, imageIDs: [UUID]) {
        rewrite(appBody, pattern: QuickNoteImageMarkdown.referencePattern) { id in
            "![[\(id.uuidString.lowercased()).png]]"
        }
    }

    /// vault body -> app body. Returns the referenced image IDs (for materializing).
    static func appBody(fromVaultBody vaultBody: String) -> (body: String, imageIDs: [UUID]) {
        rewrite(vaultBody, pattern: vaultEmbedPattern) { id in
            QuickNoteImageMarkdown.imageReference(imageID: id)
        }
    }

    private static func rewrite(
        _ text: String,
        pattern: String,
        replacement: (UUID) -> String
    ) -> (body: String, imageIDs: [UUID]) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return (text, []) }
        let ns = text as NSString
        let result = NSMutableString(string: text)
        var ids: [UUID] = []
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        // Reverse so earlier replacements don't shift later match ranges.
        for match in matches.reversed() {
            guard match.numberOfRanges > 1,
                  let id = UUID(uuidString: ns.substring(with: match.range(at: 1))) else { continue }
            ids.insert(id, at: 0)
            result.replaceCharacters(in: match.range, with: replacement(id))
        }
        return (result as String, ids)
    }

    // MARK: - File contents

    /// Build the full `.md` file text: Jack frontmatter (preserving any user
    /// frontmatter keys already in the body) followed by the vault-form body.
    static func fileContents(appBody: String, frontmatter: Frontmatter) -> String {
        let parsed = NoteFrontmatterParser.parse(appBody)
        let userPairs = parsed.values.filter { !reservedKeys.contains($0.key) }
        let (vBody, _) = vaultBody(fromAppBody: parsed.body)

        let formatter = isoFormatter()
        var lines = ["---", "\(jackIDKey): \(frontmatter.jackID.uuidString.lowercased())"]
        lines.append("\(createdKey): \(formatter.string(from: frontmatter.created))")
        lines.append("\(updatedKey): \(formatter.string(from: frontmatter.updated))")
        lines.append(contentsOf: userPairs.map { "\($0.key): \($0.value)" })
        lines.append("---")
        return lines.joined(separator: "\n") + "\n\n" + vBody
    }

    /// Parse a vault file back into its app-form body + identity.
    static func parseFile(_ text: String) -> (jackID: UUID?, appBody: String, imageIDs: [UUID]) {
        let parsed = NoteFrontmatterParser.parse(text)
        let jackID = (parsed.value(for: jackIDKey) ?? parsed.value(for: legacyIDKey))
            .flatMap { UUID(uuidString: $0) }
        let userPairs = parsed.values.filter { !reservedKeys.contains($0.key) }
        // NoteFrontmatterParser leaves one separator newline after the block;
        // strip it so the body round-trips byte-for-byte with what we wrote.
        var content = parsed.body
        if parsed.blockRange != nil, content.hasPrefix("\n") {
            content.removeFirst()
        }
        let (restored, ids) = appBody(fromVaultBody: content)

        let appBody: String
        if userPairs.isEmpty {
            appBody = restored
        } else {
            let block = (["---"] + userPairs.map { "\($0.key): \($0.value)" } + ["---"]).joined(separator: "\n")
            appBody = block + "\n\n" + restored
        }
        return (jackID, appBody, ids)
    }

    /// Stable content hash of an APP-form body — used for change detection on
    /// both sides. Frontmatter timestamps and image link style don't affect it
    /// because both sides hash the canonical app-form body.
    static func contentHash(appBody: String) -> String {
        SHA256.hash(data: Data(appBody.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func isoFormatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }
}