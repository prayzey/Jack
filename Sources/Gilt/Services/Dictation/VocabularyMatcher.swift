import Foundation

/// Substitutes likely spoken-out forms of vocabulary terms back into their
/// canonical spelling.
///
/// Three forms are checked per canonical term, in order:
///   1. **Whole-word, case-insensitive** match of the canonical itself.
///      Catches "chatgpt" / "ChatGpt" / "CHATGPT" → "ChatGPT".
///   2. **camelCase split** — for terms like "useEffect" we split at every
///      lowercase→uppercase boundary, producing "use effect", which is how
///      Parakeet typically transcribes them.
///   3. **Spelled-out uppercase runs** — for acronyms like "API", "ChatGPT",
///      or "AWS" we replace runs of 2+ uppercase letters with their letters
///      separated by spaces ("a p i", "chat g p t", "a w s"), which is the
///      most common Parakeet output for spelled acronyms.
///
/// Longer terms are processed first so they don't get partially eaten by a
/// shorter term (e.g. "useEffect" wins over "use").
enum VocabularyMatcher {
    /// Pair of canonical + strength used by the weighted-apply entry point.
    /// Keeps `apply(_:weighted:)` framework-agnostic so the matcher doesn't
    /// import `DictationModels` (and stays cheap to test in isolation).
    struct WeightedTerm: Equatable {
        let canonical: String
        let strength: Strength

        enum Strength: Equatable {
            /// Exact / spoken-form substitution only — today's behavior.
            case normal
            /// Adds per-word Soundex matching so acoustically-similar English
            /// words ("clawed") get rewritten to the canonical term ("claude").
            case strong
        }
    }

    /// Apply the substitution pipeline. Returns the transcript unchanged if
    /// the term list is empty. All terms are treated as `.normal` — i.e.
    /// today's exact / spelled-out matching only. Use `apply(_:weighted:)`
    /// when callers have per-term strength to express.
    static func apply(_ transcript: String, terms: [String]) -> String {
        guard !transcript.isEmpty, !terms.isEmpty else { return transcript }

        let deduped = Array(Set(terms.filter { !$0.isEmpty })).sorted { $0.count > $1.count }
        var result = transcript
        for term in deduped {
            for form in spokenForms(for: term) {
                result = substituteWholeWord(in: result, find: form, replaceWith: term)
            }
        }
        return result
    }

    /// Weighted pipeline. Runs the normal pass first (so exact matches
    /// always win), then a phonetic pass for any `.strong` terms.
    ///
    /// Phonetic pass is per-word Soundex: each token in the transcript gets
    /// codified, and tokens that share a code with the term — but aren't
    /// the term — get rewritten. Multi-word terms are not phonetic-matched
    /// (they only get the normal pass) because Soundex on a single token
    /// doesn't generalize cleanly across token boundaries.
    static func apply(_ transcript: String, weighted: [WeightedTerm]) -> String {
        guard !transcript.isEmpty, !weighted.isEmpty else { return transcript }

        // 1. Normal-strength pass for every term (covers both .normal and
        //    .strong — phonetic is additive, not a replacement).
        let normalNames = weighted.map(\.canonical)
        var result = apply(transcript, terms: normalNames)

        // 2. Phonetic pass for .strong terms only. Dedupe by Soundex code
        //    so two strong terms with the same code (e.g. "barrie" /
        //    "berry") don't fight; longest canonical wins.
        let strongTerms = weighted
            .filter { $0.strength == .strong }
            .map(\.canonical)
            .filter { !$0.isEmpty && !$0.contains(" ") }
            .sorted { $0.count > $1.count }
        guard !strongTerms.isEmpty else { return result }

        var seenCodes = Set<String>()
        var codeToCanonical: [String: String] = [:]
        for term in strongTerms {
            guard let code = soundex(term), seenCodes.insert(code).inserted else { continue }
            codeToCanonical[code] = term
        }
        guard !codeToCanonical.isEmpty else { return result }

        result = substitutePhonetically(in: result, codeToCanonical: codeToCanonical)
        return result
    }

    // MARK: - Spoken-form generation

    /// All the strings Parakeet might produce when the user says `term` out
    /// loud. We try each one as a whole-word substitution.
    private static func spokenForms(for term: String) -> [String] {
        var seen = Set<String>()
        var forms: [String] = []
        func add(_ s: String) {
            let trimmed = s.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted { forms.append(trimmed) }
        }

        // 1. The canonical (matched case-insensitively below)
        add(term)
        // 2. camelCase split
        let camelSplit = splitCamelCase(term)
        if camelSplit != term { add(camelSplit) }
        // 3. Uppercase runs spelled letter-by-letter
        if let spelled = spellUppercaseRuns(in: term), spelled != term {
            add(spelled)
        }
        // 4. Punctuation flattened to spaces — Parakeet rarely emits dots
        // or slashes between words. "Next.js" → "Next js", "CI/CD" → "CI CD",
        // and combined with the spelling pass below: "ci c d", "n e x t  j s".
        let flattened = flattenSeparators(term)
        if flattened != term { add(flattened) }
        // 5. Flattened + spelled together — catches things like "S.A.A.S" /
        // "C I C D" / "n e x t . js" where Parakeet broke up the term.
        if flattened != term, let combined = spellUppercaseRuns(in: flattened), combined != flattened {
            add(combined)
        }
        return forms
    }

    /// Replace common separator characters (. / -) with single spaces.
    private static func flattenSeparators(_ s: String) -> String {
        var result = ""
        for c in s {
            if c == "." || c == "/" || c == "-" {
                if !result.hasSuffix(" ") { result.append(" ") }
            } else {
                result.append(c)
            }
        }
        // Collapse double spaces and trim.
        return result.replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    /// "useEffect" → "use Effect", "TypeScript" → "Type Script",
    /// "PostgreSQL" → "Postgre SQL". Lowercase letter immediately followed
    /// by an uppercase letter gets a space inserted between them.
    private static func splitCamelCase(_ s: String) -> String {
        var result = ""
        var previous: Character?
        for c in s {
            if let p = previous, p.isLowercase, c.isUppercase {
                result.append(" ")
            }
            result.append(c)
            previous = c
        }
        return result
    }

    /// "API" → "a p i", "ChatGPT" → "chat g p t", "PostgreSQL" → "postgre s q l".
    /// Runs of 2+ uppercase letters in a row are replaced with their letters
    /// separated by spaces. The rest of the string is lowercased.
    private static func spellUppercaseRuns(in s: String) -> String? {
        // First pass — find any run of length ≥ 2
        var hasRun = false
        var i = s.startIndex
        while i < s.endIndex {
            if s[i].isUppercase {
                var j = s.index(after: i)
                while j < s.endIndex, s[j].isUppercase {
                    j = s.index(after: j)
                }
                let runLen = s.distance(from: i, to: j)
                if runLen >= 2 { hasRun = true; break }
                i = j
            } else {
                i = s.index(after: i)
            }
        }
        guard hasRun else { return nil }

        // Second pass — build the spelled-out string
        var result = ""
        i = s.startIndex
        while i < s.endIndex {
            if s[i].isUppercase {
                var j = s.index(after: i)
                while j < s.endIndex, s[j].isUppercase {
                    j = s.index(after: j)
                }
                let run = s[i..<j]
                if run.count >= 2 {
                    let lettered = run.map { String($0).lowercased() }.joined(separator: " ")
                    if !result.isEmpty, !result.hasSuffix(" ") {
                        result.append(" ")
                    }
                    result.append(lettered)
                } else {
                    result.append(String(run).lowercased())
                }
                i = j
            } else {
                result.append(String(s[i]).lowercased())
                i = s.index(after: i)
            }
        }
        return result
    }

    // MARK: - Substitution

    private static func substituteWholeWord(
        in text: String,
        find: String,
        replaceWith canonical: String
    ) -> String {
        guard !find.isEmpty else { return text }
        let escaped = NSRegularExpression.escapedPattern(for: find)
        // Use a custom boundary so that hyphenated and dotted terms (e.g.
        // "CI/CD", "Next.js") still match cleanly — \b doesn't always treat
        // "/" and "." as word boundaries the way we want.
        let pattern = "(?<![A-Za-z0-9])" + escaped + "(?![A-Za-z0-9])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: NSRegularExpression.escapedTemplate(for: canonical)
        )
    }

    // MARK: - Phonetic (Soundex)

    /// Per-word Soundex substitution. Walks the transcript a token at a
    /// time, codifies each letter-run, and rewrites tokens whose code maps
    /// to a known canonical — leaving punctuation and whitespace alone.
    ///
    /// A token is rewritten only if it's *not already* the canonical
    /// (case-insensitively). That keeps the pass from re-replacing terms
    /// the normal pass already handled.
    static func substitutePhonetically(
        in text: String,
        codeToCanonical: [String: String]
    ) -> String {
        var result = ""
        result.reserveCapacity(text.count)

        var word = ""
        for ch in text {
            if ch.isLetter {
                word.append(ch)
            } else {
                if !word.isEmpty {
                    result.append(phoneticRewrite(word, codeToCanonical: codeToCanonical))
                    word.removeAll(keepingCapacity: true)
                }
                result.append(ch)
            }
        }
        if !word.isEmpty {
            result.append(phoneticRewrite(word, codeToCanonical: codeToCanonical))
        }
        return result
    }

    private static func phoneticRewrite(
        _ word: String,
        codeToCanonical: [String: String]
    ) -> String {
        // Skip very short tokens — Soundex on 1-2 letter words is mostly
        // garbage and very prone to false positives ("a" → anything that
        // starts with A).
        guard word.count >= 4 else { return word }
        guard let code = soundex(word) else { return word }
        guard let canonical = codeToCanonical[code] else { return word }
        if word.caseInsensitiveCompare(canonical) == .orderedSame { return word }
        return canonical
    }

    /// Classic Soundex. Keeps the first letter, codifies the rest with the
    /// standard digit table, drops vowels + H/W, collapses adjacent
    /// duplicates, pads/truncates to 4 chars. Returns nil if the input has
    /// no letters.
    ///
    /// Why Soundex and not Metaphone: Soundex is small, deterministic, and
    /// good enough for the "claude / clawed" class of mishearings we
    /// actually see. Metaphone would catch more, but at the cost of a
    /// bigger implementation surface and more false positives. Easy
    /// upgrade path later if the strong-mode false-positive rate is too
    /// high in practice.
    static func soundex(_ word: String) -> String? {
        let upper = word.uppercased()
        guard let first = upper.first, first.isLetter else { return nil }

        var code = String(first)
        var lastDigit: Character? = soundexDigit(for: first)

        for ch in upper.dropFirst() {
            guard ch.isLetter else { continue }
            if ch == "H" || ch == "W" {
                // Don't update lastDigit — H/W are "transparent": a digit
                // before and after them collapses as if they weren't there.
                continue
            }
            if let digit = soundexDigit(for: ch) {
                if digit != lastDigit {
                    code.append(digit)
                }
                lastDigit = digit
            } else {
                // Vowel — resets the duplicate-collapse marker so the next
                // consonant always gets emitted.
                lastDigit = nil
            }
            if code.count == 4 { break }
        }

        while code.count < 4 { code.append("0") }
        return code
    }

    private static func soundexDigit(for ch: Character) -> Character? {
        switch ch {
        case "B", "F", "P", "V":                          return "1"
        case "C", "G", "J", "K", "Q", "S", "X", "Z":      return "2"
        case "D", "T":                                    return "3"
        case "L":                                         return "4"
        case "M", "N":                                    return "5"
        case "R":                                         return "6"
        default:                                          return nil
        }
    }
}
