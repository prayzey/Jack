import AppKit
import XCTest
@testable import Gilt

final class NoteModelsTests: XCTestCase {
    func testWorkspaceModeLabelAndDefaults() {
        XCTAssertEqual(ViewMode.workspace.label, "Workspace")
        XCTAssertEqual(AppSettings().quickNoteShortcut, .quickNoteDefault)
        XCTAssertEqual(AppSettings().quickNoteOpenPosition, .centered)
        XCTAssertEqual(AppSettings().quickNoteOpenAnimation, .slide)
        XCTAssertEqual(AppSettings().quickNoteCloseAnimation, .slide)
        XCTAssertFalse(AppSettings().reverseQuickNoteSwipeDirection)
        XCTAssertEqual(AppSettings().quickNoteNavigationControlsStyle, .standard)
        XCTAssertFalse(AppSettings().quickNoteAutoPasteFromClipboard)
        XCTAssertEqual(AppSettings().clipboardFont, .sfPro)
        XCTAssertTrue(AppSettings().mirrorNotesIntoClipboardHistory)
        XCTAssertTrue(AppSettings().restoreWorkspaceTabs)
    }

    func testQuickNotesAreOrderedOldestToNewest() {
        let older = NoteItem(
            folderID: NoteFolder.scratchpadsID,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 10),
            lastOpenedAt: Date(timeIntervalSince1970: 30),
            origin: .quickNote
        )
        let newer = NoteItem(
            folderID: NoteFolder.scratchpadsID,
            createdAt: Date(timeIntervalSince1970: 20),
            updatedAt: Date(timeIntervalSince1970: 20),
            lastOpenedAt: Date(timeIntervalSince1970: 5),
            origin: .quickNote
        )

        let ordered = orderedQuickNotes(in: [newer, older])
        XCTAssertEqual(ordered.map(\.noteID), [older.noteID, newer.noteID])
        XCTAssertEqual(ordered.last?.noteID, newer.noteID)
    }

    func testQuickAndWorkspaceAppearanceDefaultsMatchNewSurfaces() {
        let settings = AppSettings()

        XCTAssertEqual(settings.quickNoteAppearance.style, .paper)
        XCTAssertEqual(settings.quickNoteAppearance.transparencyMode, .solid)
        XCTAssertEqual(settings.quickNoteAppearance.backgroundWallpaper, .none)
        XCTAssertEqual(settings.quickNoteAppearance.surfaceOpacity, 0.94, accuracy: 0.001)

        XCTAssertEqual(settings.workspaceAppearance.backgroundTheme, .midnight)
        XCTAssertEqual(settings.workspaceAppearance.backgroundWallpaper, .none)
        XCTAssertEqual(settings.workspaceAppearance.backgroundOpacity, 0.72, accuracy: 0.001)
    }

    func testWallpaperSlotsUseDistinctFilenameStems() {
        let stems = Set(WallpaperSlot.allCases.map(\.filenameStem))
        XCTAssertEqual(stems.count, WallpaperSlot.allCases.count)
    }

    func testQuickNoteCenteredFrameUsesVisibleFrameMiddle() {
        let visibleFrame = NSRect(x: 100, y: 80, width: 1200, height: 900)

        let frame = quickNoteTargetFrame(
            placement: .centered,
            mouseLocation: NSPoint(x: 400, y: 300),
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(frame.origin.x, visibleFrame.midX - quickNoteWindowSize.width / 2, accuracy: 0.001)
        XCTAssertEqual(frame.origin.y, visibleFrame.midY - quickNoteWindowSize.height / 2, accuracy: 0.001)
    }

    func testQuickNoteMouseFrameClampsInsideVisibleFrame() {
        let visibleFrame = NSRect(x: 0, y: 40, width: 800, height: 600)

        let frame = quickNoteTargetFrame(
            placement: .mouse,
            mouseLocation: NSPoint(x: 790, y: 620),
            visibleFrame: visibleFrame
        )

        XCTAssertGreaterThanOrEqual(frame.minX, visibleFrame.minX + 16)
        XCTAssertGreaterThanOrEqual(frame.minY, visibleFrame.minY + 16)
        XCTAssertLessThanOrEqual(frame.maxX, visibleFrame.maxX - 16)
        XCTAssertLessThanOrEqual(frame.maxY, visibleFrame.maxY - 16)
    }

    func testQuickNoteTargetFrameUsesProvidedWindowSize() {
        let visibleFrame = NSRect(x: 10, y: 20, width: 900, height: 700)
        let windowSize = NSSize(width: 640, height: 360)

        let frame = quickNoteTargetFrame(
            placement: .centered,
            mouseLocation: .zero,
            visibleFrame: visibleFrame,
            windowSize: windowSize
        )

        XCTAssertEqual(frame.width, windowSize.width, accuracy: 0.001)
        XCTAssertEqual(frame.height, windowSize.height, accuracy: 0.001)
        XCTAssertEqual(frame.midX, visibleFrame.midX, accuracy: 0.001)
        XCTAssertEqual(frame.midY, visibleFrame.midY, accuracy: 0.001)
    }

    func testNoteTitleUsesHeadingFirst() {
        let markdown = """
        # Sprint Plan

        - [ ] Review
        """
        XCTAssertEqual(NoteMarkdown.displayTitle(for: markdown), "Sprint Plan")
    }

    func testDuplicateWorkspaceHeadingCanBeRemovedFromBody() {
        let body = """
        # Sprint Plan

        - [ ] Review the release
        - [ ] Ship the update
        """

        let normalized = NoteMarkdown.bodyRemovingDuplicateTitle(body, title: "Sprint Plan")

        XCTAssertEqual(
            normalized,
            """
            - [ ] Review the release
            - [ ] Ship the update
            """
        )
    }

    func testSingleLineBodyIsNotEmptiedWhenTitleMatches() {
        XCTAssertEqual(
            NoteMarkdown.bodyRemovingDuplicateTitle("Sprint Plan", title: "Sprint Plan"),
            "Sprint Plan"
        )
    }

    func testTaskExtractionUsesBoardHeadings() {
        let note = NoteItem(
            folderID: NoteFolder.notesID,
            bodyMarkdown: """
            ## Todo
            - [ ] First task

            ## Doing
            - [ ] Second task

            ## Done
            - [x] Third task
            """,
            origin: .workspace
        )

        let tasks = NoteMarkdown.extractTasks(from: note)
        XCTAssertEqual(tasks.count, 3)
        XCTAssertEqual(tasks[0].column, .todo)
        XCTAssertEqual(tasks[1].column, .doing)
        XCTAssertEqual(tasks[2].column, .done)
    }

    func testMovingTaskChangesHeadingAndCheckedState() {
        let original = """
        ## Todo
        - [ ] Ship notes

        ## Doing

        ## Done
        """

        let updated = NoteMarkdown.moveTask(in: original, lineIndex: 1, to: .done)
        XCTAssertTrue(updated.contains("## Done"))
        XCTAssertTrue(updated.contains("- [x] Ship notes"))
        XCTAssertFalse(updated.contains("## Todo\n- [ ] Ship notes"))
    }

    func testAddingTaskCreatesChecklistLineInTargetColumn() {
        let original = NoteMarkdown.emptyBoardTemplate()

        let updated = NoteMarkdown.addTask(in: original, title: "Review onboarding", to: .doing)

        XCTAssertTrue(updated.contains("- [ ] Review onboarding"))
        let note = NoteItem(folderID: NoteFolder.notesID, bodyMarkdown: updated, origin: .workspace)
        let extracted = NoteMarkdown.extractTasks(from: note).first(where: { $0.title == "Review onboarding" })
        XCTAssertEqual(extracted?.column, .doing)
    }

    func testAddingTaskToDoneCreatesCheckedLine() {
        let original = NoteMarkdown.emptyBoardTemplate()

        let updated = NoteMarkdown.addTask(in: original, title: "Ship release", to: .done)

        XCTAssertTrue(updated.contains("## Done\n- [x] Ship release"))
    }

    func testRemovingTaskDeletesChecklistLineOnly() {
        let original = """
        ## Todo
        - [ ] First task

        ## Doing
        - [ ] Keep this task

        ## Done
        """

        let updated = NoteMarkdown.removeTask(in: original, lineIndex: 1)

        XCTAssertFalse(updated.contains("- [ ] First task"))
        XCTAssertTrue(updated.contains("- [ ] Keep this task"))
        XCTAssertTrue(updated.contains("## Todo"))
    }

    func testWorkspaceTabKindRoundTrip() throws {
        let original = WorkspaceTab(kind: .noteFolder(NoteFolder.notesID), title: "Notes")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WorkspaceTab.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testKanbanBoardDetectionRequiresBoardTitleAndAllColumns() {
        XCTAssertTrue(NoteMarkdown.isKanbanBoard(markdown: NoteMarkdown.emptyBoardTemplate()))
        XCTAssertFalse(
            NoteMarkdown.isKanbanBoard(
                markdown: """
                # Sprint Plan

                ## Todo
                - [ ] One
                """
            )
        )
    }

    func testResolvedKanbanBoardNoteIDMigratesLegacyBoard() {
        let boardNote = NoteItem(
            folderID: NoteFolder.notesID,
            title: "Kanban Board",
            bodyMarkdown: NoteMarkdown.emptyBoardTemplate(),
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 30),
            lastOpenedAt: Date(timeIntervalSince1970: 30),
            origin: .workspace
        )
        let normalNote = NoteItem(
            folderID: NoteFolder.notesID,
            title: "Meeting Notes",
            bodyMarkdown: "Agenda",
            createdAt: Date(timeIntervalSince1970: 20),
            updatedAt: Date(timeIntervalSince1970: 20),
            lastOpenedAt: Date(timeIntervalSince1970: 20),
            origin: .workspace
        )

        XCTAssertEqual(
            resolvedKanbanBoardNoteIDs(explicitIDs: [], notes: [normalNote, boardNote]),
            [boardNote.noteID]
        )
    }

    func testResolvedKanbanBoardNoteIDsKeepsExplicitOrderAndDropsStale() {
        let liveA = NoteItem(folderID: NoteFolder.notesID, bodyMarkdown: "a", origin: .workspace)
        let liveB = NoteItem(folderID: NoteFolder.notesID, bodyMarkdown: "b", origin: .workspace)
        let staleID = UUID()

        // Explicit list wins (order preserved, de-duped); ids without a live
        // note are dropped, and the structural sniff is NOT used when explicit
        // boards survive.
        let resolved = resolvedKanbanBoardNoteIDs(
            explicitIDs: [liveB.noteID, staleID, liveA.noteID, liveB.noteID],
            notes: [liveA, liveB]
        )
        XCTAssertEqual(resolved, [liveB.noteID, liveA.noteID])
    }

    func testRegularWorkspaceNotesExcludeKanbanBoard() {
        let boardID = UUID()
        let boardNote = NoteItem(
            noteID: boardID,
            folderID: NoteFolder.notesID,
            title: "Kanban Board",
            bodyMarkdown: NoteMarkdown.emptyBoardTemplate(),
            origin: .workspace
        )
        let documentNote = NoteItem(
            folderID: NoteFolder.notesID,
            title: "Project Brief",
            bodyMarkdown: "Launch next week",
            origin: .workspace
        )

        let visible = regularWorkspaceNotes(from: [boardNote, documentNote], excluding: Set([boardID]))

        XCTAssertEqual(visible.map(\.noteID), [documentNote.noteID])
    }

    func testMigratedWorkspaceSessionStripsRetiredNoteTabs() {
        let noteTab = WorkspaceTab(id: UUID(), kind: .note(UUID()), title: "Draft")
        let folderTab = WorkspaceTab(id: UUID(), kind: .noteFolder(UUID()), title: "Notes")
        let clipTab = WorkspaceTab(id: UUID(), kind: .clip(UUID()), title: "Clip")
        let session = WorkspaceSession(
            tabs: [noteTab, folderTab, clipTab],
            selectedTabID: noteTab.id,
            selectedSidebarSection: .clipboard
        )

        let migrated = migratedWorkspaceSession(session, boardNoteIDs: [], notes: [])

        XCTAssertEqual(migrated.tabs.count, 1)
        XCTAssertEqual(migrated.tabs.first?.kind, clipTab.kind)
        XCTAssertEqual(migrated.selectedTabID, clipTab.id)
    }

    func testMigratedWorkspaceSessionRewritesLegacyKanbanNoteTabs() {
        let boardID = UUID()
        let boardNote = NoteItem(
            noteID: boardID,
            folderID: NoteFolder.notesID,
            title: "Work",
            bodyMarkdown: NoteMarkdown.emptyBoardTemplate(title: "Work"),
            origin: .workspace
        )
        // A legacy note-tab pointing at the board, plus an already-migrated
        // board tab for the same board, should collapse into one board tab.
        let legacyNoteTab = WorkspaceTab(id: UUID(), kind: .note(boardID), title: "Kanban Board")
        let existingBoardTab = WorkspaceTab(id: UUID(), kind: .kanbanBoard(boardID), title: "Kanban")
        let session = WorkspaceSession(
            tabs: [legacyNoteTab, existingBoardTab],
            selectedTabID: legacyNoteTab.id,
            selectedSidebarSection: .tasks
        )

        let migrated = migratedWorkspaceSession(session, boardNoteIDs: [boardID], notes: [boardNote])

        XCTAssertEqual(migrated.tabs.count, 1)
        XCTAssertEqual(migrated.tabs.first?.kind, .kanbanBoard(boardID))
        XCTAssertEqual(migrated.tabs.first?.title, "Work")
        XCTAssertEqual(migrated.selectedTabID, legacyNoteTab.id)
    }

    func testMigratedWorkspaceSessionKeepsMultipleBoardsAsSeparateTabs() {
        let workID = UUID()
        let personalID = UUID()
        let workTab = WorkspaceTab(id: UUID(), kind: .kanbanBoard(workID), title: "Work")
        let personalTab = WorkspaceTab(id: UUID(), kind: .kanbanBoard(personalID), title: "Personal")
        // A board tab whose board was deleted should be dropped.
        let goneTab = WorkspaceTab(id: UUID(), kind: .kanbanBoard(UUID()), title: "Gone")
        let session = WorkspaceSession(
            tabs: [workTab, personalTab, goneTab],
            selectedTabID: personalTab.id,
            selectedSidebarSection: .tasks
        )

        let migrated = migratedWorkspaceSession(session, boardNoteIDs: [workID, personalID], notes: [])

        XCTAssertEqual(migrated.tabs.map(\.kind), [.kanbanBoard(workID), .kanbanBoard(personalID)])
        XCTAssertEqual(migrated.selectedTabID, personalTab.id)
    }

    func testLegacyKanbanBoardSentinelTabAdoptsPrimaryBoard() {
        let primaryID = UUID()
        let sentinelTab = WorkspaceTab(
            id: UUID(),
            kind: .kanbanBoard(WorkspaceTabKind.legacyBoardSentinel),
            title: "Kanban Board"
        )
        let session = WorkspaceSession(tabs: [sentinelTab], selectedTabID: sentinelTab.id)

        let migrated = migratedWorkspaceSession(session, boardNoteIDs: [primaryID], notes: [])

        XCTAssertEqual(migrated.tabs.first?.kind, .kanbanBoard(primaryID))
    }

    func testKanbanBoardTabKindRoundTrip() throws {
        let original = WorkspaceTab(kind: .kanbanBoard(UUID()), title: "Side Projects")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WorkspaceTab.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testLegacyKanbanBoardTabDecodesToSentinel() throws {
        // Tabs persisted before per-board ids encoded `kanbanBoard` with no id.
        let json = """
        {"id":"\(UUID().uuidString)","kind":{"type":"kanbanBoard"},"title":"Kanban Board","isPinned":false,"createdAt":0}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(WorkspaceTab.self, from: json)
        XCTAssertEqual(decoded.kind, .kanbanBoard(WorkspaceTabKind.legacyBoardSentinel))
    }

    func testNotesLibraryStateMigratesLegacySingleBoardID() throws {
        let boardID = UUID()
        let json = """
        {"folders":[],"notes":[],"workspaceSession":{"tabs":[]},"kanbanBoardNoteID":"\(boardID.uuidString)","mirroredClipIDs":{}}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(NotesLibraryState.self, from: json)
        XCTAssertEqual(decoded.kanbanBoardNoteIDs, [boardID])
    }

    func testRenameBoardRewritesH1Only() {
        let original = NoteMarkdown.emptyBoardTemplate(title: "Kanban Board")
        let renamed = NoteMarkdown.renameBoard(in: original, to: "Personal")
        XCTAssertTrue(renamed.hasPrefix("# Personal"))
        XCTAssertFalse(renamed.contains("# Kanban Board"))
        // Columns are untouched.
        XCTAssertTrue(renamed.contains("## Todo"))
        XCTAssertTrue(renamed.contains("## Doing"))
        XCTAssertTrue(renamed.contains("## Done"))
        XCTAssertTrue(NoteMarkdown.displayTitle(for: renamed) == "Personal")
    }

    func testMakeNoteSnapshotClipAttachesClipboardFolder() {
        let note = NoteItem(
            folderID: NoteFolder.notesID,
            title: "Release Notes",
            bodyMarkdown: "Shipped a fix",
            origin: .workspace
        )
        let clipboardFolder = ClipFolderModel(
            folderID: ClipFolderModel.clipboardID,
            name: "Clipboard",
            isSystem: true
        )

        let clip = makeNoteSnapshotClip(note: note, sortOrder: 42, clipboardFolder: clipboardFolder)

        XCTAssertEqual(clip.title, "Release Notes")
        XCTAssertEqual(clip.sortOrder, 42)
        XCTAssertEqual(clip.folders.map(\.folderID), [ClipFolderModel.clipboardID])
    }

    func testUpdateNoteSnapshotClipRepairsMissingClipboardFolder() {
        let note = NoteItem(
            folderID: NoteFolder.notesID,
            title: "Weekly Review",
            bodyMarkdown: "Highlights",
            updatedAt: Date(timeIntervalSince1970: 99),
            origin: .workspace
        )
        let clipboardFolder = ClipFolderModel(
            folderID: ClipFolderModel.clipboardID,
            name: "Clipboard",
            isSystem: true
        )
        let clip = ClipItemModel(
            typeRaw: ClipType.text.rawValue,
            title: "Old",
            previewText: "Old",
            textValue: "Old",
            sourceAppName: "Tests"
        )

        updateNoteSnapshotClip(clip, note: note, clipboardFolder: clipboardFolder)

        XCTAssertEqual(clip.title, "Weekly Review")
        XCTAssertEqual(clip.textValue, "Highlights")
        XCTAssertEqual(clip.createdAt, note.updatedAt)
        XCTAssertEqual(clip.folders.map(\.folderID), [ClipFolderModel.clipboardID])
    }
}
