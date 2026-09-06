import Foundation

/// Parses `[[target]]` and `[[target|display]]` wiki-style links out of a
/// markdown body and returns the link targets.
///
/// We support two forms:
/// - `[[Project Apollo]]` — the link target is the displayed text
/// - `[[Project Apollo|the moonshot]]` — pipe-separated alias; first half is
///   the target (the alias is display-only and discarded here)
///
/// Things we deliberately exclude:
/// - Wikilinks inside a fenced code block (```…```)
/// - Wikilinks inside an inline code span (`…`)
/// - Empty targets like `[[]]`
///
/// All matching is line-aware: we never cross a newline inside a single link.
/// That mirrors how Obsidian/Tolaria parse and prevents a stray `]]` on a
/// later line from absorbing huge chunks of the document.
enum WikilinkExtractor {

    /// Every wikilink target in `markdown` in document order (duplicates
    /// included), skipping fenced + inline code.
    static func targets(in markdown: String) -> [String] {
        let ns = markdown as NSString
        var targets: [String] = []
        var insideFence = false

        ns.enumerateSubstrings(
            in: NSRange(location: 0, length: ns.length),
            options: .byLines
        ) { line, _, _, _ in
            guard let line else { return }
            // Toggle fence state on lines that *start* with ``` (ignore
            // language tags like ```swift). We bail entirely while inside a
            // fence — no wikilinks counted.
            if line.hasPrefix("```") {
                insideFence.toggle()
                return
            }
            if insideFence { return }

            // For each line, walk left-to-right matching `[[…]]` while
            // skipping inline-code spans delimited by single backticks.
            let codeMasked = Self.maskInlineCode(line)
            let maskedNS = codeMasked as NSString
            for match in Self.wikilinkRegex.matches(
                in: codeMasked,
                range: NSRange(location: 0, length: maskedNS.length)
            ) {
                let inner = match.range(at: 1)
                guard inner.length > 0 else { continue }
                let target = Self.parseTarget(maskedNS.substring(with: inner))
                if !target.isEmpty {
                    targets.append(target)
                }
            }
        }

        return targets
    }

    /// Every unique target referenced from `markdown`, in document order.
    /// Case-insensitive uniqueness so `[[Project apollo]]` and `[[Project
    /// Apollo]]` don't both count.
    static func uniqueTargets(in markdown: String) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for target in targets(in: markdown) {
            if seen.insert(target.lowercased()).inserted {
                result.append(target)
            }
        }
        return result
    }

    // MARK: - Internals

    private static let wikilinkRegex: NSRegularExpression = {
        // Inner capture group rejects `[`, `]`, and `\n` so we can't span
        // lines or chew through nested brackets.
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: #"\[\[([^\[\]\n]+)\]\]"#)
    }()

    /// Replace bracket characters inside a `` `code span` `` with a
    /// placeholder so any `[[…]]` inside backticks becomes `??…??` and won't
    /// match the regex.
    private static func maskInlineCode(_ line: String) -> String {
        guard line.contains("`") else { return line }
        var output = Array(line)
        var inside = false
        for i in output.indices {
            let ch = output[i]
            if ch == "`" {
                inside.toggle()
                continue
            }
            if inside, ch == "[" || ch == "]" {
                output[i] = "?"
            }
        }
        return String(output)
    }

    /// `[[target|alias]]` — everything before the first pipe is the target;
    /// the alias only affects rendering, which we don't do here.
    private static func parseTarget(_ inner: String) -> String {
        let target = inner.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        return String(target).trimmingCharacters(in: .whitespaces)
    }
}
