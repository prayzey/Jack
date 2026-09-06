import Foundation

/// Deterministic text transforms that run alongside (not via) Qwen.
///
/// Two phases:
///   - **Pre-clean** (`applyPreClean`): runs right after the transcript comes
///     back from Parakeet. Currently expands spoken punctuation commands
///     ("comma" → ","), so the cleaner and Qwen see the punctuated text.
///   - **Post-clean** (`applyPostClean`): runs after the cleaner and any
///     Qwen pass. Sentence capitalization + smart typography (curly quotes,
///     em dashes) belong here because they depend on final sentence
///     boundaries.
///
/// Each transform is gated by its own bool on `DictationSettings`. All
/// default on — the goal is for users to get "smart" behavior without
/// having to opt in, with individual escape hatches per feature.
@MainActor
enum SmartFormatter {
    /// Pre-Qwen pass — runs *before* the filler/stutter cleaner so the
    /// cleaner can see the expanded punctuation and tidy any leftover
    /// space-before-comma artifacts.
    static func applyPreClean(_ text: String, settings: DictationSettings) -> String {
        var result = text
        if settings.formatPunctuationCommands {
            // Emails first: "john dot smith at gmail dot com" must become an
            // address before VoicePunctuation could touch anything nearby.
            result = SpokenEmailFormatter.apply(result)
            result = VoicePunctuation.expand(result)
        }
        return result
    }

    /// Post-Qwen pass — runs last so it operates on the canonical, fully
    /// punctuated text. Capitalization and typography would be premature
    /// before Qwen since the model may re-flow sentences.
    static func applyPostClean(_ text: String, settings: DictationSettings) -> String {
        var result = text
        if settings.capitalizeSentences {
            result = SentenceCapitalizer.apply(result)
        }
        if settings.useSmartTypography {
            result = SmartTypography.apply(result)
        }
        return result
    }
}

/// Rewrites spoken email addresses and web domains into written form:
/// "john dot smith at gmail dot com" → "john.smith@gmail.com". Deterministic
/// on purpose — Qwen 3.5 4B title-cases the words ("John Dot Smith at Gmail")
/// instead of formatting the address, so this can't be left to the model.
///
/// Two-step design to avoid false positives:
///   1. Domains always convert: "apple dot com" → "apple.com". Safe on its
///      own ("find it at apple dot com" → "find it at apple.com").
///   2. " at " becomes "@" only when the local part is dotted
///      ("john.smith at gmail.com") or preceded by an email cue word
///      ("my email is praise at novor.dev") — a bare "it at apple.com"
///      stays a preposition.
enum SpokenEmailFormatter {
    /// The final segment must be a real TLD — this is what stops phrases
    /// like "the meeting at nine dot thirty" from becoming an address.
    /// ponytail: short allowlist of common TLDs; extend if users report one.
    private static let tlds = "com|net|org|io|co|dev|app|ai|edu|gov|me|us|uk|ca|xyz"

    /// Local part spoken with dots ("john dot smith") + "at" + domain chain.
    /// A dotted local is itself the email signal, so no cue word is needed.
    private static let fullSpokenAddressPattern =
        #"\b([a-z0-9-]+(?:[ ]dot[ ][a-z0-9-]+)+)[ ]at[ ]([a-z0-9-]+(?:[ ]dot[ ][a-z0-9-]+)*[ ]dot[ ](?:\#(tlds)))\b"#
    private static let domainPattern =
        #"\b([a-z0-9-]+(?:[ ]dot[ ][a-z0-9-]+)*)[ ]dot[ ](\#(tlds))\b"#
    private static let cuedLocalAtPattern =
        #"\b(to|is|email|address|cc|bcc|reach|contact)[ ]([a-z0-9-]+)[ ]at[ ]([a-z0-9-]+(?:\.[a-z0-9-]+)*\.(?:\#(tlds)))\b"#

    static func apply(_ text: String) -> String {
        var result = replacing(fullSpokenAddressPattern, in: text) { groups in
            spokenDots(groups[1]) + "@" + spokenDots(groups[2])
        }
        result = replacing(domainPattern, in: result) { groups in
            spokenDots(groups[1]) + "." + groups[2]
        }
        result = replacing(cuedLocalAtPattern, in: result) { groups in
            groups[1] + " " + groups[2] + "@" + groups[3]
        }
        return result
    }

    private static func spokenDots(_ text: String) -> String {
        text.replacingOccurrences(of: " dot ", with: ".", options: .caseInsensitive)
    }

    private static func replacing(
        _ pattern: String,
        in text: String,
        with builder: ([String]) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return text
        }
        let ns = text as NSString
        var result = text
        // Back-to-front so earlier ranges stay valid while replacing.
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            var groups: [String] = []
            for i in 0..<match.numberOfRanges {
                groups.append(match.range(at: i).location == NSNotFound ? "" : ns.substring(with: match.range(at: i)))
            }
            guard let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: builder(groups))
        }
        return result
    }
}

/// Maps spoken punctuation words ("comma", "new paragraph", "question mark")
/// to their actual characters. Designed for everyday dictation — if you say
/// the word, you get the symbol.
enum VoicePunctuation {
    /// Patterns are tried in order. Longer / multi-word phrases come first
    /// so they don't get partially eaten by single-word patterns
    /// ("new paragraph" must be checked before "new" or "paragraph"
    /// individually). Case-insensitive whole-word matching.
    private static let rules: [(pattern: String, replacement: String)] = [
        // Structural (block-level) — these matter most so do them first
        (#"\bnew paragraph\b"#, "\n\n"),
        (#"\b(?:new line|newline)\b"#, "\n"),
        // Multi-word punctuation phrases
        (#"\bfull stop\b"#, "."),
        (#"\bexclamation (?:point|mark)\b"#, "!"),
        (#"\bquestion mark\b"#, "?"),
        (#"\bopen paren(?:thesis|theses)?\b"#, "("),
        (#"\bclose paren(?:thesis|theses)?\b"#, ")"),
        (#"\bopen (?:quote|quotation) ?(?:s|marks)?\b"#, "\""),
        (#"\bclose (?:quote|quotation) ?(?:s|marks)?\b"#, "\""),
        (#"\bbullet point\b"#, "• "),
        (#"\bem dash\b"#, "—"),
        (#"\ben dash\b"#, "–"),
        // Single-word punctuation
        (#"\bcomma\b"#, ","),
        (#"\bperiod\b"#, "."),
        (#"\bsemi(?:-)?colon\b"#, ";"),
        (#"\bcolon\b"#, ":"),
        (#"\bdash\b"#, " — "),
        (#"\bhyphen\b"#, "-"),
        (#"\bslash\b"#, "/")
    ]

    static func expand(_ text: String) -> String {
        var result = text
        for (pattern, replacement) in rules {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: NSRegularExpression.escapedTemplate(for: replacement)
            )
        }
        result = tidyWhitespace(result)
        return result
    }

    /// After substitution we typically have spurious spaces around the new
    /// punctuation ("Hello , how are you"). Collapse them.
    private static func tidyWhitespace(_ text: String) -> String {
        var result = text
        // Drop space directly before clause punctuation.
        if let regex = try? NSRegularExpression(pattern: #"[ \t]+([,.;:!?])"#) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "$1")
        }
        // Collapse runs of tabs/spaces (but not newlines).
        if let regex = try? NSRegularExpression(pattern: #"[ \t]+"#) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: " ")
        }
        // Trim whitespace immediately before a newline.
        if let regex = try? NSRegularExpression(pattern: #"[ \t]+\n"#) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "\n")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Capitalizes the first letter of every sentence plus standalone "i" → "I".
/// Sentence boundaries are detected as `.!?` followed by whitespace, or a
/// hard newline (used by paragraph and list formatting), or the start of
/// the text.
enum SentenceCapitalizer {
    static func apply(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = ""
        result.reserveCapacity(text.count)
        var capitalizeNext = true
        var previousChar: Character?
        for char in text {
            if capitalizeNext, char.isLetter {
                result.append(Character(char.uppercased()))
                capitalizeNext = false
            } else {
                result.append(char)
                // Reset capitalize flag once we've seen any non-space
                // character — the sentence has started.
                if char.isLetter || char.isNumber {
                    capitalizeNext = false
                }
            }
            // After punctuation that ends a sentence, the next letter starts a
            // new sentence and should be capitalized.
            if char == "." || char == "!" || char == "?" || char == "\n" {
                capitalizeNext = true
            }
            previousChar = char
        }
        _ = previousChar // suppress unused warning
        // Fix standalone "i" → "I" (a very common dictation error since
        // Parakeet often outputs lowercase pronouns).
        if let regex = try? NSRegularExpression(pattern: #"\bi\b"#) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "I")
        }
        // Same for "i'm", "i'll", "i've", "i'd"
        for contraction in ["i'm", "i'll", "i've", "i'd"] {
            if let regex = try? NSRegularExpression(
                pattern: "\\b" + NSRegularExpression.escapedPattern(for: contraction) + "\\b",
                options: []
            ) {
                let range = NSRange(result.startIndex..., in: result)
                let replacement = "I" + contraction.dropFirst()
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: range,
                    withTemplate: NSRegularExpression.escapedTemplate(for: String(replacement))
                )
            }
        }
        return result
    }
}

/// Replaces straight quotes with curly quotes and double hyphens with em
/// dashes. Apostrophes in contractions ("don't", "I've") get the right
/// curl direction based on surrounding letters.
enum SmartTypography {
    static func apply(_ text: String) -> String {
        var result = text
        // Em dash from " -- "
        result = result.replacingOccurrences(of: " -- ", with: " — ")
        result = result.replacingOccurrences(of: "—", with: "—") // normalize
        // Smart quotes — alternate open/close
        result = applySmartQuotes(result)
        return result
    }

    private static func applySmartQuotes(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var inDouble = false
        let chars = Array(text)
        for (index, char) in chars.enumerated() {
            switch char {
            case "\"":
                result.append(inDouble ? "\u{201D}" : "\u{201C}")
                inDouble.toggle()
            case "'":
                // Apostrophe-vs-quote heuristic: between two letters/digits
                // it's an apostrophe. Otherwise alternate single-quote.
                let prev = index > 0 ? chars[index - 1] : nil
                let next = index < chars.count - 1 ? chars[index + 1] : nil
                let prevWord = prev?.isLetter == true || prev?.isNumber == true
                let nextWord = next?.isLetter == true || next?.isNumber == true
                if prevWord && nextWord {
                    result.append("\u{2019}") // typographic apostrophe
                } else if prevWord && !nextWord {
                    // End of word — likely close-single or possessive
                    result.append("\u{2019}")
                } else {
                    result.append("\u{2018}")
                }
            default:
                result.append(char)
            }
        }
        return result
    }
}
