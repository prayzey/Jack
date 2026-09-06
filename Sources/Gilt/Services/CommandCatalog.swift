import AppKit
import SwiftUI

/// The canonical list of "Jack surface" actions — things that open one of Jack's
/// own windows or workspace surfaces. Shared by the command palette and the grid
/// launchpad so both stay in lockstep.
///
/// Focus note: every action here keeps Jack frontmost (it opens a Jack surface),
/// so callers only need to dismiss their own UI first — no app-focus juggling.
/// Actions that must hand focus back to the user's previous app (paste, dictation)
/// are intentionally NOT here; the palette builds those itself where it has the
/// captured previous app on hand.
enum CommandCatalog {
    /// `id` of the "show clipboard" action, so the launchpad can filter it out
    /// (it would just toggle the very window the launchpad lives in).
    static let showClipboardID = "show-clipboard"

    @MainActor
    static func actions(store: ClipboardStore) -> [CommandAction] {
        let settings = store.settings

        return [
            CommandAction(
                id: showClipboardID,
                title: "Show Clipboard",
                subtitle: "Open your clipboard history",
                systemImage: "doc.on.clipboard",
                accent: ClipTypePresentation.accentColor(for: .text),
                keywords: ["history", "clips", "paste"],
                shortcutHint: settings.globalShortcut.symbolString,
                run: { AppWindowManager.shared.toggleWindow(source: "catalog-clipboard") }
            ),
            CommandAction(
                id: "quick-note",
                title: "Quick Note",
                subtitle: "Open the floating scratchpad",
                systemImage: "square.and.pencil",
                accent: Color(red: 0.96, green: 0.78, blue: 0.30),
                keywords: ["scratch", "jot", "write", "memo"],
                shortcutHint: settings.quickNoteShortcut.symbolString,
                run: { QuickNoteWindowManager.shared.toggle() }
            ),
            CommandAction(
                id: "meetings",
                title: "Meetings",
                subtitle: "Record or review a meeting",
                systemImage: "waveform",
                accent: ClipTypePresentation.accentColor(for: .audio),
                keywords: ["record", "transcribe", "call", "new meeting", "notes"],
                shortcutHint: "⌘⌥M",
                run: {
                    store.openMeetingsInWorkspace()
                    store.settings.viewMode = .workspace
                    AppWindowManager.shared.toggleWindow(source: "catalog-meetings")
                }
            ),
            CommandAction(
                id: "notes-workspace",
                title: "Notes & Workspace",
                subtitle: "Open your notes library",
                systemImage: "note.text",
                accent: ClipTypePresentation.accentColor(for: .text),
                keywords: ["documents", "markdown", "library", "writing"],
                shortcutHint: nil,
                run: {
                    store.ensureDefaultWorkspaceTab()
                    store.settings.viewMode = .workspace
                    AppWindowManager.shared.toggleWindow(source: "catalog-notes")
                }
            ),
            CommandAction(
                id: "kanban",
                title: "Kanban Board",
                subtitle: "Open your board",
                systemImage: "rectangle.split.3x1",
                accent: ClipTypePresentation.accentColor(for: .link),
                keywords: ["board", "tasks", "todo", "cards"],
                shortcutHint: nil,
                run: {
                    store.openKanbanBoard()
                    store.settings.viewMode = .workspace
                    AppWindowManager.shared.toggleWindow(source: "catalog-kanban")
                }
            ),
            CommandAction(
                id: "settings",
                title: "Settings",
                subtitle: "Open Jack settings",
                systemImage: "gearshape",
                accent: Color(white: 0.6),
                keywords: ["preferences", "config", "options"],
                shortcutHint: "⌘,",
                run: { SettingsNavigation.openSettings() }
            ),
        ]
    }
}
