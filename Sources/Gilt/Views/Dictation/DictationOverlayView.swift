import AppKit
import SwiftUI

/// Jack's floating dictation pill, after a halogen timer: a capsule with a
/// round dot grid and one line of words. It starts as a small circle,
/// stretches with your words, and shrinks to a check and one word when the
/// text lands. Cancel and finish show only while the pointer is over it; the
/// shortcut and Esc work without them. Failures show a card until dismissed.
struct DictationOverlayView: View {
    @ObservedObject var coordinator: DictationCoordinator
    @ObservedObject var store: DictationStore
    let onStop: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    /// Paces the words and springs the width, frame by frame. A class so updating it never re-renders the view.
    @State private var motion = DictationPillMotion()

    private var phase: DictationPhase { coordinator.phase }
    private var palette: DictationPillPalette { store.settings.pillTheme.palette }
    private var words: [String] {
        coordinator.liveTranscript.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    var body: some View {
        GeometryReader { geometry in
            let maxWidth = max(
                DictationCaptionLayout.pillHeight,
                geometry.size.width - DictationCaptionLayout.shadowMargin * 2
            )
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Group {
                    if case .failed(let reason) = phase {
                        failureCard(reason: reason, width: maxWidth)
                    } else {
                        pill(maxWidth: maxWidth)
                    }
                }
                // System controls (the failure card's buttons) follow the pill's
                // theme, not the Mac's appearance, or light themes get white-on-white.
                .environment(\.colorScheme, palette.isDarkShell ? .dark : .light)
                .transition(.opacity)
                .frame(width: maxWidth)
            }
            .padding(DictationCaptionLayout.shadowMargin)
            .frame(
                width: geometry.size.width,
                height: DictationCaptionLayout.maxHeight + DictationCaptionLayout.shadowMargin * 2,
                alignment: .bottom
            )
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isFailed)
        .contextMenu {
            Button(L10n.string("dictation.caption.wider", default: "Widen caption")) {
                store.settings.captionWidth = Double(DictationCaptionLayout.clampedCaptionWidth(store.settings.captionWidth + 80))
            }
            Button(L10n.string("dictation.caption.narrower", default: "Narrow caption")) {
                store.settings.captionWidth = Double(DictationCaptionLayout.clampedCaptionWidth(store.settings.captionWidth - 80))
            }
            Button(L10n.string("dictation.caption.resetWidth", default: "Reset caption width")) {
                store.settings.captionWidth = Double(DictationCaptionLayout.captionWidth)
            }
            Button(L10n.string("dictation.caption.resetPosition", default: "Move back to center")) {
                store.settings.captionOffsetX = 0
                store.settings.captionOffsetY = 0
            }
            .disabled(store.settings.captionOffsetX == 0 && store.settings.captionOffsetY == 0)
        }
    }

    // MARK: - Pill

    // One view for the whole session, so the words, the grid and the width
    // carry through listening, polishing and the finish without a swap.
    private func pill(maxWidth: CGFloat) -> some View {
        TimelineView(.animation(paused: phase == .idle || isFailed)) { timeline in
            let lineWidth = DictationCaptionLayout.lineWidth(of: words)
            let showsControls = isHovering && phase == .listening
            let _ = motion.advance(
                to: timeline.date,
                revealTarget: words.isEmpty ? 0 : lineWidth + DictationCaptionRibbon.inkEdge,
                hurry: isWorking,
                reduceMotion: reduceMotion
            ) { revealed in
                DictationCaptionLayout.pillWidth(
                    pillContent(maxWidth: maxWidth, shownTextWidth: min(lineWidth, revealed)),
                    maxWidth: maxWidth,
                    showsControls: showsControls
                )
            }
            pillBody(maxWidth: maxWidth, showsControls: showsControls)
        }
    }

    private func pillBody(maxWidth: CGFloat, showsControls: Bool) -> some View {
        let isDone = phase == .done
        // Words scroll against the width the pill is heading to, so text never
        // shifts while the pill is still opening; the opening edge only clips the soft fade.
        let viewport = DictationCaptionLayout.textViewport(pillWidth: motion.targetWidth, showsControls: showsControls)
        return ZStack(alignment: .leading) {
            DictationCaptionRibbon(
                words: words,
                stableWordCount: coordinator.liveTranscriptStableWordCount,
                color: palette.captionText,
                viewportWidth: viewport,
                revealedWidth: motion.revealed,
                isWorking: isWorking
            )
            .padding(.leading, DictationCaptionLayout.textLeading)
            .animation(.easeOut(duration: 0.2)) { $0.opacity(isDone ? 0 : 1) }

            doneLabel(width: doneLabelWidth(maxWidth: maxWidth))
                .padding(.leading, DictationCaptionLayout.textLeading)
                .animation(.easeOut(duration: 0.2)) { $0.opacity(isDone && showsDoneLabel ? 1 : 0) }

            DictationDotGrid(
                mode: gridMode,
                level: coordinator.level,
                color: accentColor,
                dimOpacity: palette.isDarkShell ? 0.16 : 0.12
            )
            .padding(.leading, DictationCaptionLayout.gridInset)

            controls
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, DictationCaptionLayout.gridInset)
                .animation(.easeOut(duration: 0.16)) { $0.opacity(showsControls ? 1 : 0) }
                .allowsHitTesting(showsControls)
        }
        .frame(width: motion.width, height: DictationCaptionLayout.pillHeight, alignment: .leading)
        .background(surface(Capsule()))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(borderStyle, lineWidth: 0.5))
        // Hover shows the buttons; press and drag anywhere else moves the pill.
        .background(PanelPointerArea { isHovering = $0 })
        .shadow(color: shadowColor, radius: 16, y: 6)
        // Grows out of a small dot when a session starts and tucks back in as the panel fades.
        .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.68)) {
            $0.scaleEffect(phase == .idle ? 0.6 : 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(statusLabel)
    }

    private func pillContent(maxWidth: CGFloat, shownTextWidth: CGFloat) -> DictationCaptionLayout.PillContent {
        switch phase {
        // A copied result is the check alone: a small circle, no words.
        case .done: return showsDoneLabel ? .label(doneLabelWidth(maxWidth: maxWidth)) : .empty
        case .idle, .failed: return .empty
        default: return words.isEmpty ? .empty : .text(shownTextWidth)
        }
    }

    private var gridMode: DictationDotGrid.Mode {
        switch phase {
        case .idle, .failed: return .off
        // React to the voice from the first sound, before any words come back.
        case .listening: return coordinator.isPreparing ? .waiting : .speaking
        case .transcribing, .rewriting, .executing, .pasting: return .working
        case .done: return .done
        }
    }

    private var isWorking: Bool { gridMode == .working }
    private var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }

    private var controls: some View {
        HStack(spacing: 4) {
            Button { coordinator.cancelSession() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.captionText.opacity(0.75))
                    .frame(width: DictationCaptionLayout.controlSize, height: DictationCaptionLayout.controlSize)
                    .background(Circle().fill(palette.captionText.opacity(0.1)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("dictation.overlay.cancel", default: "Cancel dictation"))
            .help(L10n.string("dictation.overlay.cancelHint", default: "Cancel dictation (Esc)"))

            Button(action: onStop) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(surfaceColor)
                    .frame(width: DictationCaptionLayout.controlSize, height: DictationCaptionLayout.controlSize)
                    .background(Circle().fill(accentColor))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(finishLabel)
            .help(finishLabel)
        }
    }

    // MARK: - Finish

    /// One word when the text lands.
    private func doneLabel(width: CGFloat) -> some View {
        Text(doneTitle)
            .font(.system(size: DictationCaptionLayout.fontSize, weight: .semibold))
            .foregroundStyle(palette.captionText)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: width, alignment: .leading)
    }

    private var doneTitle: String {
        if isActionsMode {
            return coordinator.lastResult
                ?? L10n.string("dictation.overlay.doneAction", default: "Done")
        }
        return coordinator.lastResultWasCopied
            ? L10n.string("dictation.overlay.copied", default: "Copied")
            : L10n.string("dictation.overlay.pasteSent", default: "Pasted")
    }

    /// Pasted text and voice actions name their result; a copied result shows only the check.
    private var showsDoneLabel: Bool { isActionsMode || !coordinator.lastResultWasCopied }

    /// The pill springs between explicit widths, so the label measures itself
    /// with the same system font it renders in.
    private func doneLabelWidth(maxWidth: CGFloat) -> CGFloat {
        let title = (doneTitle as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: DictationCaptionLayout.fontSize, weight: .semibold),
        ]).width
        let room = maxWidth - DictationCaptionLayout.textLeading - DictationCaptionLayout.textTrailing
        return min(room, ceil(title) + 1)
    }

    // MARK: - Labels

    private var statusLabel: String {
        switch phase {
        case .listening:
            if coordinator.isPreparing { return L10n.string("dictation.overlay.starting", default: "Starting…") }
            if coordinator.elapsedSeconds >= DictationAudioCaptureService.maximumDurationSeconds - 30 {
                return L10n.string("dictation.overlay.endingSoon", default: "Finishing soon")
            }
            return L10n.string("dictation.overlay.listening", default: "Listening")
        case .transcribing: return L10n.string("dictation.overlay.transcribing", default: "Transcribing…")
        case .rewriting: return L10n.string("dictation.overlay.polishing", default: "Polishing…")
        case .executing: return L10n.string("dictation.overlay.running", default: "Running…")
        case .pasting: return L10n.string("dictation.overlay.pasting", default: "Pasting…")
        case .done: return doneTitle
        case .idle, .failed: return ""
        }
    }

    private var finishLabel: String {
        switch coordinator.currentMode {
        case .actions: return L10n.string("dictation.overlay.finishAction", default: "Run command")
        case .askScreen: return L10n.string("dictation.overlay.finishQuestion", default: "Get answer")
        case .compose: return L10n.string("dictation.overlay.finishCompose", default: "Insert text")
        case .polish:
            return store.settings.autoPasteIntoActiveApp
                ? L10n.string("dictation.overlay.stop", default: "Finish and paste")
                : L10n.string("dictation.overlay.finishCopy", default: "Finish and copy")
        }
    }

    // MARK: - Failure card

    private func failureCard(reason: String, width: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: DictationCaptionLayout.cardCornerRadius, style: .continuous)
        return VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("dictation.overlay.failed", default: "Dictation stopped"))
                .font(.system(size: 13, weight: .semibold))
            Text(reason)
                .font(.system(size: 12))
                .foregroundStyle(palette.captionText.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                if !coordinator.liveTranscript.isEmpty {
                    Button(L10n.string("dictation.overlay.copyDraft", default: "Copy draft")) {
                        DictationPasteService().copyOnly(coordinator.liveTranscript, saveToHistory: store.settings.saveToClipboardHistory)
                        coordinator.cancelSession()
                    }
                }
                Button(L10n.string("dictation.overlay.settings", default: "Settings…")) {
                    coordinator.cancelSession()
                    SettingsNavigation.openSettings(tabRawValue: SettingsTab.dictate.rawValue)
                }
                Spacer(minLength: 0)
                Button(L10n.string("dictation.overlay.dismiss", default: "Dismiss")) {
                    coordinator.cancelSession()
                }
            }
            .controlSize(.small)
        }
        .foregroundStyle(palette.captionText.opacity(0.95))
        .padding(16)
        .frame(width: width, alignment: .leading)
        .background(surface(shape))
        .overlay(shape.strokeBorder(palette.captionBorder, lineWidth: 0.5))
        .shadow(color: shadowColor, radius: 16, y: 6)
    }

    // MARK: - Colors

    /// Dots and the finish button use the pill's own text color, so every theme
    /// stays black and white. Ask and Actions keep their mode colors.
    private var accentColor: Color {
        switch coordinator.currentMode {
        case .askScreen: return Color(red: 0.28, green: 0.78, blue: 0.92)
        case .actions: return Color(red: 0.28, green: 0.72, blue: 0.46)
        default: return palette.captionText
        }
    }

    private var isActionsMode: Bool { coordinator.currentMode == .actions }

    /// Icon color on filled buttons: the pill's own surface.
    private var surfaceColor: Color {
        palette.isDarkShell ? .black : .white
    }

    private func surface<S: Shape>(_ shape: S) -> some View {
        // Theme fills are slightly translucent. An opaque base underneath
        // keeps the app behind the panel from showing through the words.
        shape.fill(surfaceColor)
            .overlay(
                shape.fill(
                    LinearGradient(
                        colors: [palette.captionTop, palette.captionBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            )
    }

    private var borderColor: Color {
        switch coordinator.currentMode {
        case .askScreen: return Color(red: 0.45, green: 0.86, blue: 0.98).opacity(0.55)
        case .actions: return Color(red: 0.42, green: 0.86, blue: 0.58).opacity(0.55)
        default: return palette.captionBorder
        }
    }

    /// Dark pills get a faintly lit top edge for depth; light pills keep a plain hairline.
    private var borderStyle: AnyShapeStyle {
        guard palette.isDarkShell, coordinator.currentMode != .askScreen, coordinator.currentMode != .actions else {
            return AnyShapeStyle(borderColor)
        }
        return AnyShapeStyle(LinearGradient(
            colors: [palette.captionText.opacity(0.2), palette.captionText.opacity(0.05)],
            startPoint: .top,
            endPoint: .bottom
        ))
    }

    private var shadowColor: Color {
        palette.isDarkShell ? .black.opacity(0.45) : .black.opacity(0.16)
    }
}
