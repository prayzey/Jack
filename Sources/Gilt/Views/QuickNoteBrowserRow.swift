import SwiftUI

/// A single note row in the Quick Note browser. Shows the note title, a one-line
/// preview, and a relative timestamp. The current note is marked with an accent
/// dot (no filled box — a row-wide fill reads as a nested "box in a box").
/// Delete uses a two-step inline confirm so a stray click can't destroy a note
/// the user actually wants.
struct QuickNoteBrowserRow: View {
    let note: NoteItem
    let isCurrent: Bool
    let primaryText: Color
    let secondaryText: Color
    let accent: Color
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var confirmingDelete = false

    private var snippet: String { quickNoteBrowserSnippet(for: note) }

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 10) {
                currentMarker
                VStack(alignment: .leading, spacing: 3) {
                    Text(note.displayTitle)
                        .font(.system(size: 13, weight: isCurrent ? .semibold : .medium))
                        .foregroundStyle(primaryText)
                        .lineLimit(1)
                    if !snippet.isEmpty {
                        Text(snippet)
                            .font(.system(size: 11.5))
                            .foregroundStyle(secondaryText)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                trailing
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            // Whole row stays clickable, but no filled background — the accent
            // dot alone marks the current note.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if !hovering { confirmingDelete = false }
        }
    }

    private var currentMarker: some View {
        Circle()
            .fill(isCurrent ? accent : Color.clear)
            .frame(width: 6, height: 6)
            .padding(.top, 5)
    }

    private var trailing: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(ClipRelativeTimeFormatter.string(from: note.updatedAt))
                .font(.system(size: 10.5))
                .foregroundStyle(secondaryText.opacity(0.8))
                .padding(.top, 1)

            deleteControl
                .frame(width: 64, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var deleteControl: some View {
        if confirmingDelete {
            Button(role: .destructive, action: onDelete) {
                Text(L10n.string("ui.delete", default: "Delete"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.red)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.red.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .help("Click again to delete note")
            .accessibilityLabel(Text("Confirm delete note"))
        } else {
            Button { confirmingDelete = true } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(secondaryText)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Delete note")
            .accessibilityLabel(Text("Delete note"))
        }
    }
}
