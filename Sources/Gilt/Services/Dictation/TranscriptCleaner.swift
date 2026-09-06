import Foundation

/// Always-on text cleanup pass that runs after the engine returns a raw
/// transcript and before we paste/save.
///
/// Direct port of Handy's `filter_transcription_output` + `collapse_stutters`
/// from `audio_toolkit/text.rs`. The intent is the same: drop the disfluencies
/// a human reader expects to disappear (um, uh, hmm), and collapse stuttered
/// repetitions ("I I I think" → "I think"). No LLM required, no model load —
/// this is pure regex/string work and runs in microseconds.
enum TranscriptCleaner {
    /// English-only filler list. Handy ships per-language lists; we start
    /// English-only and grow if/when dictation supports other languages.
    /// Order doesn't matter — each is regex-stripped independently.
    private static let englishFillers: [String] = [
        "uh", "um", "uhm", "umm", "uhh",
        "ah", "ahh",
        "hmm", "hm", "mhm",
        "mmm", "mm", "mh",
        "eh", "ehh"
    ]

    /// Apply the standard cleanup pipeline. Idempotent — running it twice
    /// produces the same output. Returns the cleaned string, trimmed.
    static func clean(_ raw: String) -> String {
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return raw }
        var text = raw
        text = stripFillers(text)
        text = collapseStutters(text)
        text = normalizeWhitespace(text)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Strip the trailing period from a single-word raw transcript.
    ///
    /// Parakeet treats every utterance as a sentence and ends it with a
    /// period. When the speaker said exactly one word ("hello") that period
    /// reads as a bug — they wanted a label, name, or fragment, not a
    /// sentence. Multi-word transcripts keep their terminal punctuation
    /// since the speaker has more clearly committed to a sentence.
    ///
    /// Call this on the raw engine output BEFORE the spoken-punctuation
    /// expansion pass — otherwise dictating "hello period" (two words from
    /// Parakeet) would collapse to a single-word "hello." mid-pipeline and
    /// then get its explicit period stripped, which is the opposite of
    /// what the speaker asked for.
    static func stripSingleWordTrailingPeriod(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix("."), !trimmed.hasSuffix("..") else { return text }
        let body = trimmed.dropLast()
        // Single word = no internal whitespace and no internal period
        // (the latter keeps abbreviations like "U.S." intact in the rare
        // case Parakeet emits one).
        guard !body.isEmpty,
              !body.contains(where: { $0.isWhitespace }),
              !body.contains(".") else { return text }
        return String(body)
    }

    // MARK: - Filler removal

    /// Strip standalone filler words. The regex matches a word-boundary,
    /// optionally case-insensitive, optionally followed by a comma or period
    /// (so "Um, I think…" → ", I think…", which the whitespace normalizer
    /// then cleans up).
    private static func stripFillers(_ text: String) -> String {
        var output = text
        for filler in englishFillers {
            let pattern = #"(?i)\b\#(filler)\b[,.]?"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(output.startIndex..., in: output)
            output = regex.stringByReplacingMatches(
                in: output,
                range: range,
                withTemplate: ""
            )
        }
        return output
    }

    // MARK: - Stutter collapse

    /// Collapse 3+ consecutive identical words (case-insensitive, ignoring
    /// trailing punctuation) into a single occurrence. "I I I think" →
    /// "I think". "the the the cat" → "the cat". We keep doubles untouched
    /// because they can be intentional ("very very good").
    private static func collapseStutters(_ text: String) -> String {
        // Tokenize on whitespace, walk forward keeping a window. When the
        // current word matches the previous 2+ words, skip it.
        let tokens = text.split(separator: " ", omittingEmptySubsequences: false)
        var output: [String] = []
        for token in tokens {
            let normalized = token
                .trimmingCharacters(in: CharacterSet.punctuationCharacters)
                .lowercased()
            if output.count >= 2 {
                let last = output[output.count - 1]
                    .trimmingCharacters(in: CharacterSet.punctuationCharacters)
                    .lowercased()
                let prev = output[output.count - 2]
                    .trimmingCharacters(in: CharacterSet.punctuationCharacters)
                    .lowercased()
                if !normalized.isEmpty, normalized == last, normalized == prev {
                    // We're in a stutter run — keep the first two we already
                    // emitted (no, actually: drop the third+). Reading Handy
                    // more carefully: they collapse to ONE, not two. Fix:
                    // pop the last duplicate too so the run collapses to one.
                    output.removeLast()
                    continue
                }
            }
            output.append(String(token))
        }
        return output.joined(separator: " ")
    }

    // MARK: - Whitespace normalization

    /// Collapse runs of whitespace and leading-space-before-punctuation
    /// produced by filler removal.
    private static func normalizeWhitespace(_ text: String) -> String {
        var output = text
        // Collapse multiple spaces
        if let regex = try? NSRegularExpression(pattern: #"\s+"#) {
            let range = NSRange(output.startIndex..., in: output)
            output = regex.stringByReplacingMatches(
                in: output,
                range: range,
                withTemplate: " "
            )
        }
        // Fix "word ," and "word ." that filler removal left behind
        if let regex = try? NSRegularExpression(pattern: #"\s+([,.;:!?])"#) {
            let range = NSRange(output.startIndex..., in: output)
            output = regex.stringByReplacingMatches(
                in: output,
                range: range,
                withTemplate: "$1"
            )
        }
        return output
    }
}
