import AppKit
import Foundation

/// Inline character formatting (bold / italic / underline) for Quick Note,
/// persisted inside the note's markdown body.
///
/// Storage uses HTML-style `<b>`, `<i>`, `<u>` tags rather than markdown
/// `**`/`*`/`_`. That is deliberate: notes already contain literal asterisks
/// and underscores (IDs, passwords, code), and reinterpreting those as emphasis
/// would visually corrupt existing notes. `<b>`/`<i>`/`<u>` effectively never
/// occur in real note text, so unformatted notes round-trip byte-for-byte and
/// only text the user actually styles carries tags.
///
/// Pure string/font math with no main-actor state, so it stays nonisolated and
/// is safe to call from attribute-enumeration closures (which are not
/// actor-isolated) without Swift 6 sending violations.
enum QuickNoteInlineFormatting {
    struct Traits: OptionSet {
        let rawValue: Int
        static let bold = Traits(rawValue: 1 << 0)
        static let italic = Traits(rawValue: 1 << 1)
        static let underline = Traits(rawValue: 1 << 2)
    }

    private static let tokens: [(open: String, close: String, trait: Traits)] = [
        ("<b>", "</b>", .bold),
        ("<i>", "</i>", .italic),
        ("<u>", "</u>", .underline)
    ]

    // MARK: - Parse (markdown text -> attributed)

    /// Apply `<b>/<i>/<u>` tags found in `text` as real attributes over
    /// `baseAttributes`, stripping the tags. A backslash directly before a
    /// tag (`\<b>`) marks it as the user's literal text: the backslash is
    /// dropped and the tag characters are kept verbatim — the inverse of
    /// `escapeLiteralTags`. Tag-free text returns exactly the same run a
    /// plain `NSAttributedString(string:attributes:)` would produce, so
    /// unformatted notes are unaffected.
    static func attributedString(
        from text: String,
        baseAttributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        guard text.contains("<") else {
            return NSAttributedString(string: text, attributes: baseAttributes)
        }

        let result = NSMutableAttributedString()
        let ns = text as NSString
        var active: Traits = []
        var i = 0
        var segmentStart = 0

        // Append untouched text by NSString range, never character-by-character:
        // walking UTF-16 units through Character(UnicodeScalar(...)) destroys
        // surrogate pairs, turning every emoji into spaces.
        func flushSegment(upTo end: Int) {
            guard end > segmentStart else { return }
            let segment = ns.substring(with: NSRange(location: segmentStart, length: end - segmentStart))
            result.append(NSAttributedString(
                string: segment,
                attributes: attributes(for: active, base: baseAttributes)
            ))
        }

        while i < ns.length {
            let unit = ns.character(at: i)
            if unit == unichar(UInt16(92)), // '\'
               i + 1 < ns.length,
               let escaped = matchToken(in: ns, at: i + 1) {
                flushSegment(upTo: i)
                result.append(NSAttributedString(
                    string: ns.substring(with: NSRange(location: i + 1, length: escaped.length)),
                    attributes: attributes(for: active, base: baseAttributes)
                ))
                i += 1 + escaped.length
                segmentStart = i
                continue
            }
            if unit == unichar(UInt16(60)), // '<'
               let match = matchToken(in: ns, at: i) {
                flushSegment(upTo: i)
                if match.isClose {
                    active.remove(match.trait)
                } else {
                    active.insert(match.trait)
                }
                i += match.length
                segmentStart = i
                continue
            }
            i += 1
        }
        flushSegment(upTo: ns.length)
        return result
    }

    private static func matchToken(
        in ns: NSString,
        at index: Int
    ) -> (trait: Traits, isClose: Bool, length: Int)? {
        for token in tokens {
            if hasPrefix(token.open, in: ns, at: index) {
                return (token.trait, false, (token.open as NSString).length)
            }
            if hasPrefix(token.close, in: ns, at: index) {
                return (token.trait, true, (token.close as NSString).length)
            }
        }
        return nil
    }

    private static func hasPrefix(_ prefix: String, in ns: NSString, at index: Int) -> Bool {
        let p = prefix as NSString
        guard index + p.length <= ns.length else { return false }
        return ns.substring(with: NSRange(location: index, length: p.length)) == prefix
    }

    private static func attributes(
        for traits: Traits,
        base: [NSAttributedString.Key: Any]
    ) -> [NSAttributedString.Key: Any] {
        guard !traits.isEmpty else { return base }
        var attrs = base
        if let baseFont = base[.font] as? NSFont {
            attrs[.font] = styledFont(
                base: baseFont,
                bold: traits.contains(.bold),
                italic: traits.contains(.italic)
            )
        }
        if traits.contains(.underline) {
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        return attrs
    }

    /// Add/remove bold + italic symbolic traits on a font, preserving family and
    /// size. Falls back to the base font when the family ships no such variant.
    static func styledFont(base: NSFont, bold: Bool, italic: Bool) -> NSFont {
        var symbolic = base.fontDescriptor.symbolicTraits
        if bold { symbolic.insert(.bold) } else { symbolic.remove(.bold) }
        if italic { symbolic.insert(.italic) } else { symbolic.remove(.italic) }
        let descriptor = base.fontDescriptor.withSymbolicTraits(symbolic)
        return NSFont(descriptor: descriptor, size: base.pointSize) ?? base
    }

    // MARK: - Serialize (attributed -> markdown text)

    /// Convert a formatted text run back into tagged markdown. Operates on a
    /// plain-text segment (no attachments — the body renderer handles those).
    static func serialize(_ attributed: NSAttributedString) -> String {
        let fullRange = NSRange(location: 0, length: attributed.length)
        guard fullRange.length > 0 else { return "" }

        var output = ""
        attributed.enumerateAttributes(in: fullRange, options: []) { attrs, range, _ in
            let segment = (attributed.string as NSString).substring(with: range)
            let traits = traits(from: attrs)
            output += wrap(escapeLiteralTags(segment), in: traits)
        }
        // Collapse tag boundaries that touch (e.g. "</b><b>") so adjacent runs of
        // the same style read as one span.
        return collapseAdjacentTags(output)
    }

    /// Prefix every literal tag token the user actually typed with a
    /// backslash so the next parse keeps it as text instead of eating it as
    /// formatting. Parse consumes exactly one backslash per token, so text
    /// the user typed with its own backslashes (`\<b>`) also round-trips.
    static func escapeLiteralTags(_ text: String) -> String {
        guard text.contains("<") else { return text }
        var result = text
        for token in tokens {
            result = result.replacingOccurrences(of: token.open, with: "\\" + token.open)
            result = result.replacingOccurrences(of: token.close, with: "\\" + token.close)
        }
        return result
    }

    static func traits(from attrs: [NSAttributedString.Key: Any]) -> Traits {
        var traits: Traits = []
        if let font = attrs[.font] as? NSFont {
            let symbolic = font.fontDescriptor.symbolicTraits
            if symbolic.contains(.bold) { traits.insert(.bold) }
            if symbolic.contains(.italic) { traits.insert(.italic) }
        }
        if let raw = attrs[.underlineStyle] as? Int, raw != 0 {
            traits.insert(.underline)
        }
        return traits
    }

    private static func wrap(_ text: String, in traits: Traits) -> String {
        guard !traits.isEmpty, !text.isEmpty else { return text }
        var open = ""
        var close = ""
        // Consistent nesting order so adjacent-tag collapsing can match.
        if traits.contains(.bold) { open += "<b>"; close = "</b>" + close }
        if traits.contains(.italic) { open += "<i>"; close = "</i>" + close }
        if traits.contains(.underline) { open += "<u>"; close = "</u>" + close }
        return open + text + close
    }

    private static func collapseAdjacentTags(_ text: String) -> String {
        guard text.contains("<") else { return text }
        var result = text
        for token in tokens {
            // Negative lookbehind: a close tag preceded by a backslash is the
            // user's escaped literal text, not a formatting boundary —
            // collapsing it would delete their characters.
            let pattern = "(?<!\\\\)" + NSRegularExpression.escapedPattern(for: token.close + token.open)
            result = result.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return result
    }
}

extension NSAttributedString {
    /// True if any run carries bold/italic font traits or an underline. Lets
    /// `markdown(from:)` keep its plain-text fast path for unformatted notes.
    var containsInlineFormatting: Bool {
        var found = false
        enumerateAttributes(in: NSRange(location: 0, length: length), options: []) { attrs, _, stop in
            if !QuickNoteInlineFormatting.traits(from: attrs).isEmpty {
                found = true
                stop.pointee = true
            }
        }
        return found
    }
}
