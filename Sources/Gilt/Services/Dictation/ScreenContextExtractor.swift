import Foundation

/// Mines a raw blob of screen text (from AX or OCR) for the small set of
/// terms most likely to bias a dictation transcript usefully.
///
/// Heuristics, in order of priority:
///   1. **Identifiers with internal case/punctuation** — `useEffect`,
///      `ClipboardStore`, `NSWindow`, `snake_case`, `kebab-case`, `Next.js`.
///      These almost always benefit because Parakeet/Whisper spell them
///      phonetically.
///   2. **Acronyms** — runs of 2+ uppercase letters (`API`, `URL`, `SQL`,
///      `AWS`). Same reason.
///   3. **File paths and names with extensions** — `Models.swift`,
///      `package.json`, `tsconfig.json`. Frequent in code editors.
///   4. **Proper nouns** — capitalized words that aren't sentence starters
///      and aren't in a small stoplist. Catches people's names, product
///      names, brand spellings.
///   5. **Tokens already present in user vocabulary** are dropped so we
///      don't double-feed the matcher.
///
/// We deliberately *don't* keep ordinary nouns and verbs — the engine
/// already handles those correctly, and feeding 500 generic words to the
/// LLM context just dilutes attention.
enum ScreenContextExtractor {
    /// Returns up to `maxTerms` deduplicated context terms, ordered by
    /// estimated usefulness (highest first).
    static func extract(
        from rawText: String,
        excluding alreadyKnown: Set<String>,
        maxTerms: Int
    ) -> [String] {
        guard !rawText.isEmpty, maxTerms > 0 else { return [] }

        // Cheap tokenizer: split on whitespace, then peel surrounding punctuation
        // but *preserve* internal punctuation (dots, slashes, hyphens, underscores)
        // because those are exactly the things that mark an identifier.
        let rawTokens = rawText
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map(String.init)

        var scored: [(term: String, score: Int)] = []
        var seen = Set<String>()
        // Lowercased lookup for the "already known" set so the user-side
        // vocabulary doesn't need to match case exactly.
        let knownLowered = Set(alreadyKnown.map { $0.lowercased() })

        for raw in rawTokens {
            let cleaned = stripEdgePunctuation(raw)
            guard !cleaned.isEmpty else { continue }
            // Length sanity: tiny tokens are noise, giant tokens are
            // base64 or hash blobs that nobody dictates.
            if cleaned.count < 2 || cleaned.count > 40 { continue }
            // Stop if we've already kept it (case-insensitively).
            let lower = cleaned.lowercased()
            if seen.contains(lower) { continue }
            if knownLowered.contains(lower) { continue }
            if isStopWord(lower) { continue }
            // Pure-digit tokens — version strings without context — skip.
            if cleaned.allSatisfy({ $0.isNumber || $0 == "." }) { continue }

            guard let score = score(for: cleaned) else { continue }
            seen.insert(lower)
            scored.append((cleaned, score))
        }

        // Highest score wins. Within the same score, prefer longer terms
        // (more discriminative).
        scored.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.term.count > rhs.term.count
        }

        return Array(scored.prefix(maxTerms).map(\.term))
    }

    // MARK: - Scoring

    /// Heuristic score. Returns nil to reject the token outright.
    private static func score(for term: String) -> Int? {
        // 1. Internal underscores / hyphens / dots / slashes → identifier-ish.
        if term.contains("_") || term.contains("/") {
            return 95
        }
        // CamelCase / PascalCase — a lowercase letter immediately followed
        // by an uppercase letter anywhere in the token.
        if hasCamelTransition(term) {
            return 90
        }
        // File names with a short extension (≤5 chars).
        if let dot = term.lastIndex(of: "."), dot < term.endIndex {
            let afterDot = term[term.index(after: dot)...]
            if afterDot.count <= 5, afterDot.allSatisfy({ $0.isLetter || $0.isNumber }) {
                // Only call it a filename if there's at least one letter
                // before the dot — otherwise ".5" counts.
                let beforeDot = term[..<dot]
                if beforeDot.contains(where: { $0.isLetter }) {
                    return 80
                }
            }
        }
        // Internal hyphens / dots beyond filename case — kebab, library names.
        if term.contains("-") {
            return 70
        }
        if term.contains(".") {
            return 65
        }
        // Pure-uppercase acronym (2-6 letters).
        if term.count >= 2, term.count <= 6,
           term.allSatisfy({ $0.isLetter && $0.isUppercase }) {
            return 75
        }
        // Single capital + lowercase, but not at sentence start — proper
        // noun candidate. We can't tell sentence position cheaply, so we
        // just keep all of them at a lower score and let dedupe cap noise.
        if term.first?.isUppercase == true,
           term.dropFirst().allSatisfy({ $0.isLetter && $0.isLowercase }),
           term.count >= 4 {
            return 40
        }
        return nil
    }

    private static func hasCamelTransition(_ s: String) -> Bool {
        var previous: Character?
        for c in s {
            if let p = previous, p.isLowercase, c.isUppercase {
                return true
            }
            previous = c
        }
        return false
    }

    // MARK: - Cleanup

    /// Strip surrounding punctuation but keep internal punctuation that's
    /// meaningful (dots in `Next.js`, slashes in `CI/CD`, hyphens in
    /// `react-native`).
    private static func stripEdgePunctuation(_ s: String) -> String {
        let strip: Set<Character> = [
            ",", ";", ":", "!", "?", "\"", "'", "“", "”", "‘", "’",
            "(", ")", "[", "]", "{", "}", "<", ">", "|", "`",
            "…", "—", "–"
        ]
        var result = Substring(s)
        while let first = result.first, strip.contains(first) {
            result = result.dropFirst()
        }
        while let last = result.last, strip.contains(last) {
            result = result.dropLast()
        }
        // Trailing periods that aren't part of an extension or a multi-dot
        // name — peel them.
        while result.hasSuffix(".") {
            let dropped = result.dropLast()
            if dropped.contains(".") || dropped.allSatisfy({ $0.isLetter }) {
                // "Next.js." → "Next.js", but "Hello." → "Hello"
                if dropped.contains(".") { result = dropped; break }
                result = dropped
            } else {
                break
            }
        }
        return String(result)
    }

    // MARK: - Stop list

    /// Small high-frequency English stoplist. We don't ship a full one —
    /// these are the only words that consistently survive the scorer and
    /// shouldn't be biased on. (Note: lowercase comparison.)
    private static let stopWords: Set<String> = [
        "the", "and", "for", "are", "but", "not", "you", "all", "can",
        "had", "her", "was", "one", "our", "out", "day", "get", "has",
        "him", "his", "how", "man", "new", "now", "old", "see", "two",
        "way", "who", "boy", "did", "its", "let", "put", "say", "she",
        "too", "use", "this", "that", "with", "have", "from", "they",
        "will", "would", "there", "their", "what", "about", "which",
        "when", "make", "like", "time", "just", "him", "know", "take",
        "into", "year", "your", "good", "some", "could", "them", "than",
        "then", "look", "only", "come", "over", "think", "also", "back",
        "after", "first", "well", "even", "want", "because", "these",
        "give", "most"
    ]

    private static func isStopWord(_ lower: String) -> Bool {
        stopWords.contains(lower)
    }
}
