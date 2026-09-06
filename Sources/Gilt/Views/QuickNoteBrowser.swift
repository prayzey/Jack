import SwiftUI

/// One-line preview for a note in the browser list: the first body line after
/// the title, with light markdown tokens stripped so the preview reads as prose
/// rather than raw syntax. Image/rule lines are skipped — they'd show as noise.
@MainActor
func quickNoteBrowserSnippet(for note: NoteItem) -> String {
    let lines = note.bodyMarkdown.components(separatedBy: .newlines)
    var seenTitle = false
    for rawLine in lines {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.isEmpty { continue }
        if line.hasPrefix("![") || QuickNoteBodyRenderer.isHorizontalRuleLine(line) { continue }
        if !seenTitle {
            // The first meaningful line is already the row's title.
            seenTitle = true
            continue
        }
        return strippedMarkdownLead(line)
    }
    return ""
}

private func strippedMarkdownLead(_ line: String) -> String {
    var text = line
    // Peel common leading block markers so previews read cleanly.
    let leads = ["###### ", "##### ", "#### ", "### ", "## ", "# ", "> ", "- [ ] ", "- [x] ", "- ", "* ", "+ "]
    for lead in leads where text.hasPrefix(lead) {
        text = String(text.dropFirst(lead.count))
        break
    }
    return text.trimmingCharacters(in: .whitespaces)
}

/// Compact "tracker" control shown in the Quick Note chrome. Reads as
/// "you are on note 3 of 12" and opens the full browser on tap.
struct QuickNoteBrowseButton: View {
    let position: Int
    let total: Int
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 11, weight: .semibold))
                if total > 1 {
                    Text("\(position)/\(total)")
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(tint.opacity(0.9))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.10))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(tint.opacity(0.16), lineWidth: 0.8)
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Browse all quick notes")
        .accessibilityLabel(Text(L10n.string("ui.browse.all.quick.notes", default: "Browse all quick notes")))
    }
}

/// Full-window overlay listing every quick note with live search and jump.
/// Rendered inside `QuickNoteView`'s ZStack — the Quick Note window is a
/// standalone borderless window, so an in-window overlay sidesteps the tray's
/// sheet/window pitfalls entirely. Owns its own search `@State` so typing in the
/// search field re-renders only this overlay, never the note editor behind it.
struct QuickNoteBrowserOverlay: View {
    @Binding var isPresented: Bool
    let notes: [NoteItem]
    let currentNoteID: UUID?
    let style: QuickNoteStyle
    let onSelect: (UUID) -> Void
    let onCreate: () -> Void
    let onDelete: (UUID) -> Void

    @State private var searchText = ""
    @FocusState private var searchFocused: Bool

    private var isLight: Bool { style.isLightSurface }
    private var accent: Color { style.insertionColor }
    private var primaryText: Color { isLight ? Color.black.opacity(0.85) : Color.white.opacity(0.92) }
    private var secondaryText: Color { isLight ? Color.black.opacity(0.5) : Color.white.opacity(0.55) }
    private var panelFill: Color { isLight ? Color(white: 0.98) : Color(white: 0.11) }
    private var fieldFill: Color { isLight ? Color.black.opacity(0.05) : Color.white.opacity(0.07) }
    private var hairline: Color { isLight ? Color.black.opacity(0.10) : Color.white.opacity(0.10) }

    /// Most-recently-edited first, with any pinned notes floated to the top.
    private var filteredNotes: [NoteItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return notes
            .filter { note in
                guard !query.isEmpty else { return true }
                return "\(note.displayTitle)\n\(note.bodyMarkdown)"
                    .localizedCaseInsensitiveContains(query)
            }
            .sorted { a, b in
                if a.isPinned != b.isPinned { return a.isPinned && !b.isPinned }
                return a.updatedAt > b.updatedAt
            }
    }

    var body: some View {
        ZStack {
            // Scrim — tap anywhere outside the panel to dismiss. No
            // ignoresSafeArea: the host insets + clips this overlay to the note
            // card so the dim never bleeds into the window's transparent margin.
            Color.black.opacity(0.34)
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }

            GeometryReader { geo in
                let panelWidth = min(geo.size.width - 40, 460)
                let panelHeight = min(geo.size.height - 40, 560)
                panel
                    .frame(width: panelWidth, height: panelHeight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onKeyPress(.escape) { dismiss(); return .handled }
        .onAppear { searchFocused = true }
        .transition(.opacity)
    }

    private var panel: some View {
        VStack(spacing: 0) {
            searchHeader
            Divider().overlay(hairline)
            if filteredNotes.isEmpty {
                emptyState
            } else {
                noteList
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(panelFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(hairline, lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 30, y: 14)
    }

    private var searchHeader: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(secondaryText)
                TextField("", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(primaryText)
                    .overlay(alignment: .leading) {
                        if searchText.isEmpty {
                            Text("Search notes")
                                .foregroundStyle(secondaryText)
                                .allowsHitTesting(false)
                        }
                    }
                    .accessibilityLabel(Text("Search notes"))
                    .focused($searchFocused)
                    .onSubmit {
                        if let first = filteredNotes.first { select(first.noteID) }
                    }
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(secondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(Capsule(style: .continuous).fill(fieldFill))

            Button(action: onCreate) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(accent.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .help("New quick note")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var noteList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(filteredNotes) { note in
                    QuickNoteBrowserRow(
                        note: note,
                        isCurrent: note.noteID == currentNoteID,
                        primaryText: primaryText,
                        secondaryText: secondaryText,
                        accent: accent,
                        onSelect: { select(note.noteID) },
                        onDelete: { onDelete(note.noteID) }
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.visible)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(secondaryText)
            Text(searchText.isEmpty ? "No notes yet" : "No notes match")
                .font(.system(size: 13))
                .foregroundStyle(secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func select(_ id: UUID) {
        onSelect(id)
        isPresented = false
    }

    private func dismiss() {
        isPresented = false
    }
}
