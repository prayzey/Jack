import SwiftUI

/// The strip of recently-copied items that reveals below the compose editor.
/// Double-clicking a chip drops that clip's text at the caret so the user can
/// fold a copied link / snippet into the middle of what they're dictating, then
/// keep going. Only clips that carry insertable text are shown — pasting an
/// image or audio blob into a plain-text composer makes no sense.
struct RecentClipsTray: View {
    @EnvironmentObject private var store: ClipboardStore
    @ObservedObject var controller: DictationComposeController

    /// Cap so the tray stays a quick glance, not a second clipboard window.
    private let maxItems = 10

    private var items: [ClipItemModel] {
        store.clips
            .filter { Self.insertableString(for: $0) != nil }
            .prefix(maxItems)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.string("ui.recent.clips.double.click.to.drop.one.in", default: "Recent clips. Double-click to drop one in"))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.horizontal, 4)

            if items.isEmpty {
                Text(L10n.string("ui.nothing.copied.yet", default: "Nothing copied yet"))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(items, id: \.clipID) { clip in
                            ClipChip(clip: clip) { insert(clip) }
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 2)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private func insert(_ clip: ClipItemModel) {
        guard let text = Self.insertableString(for: clip) else { return }
        controller.insertClip(text)
    }

    /// The string a clip contributes when inserted. Links prefer their URL,
    /// everything text-bearing falls back through `textValue` / `previewText`.
    /// Returns nil for clips with no sensible plain-text form (image, audio).
    static func insertableString(for clip: ClipItemModel) -> String? {
        let candidate: String?
        switch clip.clipType {
        case .link:
            candidate = clip.urlValue ?? clip.textValue ?? clip.previewText
        case .text, .color:
            candidate = clip.textValue ?? clip.previewText
        case .image, .audio:
            candidate = clip.textValue ?? clip.urlValue
        }
        guard let candidate, !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return candidate
    }
}

/// A single tappable clip in the tray. Single-click highlights via hover;
/// double-click commits the insert (matching the interaction the user asked
/// for, and avoiding accidental inserts on a stray click).
private struct ClipChip: View {
    let clip: ClipItemModel
    let onInsert: () -> Void

    @State private var hovering = false

    private var label: String {
        let base: String
        if let title = clip.linkPageTitle, !title.isEmpty {
            base = title
        } else if !clip.title.isEmpty {
            base = clip.title
        } else {
            base = clip.previewText
        }
        let collapsed = base
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.isEmpty ? clip.previewText : collapsed
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: glyph)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(accent)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .frame(maxWidth: 180, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.14 : 0.07))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(accent.opacity(hovering ? 0.5 : 0), lineWidth: 1)
        )
        .contentShape(Capsule(style: .continuous))
        .onTapGesture(count: 2, perform: onInsert)
        .onHover { hovering = $0 }
        .help("Double-click to insert at the cursor")
    }

    private var glyph: String {
        switch clip.clipType {
        case .text:  return "text.alignleft"
        case .link:  return "link"
        case .image: return "photo"
        case .audio: return "waveform"
        case .color: return "paintpalette"
        }
    }

    private var accent: Color {
        switch clip.clipType {
        case .text:  return Color(red: 0.40, green: 0.52, blue: 0.96)
        case .link:  return Color(red: 0.30, green: 0.78, blue: 0.55)
        case .image: return Color(red: 0.93, green: 0.38, blue: 0.48)
        case .audio: return Color(red: 0.96, green: 0.58, blue: 0.28)
        case .color: return Color(red: 0.70, green: 0.40, blue: 0.90)
        }
    }
}
