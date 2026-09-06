import Foundation

enum NoteOrigin: String, Codable, CaseIterable {
    case quickNote
    case workspace
}

enum WorkspaceSidebarSection: String, Codable, CaseIterable, Identifiable {
    case clipboard
    case tasks
    case meetings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .clipboard: return "Clipboard"
        case .tasks: return "Tasks"
        case .meetings: return L10n.string("workspace.sidebar.meetings.label", default: "Meetings")
        }
    }

    var icon: String {
        switch self {
        case .clipboard: return "doc.on.clipboard"
        case .tasks: return "square.grid.3x2"
        case .meetings: return "mic.fill"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        // Legacy sessions still persist "notes" or "pulse" even though those
        // workspace surfaces are retired — land those users on Clipboard instead.
        if raw == "notes" || raw == "pulse" {
            self = .clipboard
            return
        }
        self = WorkspaceSidebarSection(rawValue: raw) ?? .clipboard
    }
}

/// A Kanban column. Originally a fixed three-case enum (`todo`, `doing`,
/// `done`); now an open value type so users can add their own columns
/// alongside the three built-ins. Identity is the lowercased markdown title,
/// so "Backlog", "BACKLOG" and " backlog " all collapse to the same column.
struct NoteTaskColumn: Hashable, Codable, Identifiable {
    /// Stable identity (lowercased trimmed `markdownTitle`). Used for equality
    /// and dictionary lookup so renaming display text doesn't lose the column.
    let id: String
    /// The exact title written into the markdown as `## <markdownTitle>`.
    /// Built-ins use English ("Todo", "Doing", "Done") so the kanban file
    /// reads identically regardless of UI locale.
    let markdownTitle: String
    /// True for the three built-in columns, which can never be deleted.
    let isBuiltIn: Bool

    /// Markdown heading line ("## Todo", "## My Custom").
    var heading: String { "## \(markdownTitle)" }

    /// Column rule: tasks living under "Done" render with the checkbox
    /// checked; everything else renders unchecked. Custom columns are
    /// always treated as in-progress regardless of title.
    var isDone: Bool { id == NoteTaskColumn.done.id }

    /// Localized title for UI. Built-ins are translatable; custom columns
    /// use the user-provided title verbatim.
    var displayTitle: String {
        switch id {
        case NoteTaskColumn.todo.id:
            return L10n.string("workspace.kanban.column.todo", default: "Todo")
        case NoteTaskColumn.doing.id:
            return L10n.string("workspace.kanban.column.doing", default: "Doing")
        case NoteTaskColumn.done.id:
            return L10n.string("workspace.kanban.column.done", default: "Done")
        default:
            return markdownTitle
        }
    }

    static let todo = NoteTaskColumn(id: "todo", markdownTitle: "Todo", isBuiltIn: true)
    static let doing = NoteTaskColumn(id: "doing", markdownTitle: "Doing", isBuiltIn: true)
    static let done = NoteTaskColumn(id: "done", markdownTitle: "Done", isBuiltIn: true)

    /// The fixed default columns every kanban board guarantees.
    static let defaults: [NoteTaskColumn] = [.todo, .doing, .done]

    /// Builds a column from an arbitrary title. If the normalized title
    /// matches a built-in id, returns the built-in (so "todo", "Todo" etc.
    /// always resolve to `.todo`); otherwise returns a fresh custom column.
    static func column(forMarkdownTitle title: String) -> NoteTaskColumn {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.lowercased()
        switch normalized {
        case NoteTaskColumn.todo.id: return .todo
        case NoteTaskColumn.doing.id: return .doing
        case NoteTaskColumn.done.id: return .done
        default:
            return NoteTaskColumn(id: normalized, markdownTitle: trimmed, isBuiltIn: false)
        }
    }

    static func == (lhs: NoteTaskColumn, rhs: NoteTaskColumn) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct NoteFolder: Codable, Identifiable, Equatable {
    var folderID: UUID
    var name: String
    var folderIconRaw: String?
    var colorRaw: String
    var sortOrder: Int
    var isSystem: Bool

    init(
        folderID: UUID = UUID(),
        name: String,
        folderIconRaw: String? = nil,
        colorRaw: String = FolderColorToken.slate.rawValue,
        sortOrder: Int = 0,
        isSystem: Bool = false
    ) {
        self.folderID = folderID
        self.name = name
        self.folderIconRaw = folderIconRaw
        self.colorRaw = colorRaw
        self.sortOrder = sortOrder
        self.isSystem = isSystem
    }

    var id: UUID { folderID }

    var color: FolderColorToken {
        FolderColorToken(rawValue: colorRaw) ?? .slate
    }

    var icon: FolderIcon? {
        FolderIcon(rawValue: folderIconRaw)
    }

    static let scratchpadsID = UUID(uuidString: "B9D254BC-17F1-4D19-BF17-321D3B2A9001")!
    static let notesID = UUID(uuidString: "B9D254BC-17F1-4D19-BF17-321D3B2A9002")!

    static let scratchpads = NoteFolder(
        folderID: scratchpadsID,
        name: "Scratchpads",
        folderIconRaw: FolderIcon.symbol("note.text.badge.plus").rawValue,
        colorRaw: FolderColorToken.amber.rawValue,
        sortOrder: 0,
        isSystem: true
    )

    static let notes = NoteFolder(
        folderID: notesID,
        name: "Notes",
        folderIconRaw: FolderIcon.symbol("books.vertical").rawValue,
        colorRaw: FolderColorToken.sapphire.rawValue,
        sortOrder: 1,
        isSystem: true
    )
}

struct NoteItem: Codable, Identifiable, Equatable {
    var noteID: UUID
    var folderID: UUID
    var title: String
    var bodyMarkdown: String
    var createdAt: Date
    var updatedAt: Date
    var lastOpenedAt: Date
    var isPinned: Bool
    var isArchived: Bool
    var origin: NoteOrigin
    /// Manual position within a folder, set by drag-reorder. Lower = higher in the list.
    /// Defaults to 0 for legacy notes; the store resolves ties by falling back to
    /// `updatedAt` (descending) so newest-edits-first still works when nothing has
    /// been manually reordered.
    var sortOrder: Int
    /// Relative folder path inside the chosen Obsidian vault where this note
    /// should be saved (e.g. "Projects/Q3"). `nil` = local-only, not synced.
    /// Phase 0 only records this; no file is written to disk yet.
    var vaultRelativeFolder: String?

    init(
        noteID: UUID = UUID(),
        folderID: UUID,
        title: String = "Untitled Note",
        bodyMarkdown: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastOpenedAt: Date = Date(),
        isPinned: Bool = false,
        isArchived: Bool = false,
        origin: NoteOrigin,
        sortOrder: Int = 0,
        vaultRelativeFolder: String? = nil
    ) {
        self.noteID = noteID
        self.folderID = folderID
        self.title = title
        self.bodyMarkdown = bodyMarkdown
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastOpenedAt = lastOpenedAt
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.origin = origin
        self.sortOrder = sortOrder
        self.vaultRelativeFolder = vaultRelativeFolder
    }

    // Backwards-compatible decoding: notes persisted before sortOrder existed
    // simply default to 0. The store assigns proper ordering on first load via
    // `seedNoteSortOrderIfNeeded()`.
    private enum CodingKeys: String, CodingKey {
        case noteID, folderID, title, bodyMarkdown, createdAt, updatedAt
        case lastOpenedAt, isPinned, isArchived, origin, sortOrder, vaultRelativeFolder
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        noteID = try c.decode(UUID.self, forKey: .noteID)
        folderID = try c.decode(UUID.self, forKey: .folderID)
        title = try c.decode(String.self, forKey: .title)
        bodyMarkdown = try c.decode(String.self, forKey: .bodyMarkdown)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        lastOpenedAt = try c.decode(Date.self, forKey: .lastOpenedAt)
        isPinned = try c.decode(Bool.self, forKey: .isPinned)
        isArchived = try c.decode(Bool.self, forKey: .isArchived)
        origin = try c.decode(NoteOrigin.self, forKey: .origin)
        sortOrder = (try? c.decodeIfPresent(Int.self, forKey: .sortOrder)) ?? 0
        vaultRelativeFolder = try? c.decodeIfPresent(String.self, forKey: .vaultRelativeFolder)
    }

    var id: UUID { noteID }

    var displayTitle: String {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? "Untitled Note" : normalized
    }

    var isEmpty: Bool {
        bodyMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct NoteTask: Identifiable, Equatable {
    var id: String
    var noteID: UUID
    var lineIndex: Int
    var title: String
    var column: NoteTaskColumn
    var isChecked: Bool
}

enum WorkspaceTabKind: Codable, Equatable {
    case note(UUID)
    case noteFolder(UUID)
    case clip(UUID)
    case clipFolder(UUID)
    /// A Kanban board tab. Each board is a distinct note, so the tab carries
    /// the board's noteID — this is what lets several boards (Work, Personal,
    /// …) live as separate tabs at once.
    case kanbanBoard(UUID)
    case meetings

    /// Placeholder board id assigned when decoding a *legacy* `kanbanBoard`
    /// tab that predates per-board ids. Migration (`migratedWorkspaceSession`)
    /// rewrites this to the primary board's real id before anything persists,
    /// so this sentinel never survives a load → save cycle.
    static let legacyBoardSentinel = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    private enum CodingKeys: String, CodingKey {
        case type
        case id
    }

    private enum TabType: String, Codable {
        case note
        case noteFolder
        case clip
        case clipFolder
        case kanbanBoard
        case pulse  // legacy — decoded but never re-emitted
        case meetings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(TabType.self, forKey: .type)
        switch type {
        case .note:
            self = .note(try container.decode(UUID.self, forKey: .id))
        case .noteFolder:
            self = .noteFolder(try container.decode(UUID.self, forKey: .id))
        case .clip:
            self = .clip(try container.decode(UUID.self, forKey: .id))
        case .clipFolder:
            self = .clipFolder(try container.decode(UUID.self, forKey: .id))
        case .kanbanBoard:
            // Legacy tabs were encoded without an id; fall back to the sentinel
            // so migration can resolve it against the real board list.
            let id = try container.decodeIfPresent(UUID.self, forKey: .id)
                ?? WorkspaceTabKind.legacyBoardSentinel
            self = .kanbanBoard(id)
        case .pulse:
            // Pulse tab kind retired — surface legacy tabs as the meetings tab so users keep a real surface.
            self = .meetings
        case .meetings:
            self = .meetings
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .note(let id):
            try container.encode(TabType.note, forKey: .type)
            try container.encode(id, forKey: .id)
        case .noteFolder(let id):
            try container.encode(TabType.noteFolder, forKey: .type)
            try container.encode(id, forKey: .id)
        case .clip(let id):
            try container.encode(TabType.clip, forKey: .type)
            try container.encode(id, forKey: .id)
        case .clipFolder(let id):
            try container.encode(TabType.clipFolder, forKey: .type)
            try container.encode(id, forKey: .id)
        case .kanbanBoard(let id):
            try container.encode(TabType.kanbanBoard, forKey: .type)
            try container.encode(id, forKey: .id)
        case .meetings:
            try container.encode(TabType.meetings, forKey: .type)
        }
    }
}

struct WorkspaceTab: Codable, Identifiable, Equatable {
    var id: UUID
    var kind: WorkspaceTabKind
    var title: String
    var isPinned: Bool
    var createdAt: Date
    /// Last time this tab was opened or clicked. Drives least-recently-used
    /// eviction when the strip hits its cap. Optional so sessions persisted
    /// before recency tracking decode cleanly (synthesized Codable uses
    /// decodeIfPresent for Optionals) — `nil` falls back to `createdAt`.
    var lastAccessedAt: Date?

    init(
        id: UUID = UUID(),
        kind: WorkspaceTabKind,
        title: String,
        isPinned: Bool = false,
        createdAt: Date = Date(),
        lastAccessedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.lastAccessedAt = lastAccessedAt
    }

    /// Recency used for eviction ordering — explicit access time when present,
    /// otherwise creation time so legacy tabs still sort sensibly.
    var recency: Date { lastAccessedAt ?? createdAt }
}

struct WorkspaceSession: Codable, Equatable {
    var tabs: [WorkspaceTab] = []
    var selectedTabID: UUID?
    var selectedSidebarSection: WorkspaceSidebarSection = .clipboard
    /// Note-folder IDs that are currently expanded in the sidebar tree.
    /// Empty by default; on first load the store seeds this with every
    /// known folder so the tree shows everything until the user collapses.
    var expandedNoteFolderIDs: [UUID] = []
    /// Persisted expand/collapse state for the Inbox virtual section. The
    /// Inbox isn't a real folder so it can't ride along in
    /// `expandedNoteFolderIDs` — that array is filtered to known folder IDs
    /// every time we save, which would silently drop a sentinel ID.
    var inboxExpanded: Bool = true

    private enum CodingKeys: String, CodingKey {
        case tabs, selectedTabID, selectedSidebarSection, expandedNoteFolderIDs, inboxExpanded
    }

    init(
        tabs: [WorkspaceTab] = [],
        selectedTabID: UUID? = nil,
        selectedSidebarSection: WorkspaceSidebarSection = .clipboard,
        expandedNoteFolderIDs: [UUID] = [],
        inboxExpanded: Bool = true
    ) {
        self.tabs = tabs
        self.selectedTabID = selectedTabID
        self.selectedSidebarSection = selectedSidebarSection
        self.expandedNoteFolderIDs = expandedNoteFolderIDs
        self.inboxExpanded = inboxExpanded
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tabs = (try? c.decodeIfPresent([WorkspaceTab].self, forKey: .tabs)) ?? []
        selectedTabID = try? c.decodeIfPresent(UUID.self, forKey: .selectedTabID)
        selectedSidebarSection = (try? c.decodeIfPresent(WorkspaceSidebarSection.self, forKey: .selectedSidebarSection)) ?? .clipboard
        expandedNoteFolderIDs = (try? c.decodeIfPresent([UUID].self, forKey: .expandedNoteFolderIDs)) ?? []
        inboxExpanded = (try? c.decodeIfPresent(Bool.self, forKey: .inboxExpanded)) ?? true
    }

    // MARK: - Tab cap (LRU)

    /// Hard ceiling on open workspace tabs. The strip is read-only width and a
    /// growing pile of tabs becomes unmaintainable, so opening past this evicts
    /// the least-recently-used tab. Kept small on purpose.
    static let maxTabCount = 7

    /// The least-recently-used tab eligible for eviction, or `nil` when every
    /// tab is protected. Pinned tabs and the currently selected tab are never
    /// eviction candidates. Pure function so it can be unit-tested without the
    /// store / SwiftData.
    func evictionCandidateID() -> UUID? {
        tabs
            .filter { !$0.isPinned && $0.id != selectedTabID }
            .min { $0.recency < $1.recency }?
            .id
    }

    /// Evict least-recently-used tabs until there's room to append one more
    /// without exceeding `maxTabCount`. Protected tabs (pinned/selected) are
    /// never dropped, so in a pathological all-protected case the count can
    /// remain at the cap rather than evicting something it shouldn't.
    mutating func makeRoomForNewTab() {
        while tabs.count >= Self.maxTabCount, let victim = evictionCandidateID() {
            tabs.removeAll { $0.id == victim }
        }
    }
}

struct NotesLibraryState: Codable, Equatable, Sendable {
    var folders: [NoteFolder] = [NoteFolder.scratchpads, NoteFolder.notes]
    var notes: [NoteItem] = []
    var workspaceSession: WorkspaceSession = WorkspaceSession()
    /// Ordered list of note ids that are Kanban boards. The order is the order
    /// boards appear in the sidebar. Replaces the old single `kanbanBoardNoteID`
    /// so people can keep several boards (Work, Personal, …) side by side.
    var kanbanBoardNoteIDs: [UUID] = []
    /// noteID.uuidString -> mirrored clipID.uuidString
    var mirroredClipIDs: [String: String] = [:]
    /// noteID.uuidString -> vault sync bookkeeping (Obsidian sync, Phase 1+).
    var vaultSyncRecords: [String: VaultSyncRecord] = [:]

    private enum CodingKeys: String, CodingKey {
        case folders, notes, workspaceSession, kanbanBoardNoteIDs, mirroredClipIDs, vaultSyncRecords
        // Legacy key — decoded for migration only, never re-emitted.
        case kanbanBoardNoteID
    }

    init(
        folders: [NoteFolder] = [NoteFolder.scratchpads, NoteFolder.notes],
        notes: [NoteItem] = [],
        workspaceSession: WorkspaceSession = WorkspaceSession(),
        kanbanBoardNoteIDs: [UUID] = [],
        mirroredClipIDs: [String: String] = [:],
        vaultSyncRecords: [String: VaultSyncRecord] = [:]
    ) {
        self.folders = folders
        self.notes = notes
        self.workspaceSession = workspaceSession
        self.kanbanBoardNoteIDs = kanbanBoardNoteIDs
        self.mirroredClipIDs = mirroredClipIDs
        self.vaultSyncRecords = vaultSyncRecords
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        folders = try c.decodeIfPresent([NoteFolder].self, forKey: .folders) ?? [NoteFolder.scratchpads, NoteFolder.notes]
        notes = try c.decodeIfPresent([NoteItem].self, forKey: .notes) ?? []
        workspaceSession = try c.decodeIfPresent(WorkspaceSession.self, forKey: .workspaceSession) ?? WorkspaceSession()
        // Prefer the new list; fall back to the legacy single id so existing
        // users keep their one board (now the first board in the list).
        if let ids = try c.decodeIfPresent([UUID].self, forKey: .kanbanBoardNoteIDs) {
            kanbanBoardNoteIDs = ids
        } else if let legacy = try c.decodeIfPresent(UUID.self, forKey: .kanbanBoardNoteID) {
            kanbanBoardNoteIDs = [legacy]
        } else {
            kanbanBoardNoteIDs = []
        }
        mirroredClipIDs = try c.decodeIfPresent([String: String].self, forKey: .mirroredClipIDs) ?? [:]
        vaultSyncRecords = try c.decodeIfPresent([String: VaultSyncRecord].self, forKey: .vaultSyncRecords) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(folders, forKey: .folders)
        try c.encode(notes, forKey: .notes)
        try c.encode(workspaceSession, forKey: .workspaceSession)
        try c.encode(kanbanBoardNoteIDs, forKey: .kanbanBoardNoteIDs)
        try c.encode(mirroredClipIDs, forKey: .mirroredClipIDs)
        try c.encode(vaultSyncRecords, forKey: .vaultSyncRecords)
    }
}
