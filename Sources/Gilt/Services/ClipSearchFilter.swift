import Foundation

/// Shared clip filtering/sorting logic used by the store's derived state.
enum ClipSearchFilter {
    static func visibleClips(
        windowClips: [ClipItemModel],
        selectedFolder: ClipFolderModel?,
        searchText: String
    ) -> [ClipItemModel] {
        guard let selectedFolder else {
            return sort(windowClips)
        }
        return textFilter(
            clips: folderScopedClips(windowClips: windowClips, selectedFolder: selectedFolder),
            searchText: searchText
        )
    }

    /// Folder membership scoping, separated from text matching so the store can
    /// cache this result across search keystrokes. Walking `item.folders` (and
    /// materializing `selectedFolder.clips` for non-Clipboard folders) traverses
    /// SwiftData relationships, doing it per keystroke was a search-typing cost.
    static func folderScopedClips(
        windowClips: [ClipItemModel],
        selectedFolder: ClipFolderModel
    ) -> [ClipItemModel] {
        // Non-Clipboard folders need their own full relationship-backed contents.
        // Filtering only the global in-memory window makes older smart-folder items
        // appear to "vanish" even though they still exist in SwiftData.
        let sourceClips = if selectedFolder.isClipboardFolder {
            windowClips
        } else {
            Array(selectedFolder.clips)
        }
        let folderID = selectedFolder.folderID
        return sourceClips.filter { item in
            item.folders.contains(where: { $0.folderID == folderID })
        }
    }

    /// Text-query matching + sort over an already folder-scoped list.
    static func textFilter(
        clips: [ClipItemModel],
        searchText: String
    ) -> [ClipItemModel] {
        let query = SearchQuery(rawValue: searchText)
        if query.isEmpty {
            return sort(clips)
        }
        return sort(clips.filter { matches($0, query: query) })
    }

    static func filter(
        clips: [ClipItemModel],
        selectedFolderID: UUID,
        searchText: String
    ) -> [ClipItemModel] {
        let folderScoped = clips.filter { item in
            item.folders.contains(where: { $0.folderID == selectedFolderID })
        }
        return textFilter(clips: folderScoped, searchText: searchText)
    }

    private static func matches(_ item: ClipItemModel, query: SearchQuery) -> Bool {
        if let typeFilter = query.typeFilter, !item.typeRaw.contains(typeFilter) {
            return false
        }
        if let appFilter = query.appFilter,
           !item.sourceAppName.localizedCaseInsensitiveContains(appFilter) {
            return false
        }
        if let tagFilter = query.tagFilter,
           !item.contentTagsRaw.localizedCaseInsensitiveContains(tagFilter),
           !(item.aiKeywordsRaw?.localizedCaseInsensitiveContains(tagFilter) ?? false) {
            return false
        }
        guard !query.freeText.isEmpty else { return true }
        return item.previewText.localizedCaseInsensitiveContains(query.freeText)
            || (item.textValue?.localizedCaseInsensitiveContains(query.freeText) ?? false)
            || (item.urlValue?.localizedCaseInsensitiveContains(query.freeText) ?? false)
            || (item.recognizedText?.localizedCaseInsensitiveContains(query.freeText) ?? false)
            || (item.aiKeywordsRaw?.localizedCaseInsensitiveContains(query.freeText) ?? false)
            || item.sourceAppName.localizedCaseInsensitiveContains(query.freeText)
            || item.typeRaw.localizedCaseInsensitiveContains(query.freeText)
    }

    /// Re-checks stale DB-backfill hits against the CURRENT query using the same
    /// two fields the database predicate matches (previewText, sourceAppName).
    /// While a fresh backfill is pending (180ms after typing pauses), extending a
    /// query keeps still-matching extras on screen instead of dropping them and
    /// re-adding them later, that grow/shrink/grow churn read as search jank.
    static func provisionalBackfillMatches(
        _ backfillClips: [ClipItemModel],
        query: String
    ) -> [ClipItemModel] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return backfillClips.filter { item in
            item.previewText.localizedStandardContains(trimmed)
                || item.sourceAppName.localizedStandardContains(trimmed)
        }
    }

    static func mergeBackfillResults(
        visibleClips: [ClipItemModel],
        backfillClips: [ClipItemModel],
        selectedFolderID: UUID
    ) -> [ClipItemModel] {
        guard !backfillClips.isEmpty else { return visibleClips }

        let visibleIDs = Set(visibleClips.map(\.clipID))
        let extras = backfillClips.filter { !visibleIDs.contains($0.clipID) }
        guard !extras.isEmpty else { return visibleClips }

        // Scope + sort stated directly (an empty-query filter() call did the
        // same thing, but coupled this merge to SearchQuery parsing semantics).
        let scopedExtras = extras.filter { item in
            item.folders.contains(where: { $0.folderID == selectedFolderID })
        }
        return visibleClips + sort(scopedExtras)
    }

    static func sort(_ clips: [ClipItemModel]) -> [ClipItemModel] {
        clips.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned && !b.isPinned }
            if a.sortOrder != b.sortOrder { return a.sortOrder > b.sortOrder }
            return a.createdAt > b.createdAt
        }
    }
}

private struct SearchQuery {
    let typeFilter: String?
    let appFilter: String?
    let tagFilter: String?
    let freeText: String

    var isEmpty: Bool {
        typeFilter == nil && appFilter == nil && tagFilter == nil && freeText.isEmpty
    }

    init(rawValue: String) {
        let raw = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var parsedTypeFilter: String?
        var parsedAppFilter: String?
        var parsedTagFilter: String?
        var queryText = ""

        for token in raw.split(whereSeparator: \.isWhitespace).map(String.init) {
            if token.hasPrefix("type:") {
                parsedTypeFilter = String(token.dropFirst(5))
            } else if token.hasPrefix("app:") {
                parsedAppFilter = String(token.dropFirst(4))
            } else if token.hasPrefix("tag:") {
                parsedTagFilter = String(token.dropFirst(4))
            } else {
                if !queryText.isEmpty { queryText += " " }
                queryText += token
            }
        }

        typeFilter = parsedTypeFilter
        appFilter = parsedAppFilter
        tagFilter = parsedTagFilter
        freeText = queryText
    }
}
