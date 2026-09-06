import SwiftUI
import UniformTypeIdentifiers

/// Workspace notes sidebar. This keeps the pre-vault in-app notes model:
/// folders and notes are stored in Jack's own state, not mirrored to disk.
struct NotesSidebarTree: View {
    @EnvironmentObject private var store: ClipboardStore

    private var goldAccent: Color { Color(red: 0.83, green: 0.66, blue: 0.26) }
    private var folders: [NoteFolder] { store.noteFolders.sorted { $0.sortOrder < $1.sortOrder } }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            sectionHeader

            InboxSection()
                .padding(.bottom, 6)

            FolderInsertionLine(targetIndex: 0)

            ForEach(Array(folders.enumerated()), id: \.element.folderID) { index, folder in
                NoteFolderGroupView(folder: folder)

                FolderInsertionLine(targetIndex: index + 1)
            }

            newFolderButton
                .padding(.top, 4)
        }
        .padding(.horizontal, 4)
    }

    private var sectionHeader: some View {
        HStack(spacing: 8) {
            Text(L10n.string("ui.notes", default: "NOTES"))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(.white.opacity(0.42))
            Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)
        }
        .padding(.top, 4)
        .padding(.bottom, 6)
        .padding(.horizontal, 4)
    }

    private var newFolderButton: some View {
        Button {
            store.createNoteFolder(name: "New Folder \(store.noteFolders.count + 1)")
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 10, weight: .semibold))
                Text(L10n.string("ui.new.folder", default: "New folder"))
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(goldAccent.opacity(0.85))
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
    }
}

private struct InboxSection: View {
    @EnvironmentObject private var store: ClipboardStore
    @State private var hover = false

    private var goldAccent: Color { Color(red: 0.83, green: 0.66, blue: 0.26) }
    private var isExpanded: Bool { store.workspaceSession.inboxExpanded }
    private var inbox: [NoteItem] { store.inboxNotes }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                if inbox.isEmpty {
                    Text(L10n.string("ui.inbox.zero.every.note.has.a.type.or.a.link", default: "Inbox zero. Every note has a type or a link."))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.42))
                        .padding(.vertical, 4)
                        .padding(.leading, 28)
                        .padding(.trailing, 6)
                } else {
                    ForEach(inbox, id: \.noteID) { note in
                        NoteTreeRow(note: note)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isExpanded)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button {
                store.workspaceSession.inboxExpanded.toggle()
                store.persistNotesLibrary()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 12, height: 12)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.easeOut(duration: 0.18), value: isExpanded)
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Image(systemName: "tray")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(goldAccent.opacity(hover ? 1 : 0.85))
                    .frame(width: 14)
                Text(L10n.string("ui.inbox", default: "Inbox"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(hover ? 1 : 0.86))
                Spacer(minLength: 0)
                if !inbox.isEmpty {
                    Text("\(inbox.count)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(goldAccent.opacity(0.85))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                store.workspaceSession.inboxExpanded.toggle()
                store.persistNotesLibrary()
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(hover ? Color.white.opacity(0.04) : Color.clear)
        )
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}

private struct NoteFolderGroupView: View {
    @EnvironmentObject private var store: ClipboardStore
    let folder: NoteFolder

    private var isExpanded: Bool { store.isNoteFolderExpanded(folder.folderID) }
    private var notesInFolder: [NoteItem] { store.workspaceNotes(in: folder.folderID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NoteFolderTreeRow(folder: folder)

            if isExpanded {
                NoteInsertionLine(folderID: folder.folderID, targetIndex: 0)

                ForEach(Array(notesInFolder.enumerated()), id: \.element.noteID) { index, note in
                    NoteTreeRow(note: note)

                    NoteInsertionLine(folderID: folder.folderID, targetIndex: index + 1)
                }

                if notesInFolder.isEmpty {
                    EmptyFolderHint(folderID: folder.folderID)
                } else {
                    NewNoteInlineButton(folderID: folder.folderID)
                }
            }
        }
        .padding(.bottom, isExpanded ? 4 : 0)
        .animation(.easeInOut(duration: 0.15), value: isExpanded)
    }
}

private struct NoteFolderTreeRow: View {
    @EnvironmentObject private var store: ClipboardStore
    let folder: NoteFolder

    @State private var hover = false
    @State private var dropTargeted = false
    @State private var isRenaming = false
    @State private var draftName = ""
    @State private var showingEditor = false
    @FocusState private var nameFieldFocused: Bool

    private var iconName: String {
        folder.icon?.rawValue.replacingOccurrences(of: "sf:", with: "") ?? "folder"
    }
    private var tint: Color { folder.color.color.opacity(0.85) }
    private var isExpanded: Bool { store.isNoteFolderExpanded(folder.folderID) }
    private var noteCount: Int { store.workspaceNotes(in: folder.folderID).count }

    var body: some View {
        HStack(spacing: 6) {
            chevron
            folderClickArea
            if hover && !isRenaming {
                Button {
                    store.createNote(origin: .workspace, folderID: folder.folderID, openInWorkspace: true)
                    store.setNoteFolderExpanded(folder.folderID, expanded: true)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 18, height: 18)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
                .help("New note in \(folder.name)")
                .transition(.opacity)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(rowBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(dropTargeted ? tint.opacity(0.65) : .clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .contextMenu {
            Button(isExpanded ? "Collapse" : "Expand") {
                store.toggleNoteFolderExpanded(folder.folderID)
            }
            Divider()
            Button(CommonCopy.newNote()) {
                store.createNote(origin: .workspace, folderID: folder.folderID, openInWorkspace: true)
                store.setNoteFolderExpanded(folder.folderID, expanded: true)
            }
            if !folder.isSystem {
                Button(CommonCopy.rename()) { beginRename() }
            }
            Button(L10n.string("ui.edit.icon.color", default: "Edit icon & color…")) { showingEditor = true }
            if !folder.isSystem {
                Divider()
                Button(CommonCopy.delete(), role: .destructive) {
                    store.deleteNoteFolder(folder.folderID)
                }
            }
        }
        .popover(isPresented: $showingEditor, arrowEdge: .trailing) {
            // Popover content is presented in a separate window; keep the
            // explicit injection rather than trusting environment inheritance
            // across the presentation boundary (a miss crashes at runtime).
            NoteFolderEditorPopover(folder: folder)
                .environmentObject(store)
        }
        .onDrag {
            let provider = NSItemProvider(object: "noteFolder:\(folder.folderID.uuidString)" as NSString)
            provider.suggestedName = folder.name
            return provider
        }
        .onDrop(of: [UTType.plainText.identifier], isTargeted: $dropTargeted) { providers in
            handleNoteDrop(providers: providers, folderID: folder.folderID, targetIndex: 0, store: store)
        }
    }

    private var chevron: some View {
        Button {
            store.toggleNoteFolderExpanded(folder.folderID)
        } label: {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 12, height: 12)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .animation(.easeOut(duration: 0.18), value: isExpanded)
        }
        .buttonStyle(.plain)
    }

    private var folderClickArea: some View {
        Button {
            if isRenaming { return }
            store.selectedNoteFolderID = folder.folderID
            store.openWorkspaceFolderTab(folder.folderID, isNoteFolder: true)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint.opacity(hover ? 1.0 : 0.78))
                    .frame(width: 14)

                if isRenaming {
                    TextField("Folder", text: $draftName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .focused($nameFieldFocused)
                        .onSubmit { commitRename() }
                        .onExitCommand { cancelRename() }
                        .onChange(of: nameFieldFocused) { _, focused in
                            if !focused && isRenaming { commitRename() }
                        }
                } else {
                    Text(folder.name)
                        .lineLimit(1)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(hover ? 1.0 : 0.82))
                }

                Spacer(minLength: 0)

                if !hover && noteCount > 0 && !isRenaming {
                    Text("\(noteCount)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.38))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                if !folder.isSystem { beginRename() }
            }
        )
    }

    private var rowBackground: Color {
        if dropTargeted { return tint.opacity(0.18) }
        if hover { return Color.white.opacity(0.04) }
        return .clear
    }

    private func beginRename() {
        draftName = folder.name
        isRenaming = true
        DispatchQueue.main.async { nameFieldFocused = true }
    }

    private func commitRename() {
        guard isRenaming else { return }
        isRenaming = false
        nameFieldFocused = false
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != folder.name else { return }
        store.renameNoteFolder(folder.folderID, name: trimmed)
    }

    private func cancelRename() {
        isRenaming = false
        nameFieldFocused = false
    }
}

private struct NoteTreeRow: View {
    @EnvironmentObject private var store: ClipboardStore
    let note: NoteItem

    @State private var hover = false

    private var iconName: String {
        note.origin == .quickNote ? "sparkles.rectangle.stack" : "doc.text"
    }
    private var tint: Color { .purple.opacity(0.72) }
    private var isSelected: Bool { store.selectedWorkspaceNoteID == note.noteID }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                store.quickNoteActiveNoteID = note.noteID
                QuickNoteWindowManager.shared.show()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: iconName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(tint.opacity(hover || isSelected ? 1.0 : 0.7))
                        .frame(width: 14)
                    Text(note.displayTitle)
                        .lineLimit(1)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(.white.opacity(hover || isSelected ? 1.0 : 0.74))
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 3)
                .padding(.leading, 28)
                .padding(.trailing, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isSelected
                              ? Color.white.opacity(0.06)
                              : (hover ? Color.white.opacity(0.03) : Color.clear))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 3) {
                NoteTreeActionButton(systemImage: "doc.on.doc", help: "Copy note") {
                    _ = store.copyNoteToClipboard(note.noteID)
                }
                NoteTreeActionButton(
                    systemImage: "trash",
                    help: "Delete note",
                    foreground: Color(red: 1.0, green: 0.74, blue: 0.74)
                ) {
                    store.deleteNote(note.noteID)
                }
            }
            .padding(.trailing, 6)
            .opacity(hover ? 1 : 0)
            .allowsHitTesting(hover)
            .animation(.easeOut(duration: 0.12), value: hover)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .contextMenu {
            Button(L10n.string("ui.copy.markdown", default: "Copy markdown")) { _ = store.copyNoteToClipboard(note.noteID) }
            Button(L10n.string("ui.save.as.clip", default: "Save as clip")) { _ = store.saveNoteAsClipSnapshot(note.noteID) }
            Divider()
            Button(CommonCopy.delete(), role: .destructive) { store.deleteNote(note.noteID) }
        }
        .onDrag {
            let provider = NSItemProvider(object: "note:\(note.noteID.uuidString)" as NSString)
            provider.suggestedName = note.displayTitle
            return provider
        }
    }
}

private struct NoteTreeActionButton: View {
    let systemImage: String
    let help: String
    var foreground: Color = .white.opacity(0.78)
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(foreground.opacity(hover ? 1 : 0.78))
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.white.opacity(hover ? 0.10 : 0.04))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

private struct EmptyFolderHint: View {
    @EnvironmentObject private var store: ClipboardStore
    let folderID: UUID
    @State private var dropTargeted = false

    var body: some View {
        Button {
            store.createNote(origin: .workspace, folderID: folderID, openInWorkspace: true)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                Text(CommonCopy.newNote())
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(.white.opacity(dropTargeted ? 0.95 : 0.45))
            .padding(.vertical, 5)
            .padding(.leading, 28)
            .padding(.trailing, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(dropTargeted
                          ? Color(red: 0.83, green: 0.66, blue: 0.26).opacity(0.14)
                          : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onDrop(of: [UTType.plainText.identifier], isTargeted: $dropTargeted) { providers in
            handleNoteDrop(providers: providers, folderID: folderID, targetIndex: 0, store: store)
        }
    }
}

private struct NewNoteInlineButton: View {
    @EnvironmentObject private var store: ClipboardStore
    let folderID: UUID

    var body: some View {
        Button {
            store.createNote(origin: .workspace, folderID: folderID, openInWorkspace: true)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                Text(CommonCopy.newNote())
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.42))
            .padding(.vertical, 3)
            .padding(.leading, 28)
        }
        .buttonStyle(.plain)
    }
}

private struct FolderInsertionLine: View {
    @EnvironmentObject private var store: ClipboardStore
    let targetIndex: Int
    @State private var dropTargeted = false

    private var goldAccent: Color { Color(red: 0.83, green: 0.66, blue: 0.26) }

    var body: some View {
        Rectangle()
            .fill(dropTargeted ? goldAccent.opacity(0.95) : .clear)
            .frame(height: dropTargeted ? 2 : 6)
            .padding(.horizontal, 6)
            .padding(.vertical, dropTargeted ? 2 : 0)
            .contentShape(Rectangle())
            .onDrop(of: [UTType.plainText.identifier], isTargeted: $dropTargeted) { providers in
                handleFolderDrop(providers: providers, targetIndex: targetIndex, store: store)
            }
    }
}

private struct NoteInsertionLine: View {
    @EnvironmentObject private var store: ClipboardStore
    let folderID: UUID
    let targetIndex: Int
    @State private var dropTargeted = false

    private var goldAccent: Color { Color(red: 0.83, green: 0.66, blue: 0.26) }

    var body: some View {
        Rectangle()
            .fill(dropTargeted ? goldAccent.opacity(0.95) : .clear)
            .frame(height: dropTargeted ? 2 : 4)
            .padding(.leading, 28)
            .padding(.trailing, 6)
            .padding(.vertical, dropTargeted ? 1 : 0)
            .contentShape(Rectangle())
            .onDrop(of: [UTType.plainText.identifier], isTargeted: $dropTargeted) { providers in
                handleNoteDrop(providers: providers, folderID: folderID, targetIndex: targetIndex, store: store)
            }
    }
}

/// Shared decode for sidebar drag payloads. Payloads are plain strings of the
/// form `"<prefix><uuid>"`; on a match, `action` runs on the main queue with
/// the parsed UUID.
@discardableResult
private func handleDrop(
    providers: [NSItemProvider],
    prefix: String,
    action: @escaping @MainActor (UUID) -> Void
) -> Bool {
    guard let provider = providers.first else { return false }
    provider.loadObject(ofClass: NSString.self) { object, _ in
        guard let string = object as? String, string.hasPrefix(prefix),
              let id = UUID(uuidString: String(string.dropFirst(prefix.count))) else { return }
        DispatchQueue.main.async {
            action(id)
        }
    }
    return true
}

@discardableResult
private func handleFolderDrop(
    providers: [NSItemProvider],
    targetIndex: Int,
    store: ClipboardStore
) -> Bool {
    handleDrop(providers: providers, prefix: "noteFolder:") { folderID in
        store.reorderNoteFolders(folderID: folderID, to: targetIndex)
    }
}

@discardableResult
private func handleNoteDrop(
    providers: [NSItemProvider],
    folderID: UUID,
    targetIndex: Int,
    store: ClipboardStore
) -> Bool {
    handleDrop(providers: providers, prefix: "note:") { noteID in
        store.moveNoteToFolder(noteID, folderID: folderID, atIndex: targetIndex)
    }
}
