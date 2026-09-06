import SwiftUI

/// Floating dictation overlay — a fixed-shape card (Handy-style): the box
/// never grows or moves; long transcripts scroll up inside the text area
/// while a control bar (record dot, level meter, timer, cancel) stays pinned
/// below. Post-release processing keeps the same shell; a short "Pasted"
/// beat closes the session.
struct DictationOverlayView: View {
    @ObservedObject var coordinator: DictationCoordinator
    @ObservedObject var store: DictationStore
    let onStop: () -> Void

    @State private var displayPhase: DictationPhase = .idle
    @State private var frozenTranscript: String = ""
    @State private var doneAppeared = false

    private var palette: DictationPillPalette { store.settings.pillTheme.palette }

    private var activeTranscript: String {
        if isProcessingPhase(displayPhase) {
            // Prefer the live text: during Polish the coordinator streams
            // Qwen's rewrite into `liveTranscript`, which is the visible
            // "text healing itself" moment. The frozen copy is only the
            // fallback for phases that publish nothing.
            let live = coordinator.liveTranscript
            return live.isEmpty ? frozenTranscript : live
        }
        return coordinator.liveTranscript
    }

    private var modeGlyphReserve: CGFloat {
        DictationCaptionLayout.modeGlyphReserve(for: coordinator.currentMode)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Group {
                if displayPhase == .done {
                    doneCard
                } else if isProcessingPhase(displayPhase) {
                    processingCard
                } else {
                    listeningCard
                }
            }
            .frame(width: DictationCaptionLayout.captionWidth)
        }
        .padding(DictationCaptionLayout.shadowMargin)
        .frame(
            width: DictationCaptionLayout.captionWidth + DictationCaptionLayout.shadowMargin * 2,
            height: DictationCaptionLayout.maxHeight + DictationCaptionLayout.shadowMargin * 2,
            alignment: .bottom
        )
        .onAppear {
            displayPhase = coordinator.phase
            syncFrozenTranscript(for: coordinator.phase)
        }
        .onChange(of: coordinator.phase) { _, newPhase in
            syncFrozenTranscript(for: newPhase)
            if newPhase == .done {
                doneAppeared = false
            }
            displayPhase = newPhase
        }
    }

    // MARK: - Listening card

    private var listeningCard: some View {
        VStack(spacing: 0) {
            DictationWritingCaptionView(
                transcript: coordinator.liveTranscript,
                stableWordCount: coordinator.liveTranscriptStableWordCount,
                level: 0.42,
                palette: palette,
                frontierColor: captionFrontierColor,
                width: DictationCaptionLayout.captionWidth,
                minHeight: DictationCaptionLayout.textAreaHeight,
                maxHeight: DictationCaptionLayout.textAreaHeight,
                fontSize: DictationCaptionLayout.fontSize,
                horizontalPadding: DictationCaptionLayout.horizontalPadding,
                verticalPadding: DictationCaptionLayout.verticalPadding,
                leadingContentInset: modeGlyphReserve
            )
            controlBar
        }
        .background(captionBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(captionBorderColor, lineWidth: captionBorderWidth)
        )
        .shadow(color: shadowColor.opacity(0.55), radius: 10, y: 4)
        .overlay(alignment: .topLeading) {
            modeGlyph
        }
    }

    /// Pinned bar: centered level meter, one button that finishes the
    /// dictation (stop → transcribe → paste). Escape cancels and discards.
    private var controlBar: some View {
        ZStack {
            DictationLevelMeter(level: coordinator.level, color: captionFrontierColor)

            HStack {
                Spacer()
                Button(action: onStop) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(palette.captionText.opacity(0.9))
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(captionFrontierColor.opacity(0.35)))
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
                .help(L10n.string("dictation.overlay.stop", default: "Finish and paste"))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: DictationCaptionLayout.controlBarHeight)
    }

    // MARK: - Processing card

    private var processingCard: some View {
        DictationProcessingCaptionView(
            transcript: activeTranscript,
            statusLabel: processingLabel,
            palette: palette,
            frontierColor: captionFrontierColor,
            width: DictationCaptionLayout.captionWidth,
            minHeight: DictationCaptionLayout.cardHeight,
            maxHeight: DictationCaptionLayout.cardHeight,
            fontSize: DictationCaptionLayout.fontSize,
            horizontalPadding: DictationCaptionLayout.horizontalPadding,
            verticalPadding: DictationCaptionLayout.verticalPadding,
            leadingContentInset: modeGlyphReserve,
            emphasizesPaste: displayPhase == .pasting
        )
        .background(captionBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(captionBorderColor.opacity(0.85), lineWidth: captionBorderWidth)
        )
        .shadow(color: shadowColor.opacity(0.5), radius: 10, y: 4)
        .overlay(alignment: .topLeading) {
            modeGlyph
        }
    }

    // MARK: - Done card

    /// The after-state: same fixed shell, a spring-in checkmark, and a one-word
    /// confirmation. Kept quiet on purpose — it flashes for under a second.
    private var doneCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(captionFrontierColor)
                .scaleEffect(doneAppeared ? 1 : 0.4)

            Text(doneLabel)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.captionText.opacity(0.92))
        }
        .frame(
            width: DictationCaptionLayout.captionWidth,
            height: DictationCaptionLayout.cardHeight
        )
        .background(captionBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(captionFrontierColor.opacity(0.45), lineWidth: captionBorderWidth)
        )
        .shadow(color: shadowColor.opacity(0.5), radius: 10, y: 4)
        .opacity(doneAppeared ? 1 : 0.6)
        .onAppear {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.62)) {
                doneAppeared = true
            }
        }
    }

    private var doneLabel: String {
        if isActionsMode {
            return coordinator.lastResult
                ?? L10n.string("dictation.overlay.doneAction", default: "Done")
        }
        return L10n.string("dictation.overlay.pasted", default: "Pasted")
    }

    private var processingLabel: String {
        switch displayPhase {
        case .transcribing:
            return L10n.string("dictation.overlay.transcribing", default: "Transcribing…")
        case .rewriting:
            return L10n.string("dictation.overlay.polishing", default: "Polishing…")
        case .executing:
            return L10n.string("dictation.overlay.running", default: "Running…")
        case .pasting:
            return L10n.string("dictation.overlay.pasting", default: "Pasting…")
        default:
            return L10n.string("dictation.overlay.transcribing", default: "Transcribing…")
        }
    }

    // MARK: - Shared chrome

    private var captionFrontierColor: Color {
        if isAskMode { return askAuraColor }
        if isActionsMode { return actionsAuraColor }
        if palette.auraColor != .clear { return palette.auraColor }
        return Color(red: 0.38, green: 0.56, blue: 0.96)
    }

    private var captionBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [palette.captionTop, palette.captionBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }

    private var captionBorderColor: Color {
        if isAskMode || isActionsMode { return modeBorderColor }
        return palette.captionBorder
    }

    private var captionBorderWidth: CGFloat {
        (isAskMode || isActionsMode) ? 1.2 : 0.8
    }

    @ViewBuilder
    private var modeGlyph: some View {
        if showAskGlyph {
            Image(systemName: "eye.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(askGlyphColor.opacity(isProcessingPhase(displayPhase) ? 0.7 : 1))
                .padding(.top, DictationCaptionLayout.modeGlyphInset)
                .padding(.leading, DictationCaptionLayout.modeGlyphInset)
        } else if showActionsGlyph {
            Image(systemName: "checklist")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(actionsGlyphColor.opacity(isProcessingPhase(displayPhase) ? 0.7 : 1))
                .padding(.top, DictationCaptionLayout.modeGlyphInset)
                .padding(.leading, DictationCaptionLayout.modeGlyphInset)
        }
    }

    // MARK: - Mode visuals

    private var isAskMode: Bool {
        coordinator.currentMode == .askScreen
    }

    private var isActionsMode: Bool {
        coordinator.currentMode == .actions
    }

    private var showAskGlyph: Bool { isAskMode }
    private var showActionsGlyph: Bool { isActionsMode }

    private var askAuraColor: Color {
        Color(red: 0.28, green: 0.78, blue: 0.92)
    }

    private var askGlyphColor: Color {
        Color(red: 0.78, green: 0.94, blue: 1.0)
    }

    private var actionsAuraColor: Color {
        Color(red: 0.28, green: 0.72, blue: 0.46)
    }

    private var actionsGlyphColor: Color {
        Color(red: 0.82, green: 0.98, blue: 0.88)
    }

    private var modeBorderColor: Color {
        if isAskMode {
            return Color(red: 0.45, green: 0.86, blue: 0.98).opacity(0.55)
        }
        return Color(red: 0.42, green: 0.86, blue: 0.58).opacity(0.55)
    }

    private var shadowColor: Color {
        if isAskMode {
            return Color(red: 0.20, green: 0.55, blue: 0.75).opacity(0.45)
        }
        if isActionsMode {
            return Color(red: 0.22, green: 0.62, blue: 0.38).opacity(0.42)
        }
        return palette.pillShadow
    }

    // MARK: - Phase helpers

    private func isProcessingPhase(_ phase: DictationPhase) -> Bool {
        switch phase {
        case .transcribing, .rewriting, .executing, .pasting:
            return true
        default:
            return false
        }
    }

    private func syncFrozenTranscript(for phase: DictationPhase) {
        if case .listening = phase {
            frozenTranscript = ""
            return
        }
        if isProcessingPhase(phase), frozenTranscript.isEmpty {
            let live = coordinator.liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !live.isEmpty {
                frozenTranscript = coordinator.liveTranscript
            }
        }
        if case .idle = phase {
            frozenTranscript = ""
        }
    }
}

// MARK: - Control bar pieces

/// Centered dot-row level meter (Handy-style): a fixed row of dots whose
/// height and brightness ripple outward from the middle with mic level.
struct DictationLevelMeter: View {
    let level: Double
    let color: Color

    private let dotCount = 11

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<dotCount, id: \.self) { index in
                Capsule()
                    .fill(color.opacity(opacity(for: index)))
                    .frame(width: 3, height: height(for: index))
            }
        }
        .animation(.easeOut(duration: 0.12), value: level)
        .frame(height: 14, alignment: .center)
    }

    /// Dots near the center respond first; the falloff makes low levels read
    /// as a small centered flicker and loud speech as a full-width ripple.
    private func responsiveness(for index: Int) -> Double {
        let mid = Double(dotCount - 1) / 2
        let distance = abs(Double(index) - mid) / mid
        return max(0, 1 - distance * 0.85)
    }

    private func height(for index: Int) -> CGFloat {
        let boosted = min(1, level * 1.6) * responsiveness(for: index)
        return 3 + CGFloat(boosted) * 11
    }

    private func opacity(for index: Int) -> Double {
        0.28 + min(1, level * 1.6) * responsiveness(for: index) * 0.62
    }
}