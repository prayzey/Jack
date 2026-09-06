import SwiftUI

/// Live scroll offset reported by the Quick Note editor, held outside
/// `QuickNoteView`'s own `@State` on purpose.
///
/// The top arrows + export menu fade as the user scrolls past the first line.
/// When this lived in a `@State CGFloat` on `QuickNoteView`, every scroll tick
/// (~60/sec) invalidated the *entire* view body — backdrop, themed card
/// background, the NSTextView bridge, and every overlay — just to nudge one
/// opacity. Moving it into an `@Observable` object means only the views that
/// actually read `offset` (the two chrome overlays below) re-render on scroll;
/// `QuickNoteView` never reads it, so the editor and card stay put. This is the
/// "isolate the changing state into a leaf" fix for SwiftUI over-rendering.
@Observable
@MainActor
final class QuickNoteScrollState {
    var offset: CGFloat = 0

    /// Distance (pts) the user scrolls before the top controls fully fade.
    /// Below it, opacity scales linearly; beyond it, the controls are hidden.
    static let fadeDistance: CGFloat = 36

    /// 1 at the top of the note, easing to 0 once scrolled past `fadeDistance`.
    var topControlsOpacity: Double {
        let clamped = min(max(offset, 0), Self.fadeDistance)
        return Double(1 - clamped / Self.fadeDistance)
    }
}

/// Vertical alpha mask that fades the editor's content to transparent near the
/// top edge. As text scrolls up it dissolves into the card instead of colliding
/// with the top chrome (note title, the n/total tracker, export menu, drag grip).
///
/// This masks the *text* to transparent rather than painting a colored cover
/// over it, so it reads correctly on every theme — solid surfaces, gradients,
/// and wallpapers alike, since whatever sits behind shows through the fade.
/// Fully transparent at the very top, fully opaque below `fadeHeight` (sized to
/// the editor's top inset so a note at rest keeps its first line crisp).
struct QuickNoteEditorTopFadeMask: View {
    let fadeHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.black.opacity(0), .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: fadeHeight)
            Rectangle().fill(Color.black)
        }
    }
}

/// In-note toggle for "append copied text automatically". Mirrors the same
/// `AppSettings` flag as the Settings row, so flipping it here or there is the
/// same switch — the ingest path reads `settings.quickNoteAutoPasteFromClipboard`
/// live. On reads as a filled tint pill (like the browse button); off is dimmed
/// and unfilled so the current state is obvious at a glance.
struct QuickNoteAutoAppendButton: View {
    @EnvironmentObject private var store: ClipboardStore
    let tint: Color

    var body: some View {
        let isOn = store.settings.quickNoteAutoPasteFromClipboard
        Button {
            store.settings.quickNoteAutoPasteFromClipboard.toggle()
        } label: {
            Image(systemName: "text.append")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint.opacity(isOn ? 0.9 : 0.4))
                .frame(width: 26, height: 26)
                .background(
                    Capsule(style: .continuous)
                        .fill(tint.opacity(isOn ? 0.14 : 0))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(tint.opacity(isOn ? 0.22 : 0.14), lineWidth: 0.8)
                )
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .help(isOn
            ? "Copied text is being appended to this note. Click to stop."
            : "Append copied text to this note automatically")
        .accessibilityLabel(Text(L10n.string("ui.auto.append.copied.text", default: "Auto append copied text")))
        .accessibilityValue(Text(isOn ? "On" : "Off"))
    }
}

/// Top drag handle + navigation arrows. Reads `scrollState.offset` so it — and
/// only it — re-renders as the user scrolls.
struct QuickNoteHeaderChrome: View {
    let scrollState: QuickNoteScrollState
    let style: QuickNoteStyle
    let navigationControlsStyle: QuickNoteNavigationControlsStyle
    let navigationState: QuickNoteNavigationState
    let onNavigate: (Int) -> Void
    let foregroundColor: Color

    var body: some View {
        QuickNoteDragHeader(
            style: style,
            navigationControlsStyle: navigationControlsStyle,
            navigationState: navigationState,
            onNavigate: onNavigate,
            controlsOpacity: scrollState.topControlsOpacity,
            foregroundColor: foregroundColor
        )
    }
}

/// Top-trailing chrome: the always-available notes-browser button plus the
/// export menu. Reads `scrollState.offset` so scrolling only re-renders this
/// overlay, not the note underneath it. The browse button stays visible at all
/// scroll positions (you should always be able to jump notes); only the export
/// menu fades as the user reads down.
struct QuickNoteExportChrome: View {
    let scrollState: QuickNoteScrollState
    let note: NoteItem?
    let tint: Color
    let browsePosition: Int
    let browseTotal: Int
    let onBrowse: () -> Void
    let vaultDestination: String?
    let hasVault: Bool
    let onChooseDestination: () -> Void

    var body: some View {
        // On narrow windows the full row used to grow leftward until the vault
        // pill sat on top of the nav arrows. Offer a compact variant (icon-only
        // pill) and reserve the arrows' top-left zone so the trailing chrome
        // physically cannot reach them.
        ViewThatFits(in: .horizontal) {
            chromeRow(compactVaultPill: false)
            chromeRow(compactVaultPill: true)
        }
        .padding(.top, 18)
        .padding(.trailing, 22)
        .padding(.leading, 96)
    }

    private func chromeRow(compactVaultPill: Bool) -> some View {
        let opacity = scrollState.topControlsOpacity
        return HStack(spacing: 8) {
            // Like the browse button, the vault destination pill stays solid at
            // every scroll offset — retargeting a note shouldn't require
            // scrolling back to the top first.
            QuickNoteVaultDestinationButton(
                destination: vaultDestination,
                hasVault: hasVault,
                tint: tint,
                iconOnly: compactVaultPill,
                action: onChooseDestination
            )
            QuickNoteBrowseButton(
                position: browsePosition,
                total: browseTotal,
                tint: tint,
                action: onBrowse
            )
            // Stays solid at every scroll offset like the browse button — you
            // should be able to flip auto-append on/off without scrolling up.
            QuickNoteAutoAppendButton(tint: tint)
            QuickNoteAIMenu(note: note, tint: tint)
                .opacity(opacity)
                .allowsHitTesting(opacity > 0.05)
                .animation(.easeOut(duration: 0.18), value: opacity)
            QuickNoteExportMenu(note: note, tint: tint)
                .opacity(opacity)
                // Don't let invisible chrome intercept clicks meant for the text below.
                .allowsHitTesting(opacity > 0.05)
                .animation(.easeOut(duration: 0.18), value: opacity)
        }
    }
}
