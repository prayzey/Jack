import SwiftUI

/// Floating dictation overlay with an adjustable width and fixed height.
/// Long transcripts follow the newest line inside the text area
/// while a control bar (level meter, status, finish, cancel) stays pinned
/// below. Processing keeps the same shell, and failures remain until dismissed.
struct DictationOverlayView: View {
    @ObservedObject var coordinator: DictationCoordinator
    @ObservedObject var store: DictationStore
    let onStop: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var displayPhase: DictationPhase { coordinator.phase }

    private var palette: DictationPillPalette { store.settings.pillTheme.palette }

    private var modeGlyphReserve: CGFloat {
        DictationCaptionLayout.modeGlyphReserve(for: coordinator.currentMode)
    }

    var body: some View {
        GeometryReader { geometry in
            let captionWidth = max(1, geometry.size.width - DictationCaptionLayout.shadowMargin * 2)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Group {
                    if case .failed(let reason) = displayPhase {
                        failureCard(reason: reason, width: captionWidth)
                    } else if displayPhase == .done {
                        doneCard(width: captionWidth)
                    } else {
                        sessionCard(width: captionWidth)
                    }
                }
                .transition(.opacity)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: displayPhase)
                .frame(width: captionWidth)
            }
            .padding(DictationCaptionLayout.shadowMargin)
            .frame(
                width: geometry.size.width,
                height: DictationCaptionLayout.maxHeight + DictationCaptionLayout.shadowMargin * 2,
                alignment: .bottom
            )
        }
        .overlay(alignment: .bottom) { resizeHandles }
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
        }
    }

    // MARK: - Session card

    // Keep the caption's identity through listening, transcription and cleanup.
    // Replacing it per phase resets its cursor and scroll position.
    private func sessionCard(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            DictationWritingCaptionView(
                transcript: coordinator.liveTranscript,
                stableWordCount: coordinator.liveTranscriptStableWordCount,
                level: isProcessingPhase(displayPhase) ? 0 : coordinator.level,
                palette: palette,
                frontierColor: captionFrontierColor,
                width: width,
                minHeight: DictationCaptionLayout.textAreaHeight,
                maxHeight: DictationCaptionLayout.textAreaHeight,
                fontSize: DictationCaptionLayout.fontSize,
                horizontalPadding: DictationCaptionLayout.horizontalPadding,
                verticalPadding: DictationCaptionLayout.verticalPadding,
                leadingContentInset: modeGlyphReserve
            )
            .overlay(alignment: .topLeading) {
                if coordinator.liveTranscript.isEmpty, !isProcessingPhase(displayPhase) {
                    Text(coordinator.isPreparing
                         ? L10n.string("dictation.overlay.preparing", default: "Starting microphone…")
                         : L10n.string("dictation.overlay.ready", default: "Speak when you're ready"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(palette.captionText.opacity(0.75))
                        .padding(.leading, 28 + modeGlyphReserve)
                        .padding(.top, DictationCaptionLayout.verticalPadding)
                }
            }
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
        .overlay(alignment: .trailing) {
            Capsule().fill(palette.captionText.opacity(0.28))
                .frame(width: 2, height: 14).padding(.trailing, 3)
                .allowsHitTesting(false)
        }
    }

    private var resizeHandles: some View {
        HStack(spacing: 0) {
            resizeHandle(.left)
            Spacer(minLength: 0)
            resizeHandle(.right)
        }
        .frame(height: DictationCaptionLayout.cardHeight)
        .padding(.bottom, DictationCaptionLayout.shadowMargin)
    }

    private func resizeHandle(_ edge: WindowResizeEdge) -> some View {
        let margin = DictationCaptionLayout.shadowMargin * 2
        return WindowFrameResizeHandle(
            edge: edge,
            minSize: CGSize(width: DictationCaptionLayout.minimumCaptionWidth + margin,
                            height: DictationCaptionLayout.sessionPanelSize.height),
            maxSize: CGSize(width: DictationCaptionLayout.maximumCaptionWidth + margin,
                            height: DictationCaptionLayout.sessionPanelSize.height),
            onResizeFinished: { frame in
                // The existing AppKit handle owns live movement; persist only on release.
                store.settings.captionWidth = Double(DictationCaptionLayout.clampedCaptionWidth(frame.width - margin))
            }
        )
        .frame(width: DictationCaptionLayout.shadowMargin)
        .help(L10n.string("dictation.caption.resize", default: "Drag to widen or narrow the caption"))
    }

    /// Recording feedback and explicit finish/cancel controls.
    private var controlBar: some View {
        HStack(spacing: 8) {
            cancelButton
            ZStack {
                if isProcessingPhase(displayPhase) {
                    ProgressView().controlSize(.small)
                } else {
                    DictationLevelMeter(level: coordinator.level, color: captionFrontierColor)
                }
            }
            .frame(width: 63, height: 16)
            .accessibilityHidden(true)
            Text(isProcessingPhase(displayPhase) ? processingLabel : recordingStatus)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.captionText.opacity(0.8))
                .contentTransition(.opacity)
            Spacer(minLength: 4)
            Button(action: onStop) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(palette.captionText)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(captionFrontierColor.opacity(0.3)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(finishLabel)
            .help(finishLabel)
            .opacity(isProcessingPhase(displayPhase) ? 0 : 1)
            .disabled(isProcessingPhase(displayPhase))
            .accessibilityHidden(isProcessingPhase(displayPhase))
        }
        .padding(.horizontal, 10)
        .frame(height: DictationCaptionLayout.controlBarHeight)
    }

    private var recordingStatus: String {
        if coordinator.isPreparing { return L10n.string("dictation.overlay.starting", default: "Starting…") }
        if coordinator.elapsedSeconds >= DictationAudioCaptureService.maximumDurationSeconds - 30 {
            return L10n.string("dictation.overlay.endingSoon", default: "Finishing soon")
        }
        return L10n.string("dictation.overlay.listening", default: "Listening")
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

    private var cancelButton: some View {
        Button { coordinator.cancelSession() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.captionText.opacity(0.85))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.string("dictation.overlay.cancel", default: "Cancel dictation"))
        .help(L10n.string("dictation.overlay.cancelHint", default: "Cancel dictation (Esc)"))
    }

    private func failureCard(reason: String, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("dictation.overlay.failed", default: "Dictation stopped"))
                .font(.system(size: 13, weight: .semibold))
            Text(reason)
                .font(.system(size: 12))
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
        .padding(14)
        .frame(width: width, alignment: .leading)
        .background(captionBackground)
        .shadow(color: shadowColor.opacity(0.5), radius: 10, y: 4)
    }

    // MARK: - Done card

    /// The after-state: same fixed shell, a quiet checkmark, and a short
    /// confirmation. Kept quiet on purpose — it flashes for under a second.
    private func doneCard(width: CGFloat) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(captionFrontierColor)

            VStack(alignment: .leading, spacing: 3) {
                Text(doneLabel)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.captionText.opacity(0.92))
                if coordinator.lastResultWasCopied {
                    Text(L10n.string("dictation.overlay.manualPaste", default: "Press ⌘V where you want the text."))
                        .font(.system(size: 11))
                        .foregroundStyle(palette.captionText.opacity(0.8))
                }
                if coordinator.polishWasSkipped {
                    Text(L10n.string("dictation.overlay.polishSkipped", default: "AI cleanup skipped; your transcript is preserved."))
                        .font(.system(size: 11))
                        .foregroundStyle(palette.captionText.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(
            width: width,
            height: DictationCaptionLayout.cardHeight
        )
        .background(captionBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(captionFrontierColor.opacity(0.45), lineWidth: captionBorderWidth)
        )
        .shadow(color: shadowColor.opacity(0.5), radius: 10, y: 4)
    }

    private var doneLabel: String {
        if isActionsMode {
            return coordinator.lastResult
                ?? L10n.string("dictation.overlay.doneAction", default: "Done")
        }
        return coordinator.lastResultWasCopied
            ? L10n.string("dictation.overlay.copied", default: "Copied — ready to paste")
            : L10n.string("dictation.overlay.pasteSent", default: "Paste sent")
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

}

// MARK: - Control bar pieces

/// Centered dot-row level meter (Handy-style): a fixed row of dots whose
/// height and brightness ripple outward from the middle with mic level.
struct DictationLevelMeter: View {
    let level: Double
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let dotCount = 11

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<dotCount, id: \.self) { index in
                Capsule()
                    .fill(color.opacity(opacity(for: index)))
                    .frame(width: 3, height: height(for: index))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: level)
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
