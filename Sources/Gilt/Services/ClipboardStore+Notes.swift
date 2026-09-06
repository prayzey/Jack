import AppKit
import Foundation
import OSLog

private let quickNoteStoreLog = Logger(subsystem: AppBrand.logSubsystem, category: "QuickNote.Store")

/// Serial queue for encoding + writing the notes library off the main thread.
/// The JSON encode scales with total note count, so doing it inline on the
/// main actor made every debounced save janky once a user accumulated notes.
/// Serial so writes never overlap or race the file.
private let notesPersistQueue = DispatchQueue(label: "ink.gilt.notes-persist", qos: .utility)

func orderedQuickNotes(in notes: [NoteItem]) -> [NoteItem] {
    notes
        .filter { $0.origin == .quickNote && !$0.isArchived }
        .sorted {
            if $0.createdAt != $1.createdAt {
                return $0.createdAt < $1.createdAt
            }
            return $0.noteID.uuidString < $1.noteID.uuidString
        }
}

extension ClipboardStore {
    // MARK: - Persistence

    func loadNotesLibrary() {
        guard let data = try? Data(contentsOf: notesFileURL),
              let decoded = try? JSONDecoder().decode(NotesLibraryState.self, from: data) else {
            quickNoteStoreLog.info("loadNotesLibrary: no file or decode failed at \(self.notesFileURL.path, privacy: .public)")
            noteFolders = [NoteFolder.scratchpads, NoteFolder.notes]
            notes = []
            workspaceSession = WorkspaceSession()
            mirroredNoteClipIDs = [:]
            vaultSyncRecords = [:]
            kanbanBoardNoteIDs = []
            return
        }

        let loadedQuickCount = decoded.notes.filter { $0.origin == .quickNote }.count
        quickNoteStoreLog.info("loadNotesLibrary: file=\(self.notesFileURL.path, privacy: .public) totalNotes=\(decoded.notes.count) quickNotes=\(loadedQuickCount)")
        noteFolders = decoded.folders.sorted { $0.sortOrder < $1.sortOrder }
        notes = decoded.notes
        let resolvedBoardNoteIDs = resolvedKanbanBoardNoteIDs(
            explicitIDs: decoded.kanbanBoardNoteIDs,
            notes: notes
        )
        kanbanBoardNoteIDs = resolvedBoardNoteIDs
        workspaceSession = settings.restoreWorkspaceTabs
            ? migratedWorkspaceSession(decoded.workspaceSession, boardNoteIDs: resolvedBoardNoteIDs, notes: notes)
            : WorkspaceSession()
        mirroredNoteClipIDs = Dictionary(
            uniqueKeysWithValues: decoded.mirroredClipIDs.compactMap { key, value in
                guard let noteID = UUID(uuidString: key),
                      let clipID = UUID(uuidString: value) else {
                    return nil
                }
                return (noteID, clipID)
            }
        )
        vaultSyncRecords = Dictionary(
            uniqueKeysWithValues: decoded.vaultSyncRecords.compactMap { key, value in
                guard let noteID = UUID(uuidString: key) else { return nil }
                return (noteID, value)
            }
        )

        let cleanedVaultResidue = removeVaultExperimentResidueIfNeeded()
        let normalizedWorkspaceSurface = normalizeRetiredWorkspaceNotesSurface()
        let sweptEmptyQuickNotes = sweepEmptyQuickNotesOnLaunch()

        if decoded.kanbanBoardNoteIDs != resolvedBoardNoteIDs
            || (settings.restoreWorkspaceTabs
                && decoded.workspaceSession != workspaceSession)
            || cleanedVaultResidue
            || normalizedWorkspaceSurface
            || sweptEmptyQuickNotes {
            persistNotesLibrary()
        }

        // Begin watching the vault and reconcile anything edited while we were
        // closed (covers missed FSEvents + iCloud/Dropbox files that arrived late).
        if hasNotesVault {
            startVaultWatcher()
            reconcileVault(reason: "launch")
        }
    }

    /// Sweep empty quick notes out of the store on launch. Past versions of
    /// the cleanup path preserved any note the user had ever typed in (even
    /// after they cleared it), which left ghost empty notes scattered through
    /// the swipe list. The current rule is "empty quick note = gone," and
    /// this brings the persisted state in line with it.
    @discardableResult
    private func sweepEmptyQuickNotesOnLaunch() -> Bool {
        let empties = notes.filter { $0.origin == .quickNote && $0.isEmpty }
        guard !empties.isEmpty else { return false }
        quickNoteStoreLog.info("sweepEmptyQuickNotesOnLaunch removing \(empties.count) empty quickNote(s)")
        for note in empties {
            removeNoteImageAttachments(for: note.noteID)
            mirroredNoteClipIDs.removeValue(forKey: note.noteID)
        }
        let removedIDs = Set(empties.map(\.noteID))
        notes = notes.filter { !removedIDs.contains($0.noteID) }
        return true
    }

    /// Workspace used to ship an in-app notes library (folders, inbox, tabs).
    /// Quick Notes and the Kanban board still rely on the notes store, but the
    /// sidebar/tab surface is retired — strip orphaned workspace documents and
    /// note tabs every launch so restored sessions cannot resurrect Notes UI.
    @discardableResult
    private func normalizeRetiredWorkspaceNotesSurface() -> Bool {
        let boardIDs = resolvedKanbanBoardNoteIDs(explicitIDs: kanbanBoardNoteIDs, notes: notes)
        let boardIDSet = Set(boardIDs)
        let keepNoteIDs = Set(notes.compactMap { note -> UUID? in
            if note.origin == .quickNote { return note.noteID }
            if boardIDSet.contains(note.noteID) { return note.noteID }
            return nil
        })
        var changed = false

        let removedNoteIDs = notes.map(\.noteID).filter { !keepNoteIDs.contains($0) }
        if !removedNoteIDs.isEmpty {
            let removedOrigins = removedNoteIDs.compactMap { id in notes.first(where: { $0.noteID == id })?.origin.rawValue }.joined(separator: ",")
            quickNoteStoreLog.info("normalizeRetiredWorkspaceNotesSurface removing \(removedNoteIDs.count) notes origins=[\(removedOrigins, privacy: .public)]")
            for noteID in removedNoteIDs {
                removeNoteImageAttachments(for: noteID)
                mirroredNoteClipIDs.removeValue(forKey: noteID)
            }
            notes = notes.filter { keepNoteIDs.contains($0.noteID) }
            noteFolders = [NoteFolder.scratchpads, NoteFolder.notes]
            selectedNoteFolderID = NoteFolder.scratchpadsID
            changed = true
        }

        // Keep the tracked board list in sync with whatever boards survived.
        let survivingBoardIDs = boardIDs.filter { id in notes.contains { $0.noteID == id } }
        if survivingBoardIDs != kanbanBoardNoteIDs {
            kanbanBoardNoteIDs = survivingBoardIDs
            changed = true
        }

        let normalizedSession = migratedWorkspaceSession(workspaceSession, boardNoteIDs: kanbanBoardNoteIDs, notes: notes)
        if normalizedSession != workspaceSession {
            workspaceSession = normalizedSession
            changed = true
        }

        return changed
    }

    /// Debounced entry point for notes persistence. Note edits (typing in a
    /// Quick Note, drag-reorders, board updates) can fire dozens of times per
    /// second, and each write serializes the entire notes library to JSON —
    /// so callers must go through this coalescing layer, not the immediate
    /// writer. Pending writes are flushed on app termination by
    /// `flushPendingSaves` (see ClipboardStore+Enrichment).
    func persistNotesLibrary() {
        pendingNotesPersistWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingNotesPersistWorkItem = nil
            self.persistNotesLibraryNow()
        }
        pendingNotesPersistWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    /// Immediate full-library write. Only the debounce above and the
    /// termination flush should call this directly.
    ///
    /// The `state` snapshot is built on the main actor (cheap, copy-on-write),
    /// then the heavy JSON encode + atomic disk write run on `notesPersistQueue`
    /// off the main thread. Because `state` is a value snapshot, later main-actor
    /// mutations to `notes` can't corrupt this write. Pass `synchronous: true`
    /// (termination flush) to block until the bytes land.
    func persistNotesLibraryNow(synchronous: Bool = false) {
        let state = NotesLibraryState(
            folders: noteFolders.sorted { $0.sortOrder < $1.sortOrder },
            notes: notes,
            workspaceSession: workspaceSession,
            kanbanBoardNoteIDs: kanbanBoardNoteIDs,
            mirroredClipIDs: Dictionary(
                uniqueKeysWithValues: mirroredNoteClipIDs.map { ($0.key.uuidString, $0.value.uuidString) }
            ),
            vaultSyncRecords: Dictionary(
                uniqueKeysWithValues: vaultSyncRecords.map { ($0.key.uuidString, $0.value) }
            )
        )
        let url = notesFileURL

        if synchronous {
            notesPersistQueue.sync { Self.writeNotesLibrary(state, to: url) }
        } else {
            notesPersistQueue.async { Self.writeNotesLibrary(state, to: url) }
        }
    }

    /// Encode + atomic write. `nonisolated` so it runs on `notesPersistQueue`
    /// rather than hopping back to the main actor.
    nonisolated private static func writeNotesLibrary(_ state: NotesLibraryState, to url: URL) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func ensureSystemNoteFolders() {
        if !noteFolders.contains(where: { $0.folderID == NoteFolder.scratchpadsID }) {
            noteFolders.insert(NoteFolder.scratchpads, at: 0)
        }
        if !noteFolders.contains(where: { $0.folderID == NoteFolder.notesID }) {
            noteFolders.append(NoteFolder.notes)
        }
        noteFolders = noteFolders
            .sorted { $0.sortOrder < $1.sortOrder }
            .enumerated()
            .map { index, folder in
                var mutable = folder
                mutable.sortOrder = index
                return mutable
            }
        seedNoteSortOrderIfNeeded()
        seedExpandedNoteFoldersIfNeeded()
        persistNotesLibrary()
    }

    /// First-launch migration: legacy notes all decode with `sortOrder == 0`.
    /// Assign each note (within its folder) a unique sortOrder derived from
    /// `updatedAt` so the visible order doesn't shuffle, and so subsequent
    /// drag-reorders have stable integer slots to work with.
    private func seedNoteSortOrderIfNeeded() {
        // Only seed if every note still has the default value — protects
        // against re-seeding once the user has actually reordered.
        guard !notes.isEmpty, notes.allSatisfy({ $0.sortOrder == 0 }) else { return }
        let grouped = Dictionary(grouping: notes.indices, by: { notes[$0].folderID })
        for folderID in grouped.keys {
            let indices = grouped[folderID]!.sorted {
                // Pinned first, then newest-edited.
                if notes[$0].isPinned != notes[$1].isPinned { return notes[$0].isPinned }
                return notes[$0].updatedAt > notes[$1].updatedAt
            }
            for (slot, idx) in indices.enumerated() {
                notes[idx].sortOrder = slot
            }
        }
    }

    /// On first launch after the nested-tree redesign, the persisted
    /// `expandedNoteFolderIDs` is empty. Seeding it with every known folder
    /// means the user sees a fully-expanded tree (familiar Notes/Bear shape)
    /// rather than an empty sidebar that requires clicking each chevron.
    private func seedExpandedNoteFoldersIfNeeded() {
        guard workspaceSession.expandedNoteFolderIDs.isEmpty else { return }
        workspaceSession.expandedNoteFolderIDs = noteFolders.map { $0.folderID }
    }

    /// The short-lived markdown-vault experiment could import hundreds of
    /// external files into Jack's notes store. Once the vault feature is gone,
    /// restoring that bulk on workspace launch can freeze the app before the
    /// user sees a window. Keep Quick Notes and the task board, then reset the
    /// note-library surface back to its lightweight in-app baseline.
    private func removeVaultExperimentResidueIfNeeded() -> Bool {
        let workspaceNoteCount = notes.filter { $0.origin == .workspace }.count
        guard workspaceNoteCount >= 200 || noteFolders.count >= 50 else { return false }

        let boardIDs = resolvedKanbanBoardNoteIDs(explicitIDs: kanbanBoardNoteIDs, notes: notes)
        let boardIDSet = Set(boardIDs)
        let keepNoteIDs = Set(notes.compactMap { note -> UUID? in
            if note.origin == .quickNote { return note.noteID }
            if boardIDSet.contains(note.noteID) { return note.noteID }
            return nil
        })
        let removedNoteIDs = notes
            .map(\.noteID)
            .filter { !keepNoteIDs.contains($0) }

        for noteID in removedNoteIDs {
            removeNoteImageAttachments(for: noteID)
            mirroredNoteClipIDs.removeValue(forKey: noteID)
        }

        notes = notes.compactMap { note in
            guard keepNoteIDs.contains(note.noteID) else { return nil }
            var kept = note
            if kept.origin == .quickNote {
                kept.folderID = NoteFolder.scratchpadsID
            } else {
                kept.folderID = NoteFolder.notesID
            }
            return kept
        }

        noteFolders = [NoteFolder.scratchpads, NoteFolder.notes]
        selectedNoteFolderID = NoteFolder.scratchpadsID
        kanbanBoardNoteIDs = boardIDs.filter { id in notes.contains { $0.noteID == id } }
        workspaceSession = workspaceSessionAfterRemovingNoteTabs(boardNoteIDs: kanbanBoardNoteIDs)
        return true
    }

    private func workspaceSessionAfterRemovingNoteTabs(boardNoteIDs: [UUID]) -> WorkspaceSession {
        // migratedWorkspaceSession already rewrites legacy note-tabs into board
        // tabs, drops retired note/folder tabs, and fixes the selection.
        var session = migratedWorkspaceSession(workspaceSession, boardNoteIDs: boardNoteIDs, notes: notes)
        session.expandedNoteFolderIDs = [NoteFolder.scratchpadsID, NoteFolder.notesID]
        session.inboxExpanded = true
        return session
    }

    // MARK: - Lookups

    var selectedNoteFolder: NoteFolder? {
        noteFolders.first(where: { $0.folderID == selectedNoteFolderID })
    }

    var filteredNotes: [NoteItem] {
        let query = workspaceSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return workspaceDocumentNotes
            .filter { note in
                return note.folderID == selectedNoteFolderID
            }
            .filter { note in
                guard !query.isEmpty else { return true }
                let haystack = "\(note.title)\n\(note.bodyMarkdown)"
                return haystack.localizedCaseInsensitiveContains(query)
            }
            .sorted(by: noteOrderingPredicate)
    }

    /// Shared ordering used by every "notes in a folder" view: pinned notes
    /// rise to the top; among equally-pinned notes, the user's manual
    /// `sortOrder` decides position; `updatedAt` is the tiebreaker so legacy
    /// notes still feel newest-first before they've been reordered.
    private func noteOrderingPredicate(_ a: NoteItem, _ b: NoteItem) -> Bool {
        if a.isPinned != b.isPinned { return a.isPinned && !b.isPinned }
        if a.sortOrder != b.sortOrder { return a.sortOrder < b.sortOrder }
        return a.updatedAt > b.updatedAt
    }

    var workspaceFilteredClips: [ClipItemModel] {
        let query = workspaceSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return clips
            .filter { item in
                item.folders.contains(where: { $0.folderID == selectedFolderID }) || selectedFolderID == ClipFolderModel.clipboardID
            }
            .filter { item in
                guard !query.isEmpty else { return true }
                let haystack = "\(item.title)\n\(item.previewText)\n\(item.textValue ?? "")"
                return haystack.localizedCaseInsensitiveContains(query)
            }
    }

    var quickNotes: [NoteItem] {
        orderedQuickNotes(in: notes)
    }

    // MARK: - Boards

    /// Every Kanban board, in sidebar order. Each board is a workspace note
    /// whose body is markdown (`# Name` + `## Todo/Doing/Done` + checklist lines).
    var kanbanBoards: [NoteItem] {
        kanbanBoardNoteIDs.compactMap { id in
            guard let board = note(with: id), !board.isArchived else { return nil }
            return board
        }
    }

    /// The board shown by the currently selected tab, or `nil` when the
    /// selection isn't a board. Drives the sidebar's active-row highlight.
    var selectedBoardNoteID: UUID? {
        guard let selectedTabID = workspaceSession.selectedTabID,
              let tab = workspaceSession.tabs.first(where: { $0.id == selectedTabID }),
              case .kanbanBoard(let id) = tab.kind else { return nil }
        return id
    }

    /// Board that task-level actions target: the selected board, else the first
    /// board in the list. `nil` only when no boards exist yet.
    var activeBoardNoteID: UUID? {
        if let selectedBoardNoteID, kanbanBoardNoteIDs.contains(selectedBoardNoteID) {
            return selectedBoardNoteID
        }
        return kanbanBoardNoteIDs.first
    }

    func boardDisplayTitle(_ noteID: UUID) -> String {
        note(with: noteID)?.displayTitle ?? NoteMarkdown.boardTitle
    }

    /// Resolves a board note by id, but only if it's a tracked, live board.
    private func boardNote(_ noteID: UUID) -> NoteItem? {
        guard kanbanBoardNoteIDs.contains(noteID),
              let note = note(with: noteID), !note.isArchived else { return nil }
        return note
    }

    struct BoardParseCacheEntry {
        let body: String
        let tasks: [NoteTask]
        let columns: [NoteTaskColumn]
    }

    /// Tasks for a single board, preserving markdown line order within each
    /// column so drag-reordering stays stable and meaningful. Memoized — see
    /// `boardParse(for:)`.
    func extractedTasks(forBoard noteID: UUID) -> [NoteTask] {
        boardParse(for: noteID)?.tasks ?? []
    }

    /// Columns present on a board, in display order. Always begins with the
    /// three built-ins (Todo, Doing, Done) followed by user-added columns.
    /// Memoized — see `boardParse(for:)`.
    func boardColumns(forBoard noteID: UUID) -> [NoteTaskColumn] {
        boardParse(for: noteID)?.columns ?? NoteTaskColumn.defaults
    }

    /// Single memoized markdown parse per board note. Kanban's body pass asks
    /// for tasks once per column plus columns twice, and re-runs on every
    /// store change and drag-preview tick — parsing the note each time made
    /// dragging cards feel heavy. The cache revalidates against the note's
    /// current body, so any edit (move/reorder/rename task, typing) is picked
    /// up on the next read without explicit invalidation hooks.
    private func boardParse(for noteID: UUID) -> BoardParseCacheEntry? {
        guard let note = boardNote(noteID) else { return nil }
        if let cached = boardParseCache[noteID], cached.body == note.bodyMarkdown {
            return cached
        }
        let entry = BoardParseCacheEntry(
            body: note.bodyMarkdown,
            tasks: NoteMarkdown.extractTasks(from: note),
            columns: NoteMarkdown.extractColumns(from: note.bodyMarkdown)
        )
        boardParseCache[noteID] = entry
        return entry
    }

    var workspaceDocumentNotes: [NoteItem] {
        regularWorkspaceNotes(from: notes, excluding: Set(kanbanBoardNoteIDs))
            .filter { !$0.isArchived }
    }

    /// Tolaria-style "Inbox" view: every workspace note that hasn't been
    /// classified yet (no frontmatter `type:` and no outgoing `[[wikilinks]]`).
    /// As the user types or links, notes leave the inbox automatically.
    var inboxNotes: [NoteItem] {
        workspaceDocumentNotes
            .filter { NoteInboxFilter.isInbox($0.bodyMarkdown) }
            .sorted(by: noteOrderingPredicate)
    }

    func workspaceNotes(in folderID: UUID) -> [NoteItem] {
        workspaceDocumentNotes
            .filter { $0.folderID == folderID }
            .sorted(by: noteOrderingPredicate)
    }

    func note(with id: UUID) -> NoteItem? {
        notes.first(where: { $0.noteID == id })
    }

    var selectedWorkspaceNoteID: UUID? {
        guard let selectedTabID = workspaceSession.selectedTabID,
              let tab = workspaceSession.tabs.first(where: { $0.id == selectedTabID }) else {
            return nil
        }
        if case .note(let noteID) = tab.kind {
            return noteID
        }
        return nil
    }

    // MARK: - Quick Note appearance

    /// Swap the Quick Note theme for a random different one. Only the theme
    /// style changes — the user's font, size, colours, and wallpaper are left
    /// alone on purpose. Mutating the nested struct reassigns `settings`,
    /// which fires its `didSet` to persist and re-render every quick note.
    func randomizeQuickNoteStyle() {
        settings.quickNoteAppearance.style = QuickNoteStyle.randomStyle(
            excluding: settings.quickNoteAppearance.style
        )
    }

    // MARK: - Notes

    @discardableResult
    func createNote(
        origin: NoteOrigin,
        folderID: UUID? = nil,
        initialMarkdown: String = "",
        openInWorkspace: Bool = false
    ) -> NoteItem {
        let resolvedFolderID = folderID ?? (origin == .quickNote ? NoteFolder.scratchpadsID : NoteFolder.notesID)
        let now = Date()
        // New notes land at the top of their folder. We shift every existing
        // sortOrder in the folder up by one so the new note can take slot 0
        // without colliding — keeps slot integers stable and ordered.
        let folderNoteIndices = notes.indices.filter { notes[$0].folderID == resolvedFolderID }
        for idx in folderNoteIndices { notes[idx].sortOrder += 1 }
        let note = NoteItem(
            folderID: resolvedFolderID,
            title: NoteMarkdown.displayTitle(for: initialMarkdown),
            bodyMarkdown: initialMarkdown,
            createdAt: now,
            updatedAt: now,
            lastOpenedAt: now,
            origin: origin,
            sortOrder: 0
        )
        notes.append(note)
        selectedNoteFolderID = resolvedFolderID
        persistNotesLibrary()
        Analytics.noteCreated(origin: origin.rawValue)
        if openInWorkspace, origin == .quickNote {
            quickNoteActiveNoteID = note.noteID
            QuickNoteWindowManager.shared.show()
        }
        if settings.mirrorNotesIntoClipboardHistory, !note.isEmpty {
            syncMirroredClip(for: note.noteID)
        }
        return note
    }

    func updateNoteBody(_ noteID: UUID, markdown: String, syncMirror: Bool = false) {
        guard let index = notes.firstIndex(where: { $0.noteID == noteID }) else {
            quickNoteStoreLog.info("updateNoteBody: note not found id=\(noteID.uuidString, privacy: .public) chars=\(markdown.count)")
            return
        }
        guard notes[index].bodyMarkdown != markdown else { return }
        // Gated: this fires on every coalesced keystroke. OSLog interpolation in
        // the hot edit path is needless cost in release builds.
        if stateDebugLoggingEnabled {
            quickNoteStoreLog.info("updateNoteBody id=\(noteID.uuidString, privacy: .public) origin=\(self.notes[index].origin.rawValue, privacy: .public) oldChars=\(self.notes[index].bodyMarkdown.count) newChars=\(markdown.count)")
        }
        notes[index].bodyMarkdown = markdown
        var shouldRefreshWorkspaceTitles = false
        if notes[index].origin == .quickNote {
            let derivedTitle = NoteMarkdown.displayTitle(for: markdown)
            if notes[index].title != derivedTitle {
                notes[index].title = derivedTitle
                shouldRefreshWorkspaceTitles = true
            }
        }
        notes[index].updatedAt = Date()
        notes[index].lastOpenedAt = Date()
        persistNotesLibrary()
        scheduleVaultSync(for: noteID)
        if syncMirror, settings.mirrorNotesIntoClipboardHistory {
            syncMirroredClip(for: noteID)
        }
        if shouldRefreshWorkspaceTitles {
            refreshWorkspaceTitles()
        }
    }

    func updateNoteTitle(_ noteID: UUID, title: String, syncMirror: Bool = false) {
        guard let index = notes.firstIndex(where: { $0.noteID == noteID }) else { return }
        guard notes[index].title != title else { return }
        notes[index].title = title
        notes[index].updatedAt = Date()
        notes[index].lastOpenedAt = Date()
        persistNotesLibrary()
        scheduleVaultSync(for: noteID)
        if syncMirror, settings.mirrorNotesIntoClipboardHistory {
            syncMirroredClip(for: noteID)
        }
        refreshWorkspaceTitles()
    }

    func finalizeNoteEdits(_ noteID: UUID) {
        touchNote(noteID)
        if settings.mirrorNotesIntoClipboardHistory {
            syncMirroredClip(for: noteID)
        }
    }

    func touchNote(_ noteID: UUID) {
        guard let index = notes.firstIndex(where: { $0.noteID == noteID }) else { return }
        notes[index].lastOpenedAt = Date()
        persistNotesLibrary()
    }

    func cleanupQuickNoteIfNeeded(_ noteID: UUID) {
        guard let note = note(with: noteID) else {
            quickNoteStoreLog.info("cleanupQuickNoteIfNeeded: note not found id=\(noteID.uuidString, privacy: .public)")
            return
        }
        // Quick notes that are empty at cleanup time get deleted, period —
        // whether they were freshly created by a swipe or had content the
        // user later cleared. The user has told us twice that empty notes
        // shouldn't linger: they pollute the scroll list and make reopening
        // land on a blank page that feels like "a new note was created."
        // Cleanup only fires on hide/close/swipe-away, so a note the user
        // is *currently editing* (even if momentarily empty) is never lost.
        if note.origin == .quickNote && note.isEmpty {
            quickNoteStoreLog.info("cleanupQuickNoteIfNeeded: DELETING empty quickNote id=\(noteID.uuidString, privacy: .public)")
            deleteNote(noteID)
        } else {
            quickNoteStoreLog.info("cleanupQuickNoteIfNeeded: keeping note id=\(noteID.uuidString, privacy: .public) origin=\(note.origin.rawValue, privacy: .public) chars=\(note.bodyMarkdown.count)")
            touchNote(noteID)
        }
    }

    func deleteNote(_ noteID: UUID) {
        // Trash the vault copy (recoverable) before we drop the note + its record.
        removeVaultFile(for: noteID)
        removeNoteImageAttachments(for: noteID)
        notes.removeAll { $0.noteID == noteID }
        kanbanBoardNoteIDs.removeAll { $0 == noteID }
        if quickNoteActiveNoteID == noteID {
            quickNoteActiveNoteID = nil
        }
        if let mirroredClipID = mirroredNoteClipIDs.removeValue(forKey: noteID) {
            deleteClips([mirroredClipID])
        }
        workspaceSession.tabs.removeAll { tab in
            switch tab.kind {
            case .note(let id): return id == noteID
            case .kanbanBoard(let id): return id == noteID
            default: return false
            }
        }
        if workspaceSession.selectedTabID != nil,
           !workspaceSession.tabs.contains(where: { $0.id == workspaceSession.selectedTabID }) {
            workspaceSession.selectedTabID = workspaceSession.tabs.last?.id
        }
        persistNotesLibrary()
    }

    func createNoteFolder(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let folder = NoteFolder(
            name: trimmed,
            folderIconRaw: FolderIcon.symbol("folder").rawValue,
            colorRaw: FolderColorToken.emerald.rawValue,
            sortOrder: noteFolders.count
        )
        noteFolders.append(folder)
        persistNotesLibrary()
    }

    func renameNoteFolder(_ folderID: UUID, name: String) {
        guard let index = noteFolders.firstIndex(where: { $0.folderID == folderID }) else { return }
        guard !noteFolders[index].isSystem else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        noteFolders[index].name = trimmed
        refreshWorkspaceTitles()
        persistNotesLibrary()
    }

    func updateNoteFolderIcon(_ folderID: UUID, icon: FolderIcon?) {
        guard let index = noteFolders.firstIndex(where: { $0.folderID == folderID }) else { return }
        guard !noteFolders[index].isSystem else { return }
        noteFolders[index].folderIconRaw = icon?.rawValue
        persistNotesLibrary()
    }

    func updateNoteFolderColor(_ folderID: UUID, color: FolderColorToken) {
        guard let index = noteFolders.firstIndex(where: { $0.folderID == folderID }) else { return }
        guard !noteFolders[index].isSystem else { return }
        noteFolders[index].colorRaw = color.rawValue
        persistNotesLibrary()
    }

    func deleteNoteFolder(_ folderID: UUID) {
        guard folderID != NoteFolder.scratchpadsID, folderID != NoteFolder.notesID else { return }
        noteFolders.removeAll { $0.folderID == folderID }
        for index in notes.indices where notes[index].folderID == folderID {
            notes[index].folderID = NoteFolder.notesID
            notes[index].updatedAt = Date()
        }
        if selectedNoteFolderID == folderID {
            selectedNoteFolderID = NoteFolder.notesID
        }
        persistNotesLibrary()
    }

    // MARK: - Board CRUD

    /// Creates a new empty board named `name` and opens it in its own tab.
    /// Returns the new board's note id.
    @discardableResult
    func createBoard(name: String) -> UUID {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let boardName = trimmed.isEmpty ? NoteMarkdown.boardTitle : trimmed
        // createNote derives the note title from the markdown H1, so the board
        // name lives in one place (`# <name>`) and the title mirrors it.
        let note = createNote(
            origin: .workspace,
            folderID: NoteFolder.notesID,
            initialMarkdown: NoteMarkdown.emptyBoardTemplate(title: boardName),
            openInWorkspace: false
        )
        kanbanBoardNoteIDs.append(note.noteID)
        persistNotesLibrary()
        openBoard(note.noteID)
        return note.noteID
    }

    /// Renames a board: rewrites its markdown H1 and mirrors it into the note
    /// title so the sidebar row and tab update together.
    func renameBoard(_ noteID: UUID, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              kanbanBoardNoteIDs.contains(noteID),
              let note = note(with: noteID) else { return }
        let updatedMarkdown = NoteMarkdown.renameBoard(in: note.bodyMarkdown, to: trimmed)
        updateNoteBody(noteID, markdown: updatedMarkdown, syncMirror: true)
        // updateNoteTitle refreshes workspace tab titles for us.
        updateNoteTitle(noteID, title: trimmed)
    }

    /// Deletes a board and its underlying note (which closes its tab too).
    func deleteBoard(_ noteID: UUID) {
        guard kanbanBoardNoteIDs.contains(noteID) else { return }
        deleteNote(noteID)
    }

    // MARK: - Tasks

    func tasks(for column: NoteTaskColumn, inBoard noteID: UUID) -> [NoteTask] {
        extractedTasks(forBoard: noteID).filter { $0.column == column }
    }

    func moveTask(_ task: NoteTask, to column: NoteTaskColumn) {
        guard let note = note(with: task.noteID) else { return }
        let updated = NoteMarkdown.moveTask(in: note.bodyMarkdown, lineIndex: task.lineIndex, to: column)
        updateNoteBody(task.noteID, markdown: updated, syncMirror: true)
    }

    /// Moves `task` into `column` at the given position among existing tasks in that
    /// column. `targetIndex` represents the slot index in the column's task list as
    /// shown to the user, *before* the moved task is reinserted. Pass `nil` to append.
    func reorderTask(_ task: NoteTask, to column: NoteTaskColumn, targetIndex: Int?) {
        guard let note = note(with: task.noteID) else { return }

        // Normalize: when moving within the same column, removing the source row
        // shifts every later slot up by one. The caller passes the index in the
        // original list, so we adjust before forwarding to the markdown layer
        // (which sees the post-removal list).
        var adjusted = targetIndex
        if task.column == column, let raw = targetIndex {
            let tasksInColumn = extractedTasks(forBoard: task.noteID).filter { $0.column == column }
            if let currentIndex = tasksInColumn.firstIndex(where: { $0.id == task.id }),
               raw > currentIndex {
                adjusted = raw - 1
            }
            // Dropping on its own slot or the slot directly after itself is a no-op.
            if adjusted == tasksInColumn.firstIndex(where: { $0.id == task.id }) {
                return
            }
        }

        let updated = NoteMarkdown.moveTask(
            in: note.bodyMarkdown,
            lineIndex: task.lineIndex,
            to: column,
            targetIndex: adjusted
        )
        updateNoteBody(task.noteID, markdown: updated, syncMirror: true)
    }

    func renameTask(_ task: NoteTask, to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != task.title else { return }
        guard let note = note(with: task.noteID) else { return }
        let updated = NoteMarkdown.renameTask(in: note.bodyMarkdown, lineIndex: task.lineIndex, newTitle: trimmed)
        updateNoteBody(task.noteID, markdown: updated, syncMirror: true)
    }

    func createTask(title: String, in column: NoteTaskColumn, boardID: UUID) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let note = boardNote(boardID) else { return }
        let updated = NoteMarkdown.addTask(in: note.bodyMarkdown, title: trimmed, to: column)
        updateNoteBody(boardID, markdown: updated, syncMirror: true)
    }

    func deleteTask(_ task: NoteTask) {
        guard let note = note(with: task.noteID) else { return }
        let updated = NoteMarkdown.removeTask(in: note.bodyMarkdown, lineIndex: task.lineIndex)
        updateNoteBody(task.noteID, markdown: updated, syncMirror: true)
    }

    /// Adds a new kanban column with the given title to `boardID`. Returns the
    /// resolved column on success (so the caller can immediately focus/compose
    /// it), or nil if the title is empty. Re-adding an existing column id is a
    /// no-op and returns the existing column.
    @discardableResult
    func addKanbanColumn(title: String, boardID: UUID) -> NoteTaskColumn? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let note = boardNote(boardID) else { return nil }
        guard let result = NoteMarkdown.addColumn(in: note.bodyMarkdown, title: trimmed) else {
            return nil
        }
        updateNoteBody(boardID, markdown: result.markdown, syncMirror: true)
        return result.column
    }

    /// Removes a custom kanban column and every task it contains from `boardID`.
    /// Built-in columns (`.todo`, `.doing`, `.done`) cannot be removed.
    func removeKanbanColumn(_ column: NoteTaskColumn, boardID: UUID) {
        guard !column.isBuiltIn, let note = boardNote(boardID) else { return }
        let updated = NoteMarkdown.removeColumn(in: note.bodyMarkdown, column: column)
        guard updated != note.bodyMarkdown else { return }
        updateNoteBody(boardID, markdown: updated, syncMirror: true)
    }

    // MARK: - Workspace Tabs

    func ensureDefaultWorkspaceTab() {
        guard workspaceSession.tabs.isEmpty else { return }
        openKanbanBoard()
    }

    func openClipInWorkspace(_ clipID: UUID) {
        let title = clips.first(where: { $0.clipID == clipID })?.title ?? "Clip"
        openWorkspaceTab(kind: .clip(clipID), preferredTitle: title)
        workspaceSession.selectedSidebarSection = .clipboard
        persistNotesLibrary()
    }

    func openWorkspaceFolderTab(_ folderID: UUID, isNoteFolder: Bool) {
        guard !isNoteFolder else { return }
        let title = folders.first(where: { $0.folderID == folderID })?.name ?? "Clipboard"
        openWorkspaceTab(kind: .clipFolder(folderID), preferredTitle: title)
        persistNotesLibrary()
    }

    /// Opens the active board (the selected board tab, else the first board),
    /// creating a default board if none exist. Used by the Tasks nav tab and
    /// the command palette.
    func openKanbanBoard() {
        let boardID = activeBoardNoteID ?? ensurePrimaryBoardID()
        openBoard(boardID)
    }

    /// Opens a specific board in its own tab and switches the sidebar to Tasks.
    func openBoard(_ noteID: UUID) {
        guard note(with: noteID) != nil else { return }
        if !kanbanBoardNoteIDs.contains(noteID) {
            kanbanBoardNoteIDs.append(noteID)
        }
        openWorkspaceTab(kind: .kanbanBoard(noteID), preferredTitle: boardDisplayTitle(noteID))
        workspaceSession.selectedSidebarSection = .tasks
        persistNotesLibrary()
        Analytics.kanbanBoardOpened(totalBoards: kanbanBoardNoteIDs.count)
    }

    /// Open the Meetings dashboard tab in the workspace.
    /// Singleton surface — no ID, no folder, just one
    /// tab that lists every captured meeting and lets the user start a new one.
    func openMeetingsInWorkspace() {
        openWorkspaceTab(kind: .meetings, preferredTitle: "Meetings")
        workspaceSession.selectedSidebarSection = .meetings
        persistNotesLibrary()
    }

    /// Open a specific note as a workspace tab. Used by the command palette so a
    /// note search result lands directly on the document.
    func openNoteInWorkspace(_ noteID: UUID) {
        let title = note(with: noteID)?.displayTitle ?? "Note"
        openWorkspaceTab(kind: .note(noteID), preferredTitle: title)
        persistNotesLibrary()
    }

    /// Reassign a note to a different folder — used by sidebar drag-drop onto
    /// a folder header. The note lands at the *top* of the destination folder
    /// (slot 0); every existing sortOrder there shifts down by one. The source
    /// folder is resequenced afterwards so its slot integers stay contiguous.
    func moveNoteToFolder(_ noteID: UUID, folderID: UUID) {
        guard let index = notes.firstIndex(where: { $0.noteID == noteID }) else { return }
        guard noteFolders.contains(where: { $0.folderID == folderID }) else { return }
        guard notes[index].folderID != folderID else { return }
        let sourceFolderID = notes[index].folderID

        // Push everything in destination down to make room at the top.
        for i in notes.indices where notes[i].folderID == folderID {
            notes[i].sortOrder += 1
        }
        notes[index].folderID = folderID
        notes[index].sortOrder = 0
        notes[index].updatedAt = Date()

        // Re-sequence the source folder so slot integers stay contiguous —
        // not strictly required for correctness, but keeps later reorder math
        // simple and the debugger output sane.
        resequenceNoteSlots(in: sourceFolderID)
        persistNotesLibrary()
    }

    /// Drop a note into `folderID` at a specific visible index. Used by the
    /// sidebar tree when the user drags a note into the gap between two notes
    /// of another folder. `targetIndex` is the index *in the destination's
    /// ordered list* where the note should land. If the source and destination
    /// folder match, falls through to `reorderNoteInFolder`.
    func moveNoteToFolder(_ noteID: UUID, folderID: UUID, atIndex targetIndex: Int) {
        guard let note = note(with: noteID) else { return }
        if note.folderID == folderID {
            reorderNoteInFolder(noteID: noteID, to: targetIndex)
            return
        }
        moveNoteToFolder(noteID, folderID: folderID)
        // After the cross-folder move the note is at slot 0; nudge it down to
        // the requested target. `reorderNoteInFolder` handles bounds itself.
        if targetIndex > 0 { reorderNoteInFolder(noteID: noteID, to: targetIndex) }
    }

    /// Move a note to a new position *within its current folder*. Indices are
    /// expressed against the user-visible ordered list (after applying the
    /// shared `noteOrderingPredicate`). Pinned notes are reordered relative
    /// to other pinned notes only — pin-state is not changed here.
    func reorderNoteInFolder(noteID: UUID, to targetIndex: Int) {
        guard let note = note(with: noteID) else { return }
        let ordered = workspaceNotes(in: note.folderID)
        guard let currentIndex = ordered.firstIndex(where: { $0.noteID == noteID }) else { return }
        // Pure index math lives in `NoteOrdering` so it can be tested without
        // standing up a SwiftData container.
        let reordered = NoteOrdering.reorder(ordered, from: currentIndex, to: targetIndex)
        // No-op fast path: the helper returns the input unchanged when the
        // target collapses to the same slot. Skip the write to avoid touching
        // `updatedAt` on every drop attempt.
        guard reordered.map({ $0.noteID }) != ordered.map({ $0.noteID }) else { return }
        for (slot, n) in reordered.enumerated() {
            if let idx = notes.firstIndex(where: { $0.noteID == n.noteID }) {
                notes[idx].sortOrder = slot
            }
        }
        persistNotesLibrary()
    }

    /// Reassign sortOrder values 0..n-1 to every note in a folder, preserving
    /// current visible order. Called after a cross-folder move so the source
    /// folder doesn't end up with sparse slot integers.
    private func resequenceNoteSlots(in folderID: UUID) {
        let ordered = workspaceNotes(in: folderID)
        for (slot, n) in ordered.enumerated() {
            if let idx = notes.firstIndex(where: { $0.noteID == n.noteID }) {
                notes[idx].sortOrder = slot
            }
        }
    }

    /// Move a folder in the sidebar. Indices are against the visible folder
    /// list (already sorted by `sortOrder` on load). System folders can be
    /// reordered alongside user folders — there's no reason to lock them.
    func reorderNoteFolders(folderID: UUID, to targetIndex: Int) {
        let ordered = noteFolders.sorted { $0.sortOrder < $1.sortOrder }
        guard let currentIndex = ordered.firstIndex(where: { $0.folderID == folderID }) else { return }
        let reordered = NoteOrdering.reorder(ordered, from: currentIndex, to: targetIndex)
        guard reordered.map({ $0.folderID }) != ordered.map({ $0.folderID }) else { return }
        for (slot, f) in reordered.enumerated() {
            if let idx = noteFolders.firstIndex(where: { $0.folderID == f.folderID }) {
                noteFolders[idx].sortOrder = slot
            }
        }
        noteFolders.sort { $0.sortOrder < $1.sortOrder }
        persistNotesLibrary()
    }

    // MARK: - Expand / collapse

    func isNoteFolderExpanded(_ folderID: UUID) -> Bool {
        workspaceSession.expandedNoteFolderIDs.contains(folderID)
    }

    func setNoteFolderExpanded(_ folderID: UUID, expanded: Bool) {
        var set = Set(workspaceSession.expandedNoteFolderIDs)
        if expanded { set.insert(folderID) } else { set.remove(folderID) }
        workspaceSession.expandedNoteFolderIDs = noteFolders
            .map { $0.folderID }
            .filter { set.contains($0) }
        persistNotesLibrary()
    }

    func toggleNoteFolderExpanded(_ folderID: UUID) {
        setNoteFolderExpanded(folderID, expanded: !isNoteFolderExpanded(folderID))
    }

    func closeWorkspaceTab(_ tabID: UUID) {
        workspaceSession.tabs.removeAll { $0.id == tabID }
        if workspaceSession.selectedTabID == tabID {
            workspaceSession.selectedTabID = workspaceSession.tabs.last?.id
        }
        persistNotesLibrary()
    }

    func selectWorkspaceTab(_ tabID: UUID) {
        // Clicking a tab counts as "recently used" so it survives LRU eviction.
        if let index = workspaceSession.tabs.firstIndex(where: { $0.id == tabID }) {
            workspaceSession.tabs[index].lastAccessedAt = Date()
        }
        workspaceSession.selectedTabID = tabID
        persistNotesLibrary()
    }

    private func openWorkspaceTab(kind: WorkspaceTabKind, preferredTitle: String) {
        // Re-activating an existing tab also refreshes its recency so it isn't
        // the next thing evicted.
        if let index = workspaceSession.tabs.firstIndex(where: { $0.kind == kind }) {
            workspaceSession.tabs[index].lastAccessedAt = Date()
            workspaceSession.selectedTabID = workspaceSession.tabs[index].id
            return
        }
        // Enforce the cap before appending so the strip can't grow unbounded.
        workspaceSession.makeRoomForNewTab()
        let tab = WorkspaceTab(kind: kind, title: preferredTitle, lastAccessedAt: Date())
        workspaceSession.tabs.append(tab)
        workspaceSession.selectedTabID = tab.id
    }

    func refreshWorkspaceTitles() {
        workspaceSession.tabs = workspaceSession.tabs.map { tab in
            var mutable = tab
            switch tab.kind {
            case .note(let noteID):
                mutable.title = note(with: noteID)?.displayTitle ?? tab.title
            case .noteFolder(let folderID):
                mutable.title = noteFolders.first(where: { $0.folderID == folderID })?.name ?? tab.title
            case .clip(let clipID):
                mutable.title = clips.first(where: { $0.clipID == clipID })?.title ?? tab.title
            case .clipFolder(let folderID):
                mutable.title = folders.first(where: { $0.folderID == folderID })?.name ?? tab.title
            case .kanbanBoard(let boardID):
                mutable.title = boardDisplayTitle(boardID)
            case .meetings:
                mutable.title = "Meetings"
            }
            return mutable
        }
        persistNotesLibrary()
    }

    /// Returns the first live board, recovering a legacy board or creating a
    /// default one if the list is empty. Used when the user opens Tasks but has
    /// no board yet.
    @discardableResult
    private func ensurePrimaryBoardID() -> UUID {
        let liveNoteIDs = Set(notes.filter { !$0.isArchived }.map(\.noteID))
        if let first = kanbanBoardNoteIDs.first(where: { liveNoteIDs.contains($0) }) {
            return first
        }

        // Recover boards that exist as notes but aren't tracked yet (legacy
        // single-board upgrade, or a list that fell out of sync).
        let recovered = resolvedKanbanBoardNoteIDs(explicitIDs: kanbanBoardNoteIDs, notes: notes)
        if let first = recovered.first {
            kanbanBoardNoteIDs = recovered
            workspaceSession = migratedWorkspaceSession(workspaceSession, boardNoteIDs: recovered, notes: notes)
            persistNotesLibrary()
            return first
        }

        let note = createNote(
            origin: .workspace,
            folderID: NoteFolder.notesID,
            initialMarkdown: NoteMarkdown.emptyBoardTemplate(),
            openInWorkspace: false
        )
        kanbanBoardNoteIDs = [note.noteID]
        workspaceSession = migratedWorkspaceSession(workspaceSession, boardNoteIDs: kanbanBoardNoteIDs, notes: notes)
        persistNotesLibrary()
        return note.noteID
    }

    // MARK: - Clipboard Integration

    @discardableResult
    func copyNoteToClipboard(_ noteID: UUID) -> Bool {
        guard let note = note(with: noteID) else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let didWrite = pasteboard.setString(note.bodyMarkdown, forType: .string)
        guard didWrite else { return false }
        suppressedPasteboardChangeCount = pasteboard.changeCount
        return true
    }

    @discardableResult
    func saveNoteAsClipSnapshot(_ noteID: UUID) -> UUID? {
        guard let note = note(with: noteID) else { return nil }
        let clipID = createOrUpdateSnapshotClip(for: note, existingClipID: mirroredNoteClipIDs[noteID])
        mirroredNoteClipIDs[noteID] = clipID
        persistNotesLibrary()
        return clipID
    }

    func syncMirroredClip(for noteID: UUID) {
        guard let note = note(with: noteID) else { return }
        if note.isEmpty {
            if let clipID = mirroredNoteClipIDs.removeValue(forKey: noteID) {
                deleteClips([clipID])
            }
            persistNotesLibrary()
            return
        }

        let clipID = createOrUpdateSnapshotClip(for: note, existingClipID: mirroredNoteClipIDs[noteID])
        mirroredNoteClipIDs[noteID] = clipID
        persistNotesLibrary()
    }

    func isMirroredNoteClip(_ clip: ClipItemModel) -> Bool {
        mirroredNoteClipIDs.values.contains(clip.clipID) || clip.sourceBundleID == "ink.gilt.note"
    }

    private func createOrUpdateSnapshotClip(for note: NoteItem, existingClipID: UUID?) -> UUID {
        let clipboardFolder = folders.first(where: { $0.folderID == ClipFolderModel.clipboardID })

        if let existingClipID,
           let clip = clips.first(where: { $0.clipID == existingClipID }) {
            let previousHash = clip.contentHash
            updateNoteSnapshotClip(clip, note: note, clipboardFolder: clipboardFolder)
            let refreshedHash = ContentFingerprint.fingerprint(for: clip)
            if previousHash != refreshedHash, contentHashIndex[previousHash] == clip.clipID {
                contentHashIndex.removeValue(forKey: previousHash)
            }
            clip.contentHash = refreshedHash
            registerClipInHashIndex(clip)
            save()
            refreshClips()
            return clip.clipID
        }

        let nextSortOrder = highestSortOrder + 1
        let clip = makeNoteSnapshotClip(note: note, sortOrder: nextSortOrder, clipboardFolder: clipboardFolder)
        highestSortOrder = nextSortOrder
        modelContext.insert(clip)
        registerClipInHashIndex(clip)
        save()
        refreshClips()
        return clip.clipID
    }
}
