import Foundation

/// Splits transcript chunks into prompt-sized windows for the summarizer and
/// Q&A models. Pure value-type logic so we can unit test it cleanly.
struct MeetingTranscriptChunker {
    /// Maximum length of a single window passed to the summarizer, measured in characters.
    /// Conservative for a 4B Q4 LLM running locally on a Mac.
    var maxWindowCharacters: Int = 3_500
    /// Overlap between adjacent windows so context is preserved across boundaries.
    var overlapCharacters: Int = 350

    func windows(from chunks: [MeetingTranscriptChunk]) -> [[MeetingTranscriptChunk]] {
        guard !chunks.isEmpty else { return [] }
        var result: [[MeetingTranscriptChunk]] = []
        var current: [MeetingTranscriptChunk] = []
        var currentLength = 0

        for chunk in chunks {
            let chunkLength = chunk.text.count + 12 // include a small timestamp prefix
            if currentLength + chunkLength > maxWindowCharacters, !current.isEmpty {
                result.append(current)
                current = trailingOverlap(of: current, characters: overlapCharacters)
                currentLength = current.reduce(0) { $0 + $1.text.count + 12 }
            }
            current.append(chunk)
            currentLength += chunkLength
        }

        if !current.isEmpty {
            result.append(current)
        }
        return result
    }

    /// Returns the most relevant transcript chunks for a question, scored by
    /// token overlap. Cheap and deterministic — meets the "look at relevant
    /// pages, not the whole notebook" guidance in the plan.
    func mostRelevantChunks(
        for question: String,
        in chunks: [MeetingTranscriptChunk],
        maxChunks: Int = 6
    ) -> [MeetingTranscriptChunk] {
        guard !chunks.isEmpty else { return [] }
        let questionTokens = tokens(in: question)
        guard !questionTokens.isEmpty else {
            return Array(chunks.suffix(maxChunks))
        }
        let scored = chunks.map { chunk -> (score: Double, chunk: MeetingTranscriptChunk) in
            let chunkTokens = tokens(in: chunk.text)
            guard !chunkTokens.isEmpty else { return (0, chunk) }
            let intersection = questionTokens.intersection(chunkTokens).count
            let union = questionTokens.union(chunkTokens).count
            let jaccard = Double(intersection) / Double(max(union, 1))
            return (jaccard, chunk)
        }
        return scored
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
            .prefix(maxChunks)
            .map { $0.chunk }
    }

    private func tokens(in text: String) -> Set<String> {
        let normalized = text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && $0.count > 2 }
        return Set(normalized).subtracting(Self.stopWords)
    }

    /// Common English/Spanish/German function words that would otherwise produce
    /// false matches across nearly every chunk. Kept here (not externalized)
    /// because chunker behavior depends on it being stable for tests.
    private static let stopWords: Set<String> = [
        // English
        "the", "and", "for", "with", "that", "this", "from", "were", "have",
        "was", "are", "you", "your", "our", "but", "not", "they", "them",
        "his", "her", "him", "its", "she", "all", "any", "who", "did",
        "what", "when", "where", "why", "how", "will", "can", "could",
        "would", "should", "about", "into", "than", "then", "say", "said",
        // Spanish
        "que", "los", "las", "una", "uno", "con", "por", "para", "como",
        "esta", "este", "esto", "son", "del", "del", "tambien",
        // German
        "und", "der", "die", "das", "den", "dem", "ein", "eine", "einen",
        "auf", "ist", "von", "mit", "fur", "wir", "ihr", "sie"
    ]

    private func trailingOverlap(
        of chunks: [MeetingTranscriptChunk],
        characters: Int
    ) -> [MeetingTranscriptChunk] {
        guard characters > 0 else { return [] }
        var collected: [MeetingTranscriptChunk] = []
        var total = 0
        for chunk in chunks.reversed() {
            collected.insert(chunk, at: 0)
            total += chunk.text.count
            if total >= characters { break }
        }
        return collected
    }
}
