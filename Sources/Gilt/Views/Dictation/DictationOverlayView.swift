import AppKit
import SwiftUI

/// Floating dictation overlay with an adjustable width. The card hugs one
/// line while listening, grows to three, then follows the newest line, with
/// a control bar (cancel, level meter, status, finish) pinned below.
/// Processing keeps the same shell, finishing shrinks it into a small
/// confirmation pill, and failures remain until dismissed.
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
                    } else {
                        sessionCard(width: captionWidth)
                    }
                }
                // System controls (the failure card's buttons) follow the card's
                // theme, not the Mac's appearance, or light themes get white-on-white.
                .environment(\.colorScheme, palette.isDarkShell ? .dark : .light)
                .transition(.opacity)
                .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.82), value: displayPhase)
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

    // Keep the caption's identity through listening, transcription, cleanup
    // and the finish. Replacing it per phase resets its cursor and scroll
    // position, and swapping in a separate done card made the ending jump.
    private func sessionCard(width: CGFloat) -> some View {
        // Idle shares the collapsed shape so the card tucks away as the panel
        // fades out, and grows out of the same small pill on the next start.
        let collapsed = displayPhase == .done || displayPhase == .idle
        let pill = displayPhase == .done ? doneSize(maxWidth: width) : CGSize(width: 120, height: 36)
        let shape = RoundedRectangle(
            // A capsule while it holds one line; taller pills keep a softer 18pt corner.
            cornerRadius: collapsed ? min(pill.height / 2, 18) : DictationCaptionLayout.cornerRadius,
            style: .continuous
        )
        return VStack(spacing: 0) {
            DictationWritingCaptionView(
                transcript: coordinator.liveTranscript,
                stableWordCount: coordinator.liveTranscriptStableWordCount,
                level: isProcessingPhase(displayPhase) ? 0 : coordinator.level,
                palette: palette,
                frontierColor: captionFrontierColor,
                width: width,
                minHeight: DictationCaptionLayout.textAreaMinHeight,
                maxHeight: DictationCaptionLayout.textAreaMaxHeight,
                fontSize: DictationCaptionLayout.fontSize,
                horizontalPadding: DictationCaptionLayout.horizontalPadding,
                verticalPadding: DictationCaptionLayout.verticalPadding,
                leadingContentInset: modeGlyphReserve
            )
            controlBar
        }
        .frame(width: width)
        .overlay(alignment: .topLeading) { modeGlyph }
        .opacity(collapsed ? 0 : 1)
        .frame(width: collapsed ? pill.width : nil, height: collapsed ? pill.height : nil)
        .overlay {
            doneContent(size: pill)
                .opacity(displayPhase == .done ? 1 : 0)
        }
        .background(captionSurface(shape))
        .clipShape(shape)
        .overlay(shape.strokeBorder(captionBorderColor, lineWidth: captionBorderWidth))
        .shadow(color: shadowColor.opacity(0.5), radius: 12, y: 5)
    }

    private var resizeHandles: some View {
        HStack(spacing: 0) {
            resizeHandle(.left)
            Spacer(minLength: 0)
            resizeHandle(.right)
        }
        .padding(.horizontal, DictationCaptionLayout.shadowMargin - WindowResizeHandleMetrics.edgeThickness / 2)
        .frame(height: DictationCaptionLayout.minimumCardHeight)
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
        .frame(width: WindowResizeHandleMetrics.edgeThickness)
        .help(L10n.string("dictation.caption.resize", default: "Drag to widen or narrow the caption"))
    }

    /// Recording feedback and explicit finish/cancel controls. Both buttons
    /// are the same size and sit on the text's inset, so the card's edges line up.
    private var controlBar: some View {
        HStack(spacing: 10) {
            cancelButton
            // The spinner takes only its own width, so "Polishing…" sits right beside it.
            Group {
                if isProcessingPhase(displayPhase) {
                    ProgressView().controlSize(.small).scaleEffect(0.8).frame(width: 16, height: 16)
                } else {
                    DictationLevelMeter(level: coordinator.level, color: captionFrontierColor)
                        .frame(width: 63, height: 16)
                }
            }
            .accessibilityHidden(true)
            Text(isProcessingPhase(displayPhase) ? processingLabel : recordingStatus)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(palette.captionText.opacity(0.55))
                .contentTransition(.opacity)
            Spacer(minLength: 4)
            Button(action: onStop) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(surfaceColor)
                    .frame(width: DictationCaptionLayout.controlSize, height: DictationCaptionLayout.controlSize)
                    .background(Circle().fill(captionFrontierColor))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(finishLabel)
            .help(finishLabel)
            .opacity(isProcessingPhase(displayPhase) ? 0 : 1)
            .disabled(isProcessingPhase(displayPhase))
            .accessibilityHidden(isProcessingPhase(displayPhase))
        }
        .padding(.horizontal, DictationCaptionLayout.inset)
        .padding(.bottom, DictationCaptionLayout.inset)
        .frame(height: DictationCaptionLayout.controlBarHeight, alignment: .top)
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
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(palette.captionText.opacity(0.7))
                .frame(width: DictationCaptionLayout.controlSize, height: DictationCaptionLayout.controlSize)
                .background(Circle().fill(palette.captionText.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.string("dictation.overlay.cancel", default: "Cancel dictation"))
        .help(L10n.string("dictation.overlay.cancelHint", default: "Cancel dictation (Esc)"))
    }

    private func failureCard(reason: String, width: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: DictationCaptionLayout.cornerRadius, style: .continuous)
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
        .background(captionSurface(shape))
        .overlay(shape.strokeBorder(palette.captionBorder, lineWidth: 0.8))
        .shadow(color: shadowColor.opacity(0.5), radius: 12, y: 5)
    }

    // MARK: - Done pill

    /// The after-state: the session card shrinks into a small pill with a
    /// check and one short word. Kept quiet on purpose; it shows for about a second.
    private func doneContent(size: CGSize) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 8.5, weight: .heavy))
                .foregroundStyle(surfaceColor)
                .frame(width: 18, height: 18)
                .background(Circle().fill(captionFrontierColor))
            VStack(alignment: .leading, spacing: 1) {
                Text(doneLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.captionText)
                ForEach(doneDetails, id: \.self) { detail in
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.captionText.opacity(0.6))
                }
            }
            .lineLimit(1)
        }
        .padding(.leading, 9)
        .padding(.trailing, 14)
        .frame(width: size.width, height: size.height, alignment: .leading)
    }

    /// Lines under the done title: how to paste a copied result, and whether cleanup was skipped.
    private var doneDetails: [String] {
        var details: [String] = []
        if coordinator.lastResultWasCopied {
            details.append(L10n.string("dictation.overlay.manualPaste", default: "Press ⌘V to paste"))
        }
        if coordinator.polishWasSkipped {
            details.append(L10n.string("dictation.overlay.polishSkipped", default: "AI cleanup skipped"))
        }
        return details
    }

    /// The pill animates between explicit sizes, so it measures its own text
    /// with the same system fonts the labels render in.
    private func doneSize(maxWidth: CGFloat) -> CGSize {
        let titleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let detailFont = NSFont.systemFont(ofSize: 11)
        let widths = [(doneLabel as NSString).size(withAttributes: [.font: titleFont]).width]
            + doneDetails.map { ($0 as NSString).size(withAttributes: [.font: detailFont]).width }
        let width = 9 + 18 + 8 + ceil(widths.max() ?? 0) + 2 + 14
        return CGSize(width: min(maxWidth, width), height: 36 + CGFloat(doneDetails.count) * 14)
    }

    private var doneLabel: String {
        if isActionsMode {
            return coordinator.lastResult
                ?? L10n.string("dictation.overlay.doneAction", default: "Done")
        }
        return coordinator.lastResultWasCopied
            ? L10n.string("dictation.overlay.copied", default: "Copied")
            : L10n.string("dictation.overlay.pasteSent", default: "Pasted")
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

    /// Dot, meter and buttons use the caption's own text color, so every theme
    /// stays black and white. Ask and Actions keep their mode colors.
    private var captionFrontierColor: Color {
        if isAskMode { return askAuraColor }
        if isActionsMode { return actionsAuraColor }
        return palette.captionText
    }

    /// Icon color on filled buttons: the card's own surface.
    private var surfaceColor: Color {
        palette.isDarkShell ? .black : .white
    }

    private func captionSurface(_ shape: RoundedRectangle) -> some View {
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

    private var captionBorderColor: Color {
        if isAskMode || isActionsMode { return modeBorderColor }
        return palette.captionBorder
    }

    private var captionBorderWidth: CGFloat {
        (isAskMode || isActionsMode) ? 1.2 : 0.8
    }

    @ViewBuilder
    private var modeGlyph: some View {
        if showAskGlyph || showActionsGlyph {
            Image(systemName: showAskGlyph ? "eye.fill" : "checklist")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle((showAskGlyph ? askGlyphColor : actionsGlyphColor).opacity(isProcessingPhase(displayPhase) ? 0.7 : 1))
                .frame(height: DictationCaptionLayout.lineHeight)
                .padding(.top, DictationCaptionLayout.verticalPadding)
                .padding(.leading, DictationCaptionLayout.inset)
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
