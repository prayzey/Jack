import Foundation

enum QuickNoteImageMarkdown {
    /// Stable in-app image reference embedded in note markdown.
    static let schemePrefix = "jack-image:"

    static var referencePattern: String {
        #"!\[[^\]]*\]\(jack-image:([0-9a-fA-F-]{36})\)"#
    }

    static func imageReference(imageID: UUID) -> String {
        "![image](\(schemePrefix)\(imageID.uuidString.lowercased()))"
    }

    static func imageBlock(imageID: UUID) -> String {
        "\n\n\(imageReference(imageID: imageID))\n\n"
    }

    static func imageIDs(in markdown: String) -> [UUID] {
        guard let regex = try? NSRegularExpression(pattern: referencePattern) else { return [] }
        let nsMarkdown = markdown as NSString
        let matches = regex.matches(
            in: markdown,
            range: NSRange(location: 0, length: nsMarkdown.length)
        )
        return matches.compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            let idString = nsMarkdown.substring(with: match.range(at: 1))
            return UUID(uuidString: idString)
        }
    }

    static func plainTextReplacingImageReferences(_ markdown: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: referencePattern) else { return markdown }
        let nsMarkdown = markdown as NSString
        let replaced = regex.stringByReplacingMatches(
            in: markdown,
            range: NSRange(location: 0, length: nsMarkdown.length),
            withTemplate: ""
        )
        // Collapse the blank lines left behind by removed references with a
        // regex over the whole run — a single literal "\n\n\n" pass only
        // shortens a 4+ newline run by one and leaves triples behind.
        return replaced
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
