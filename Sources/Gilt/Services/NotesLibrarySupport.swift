import Foundation

/// Resolves which notes are Kanban boards, in sidebar order. Explicit ids that
/// still point at a live note are kept (de-duplicated). When none survive — the
/// legacy single-board case on first upgrade — any note whose body is
/// structurally a board is adopted so the user keeps their tasks.
func resolvedKanbanBoardNoteIDs(explicitIDs: [UUID], notes: [NoteItem]) -> [UUID] {
    var seen = Set<UUID>()
    let resolved = explicitIDs.filter { id in
        guard notes.contains(where: { $0.noteID == id && !$0.isArchived }) else { return false }
        return seen.insert(id).inserted
    }
    if !resolved.isEmpty { return resolved }

    return notes
        .filter { note in
            note.origin == .workspace
                && !note.isArchived
                && NoteMarkdown.isKanbanBoard(markdown: note.bodyMarkdown)
        }
        .sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.noteID.uuidString < rhs.noteID.uuidString
        }
        .map(\.noteID)
}

func regularWorkspaceNotes(from notes: [NoteItem], excluding boardNoteIDs: Set<UUID>) -> [NoteItem] {
    notes.filter { !boardNoteIDs.contains($0.noteID) }
}

/// Display name for a board tab — the board note's title, falling back to the
/// generic board title if the note can't be found.
func boardTabTitle(for noteID: UUID, notes: [NoteItem]) -> String {
    notes.first(where: { $0.noteID == noteID })?.displayTitle ?? NoteMarkdown.boardTitle
}

func migratedWorkspaceSession(
    _ session: WorkspaceSession,
    boardNoteIDs: [UUID],
    notes: [NoteItem]
) -> WorkspaceSession {
    var migratedSession = session
    var migratedTabs: [WorkspaceTab] = []
    var selectedTabID = session.selectedTabID
    let primaryBoardID = boardNoteIDs.first
    let boardIDSet = Set(boardNoteIDs)

    for tab in session.tabs {
        let normalizedKind: WorkspaceTabKind?
        switch tab.kind {
        case .note(let noteID):
            // A legacy note-tab that pointed at a board becomes a board tab.
            normalizedKind = boardIDSet.contains(noteID) ? .kanbanBoard(noteID) : nil
        case .noteFolder:
            normalizedKind = nil
        case .kanbanBoard(let id):
            if id == WorkspaceTabKind.legacyBoardSentinel {
                // Pre-multi-board tab: point it at the primary board, or drop
                // it if no boards exist at all.
                normalizedKind = primaryBoardID.map { .kanbanBoard($0) }
            } else if boardIDSet.contains(id) {
                normalizedKind = .kanbanBoard(id)
            } else {
                // Board was deleted out from under this tab.
                normalizedKind = nil
            }
        case .clip, .clipFolder, .meetings:
            normalizedKind = tab.kind
        }

        guard let normalizedKind else { continue }

        if let existing = migratedTabs.first(where: { $0.kind == normalizedKind }) {
            if selectedTabID == tab.id {
                selectedTabID = existing.id
            }
            continue
        }

        var migratedTab = tab
        migratedTab.kind = normalizedKind
        if case .kanbanBoard(let id) = normalizedKind {
            migratedTab.title = boardTabTitle(for: id, notes: notes)
        }
        migratedTabs.append(migratedTab)

        if selectedTabID == tab.id {
            selectedTabID = migratedTab.id
        }
    }

    migratedSession.tabs = migratedTabs
    migratedSession.selectedTabID = selectedTabID

    if migratedSession.selectedTabID != nil,
       migratedSession.tabs.contains(where: { $0.id == migratedSession.selectedTabID }) == false {
        migratedSession.selectedTabID = migratedSession.tabs.last?.id
    }

    return migratedSession
}

func updateNoteSnapshotClip(_ clip: ClipItemModel, note: NoteItem, clipboardFolder: ClipFolderModel?) {
    clip.title = note.displayTitle
    clip.previewText = NoteMarkdown.plainPreview(for: note.bodyMarkdown)
    clip.textValue = note.bodyMarkdown
    clip.createdAt = note.updatedAt
    clip.sourceAppName = "\(AppBrand.displayName) Note"
    clip.sourceBundleID = "ink.gilt.note"

    guard let clipboardFolder else { return }
    if !clip.folders.contains(where: { $0.folderID == clipboardFolder.folderID }) {
        clip.folders.append(clipboardFolder)
    }
}

func makeNoteSnapshotClip(note: NoteItem, sortOrder: Int, clipboardFolder: ClipFolderModel?) -> ClipItemModel {
    let clip = ClipItemModel(
        clipID: UUID(),
        typeRaw: ClipType.text.rawValue,
        title: note.displayTitle,
        previewText: NoteMarkdown.plainPreview(for: note.bodyMarkdown),
        textValue: note.bodyMarkdown,
        sourceAppName: "\(AppBrand.displayName) Note",
        sourceBundleID: "ink.gilt.note",
        createdAt: note.updatedAt,
        contentHash: "",
        sortOrder: sortOrder,
        folders: clipboardFolder.map { [$0] } ?? []
    )
    clip.contentHash = ContentFingerprint.fingerprint(for: clip)
    return clip
}
