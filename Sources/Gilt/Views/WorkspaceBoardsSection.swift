import SwiftUI

/// Sidebar section listing the user's Kanban boards. Boards are the unit people
/// organize their life around (Work, Personal, Side Projects), each with its own
/// Todo/Doing/Done columns — so the sidebar lists boards here, not the tasks of
/// a single board. Tapping a board opens it in its own tab.
struct WorkspaceBoardsSection: View {
    @EnvironmentObject private var store: ClipboardStore

    @State private var isCreating = false
    @State private var draftName = ""
    @State private var renamingBoardID: UUID?
    @State private var renameDraft = ""
    @FocusState private var createFocused: Bool
    @FocusState private var renameFocused: Bool

    private var goldAccent: Color { Color(red: 0.83, green: 0.66, blue: 0.26) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if store.kanbanBoards.isEmpty && !isCreating {
                emptyState
            } else {
                ForEach(store.kanbanBoards) { board in
                    boardRow(board)
                }
            }

            if isCreating { createRow }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text(L10n.string("workspace.boards.sectionTitle", default: "Boards").uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(.white.opacity(0.42))
            Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)
            Button(action: beginCreate) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.62))
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help(L10n.string("workspace.boards.new", default: "New board"))
        }
        .padding(.top, 4)
        .padding(.horizontal, 4)
    }

    private var emptyState: some View {
        Text(L10n.string(
            "workspace.boards.empty",
            default: "No boards yet. Create one to start organizing tasks."
        ))
        .font(.system(size: 12))
        .foregroundStyle(.white.opacity(0.48))
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
    }

    // MARK: - Rows

    @ViewBuilder
    private func boardRow(_ board: NoteItem) -> some View {
        if renamingBoardID == board.noteID {
            renameRow(board)
        } else {
            BoardSidebarRow(
                title: board.displayTitle,
                taskCount: store.extractedTasks(forBoard: board.noteID).count,
                isActive: store.selectedBoardNoteID == board.noteID,
                accent: goldAccent,
                open: { store.openBoard(board.noteID) },
                rename: { beginRename(board) },
                delete: { store.deleteBoard(board.noteID) }
            )
        }
    }

    private func renameRow(_ board: NoteItem) -> some View {
        TextField("", text: $renameDraft)
            .textFieldStyle(.plain)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(.white)
            .focused($renameFocused)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
            .onSubmit { commitRename(board) }
            .onExitCommand { renamingBoardID = nil }
            .onChange(of: renameFocused) { _, focused in
                // Commit on blur so clicking away saves rather than discards.
                if !focused, renamingBoardID == board.noteID { commitRename(board) }
            }
    }

    private var createRow: some View {
        TextField(
            L10n.string("workspace.boards.namePlaceholder", default: "Board name"),
            text: $draftName
        )
        .textFieldStyle(.plain)
        .font(.system(size: 12.5, weight: .medium))
        .foregroundStyle(.white)
        .focused($createFocused)
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
        .onSubmit(commitCreate)
        .onExitCommand(perform: cancelCreate)
        .onChange(of: createFocused) { _, focused in
            if !focused, isCreating { commitCreate() }
        }
    }

    // MARK: - Actions

    private func beginCreate() {
        renamingBoardID = nil
        draftName = ""
        isCreating = true
        DispatchQueue.main.async { createFocused = true }
    }

    private func commitCreate() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        isCreating = false
        createFocused = false
        draftName = ""
        guard !trimmed.isEmpty else { return }
        store.createBoard(name: trimmed)
    }

    private func cancelCreate() {
        isCreating = false
        createFocused = false
        draftName = ""
    }

    private func beginRename(_ board: NoteItem) {
        isCreating = false
        renameDraft = board.displayTitle
        renamingBoardID = board.noteID
        DispatchQueue.main.async { renameFocused = true }
    }

    private func commitRename(_ board: NoteItem) {
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        renamingBoardID = nil
        renameFocused = false
        guard !trimmed.isEmpty, trimmed != board.displayTitle else { return }
        store.renameBoard(board.noteID, to: trimmed)
    }
}

/// A single board row: kanban glyph + name + task-count badge. The active board
/// (the one shown in the selected tab) reads brighter with a gold accent.
private struct BoardSidebarRow: View {
    let title: String
    let taskCount: Int
    let isActive: Bool
    let accent: Color
    let open: () -> Void
    let rename: () -> Void
    let delete: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isActive ? accent : .white.opacity(hover ? 1.0 : 0.7))
                    .frame(width: 16)
                Text(title)
                    .lineLimit(1)
                    .font(.system(size: 12.5, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(.white.opacity(isActive ? 1.0 : (hover ? 0.95 : 0.78)))
                Spacer(minLength: 6)
                if taskCount > 0 {
                    Text("\(taskCount)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(isActive ? 0.06 : (hover ? 0.03 : 0)))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .contextMenu {
            Button(L10n.string("workspace.boards.rename", default: "Rename"), action: rename)
            Button(
                L10n.string("workspace.boards.delete", default: "Delete board"),
                role: .destructive,
                action: delete
            )
        }
    }
}
