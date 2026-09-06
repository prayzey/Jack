import AppKit
import SwiftUI

/// Backing state for the command palette. Owns the query, the flattened result
/// list, and the keyboard selection. Also carries the `capturedPreviousApp` so
/// paste/dictation actions can hand focus back to whatever the user was using
/// when they summoned the palette.
@MainActor
final class CommandPaletteModel: ObservableObject {
    @Published var query: String = "" {
        didSet { rebuild() }
    }
    @Published private(set) var items: [CommandPaletteItem] = []
    @Published var selectedIndex: Int = 0
    /// Bumped on every `show()` so the SwiftUI view can re-focus the search field
    /// even though the hosting view is reused across opens (it only appears once).
    @Published var focusToken: Int = 0

    /// The app that was frontmost when the palette opened. Set by the window
    /// manager before the palette steals focus.
    var capturedPreviousApp: NSRunningApplication?

    private weak var store: ClipboardStore?
    private var onDismiss: () -> Void = {}
    /// Rebuilt each open so shortcut hints and feature availability stay current.
    private var allActions: [CommandAction] = []

    func configure(store: ClipboardStore, onDismiss: @escaping () -> Void) {
        self.store = store
        self.onDismiss = onDismiss
    }

    /// Reset to the just-opened state: fresh action catalog, empty query, default
    /// result list, selection at the top.
    func reset() {
        rebuildActions()
        query = ""          // didSet rebuilds the item list
        selectedIndex = 0
        focusToken &+= 1
    }

    // MARK: - Keyboard navigation

    func moveDown() {
        guard !items.isEmpty else { return }
        selectedIndex = min(selectedIndex + 1, items.count - 1)
    }

    func moveUp() {
        guard !items.isEmpty else { return }
        selectedIndex = max(selectedIndex - 1, 0)
    }

    func selectIndex(_ index: Int) {
        guard items.indices.contains(index) else { return }
        selectedIndex = index
    }

    /// Dismiss the palette, then run the selected row's action. Dismissing first
    /// matters: paste/dictation need Jack out of the way so the keystroke lands in
    /// the user's previous app.
    func activateSelection() {
        guard items.indices.contains(selectedIndex) else { return }
        let item = items[selectedIndex]
        onDismiss()
        item.run()
    }

    func activate(_ item: CommandPaletteItem) {
        onDismiss()
        item.run()
    }

    // MARK: - Result building

    private func rebuildActions() {
        guard let store else { allActions = []; return }
        var list = CommandCatalog.actions(store: store)

        // Focus-restoring actions are built here (not in CommandCatalog) because
        // they need `capturedPreviousApp` to send text/keystrokes to the right app.
        if DictationLauncher.shared.isDictationEnabled {
            list.append(CommandAction(
                id: "dictation",
                title: "Start Dictation",
                subtitle: "Speak and insert text into your last app",
                systemImage: "mic",
                accent: ClipTypePresentation.accentColor(for: .image),
                keywords: ["voice", "speak", "transcribe", "type", "talk"],
                shortcutHint: nil,
                run: { [weak self] in self?.startDictation(ask: false) }
            ))
        }
        if DictationLauncher.shared.isAskScreenEnabled {
            list.append(CommandAction(
                id: "ask-screen",
                title: "Ask the Screen",
                subtitle: "Ask about what's on your screen",
                systemImage: "sparkles",
                accent: ClipTypePresentation.accentColor(for: .text),
                keywords: ["ai", "question", "vision", "screen"],
                shortcutHint: nil,
                run: { [weak self] in self?.startDictation(ask: true) }
            ))
        }
        if DictationLauncher.shared.isVoiceActionsEnabled {
            list.append(CommandAction(
                id: "voice-actions",
                title: "Voice Action",
                subtitle: "Set a reminder or control Spotify by voice",
                systemImage: "checklist",
                accent: ClipTypePresentation.accentColor(for: .link),
                keywords: ["remind", "reminder", "command", "action", "spotify", "play", "pause"],
                shortcutHint: nil,
                run: { [weak self] in self?.startVoiceActions() }
            ))
        }
        allActions = list
    }

    private func rebuild() {
        guard let store else { items = []; return }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let searching = !trimmed.isEmpty
        var result: [CommandPaletteItem] = []

        // Actions
        for action in CommandPaletteMatcher.filterActions(allActions, query: query, limit: 12) {
            result.append(CommandPaletteItem(
                id: "action-\(action.id)",
                section: .actions,
                title: action.title,
                subtitle: action.subtitle,
                systemImage: action.systemImage,
                accent: action.accent,
                trailingText: action.shortcutHint,
                run: action.run
            ))
        }

        // Clips — newest first; show 5 recent by default, more while searching.
        let clipMatches = store.clips
            .filter { clip in
                !searching || CommandPaletteMatcher.matches(
                    query: trimmed,
                    fields: [clip.title, clip.previewText, clip.textValue ?? "", clip.urlValue ?? "", clip.sourceAppName]
                )
            }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(searching ? 8 : 5)
        for clip in clipMatches {
            result.append(CommandPaletteItem(
                id: "clip-\(clip.clipID.uuidString)",
                section: .clips,
                title: Self.singleLine(clip.title.isEmpty ? clip.previewText : clip.title),
                subtitle: clip.sourceAppName.isEmpty ? nil : clip.sourceAppName,
                systemImage: Self.symbol(for: clip.clipType),
                accent: ClipTypePresentation.accentColor(for: clip.clipType),
                trailingText: Self.relativeTime(clip.createdAt),
                run: { [weak self] in self?.pasteClip(clip) }
            ))
        }

        // Notes, meetings, reminders only surface while searching — they have no
        // useful "browse the latest" default, and keep the opening list clean.
        if searching {
            let noteMatches = store.notes
                .filter { !$0.isArchived }
                .filter { CommandPaletteMatcher.matches(query: trimmed, fields: [$0.displayTitle, $0.bodyMarkdown]) }
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(6)
            for note in noteMatches {
                result.append(CommandPaletteItem(
                    id: "note-\(note.noteID.uuidString)",
                    section: .notes,
                    title: note.displayTitle,
                    subtitle: Self.notePreview(note.bodyMarkdown),
                    systemImage: "note.text",
                    accent: ClipTypePresentation.accentColor(for: .text),
                    trailingText: Self.relativeTime(note.updatedAt),
                    run: { [weak self] in self?.openNote(note) }
                ))
            }

            let meetingMatches = MeetingHub.shared.store.sessions
                .filter { CommandPaletteMatcher.matches(query: trimmed, fields: [$0.displayTitle]) }
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(6)
            for meeting in meetingMatches {
                result.append(CommandPaletteItem(
                    id: "meeting-\(meeting.meetingID.uuidString)",
                    section: .meetings,
                    title: meeting.displayTitle,
                    subtitle: "Meeting",
                    systemImage: "waveform",
                    accent: ClipTypePresentation.accentColor(for: .audio),
                    trailingText: Self.relativeTime(meeting.createdAt),
                    run: { [weak self] in self?.openMeeting(meeting) }
                ))
            }

            let reminderMatches = CommandPaletteMatcher.filter(
                store.settings.pulseReminders, query: query, limit: 6
            ) { [$0.message, $0.sourceTitle ?? ""] }
            for reminder in reminderMatches {
                result.append(CommandPaletteItem(
                    id: "reminder-\(reminder.id.uuidString)",
                    section: .reminders,
                    title: Self.singleLine(reminder.message),
                    subtitle: reminder.sourceTitle,
                    systemImage: "bell",
                    accent: ClipTypePresentation.accentColor(for: .audio),
                    trailingText: reminder.dueAt.map(Self.relativeTime),
                    run: { [weak self] in self?.copyReminder(reminder) }
                ))
            }
        }

        items = result
        if selectedIndex >= result.count { selectedIndex = max(0, result.count - 1) }
    }

    // MARK: - Actions

    private func pasteClip(_ clip: ClipItemModel) {
        guard let store else { return }
        // The palette is a separate window, so the paste pipeline's idea of "the
        // app to restore" is stale. Point it at the app we captured on open.
        AppWindowManager.shared.setPasteRestoreTarget(capturedPreviousApp)
        store.copyToClipboard(clips: [clip], autoPaste: true)
    }

    private func openNote(_ note: NoteItem) {
        guard let store else { return }
        store.openNoteInWorkspace(note.noteID)
        store.settings.viewMode = .workspace
        AppWindowManager.shared.toggleWindow(source: "palette-note")
    }

    private func openMeeting(_ meeting: MeetingSession) {
        guard let store else { return }
        store.openMeetingsInWorkspace()
        MeetingHub.shared.focusMeeting(meeting.meetingID)
        store.settings.viewMode = .workspace
        AppWindowManager.shared.toggleWindow(source: "palette-meeting")
    }

    private func copyReminder(_ reminder: PulseReminder) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(reminder.message, forType: .string)
    }

    private func startDictation(ask: Bool) {
        // Hand focus back to the user's app first, then start dictation a beat
        // later so the transcription lands there instead of in Jack.
        capturedPreviousApp?.activate(options: [.activateAllWindows])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            if ask {
                DictationLauncher.shared.startAskScreen()
            } else {
                DictationLauncher.shared.startDictation()
            }
        }
    }

    private func startVoiceActions() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            DictationLauncher.shared.startVoiceActions()
        }
    }

    // MARK: - Formatting helpers

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    static func relativeTime(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    static func singleLine(_ text: String) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.count > 90 ? String(collapsed.prefix(90)) + "…" : collapsed
    }

    static func notePreview(_ markdown: String) -> String? {
        let firstContentLine = markdown
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let firstContentLine else { return nil }
        let cleaned = firstContentLine.trimmingCharacters(in: CharacterSet(charactersIn: "# >-*").union(.whitespaces))
        return cleaned.isEmpty ? nil : singleLine(cleaned)
    }

    static func symbol(for type: ClipType) -> String {
        switch type {
        case .text: return "doc.text"
        case .link: return "link"
        case .image: return "photo"
        case .audio: return "waveform"
        case .color: return "paintpalette"
        }
    }
}
