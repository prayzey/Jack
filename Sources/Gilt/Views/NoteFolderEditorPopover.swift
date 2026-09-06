import SwiftUI

/// Popover editor for a user-created note folder — rename, change icon, change
/// color. System folders (Scratchpads, Notes) cannot be edited; the surfaces
/// that present this popover gate it behind `!folder.isSystem`.
struct NoteFolderEditorPopover: View {
    @EnvironmentObject private var store: ClipboardStore
    let folder: NoteFolder

    private static let presetSymbols = [
        "folder", "tray.full", "bookmark", "star", "heart", "bolt",
        "paperplane", "briefcase", "terminal", "paintpalette", "music.note", "lock"
    ]

    @State private var draftName = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Name")
                TextField("Folder name", text: $draftName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, weight: .medium))
                    .focused($nameFocused)
                    .onSubmit { commitName() }
                    .onChange(of: nameFocused) { _, focused in
                        if !focused { commitName() }
                    }
            }

            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Icon")
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6),
                    spacing: 8
                ) {
                    ForEach(Self.presetSymbols, id: \.self) { symbol in
                        iconSwatch(symbol)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Color")
                HStack(spacing: 9) {
                    ForEach(FolderColorToken.allCases, id: \.self) { token in
                        colorSwatch(token)
                    }
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(width: 300)
        .onAppear { draftName = folder.name }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(1.8)
            .foregroundStyle(.secondary)
    }

    private func iconSwatch(_ symbol: String) -> some View {
        let selected = folder.icon == .symbol(symbol)
        return Button {
            store.updateNoteFolderIcon(folder.folderID, icon: .symbol(symbol))
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.75))
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(selected ? folder.color.color.opacity(0.85) : Color.secondary.opacity(0.1))
                )
        }
        .buttonStyle(.plain)
    }

    private func colorSwatch(_ token: FolderColorToken) -> some View {
        let selected = folder.color == token
        return Button {
            store.updateNoteFolderColor(folder.folderID, color: token)
        } label: {
            Circle()
                .fill(token.color)
                .frame(width: 22, height: 22)
                .overlay(
                    Circle()
                        .strokeBorder(Color.primary.opacity(selected ? 0.9 : 0.15),
                                      lineWidth: selected ? 2 : 1)
                )
        }
        .buttonStyle(.plain)
        .help(token.label)
    }

    private func commitName() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != folder.name else {
            draftName = folder.name
            return
        }
        store.renameNoteFolder(folder.folderID, name: trimmed)
    }
}
