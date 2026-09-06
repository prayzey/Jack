import AppKit
import SwiftUI

struct WorkspaceClipDetailView: View {
    @EnvironmentObject private var store: ClipboardStore
    let clipID: UUID

    // Inline editing state — mirrors the pattern used in ClipPreviewOverlay so the
    // editing affordances behave identically across the tray preview and workspace.
    @State private var isEditing = false
    @State private var editText = ""
    @FocusState private var editorFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let item {
                    headerSection(for: item)

                    if store.isMirroredNoteClip(item) {
                        Label(L10n.string("ui.mirrored.note.snapshot", default: "Mirrored note snapshot"), systemImage: "note.text.badge.plus")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.orange.opacity(0.18)))
                            .foregroundStyle(Color.orange)
                    }

                    contentSection(for: item)
                } else {
                    Text(L10n.string("ui.clip", default: "Clip"))
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        // Switching to a different clip tab must abandon any in-flight edit so the
        // editor doesn't leak text from the previous clip into the next one.
        .onChange(of: clipID) { _, _ in
            cancelEdit()
        }
        .onExitCommand {
            // Only swallow Escape when actively editing; otherwise let WorkspaceView's
            // outer handler close the window as usual.
            if isEditing { cancelEdit() }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func headerSection(for item: ClipItemModel) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(workspaceClipTypeLabel(item.clipType))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(2.4)
                    .foregroundStyle(workspaceClipTypeAccent(item.clipType).opacity(0.85))
                Text(displayTitle(for: item))
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 12)
            actionToolbar(for: item)
                .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func actionToolbar(for item: ClipItemModel) -> some View {
        if isEditing {
            HStack(spacing: 8) {
                pillButton(
                    title: "Cancel",
                    systemImage: "xmark",
                    fill: Color.white.opacity(0.08),
                    foreground: .white.opacity(0.85),
                    help: "Cancel (Esc)"
                ) {
                    cancelEdit()
                }

                pillButton(
                    title: "Save",
                    systemImage: "checkmark",
                    fill: workspaceClipTypeAccent(item.clipType).opacity(0.9),
                    foreground: .white,
                    bold: true,
                    help: "Save (⌘↩)"
                ) {
                    commitEdit(for: item)
                }
            }
        } else if ClipboardStore.canInlineEdit(item.clipType) {
            HStack(spacing: 8) {
                transformMenu(for: item)

                pillButton(
                    title: "Copy",
                    systemImage: "doc.on.doc",
                    fill: Color.white.opacity(0.08),
                    foreground: .white.opacity(0.85),
                    help: "Copy"
                ) {
                    store.loadSelectedOrSingleToClipboard(
                        primaryID: item.clipID,
                        autoPaste: false
                    )
                }

                pillButton(
                    title: "Edit",
                    systemImage: "pencil",
                    fill: workspaceClipTypeAccent(item.clipType).opacity(0.22),
                    foreground: workspaceClipTypeAccent(item.clipType),
                    bold: true,
                    help: "Edit (⌘E)"
                ) {
                    beginEdit(for: item)
                }
                .keyboardShortcut("e", modifiers: .command)
            }
        }
    }

    private func pillButton(
        title: String,
        systemImage: String,
        fill: Color,
        foreground: Color,
        bold: Bool = false,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: bold ? .semibold : .medium))
                Text(title)
                    .font(.system(size: 12, weight: bold ? .semibold : .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(fill))
            .foregroundStyle(foreground)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    @ViewBuilder
    private func transformMenu(for item: ClipItemModel) -> some View {
        Menu {
            ForEach(Array(TextTransform.groupedForMenu.enumerated()), id: \.offset) { groupIndex, entry in
                if groupIndex > 0 {
                    Divider()
                }
                ForEach(entry.transforms, id: \.rawValue) { transform in
                    Button {
                        store.transformClipText(item.clipID, transform: transform)
                    } label: {
                        Label(transform.label, systemImage: transform.icon)
                    }
                }
            }
        } label: {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                .foregroundStyle(.white.opacity(0.85))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Transform Text")
    }

    // MARK: - Content

    @ViewBuilder
    private func contentSection(for item: ClipItemModel) -> some View {
        switch item.clipType {
        case .image:
            // AsyncClipThumbnail decodes off-main and its clipID-matched state
            // replaces the old manual reset-at-task-start when switching tabs.
            if let data = item.imageData {
                AsyncClipThumbnail(clipID: item.clipID, data: data, tier: .full) { nsImage in
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                } pending: {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.white.opacity(0.04))
                        .frame(maxWidth: .infinity, minHeight: 180)
                } unavailable: {
                    placeholder("Image data unavailable")
                }
            } else {
                placeholder("Image data unavailable")
            }
        case .link:
            if isEditing {
                editorContent(for: item)
            } else {
                linkReadOnlyContent(for: item)
            }
        case .audio:
            audioReadOnlyContent(for: item)
        case .text, .color:
            if isEditing {
                editorContent(for: item)
            } else {
                textReadOnlyContent(for: item)
            }
        }
    }

    private func editorContent(for item: ClipItemModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $editText)
                .font(looksLikeCode(item) ? .system(size: 14, design: .monospaced) : .system(size: 14))
                .foregroundStyle(.white.opacity(0.92))
                .scrollContentBackground(.hidden)
                .focused($editorFocused)
                .frame(minHeight: 240)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.05)))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(workspaceClipTypeAccent(item.clipType).opacity(0.45), lineWidth: 1)
                )
                .onKeyPress(.return, phases: .down) { keyPress in
                    guard keyPress.modifiers.contains(.command) else { return .ignored }
                    commitEdit(for: item)
                    return .handled
                }

            HStack(spacing: 6) {
                Image(systemName: "command")
                    .font(.system(size: 9, weight: .semibold))
                Text("⌘↩ to save · Esc to cancel")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.4))
            .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private func linkReadOnlyContent(for item: ClipItemModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title = item.linkPageTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            if let desc = item.linkDescriptionText?.trimmingCharacters(in: .whitespacesAndNewlines), !desc.isEmpty {
                Text(desc)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.7))
            }
            if let url = item.urlValue {
                Text(url)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.05)))
    }

    @ViewBuilder
    private func textReadOnlyContent(for item: ClipItemModel) -> some View {
        let body = item.textValue ?? item.previewText
        Text(body)
            .font(looksLikeCode(item) ? .system(size: 14, design: .monospaced) : .system(size: 14))
            .foregroundStyle(.white.opacity(0.86))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.05)))
    }

    @ViewBuilder
    private func audioReadOnlyContent(for item: ClipItemModel) -> some View {
        let body = item.textValue ?? item.previewText
        Text(body)
            .font(.system(size: 14))
            .foregroundStyle(.white.opacity(0.86))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.05)))
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.45))
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.05)))
    }

    // MARK: - Edit Lifecycle

    private func beginEdit(for item: ClipItemModel) {
        guard ClipboardStore.canInlineEdit(item.clipType) else { return }
        editText = item.textValue ?? item.urlValue ?? item.previewText
        isEditing = true
        // Slight async delay so the TextEditor exists before we focus it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            editorFocused = true
        }
    }

    private func commitEdit(for item: ClipItemModel) {
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Empty edits would no-op in updateClipText, so just bail out cleanly.
        guard !trimmed.isEmpty else {
            cancelEdit()
            return
        }
        store.updateClipText(item.clipID, newText: editText)
        isEditing = false
        editorFocused = false
    }

    private func cancelEdit() {
        isEditing = false
        editorFocused = false
        editText = ""
    }

    // MARK: - Helpers

    private func looksLikeCode(_ item: ClipItemModel) -> Bool {
        item.contentTags.contains(.code)
    }

    private func displayTitle(for item: ClipItemModel) -> String {
        switch item.clipType {
        case .link:
            if let pageTitle = item.linkPageTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !pageTitle.isEmpty {
                return pageTitle
            }
            if let url = item.urlValue, let host = URL(string: url)?.host { return host }
            return item.urlValue ?? item.previewText
        case .image:
            if let data = item.imageData,
               let dimensions = ThumbnailService.shared.dimensions(for: item.clipID, data: data) {
                return "Image · \(dimensions.replacingOccurrences(of: "×", with: " × "))"
            }
            return "Image"
        case .audio:
            let raw = item.textValue ?? item.previewText
            return URL(fileURLWithPath: raw).lastPathComponent
        case .text, .color:
            let candidate = item.textValue ?? item.previewText
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return "Untitled" }
            let firstLine = trimmed.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? trimmed
            return String(firstLine.prefix(120))
        }
    }

    private var item: ClipItemModel? {
        store.clips.first(where: { $0.clipID == clipID })
    }
}
