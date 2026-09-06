import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Top-trailing chrome menu for sending the current Quick Note somewhere
/// useful. Storage is already plain markdown (`NoteItem.bodyMarkdown`), so
/// each action is a thin wrapper — no conversion layer, no lossy export.
struct QuickNoteExportMenu: View {
    /// Nil until the first note is created. Hides the menu entirely so the
    /// chrome doesn't flash an unusable button on first open.
    let note: NoteItem?
    let tint: Color

    var body: some View {
        if let note {
            Menu {
                Button {
                    QuickNoteExporter.copyAsMarkdown(note)
                } label: {
                    Label(L10n.string("ui.copy.as.markdown", default: "Copy as Markdown"), systemImage: "doc.on.clipboard")
                }

                Button {
                    QuickNoteExporter.saveAsMarkdownFile(note)
                } label: {
                    Label(L10n.string("ui.save.as.md.file", default: "Save as .md file…"), systemImage: "square.and.arrow.down")
                }

                Divider()

                Button {
                    QuickNoteExporter.openInObsidian(note)
                } label: {
                    Label(L10n.string("ui.open.in.obsidian", default: "Open in Obsidian"), systemImage: "arrow.up.right.square")
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint.opacity(0.78))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .tint(tint)
            .foregroundStyle(tint)
            .fixedSize()
            .help("Send this note to Markdown, a file, or Obsidian")
        }
    }
}

@MainActor
enum QuickNoteExporter {
    /// Drop the raw markdown onto the system pasteboard. Title is intentionally
    /// excluded — paste targets that already have a title field (Notion, an
    /// email subject line) would double up otherwise. Users who want the
    /// title can prepend it themselves with one keystroke.
    static func copyAsMarkdown(_ note: NoteItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(note.bodyMarkdown, forType: .string)
    }

    /// Writes the note as a `.md` file via NSSavePanel. The filename defaults
    /// to the note's display title so most users can hit Return without
    /// renaming. We embed an H1 with the title so the saved file reads well
    /// on its own — the in-app body alone has no title because the title is
    /// edited separately in the workspace UI.
    static func saveAsMarkdownFile(_ note: NoteItem) {
        let panel = NSSavePanel()
        panel.title = "Save Quick Note"
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = sanitizedFilename(for: note) + ".md"
        if let mdType = UTType("net.daringfireball.markdown") {
            panel.allowedContentTypes = [mdType]
        } else {
            panel.allowedContentTypes = [.plainText]
        }

        guard panel.runModalInFront() == .OK, let url = panel.url else { return }
        let document = composedMarkdown(for: note)
        do {
            try document.data(using: .utf8)?.write(to: url, options: .atomic)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't save note"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModalInFront()
        }
    }

    /// Hands the note off to Obsidian via its `obsidian://new` URL scheme.
    /// This opens the user's default vault — if Obsidian isn't installed,
    /// macOS will surface its usual "no app set to open this URL" alert,
    /// which is the right behaviour: we don't want to silently swallow it.
    static func openInObsidian(_ note: NoteItem) {
        var components = URLComponents()
        components.scheme = "obsidian"
        components.host = "new"
        components.queryItems = [
            URLQueryItem(name: "name", value: note.displayTitle),
            URLQueryItem(name: "content", value: note.bodyMarkdown)
        ]
        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }

    private static func composedMarkdown(for note: NoteItem) -> String {
        let title = note.displayTitle
        let body = note.bodyMarkdown
        if body.hasPrefix("# ") {
            return body
        }
        return "# \(title)\n\n\(body)"
    }

    private static func sanitizedFilename(for note: NoteItem) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = note.displayTitle
            .components(separatedBy: invalid)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Quick Note" : cleaned
    }
}
