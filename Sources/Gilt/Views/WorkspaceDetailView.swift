import SwiftUI

struct WorkspaceDetailView: View {
    @EnvironmentObject private var store: ClipboardStore

    private var goldAccent: Color { Color(red: 0.83, green: 0.66, blue: 0.26) }

    var body: some View {
        Group {
            if let tab = selectedTab {
                switch tab.kind {
                case .clip(let clipID):
                    WorkspaceClipDetailView(clipID: clipID)
                case .kanbanBoard(let boardID):
                    KanbanBoardView(boardID: boardID)
                        .id(boardID)
                case .meetings:
                    WorkspaceMeetingsView()
                        .environmentObject(store)
                case .note, .noteFolder:
                    retiredNotesEmptyState
                case .clipFolder(let folderID):
                    WorkspaceClipFolderView(folderID: folderID, accent: goldAccent)
                        .environmentObject(store)
                }
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(goldAccent.opacity(0.7))
            Text(L10n.string("ui.nothing.open", default: "Nothing open"))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            Text(L10n.string("ui.pick.something.from.the.sidebar.to.open.it.here", default: "Pick something from the sidebar to open it here."))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var retiredNotesEmptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "note.text")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(goldAccent.opacity(0.7))
            Text(L10n.string("ui.notes.moved.to.quick.note", default: "Notes moved to Quick Note"))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            Text(L10n.string("ui.use.quick.note.from.the.menu.bar.or..9c1c50", default: "Use Quick Note from the menu bar, or open Tasks for the Kanban board."))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var selectedTab: WorkspaceTab? {
        store.workspaceSession.tabs.first(where: { $0.id == store.workspaceSession.selectedTabID })
    }
}

private struct WorkspaceFolderResultView<Content: View, Accessory: View>: View {
    let title: String
    let accent: Color
    let isEmpty: Bool
    let emptyMessage: String
    @ViewBuilder let content: Content
    @ViewBuilder let accessory: Accessory

    init(
        title: String,
        accent: Color,
        isEmpty: Bool,
        emptyMessage: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.title = title
        self.accent = accent
        self.isEmpty = isEmpty
        self.emptyMessage = emptyMessage
        self.content = content()
        self.accessory = accessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 28)
                .padding(.top, 26)
                .padding(.bottom, isEmpty ? 0 : 18)

            if isEmpty {
                // Keeps the title pinned at top and centers the empty-state
                // message in whatever vertical space remains in the detail pane.
                EmptyFolderMessage(message: emptyMessage, accent: accent)
                    .id(title)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, 26)
            } else {
                ScrollView {
                    // Lazy so folders with hundreds of clips only materialize
                    // visible rows (each row carries a thumbnail task); a plain
                    // VStack built all of them on every store change.
                    LazyVStack(alignment: .leading, spacing: 0) {
                        content
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 26)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string("ui.folder", default: "FOLDER"))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(2.4)
                    .foregroundStyle(accent.opacity(0.85))
                Text(title)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .tracking(-0.4)
            }
            Spacer(minLength: 12)
            accessory
        }
    }
}

private struct EmptyFolderMessage: View {
    let message: String
    let accent: Color
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(accent.opacity(0.7))
                .symbolRenderingMode(.hierarchical)

            Text(L10n.string("common.nothingHereYet", default: "Nothing here yet"))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .tracking(-0.2)

            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 6)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                appeared = true
            }
        }
    }
}

private enum WorkspaceClipLayout: String {
    case list
    case grid
}

struct WorkspaceClipFolderView: View {
    let folderID: UUID
    let accent: Color

    @EnvironmentObject private var store: ClipboardStore
    @AppStorage("workspaceClipLayout") private var layoutRaw: String = WorkspaceClipLayout.list.rawValue

    private var layout: WorkspaceClipLayout {
        WorkspaceClipLayout(rawValue: layoutRaw) ?? .list
    }

    private var folderName: String {
        store.folders.first(where: { $0.folderID == folderID })?.name ?? "Folder"
    }

    private var clips: [ClipItemModel] {
        store.clips.filter { $0.folders.contains(where: { $0.folderID == folderID }) }
    }

    var body: some View {
        // Bind once: the filter walks every clip's SwiftData folder
        // relationship, so computing it for isEmpty and again for the list
        // doubled the cost of every body pass.
        let clips = self.clips
        return WorkspaceFolderResultView(
            title: folderName,
            accent: accent,
            isEmpty: clips.isEmpty,
            emptyMessage: "Drag a clip from the tray to drop it into this folder."
        ) {
            switch layout {
            case .list:
                ForEach(clips, id: \.clipID) { clip in
                    WorkspaceClipListRow(clip: clip, accent: accent) {
                        store.openClipInWorkspace(clip.clipID)
                    }
                }
            case .grid:
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 14)],
                    alignment: .leading,
                    spacing: 14
                ) {
                    ForEach(clips, id: \.clipID) { clip in
                        WorkspaceClipGridCell(clip: clip) {
                            store.openClipInWorkspace(clip.clipID)
                        }
                    }
                }
            }
        } accessory: {
            layoutToggle
        }
    }

    private var layoutToggle: some View {
        HStack(spacing: 2) {
            toggleButton(.list, icon: "list.bullet")
            toggleButton(.grid, icon: "square.grid.2x2")
        }
        .padding(3)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 0.5))
    }

    private func toggleButton(_ mode: WorkspaceClipLayout, icon: String) -> some View {
        let selected = layout == mode
        return Button {
            layoutRaw = mode.rawValue
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(selected ? Color.black.opacity(0.8) : Color.white.opacity(0.65))
                .frame(width: 28, height: 22)
                .background(Capsule().fill(selected ? Color.white.opacity(0.9) : Color.clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct WorkspaceClipListRow: View {
    let clip: ClipItemModel
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                WorkspaceClipGlyph(clip: clip, size: 32, cornerRadius: 7, iconSize: 14)
                VStack(alignment: .leading, spacing: 3) {
                    Text(workspaceClipDisplayTitle(clip))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                    if let subtitle = workspaceClipSubtitle(clip) {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct WorkspaceClipGridCell: View {
    let clip: ClipItemModel
    let action: () -> Void

    private var typeAccent: Color { workspaceClipTypeAccent(clip.clipType) }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                header
                content
                    .frame(maxWidth: .infinity, minHeight: 92, maxHeight: 92, alignment: .topLeading)
                    .padding(10)
                    .background(Color(nsColor: NSColor(white: 0.12, alpha: 1.0)))
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: workspaceClipTypeIcon(clip.clipType))
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
            Text(workspaceClipTypeLabel(clip.clipType))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.9))
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            LinearGradient(
                colors: [typeAccent.opacity(0.95), typeAccent.opacity(0.75)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }

    @ViewBuilder
    private var content: some View {
        switch clip.clipType {
        case .image:
            // Fills the cell and clips to its bounds — wide images can no
            // longer overflow the card. Decodes off the main thread so the
            // list/grid toggle stays smooth.
            WorkspaceClipFillImage(clip: clip)
        default:
            VStack(alignment: .leading, spacing: 4) {
                Text(workspaceClipDisplayTitle(clip))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(2)
                if let subtitle = workspaceClipSubtitle(clip) {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(3)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

fileprivate func workspaceClipDisplayTitle(_ clip: ClipItemModel) -> String {
    switch clip.clipType {
    case .link:
        if let pageTitle = clip.linkPageTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !pageTitle.isEmpty {
            return pageTitle
        }
        if let url = clip.urlValue, let host = URL(string: url)?.host {
            return host
        }
        return clip.urlValue ?? clip.previewText
    case .image:
        return "Image"
    case .audio:
        let raw = clip.textValue ?? clip.previewText
        return URL(fileURLWithPath: raw).lastPathComponent
    case .text, .color:
        let candidate = clip.textValue ?? clip.previewText
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Untitled" }
        return trimmed.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? trimmed
    }
}

@MainActor
fileprivate func workspaceClipSubtitle(_ clip: ClipItemModel) -> String? {
    switch clip.clipType {
    case .link:
        return clip.urlValue
    case .image:
        if let data = clip.imageData,
           let dimensions = ThumbnailService.shared.dimensions(for: clip.clipID, data: data) {
            return dimensions.replacingOccurrences(of: "×", with: " × ")
        }
        return nil
    case .audio:
        return clip.previewText
    case .text, .color:
        let candidate = clip.textValue ?? clip.previewText
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = trimmed.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard lines.count > 1 else { return nil }
        return String(lines[1]).trimmingCharacters(in: .whitespaces)
    }
}

func workspaceClipTypeIcon(_ type: ClipType) -> String {
    switch type {
    case .text: return "text.alignleft"
    case .link: return "link"
    case .image: return "photo"
    case .audio: return "waveform"
    case .color: return "paintpalette"
    }
}

func workspaceClipTypeLabel(_ type: ClipType) -> String {
    switch type {
    case .text: return "TEXT"
    case .link: return "LINK"
    case .image: return "IMAGE"
    case .audio: return "AUDIO"
    case .color: return "COLOR"
    }
}

func workspaceClipTypeAccent(_ type: ClipType) -> Color {
    switch type {
    case .text: return Color(red: 0.40, green: 0.52, blue: 0.96)
    case .link: return Color(red: 0.30, green: 0.78, blue: 0.55)
    case .image: return Color(red: 0.93, green: 0.38, blue: 0.48)
    case .audio: return Color(red: 0.96, green: 0.58, blue: 0.28)
    case .color: return Color(red: 0.70, green: 0.40, blue: 0.90)
    }
}
