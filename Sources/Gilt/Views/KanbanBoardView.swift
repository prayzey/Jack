import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct KanbanBoardView: View {
    let boardID: UUID
    @EnvironmentObject private var store: ClipboardStore
    @State private var taskDraftTitle = ""
    @State private var composingColumn: NoteTaskColumn?
    @Namespace private var taskMotion

    // Inline composer for adding a brand-new column at the end of the board.
    @State private var isComposingColumn = false
    @State private var columnDraftTitle = ""

    // Drag-reorder preview state. When set, the listed columns reorder their
    // visible task list so other cards animate out of the way and the user
    // can see exactly where the card will land before releasing.
    @State private var draggingTaskID: String?
    @State private var dropTargetColumn: NoteTaskColumn?
    @State private var dropTargetIndex: Int?

    // NSEvent monitors are installed for the duration of an active drag so
    // that releasing anywhere on screen reliably clears preview state. SwiftUI
    // DropDelegate callbacks alone are not sufficient: if the user releases
    // over a non-target (e.g. another app, the menu bar) no `performDrop`
    // fires and the source card would otherwise stay visually dimmed.
    @State private var dragEndLocalMonitor: Any?
    @State private var dragEndGlobalMonitor: Any?

    private var boardColumns: [(column: NoteTaskColumn, tasks: [NoteTask])] {
        // Pulled from the store rather than `.defaults` so user-added columns
        // appear alongside the built-in Todo/Doing/Done trio.
        store.boardColumns(forBoard: boardID).map { ($0, store.tasks(for: $0, inBoard: boardID)) }
    }

    private func resetDragState() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            draggingTaskID = nil
            dropTargetColumn = nil
            dropTargetIndex = nil
        }
        cancelDragEndTracking()
    }

    private func beginDragEndTracking() {
        cancelDragEndTracking()
        // Local monitor catches releases inside the app window; global monitor
        // catches releases anywhere else (other apps, desktop, menu bar). The
        // tiny delay defers the reset enough for `performDrop` to commit the
        // reorder before we wipe the preview state.
        let scheduleReset: () -> Void = {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 60_000_000)
                resetDragState()
            }
        }
        dragEndLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { event in
            scheduleReset()
            return event
        }
        dragEndGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { _ in
            scheduleReset()
        }
    }

    private func cancelDragEndTracking() {
        if let monitor = dragEndLocalMonitor {
            NSEvent.removeMonitor(monitor)
            dragEndLocalMonitor = nil
        }
        if let monitor = dragEndGlobalMonitor {
            NSEvent.removeMonitor(monitor)
            dragEndGlobalMonitor = nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.boardDisplayTitle(boardID))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    Text(
                        L10n.string(
                            "workspace.kanban.subtitle",
                            default: "Create tasks with the Add Task buttons, then drag cards between columns."
                        )
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 18) {
                    ForEach(boardColumns, id: \.column) { entry in
                        KanbanColumnView(
                            boardID: boardID,
                            column: entry.column,
                            tasks: entry.tasks,
                            isComposingTask: composingColumn == entry.column,
                            taskDraftTitle: $taskDraftTitle,
                            taskMotion: taskMotion,
                            draggingTaskID: $draggingTaskID,
                            dropTargetColumn: $dropTargetColumn,
                            dropTargetIndex: $dropTargetIndex,
                            onAddTask: { startTaskComposer(for: entry.column) },
                            onCancelTaskComposer: cancelTaskComposer,
                            onCreateTask: { createTaskFromComposer(in: entry.column) },
                            onDeleteTask: { store.deleteTask($0) },
                            onRenameTask: { task, newTitle in
                                store.renameTask(task, to: newTitle)
                            },
                            onDeleteColumn: { store.removeKanbanColumn(entry.column, boardID: boardID) }
                        )
                        .environmentObject(store)
                    }
                    KanbanAddColumnSlot(
                        isComposing: $isComposingColumn,
                        draftTitle: $columnDraftTitle,
                        onCommit: commitNewColumn,
                        onCancel: cancelNewColumn
                    )
                }
                .padding(.bottom, 8)
                .animation(.spring(response: 0.32, dampingFraction: 0.84), value: store.boardColumns(forBoard: boardID).map(\.id))
            }

            if store.extractedTasks(forBoard: boardID).isEmpty {
                Button {
                    startTaskComposer(for: .todo)
                } label: {
                    Label(
                        L10n.string("workspace.kanban.emptyCta", default: "Create your first task"),
                        systemImage: "checklist"
                    )
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.86))
            }
        }
        .padding(24)
        // Install/remove NSEvent monitors as drags begin/end. This is the
        // single source of truth for "the drag is finished" -- DropDelegate
        // callbacks may not fire when the user releases outside any target.
        .onChange(of: draggingTaskID) { _, newValue in
            if newValue != nil {
                beginDragEndTracking()
            } else {
                cancelDragEndTracking()
            }
        }
        .onDisappear { cancelDragEndTracking() }
    }

    private func startTaskComposer(for column: NoteTaskColumn) {
        taskDraftTitle = ""
        composingColumn = column
    }

    private func cancelTaskComposer() {
        taskDraftTitle = ""
        composingColumn = nil
    }

    private func createTaskFromComposer(in column: NoteTaskColumn) {
        guard composingColumn == column else { return }
        let trimmed = taskDraftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.createTask(title: trimmed, in: column, boardID: boardID)
        cancelTaskComposer()
    }

    private func commitNewColumn() {
        let trimmed = columnDraftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            cancelNewColumn()
            return
        }
        store.addKanbanColumn(title: trimmed, boardID: boardID)
        columnDraftTitle = ""
        isComposingColumn = false
    }

    private func cancelNewColumn() {
        columnDraftTitle = ""
        isComposingColumn = false
    }
}

private struct KanbanColumnView: View {
    @EnvironmentObject private var store: ClipboardStore
    let boardID: UUID
    let column: NoteTaskColumn
    let tasks: [NoteTask]
    let isComposingTask: Bool
    @Binding var taskDraftTitle: String
    let taskMotion: Namespace.ID
    @Binding var draggingTaskID: String?
    @Binding var dropTargetColumn: NoteTaskColumn?
    @Binding var dropTargetIndex: Int?
    @FocusState private var taskFieldFocused: Bool
    let onAddTask: () -> Void
    let onCancelTaskComposer: () -> Void
    let onCreateTask: () -> Void
    let onDeleteTask: (NoteTask) -> Void
    let onRenameTask: (NoteTask, String) -> Void
    let onDeleteColumn: () -> Void

    /// Slots rendered for this column during a drag: real task rows for
    /// every non-dragging task, plus a single placeholder slot at the hovered
    /// position. The dragging card itself is never re-rendered here -- the
    /// system already shows its drag image attached to the cursor, and adding
    /// our own copy made it look like a ghost duplicate trailing the pointer.
    private var slots: [KanbanSlot] {
        let filtered = tasks.filter { $0.id != draggingTaskID }
        var list = filtered.map(KanbanSlot.task)
        if draggingTaskID != nil,
           dropTargetColumn == column,
           let raw = dropTargetIndex {
            let clamped = max(0, min(raw, list.count))
            list.insert(.placeholder, at: clamped)
        }
        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(column.displayTitle)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                Text("\(tasks.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
                Spacer(minLength: 8)
                Button(action: onAddTask) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .padding(8)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.86))
            }
            .contentShape(Rectangle())
            .contextMenu {
                if !column.isBuiltIn {
                    Button(
                        L10n.string("workspace.kanban.column.delete", default: "Delete column"),
                        role: .destructive,
                        action: onDeleteColumn
                    )
                }
            }

            ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                switch slot {
                case .task(let task):
                    KanbanTaskRow(
                        task: task,
                        qwenCacheDirectory: store.qwenModelCacheURL,
                        customPresets: store.settings.kanbanCustomAssistPresets,
                        taskMotion: taskMotion,
                        onDelete: { onDeleteTask(task) },
                        onRename: { newTitle in onRenameTask(task, newTitle) }
                    )
                    .onDrag {
                        // Mark the source synchronously-on-next-tick so every
                        // column hides it from its visible list and the
                        // placeholder slot can take its place.
                        DispatchQueue.main.async { draggingTaskID = task.id }
                        return NSItemProvider(object: task.id as NSString)
                    }
                    .onDrop(
                        of: [UTType.text.identifier],
                        delegate: NoteTaskDropDelegate(
                            boardID: boardID,
                            column: column,
                            targetIndex: index,
                            store: store,
                            draggingTaskID: $draggingTaskID,
                            dropTargetColumn: $dropTargetColumn,
                            dropTargetIndex: $dropTargetIndex
                        )
                    )
                case .placeholder:
                    KanbanDropPlaceholder()
                        .onDrop(
                            of: [UTType.text.identifier],
                            delegate: NoteTaskDropDelegate(
                                boardID: boardID,
                                column: column,
                                targetIndex: index,
                                store: store,
                                draggingTaskID: $draggingTaskID,
                                dropTargetColumn: $dropTargetColumn,
                                dropTargetIndex: $dropTargetIndex
                            )
                        )
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: slots.map(\.id))

            // Composer renders immediately after the existing cards -- exactly where
            // the new task will land when created. Kept minimal (no nested card chrome)
            // so it reads as a placeholder slot rather than a card-within-a-card.
            if isComposingTask {
                KanbanComposerRow(
                    text: $taskDraftTitle,
                    qwenCacheDirectory: store.qwenModelCacheURL,
                    customPresets: store.settings.kanbanCustomAssistPresets,
                    isFocused: $taskFieldFocused,
                    onCommit: onCreateTask,
                    onCancel: onCancelTaskComposer
                )
            }

            // Trailing flexible area: append-on-drop when the user releases below
            // the last card. minHeight gives an actual hit target even when empty.
            Color.clear
                .frame(minHeight: 40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onDrop(
                    of: [UTType.text.identifier],
                    delegate: NoteTaskDropDelegate(
                        boardID: boardID,
                        column: column,
                        targetIndex: nil,
                        store: store,
                        draggingTaskID: $draggingTaskID,
                        dropTargetColumn: $dropTargetColumn,
                        dropTargetIndex: $dropTargetIndex
                    )
                )
        }
        .padding(16)
        .frame(width: 292)
        .frame(minHeight: 560, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.white.opacity(dropTargetColumn == column && draggingTaskID != nil ? 0.07 : 0.04))
        )
        .overlay(
            // Subtle highlight when this column is the active drop target so
            // horizontal cross-column moves read as clearly as vertical ones.
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(
                    Color.white.opacity(dropTargetColumn == column && draggingTaskID != nil ? 0.18 : 0.0),
                    lineWidth: 1
                )
        )
        .animation(.easeOut(duration: 0.18), value: dropTargetColumn == column)
        // Column-wide catch-all: as soon as the cursor enters any part of
        // this column (header, gaps between cards, padding), treat it as
        // "append to end of this column" so the placeholder slides in and
        // the source column closes its gap. Per-card and trailing-zone
        // delegates take precedence when the cursor is over them.
        .onDrop(
            of: [UTType.text.identifier],
            delegate: NoteTaskDropDelegate(
                boardID: boardID,
                column: column,
                targetIndex: nil,
                store: store,
                draggingTaskID: $draggingTaskID,
                dropTargetColumn: $dropTargetColumn,
                dropTargetIndex: $dropTargetIndex
            )
        )
        .onChange(of: isComposingTask) { _, newValue in
            // Keep task entry keyboard-first: when a column enters compose mode,
            // focus the field immediately so users can type without an extra click.
            guard newValue else {
                taskFieldFocused = false
                return
            }
            DispatchQueue.main.async {
                taskFieldFocused = true
            }
        }
    }
}

/// A row in a column's visible list during a drag: either a real task or
/// the lightweight "this is where it will land" placeholder.
private enum KanbanSlot: Identifiable {
    case task(NoteTask)
    case placeholder

    var id: String {
        switch self {
        case .task(let task): return task.id
        case .placeholder: return "__kanban_drop_placeholder__"
        }
    }
}

private struct KanbanDropPlaceholder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 18)
            .strokeBorder(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .frame(width: 260, height: 44)
            .transition(.scale(scale: 0.98).combined(with: .opacity))
    }
}

private struct KanbanTaskRow: View {
    let task: NoteTask
    let qwenCacheDirectory: URL
    let customPresets: [KanbanCustomAssistPreset]
    let taskMotion: Namespace.ID
    let onDelete: () -> Void
    let onRename: (String) -> Void

    @State private var isEditing = false
    @State private var draft = ""
    @State private var isAssisting = false
    @State private var assistStatusMessage: String?
    @FocusState private var editFocused: Bool

    private var assistChoices: [KanbanAssistChoice] {
        KanbanAssistCatalog.choices(customPresets: customPresets)
    }

    private var sourceText: String {
        isEditing ? draft : task.title
    }

    private var hasAssistableText: Bool {
        !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                if isEditing {
                    TextField(
                        L10n.string("workspace.kanban.editPlaceholder", default: "Task title"),
                        text: $draft,
                        axis: .vertical
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1...8)
                    .focused($editFocused)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onSubmit(commitEdit)
                } else {
                    Text(task.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.88))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if isEditing {
                    Button(action: commitEdit) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.78))
                } else {
                    Button(action: beginEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.55))
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.55))
                }
            }

            if isEditing {
                KanbanTextAssistBar(
                    text: $draft,
                    cacheDirectory: qwenCacheDirectory,
                    customPresets: customPresets
                )
            } else if let assistStatusMessage {
                Text(assistStatusMessage)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(width: 260, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.06)))
        .matchedGeometryEffect(id: task.id, in: taskMotion)
        .transition(.asymmetric(
            insertion: .scale(scale: 0.96).combined(with: .opacity),
            removal: .opacity
        ))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { beginEdit() }
        .contextMenu {
            if hasAssistableText {
                Section(
                    L10n.string(
                        "workspace.kanban.assist.menuSection",
                        default: "Writing help"
                    )
                ) {
                    ForEach(assistChoices) { choice in
                        Button {
                            Task { await applyAssist(choice) }
                        } label: {
                            if isAssisting {
                                Label(choice.menuTitle, systemImage: "ellipsis")
                            } else {
                                Text(choice.menuTitle)
                            }
                        }
                        .disabled(isAssisting)
                    }
                }
            }
            Button(L10n.string("workspace.kanban.edit", default: "Edit"), action: beginEdit)
            Button(
                L10n.string("workspace.kanban.delete", default: "Delete"),
                role: .destructive,
                action: onDelete
            )
        }
    }

    @MainActor
    private func applyAssist(_ choice: KanbanAssistChoice) async {
        guard hasAssistableText, !isAssisting else { return }
        isAssisting = true
        assistStatusMessage = nil
        defer { isAssisting = false }

        let engine = KanbanTextAssistEngine(cacheDirectory: qwenCacheDirectory)
        let outcome = await engine.process(text: sourceText, choice: choice)
        switch outcome {
        case .improved(let improved):
            if isEditing {
                draft = improved
            } else {
                onRename(improved)
            }
        case .unchanged:
            break
        case .modelNotDownloaded:
            assistStatusMessage = L10n.string(
                "workspace.kanban.assist.modelMissing",
                default: "Download the on-device Qwen model in Settings (Dictation or Meetings) to use writing help."
            )
        case .failed:
            assistStatusMessage = L10n.string(
                "workspace.kanban.assist.failed",
                default: "Couldn't improve the text. Try again."
            )
        }
    }

    private func beginEdit() {
        draft = task.title
        isEditing = true
        DispatchQueue.main.async { editFocused = true }
    }

    private func commitEdit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != task.title {
            onRename(trimmed)
        }
        isEditing = false
        editFocused = false
    }
}

private struct KanbanComposerRow: View {
    @Binding var text: String
    let qwenCacheDirectory: URL
    let customPresets: [KanbanCustomAssistPreset]
    var isFocused: FocusState<Bool>.Binding
    let onCommit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Multi-line wrapping TextField -- typing long content grows the
            // composer downward instead of scrolling horizontally and hiding text.
            TextField(
                L10n.string("workspace.kanban.newTaskPlaceholder", default: "What should be done?"),
                text: $text,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(0.92))
            .lineLimit(1...8)
            .focused(isFocused)
            .onSubmit(onCommit)

            KanbanTextAssistBar(
                text: $text,
                cacheDirectory: qwenCacheDirectory,
                customPresets: customPresets
            )

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button(L10n.string("workspace.kanban.cancel", default: "Cancel"), action: onCancel)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Button(L10n.string("workspace.kanban.create", default: "Add"), action: onCommit)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
            }
        }
        .padding(14)
        .frame(width: 260, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        )
        .transition(.opacity)
    }
}

/// Trailing slot at the right of the kanban that lets the user add a new
/// custom column inline. Tapping reveals a TextField; submitting commits via
/// `onCommit`. Visually mirrors the dashed-border composer used elsewhere on
/// the board so the affordance reads as "placeholder" rather than a card.
private struct KanbanAddColumnSlot: View {
    @Binding var isComposing: Bool
    @Binding var draftTitle: String
    let onCommit: () -> Void
    let onCancel: () -> Void
    @FocusState private var fieldFocused: Bool

    var body: some View {
        Group {
            if isComposing {
                composer
            } else {
                addButton
            }
        }
        .frame(width: 292)
        .frame(minHeight: 560, alignment: .topLeading)
        .animation(.spring(response: 0.32, dampingFraction: 0.84), value: isComposing)
    }

    private var addButton: some View {
        Button {
            draftTitle = ""
            isComposing = true
            DispatchQueue.main.async { fieldFocused = true }
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                Text(L10n.string("workspace.kanban.column.add", default: "Add column"))
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.6))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(
                        Color.white.opacity(0.16),
                        style: StrokeStyle(lineWidth: 1.2, dash: [6, 5])
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.string("workspace.kanban.column.newTitle", default: "New column"))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.78))
                .textCase(.uppercase)
                .tracking(0.6)

            TextField(
                L10n.string("workspace.kanban.column.placeholder", default: "Column name"),
                text: $draftTitle
            )
            .textFieldStyle(.plain)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white.opacity(0.95))
            .focused($fieldFocused)
            .onSubmit(onCommit)
            .onExitCommand(perform: onCancel)

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button(L10n.string("workspace.kanban.cancel", default: "Cancel"), action: onCancel)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Button(L10n.string("workspace.kanban.column.create", default: "Add"), action: onCommit)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.16)))
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        )
        .onChange(of: isComposing) { _, newValue in
            guard newValue else {
                fieldFocused = false
                return
            }
            DispatchQueue.main.async { fieldFocused = true }
        }
    }
}

private struct NoteTaskDropDelegate: DropDelegate {
    let boardID: UUID
    let column: NoteTaskColumn
    /// Slot index within the column the dropped task should occupy.
    /// `nil` appends to the end (used by the column's trailing drop zone).
    let targetIndex: Int?
    let store: ClipboardStore
    @Binding var draggingTaskID: String?
    @Binding var dropTargetColumn: NoteTaskColumn?
    @Binding var dropTargetIndex: Int?

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.text])
    }

    func dropEntered(info: DropInfo) {
        // Update the live preview slot. Other cards in this column animate
        // to make room because `slots` reorders around this hover position.
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            dropTargetColumn = column
            dropTargetIndex = targetIndex
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        // State (draggingTaskID, dropTarget*) is reset by the board-level
        // mouse-up monitor in KanbanBoardView. We only commit the reorder
        // here so the model update animates as the preview state unwinds.
        guard let provider = info.itemProviders(for: [UTType.text]).first else {
            return false
        }
        provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { item, _ in
            let id: String?
            if let data = item as? Data {
                id = String(data: data, encoding: .utf8)
            } else if let string = item as? String {
                id = string
            } else if let string = item as? NSString {
                id = string as String
            } else {
                id = nil
            }

            Task { @MainActor in
                guard let id,
                      let task = store.extractedTasks(forBoard: boardID).first(where: { $0.id == id }) else { return }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                    store.reorderTask(task, to: column, targetIndex: targetIndex)
                }
            }
        }
        return true
    }
}
