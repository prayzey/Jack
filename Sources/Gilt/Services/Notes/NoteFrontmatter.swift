import Foundation

/// YAML-lite frontmatter parser for note bodies.
///
/// A note's frontmatter is the optional `---`-delimited block at the top of
/// the markdown body, e.g.:
///
/// ```
/// ---
/// type: project
/// status: active
/// tags: roadmap, q1
/// ---
///
/// # The actual note begins here
/// ```
///
/// We deliberately don't pull in a full YAML library — Tolaria uses a
/// frontmatter dialect that's basically `key: value` pairs and comma-separated
/// lists, and that's all our UI surfaces today. The full YAML grammar
/// (anchors, multiline scalars, nested maps) is overkill and would couple us
/// to an external dependency.
///
/// What we support:
/// - `key: value`
/// - `key: "quoted value with: colons"` (quotes preserved if balanced)
/// - `key: a, b, c` for list-style values (stored as a comma-joined string)
/// - Whitespace around keys and values is trimmed
/// - Lines without a colon are ignored (no errors, no surprises)
///
/// What we don't support yet:
/// - Nested maps (`a:\n  b: 1`)
/// - Multiline scalars (`a: |\n  line1\n  line2`)
/// - Anchors and references
// Note: not `Equatable` because the values array uses tuple elements, which
// don't synthesize ==. Tests check fields individually rather than the whole
// struct.
struct NoteFrontmatter {
    /// Parsed `key: value` pairs in the order they appeared. Keys are
    /// lowercased so callers don't have to worry about `Type:` vs `type:`.
    let values: [(key: String, value: String)]
    /// Frontmatter delimiter range in the source (`---` open through `---`
    /// close, inclusive of the trailing newline). Use this to find where the
    /// body actually starts.
    let blockRange: Range<String.Index>?
    /// Body content with the frontmatter prefix removed. If there was no
    /// frontmatter, this equals the source markdown.
    let body: String

    /// Fast key lookup. Returns the first match (frontmatter shouldn't have
    /// duplicate keys, but if it does, the first one wins).
    func value(for key: String) -> String? {
        let normalized = key.lowercased()
        return values.first(where: { $0.key == normalized })?.value
    }

    /// Convenience: the conventional `type:` field used by Tolaria's
    /// "types as lenses" model. Lowercased; returns nil if absent.
    var type: String? { value(for: "type") }
}

enum NoteFrontmatterParser {

    /// Parse the leading `---\n…\n---\n` block from `markdown`. If the
    /// document doesn't begin with a delimiter line, returns a frontmatter
    /// with empty `values` and `body == raw`. A start delimiter without a
    /// matching close delimiter is treated the same way (we don't want a
    /// stray `---` mid-document to swallow the rest of the note).
    static func parse(_ markdown: String) -> NoteFrontmatter {
        // Must start with `---` on its own line (allowing trailing whitespace).
        let nsString = markdown as NSString
        let firstNewline = nsString.range(of: "\n")

        // No newline => single-line document => no frontmatter possible.
        guard firstNewline.location != NSNotFound else {
            return NoteFrontmatter(values: [], blockRange: nil, body: markdown)
        }

        let firstLine = nsString
            .substring(with: NSRange(location: 0, length: firstNewline.location))
            .trimmingCharacters(in: .whitespaces)
        guard firstLine == "---" else {
            return NoteFrontmatter(values: [], blockRange: nil, body: markdown)
        }

        // Find the closing `---` line. Search starts *after* the first newline.
        let searchStart = firstNewline.location + firstNewline.length
        let restRange = NSRange(location: searchStart, length: nsString.length - searchStart)
        let closeMatch = nsString.range(of: #"(?m)^---\s*$"#, options: .regularExpression, range: restRange)
        guard closeMatch.location != NSNotFound else {
            // Unterminated frontmatter — treat the whole document as body so
            // users don't lose work to a typo.
            return NoteFrontmatter(values: [], blockRange: nil, body: markdown)
        }

        // Body starts right after the closing delimiter's trailing newline
        // (if any). Trim the leading blank line that conventionally sits
        // between frontmatter and content.
        let afterCloseStart = closeMatch.location + closeMatch.length
        var bodyStart = afterCloseStart
        if bodyStart < nsString.length,
           nsString.substring(with: NSRange(location: bodyStart, length: 1)) == "\n" {
            bodyStart += 1
        }
        let body = nsString.substring(with: NSRange(location: bodyStart, length: nsString.length - bodyStart))

        // Slice frontmatter body (between the two delimiters) and parse pairs.
        let fmBodyRange = NSRange(location: searchStart, length: closeMatch.location - searchStart)
        let fmBody = nsString.substring(with: fmBodyRange)
        let pairs = parsePairs(fmBody)

        // Compute Swift String index range for the whole frontmatter block.
        let blockRange = Range(NSRange(location: 0, length: bodyStart), in: markdown)
        return NoteFrontmatter(values: pairs, blockRange: blockRange, body: body)
    }

    private static func parsePairs(_ body: String) -> [(key: String, value: String)] {
        var pairs: [(key: String, value: String)] = []
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Skip blank lines and lines we treat as YAML comments (`# …`).
            // Frontmatter "comments" are rare but easy to support and avoid
            // surprising parses.
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard let colonIndex = trimmed.firstIndex(of: ":") else { continue }
            let rawKey = trimmed[..<colonIndex].trimmingCharacters(in: .whitespaces).lowercased()
            guard !rawKey.isEmpty else { continue }
            var rawValue = String(trimmed[trimmed.index(after: colonIndex)...])
                .trimmingCharacters(in: .whitespaces)
            // Strip a *balanced* pair of surrounding quotes. Unbalanced quotes
            // stay as-is so the user sees what they typed.
            if rawValue.count >= 2,
               let first = rawValue.first,
               let last = rawValue.last,
               first == last,
               first == "\"" || first == "'" {
                rawValue = String(rawValue.dropFirst().dropLast())
            }
            pairs.append((key: rawKey, value: rawValue))
        }
        return pairs
    }
}
