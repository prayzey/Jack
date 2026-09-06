import Foundation

/// Tolaria's "inbox" view = notes that haven't been *categorized* yet.
///
/// A note counts as inbox material when **both** signals are absent:
/// - No `type:` field in the frontmatter (so the user hasn't classified it
///   with a project / person / responsibility / etc.)
/// - No outgoing `[[wikilinks]]` (so it isn't woven into the graph)
///
/// The intuition: as soon as you assign a type or link the note into the
/// rest of your knowledge base, it stops being "needs organizing" and lives
/// somewhere meaningful. Inbox automatically empties as you do real work.
///
/// We intentionally do NOT consider pinned/folder/sortOrder state — those
/// are orthogonal to whether a note has been classified. A pinned but
/// untyped, unlinked note is still inbox material.
enum NoteInboxFilter {

    /// Returns true if `markdown` should appear in the inbox virtual view.
    static func isInbox(_ markdown: String) -> Bool {
        let frontmatter = NoteFrontmatterParser.parse(markdown)
        if let type = frontmatter.type, !type.trimmingCharacters(in: .whitespaces).isEmpty {
            return false
        }
        // Use `frontmatter.body` (frontmatter stripped) when counting links so
        // a stray `[[…]]` *inside* the YAML block doesn't accidentally
        // classify a note as organized.
        let outgoing = WikilinkExtractor.uniqueTargets(in: frontmatter.body)
        return outgoing.isEmpty
    }
}
