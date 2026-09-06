import Foundation

/// Pure matching + limiting rules for the command palette. No UI and no app
/// state, so the search behavior (what matches, how many survive, the empty-query
/// "show everything up to the limit" rule) is unit-testable in isolation.
///
/// All matching is case- and diacritic-insensitive substring matching. An empty
/// (or whitespace-only) query matches everything — the palette uses that to show
/// a useful default list the moment it opens.
enum CommandPaletteMatcher {
    /// True when `query` is found in any of `fields`. Empty query matches all.
    static func matches(query: String, _ fields: String...) -> Bool {
        matches(query: query, fields: fields)
    }

    static func matches(query: String, fields: [String]) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return fields.contains { field in
            field.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    /// Filter the action catalog. Matches against title, subtitle, and keywords.
    static func filterActions(_ actions: [CommandAction], query: String, limit: Int) -> [CommandAction] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matched = actions.filter { action in
            guard !trimmed.isEmpty else { return true }
            return matches(query: trimmed, fields: [action.title, action.subtitle] + action.keywords)
        }
        return Array(matched.prefix(max(0, limit)))
    }

    /// Generic content filter: callers pass each item's searchable text fields via
    /// `fields`, and get back the surviving items capped at `limit`. Keeps the
    /// clip/note/meeting/reminder filtering in one tested place without this file
    /// having to know about any concrete model type.
    static func filter<Item>(
        _ items: [Item],
        query: String,
        limit: Int,
        fields: (Item) -> [String]
    ) -> [Item] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matched = items.filter { item in
            guard !trimmed.isEmpty else { return true }
            return matches(query: trimmed, fields: fields(item))
        }
        return Array(matched.prefix(max(0, limit)))
    }
}
