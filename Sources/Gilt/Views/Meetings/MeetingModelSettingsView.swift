import SwiftUI

/// Local model management sheet. Workspace aesthetic — gold eyebrow + title,
/// hairline-divided rows, gold pill for actions. No purple chrome.
struct MeetingModelSettingsView: View {
    @ObservedObject var meetingStore: MeetingStore
    @ObservedObject var modelManager: MeetingModelManager
    let accent: Color
    @EnvironmentObject private var clipboardStore: ClipboardStore
    @ObservedObject private var ai = OnDeviceAIService.shared
    @Environment(\.dismiss) private var dismiss

    /// The engine that will actually write the next recap, resolved the same way
    /// MeetingSummarizationService resolves it. The radio reflects reality, not
    /// just the stored preference — if Apple Intelligence can't run, Qwen shows
    /// as selected even when the user previously preferred Apple.
    private var summarizationChoice: MeetingSummarizationChoice {
        MeetingSummarizationChoice.effective(
            preferApple: clipboardStore.settings.aiMeetingPreferAppleModel,
            appleUsable: ai.status.isUsable
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 14)

            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sectionHeader(
                        title: "Transcription",
                        subtitle: "Speech-to-text models. Pick one per language."
                    )
                    ForEach(MeetingTranscriptionEngine.meetingEngines) { engine in
                        transcriptionRow(engine)
                    }

                    sectionHeader(
                        title: "Summarization & Q&A",
                        subtitle: "Choose which model writes recaps, action items, and Ask answers."
                    )
                    appleIntelligenceRow
                    summaryRow

                    privacyFootnote
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                        .padding(.bottom, 24)
                }
            }
            .scrollIndicators(.hidden)

            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
            footer
        }
        .background(Color(white: 0.08))
        .onAppear { ai.refreshStatus() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.string("ui.models", default: "MODELS"))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(2.4)
                .foregroundStyle(accent.opacity(0.85))
            Text(L10n.string("ui.local.meeting.models", default: "Local meeting models"))
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .tracking(-0.3)
            Text(L10n.string("ui.all.downloads.stay.on.this.mac", default: "All downloads stay on this Mac."))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.55))
        }
        // Match the left edge of the rows below. Without an explicit
        // full-width frame the VStack hugs its text and the parent VStack
        // (default .center) floats the whole header to the middle.
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Sections

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(2.0)
                .foregroundStyle(.white.opacity(0.45))
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 8)
    }

    private func transcriptionRow(_ engine: MeetingTranscriptionEngine) -> some View {
        let state = modelManager.transcriptionState(for: engine)
        return modelRow(
            title: engine.displayName,
            subtitle: subtitleFor(engine),
            sizeBytes: engine.approximateDownloadSizeBytes,
            state: state,
            onDownload: { Task { await modelManager.downloadTranscriptionModel(engine) } },
            onDelete: { modelManager.deleteModel(engine) }
        )
    }

    /// Apple Intelligence as a selectable summarization engine. No download or
    /// delete — it ships with macOS — so the row is a pure radio choice.
    private var appleIntelligenceRow: some View {
        let usable = ai.status.isUsable
        let selected = summarizationChoice == .appleIntelligence
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                radioIndicator(selected: selected)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(L10n.string("ui.apple.intelligence", default: "Apple Intelligence"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                        availabilityBadge(usable: usable)
                    }
                    Text(L10n.string("ui.built.in.no.download.runs.privately.on.this.mac", default: "Built in · no download · runs privately on this Mac"))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer(minLength: 12)
            }

            if !usable {
                Text(ai.status.title)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.leading, 28)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
        }
        .opacity(usable ? 1 : 0.55)
        .contentShape(Rectangle())
        .onTapGesture {
            guard usable else { return }
            clipboardStore.settings.aiMeetingPreferAppleModel = true
        }
    }

    private var summaryRow: some View {
        let state = modelManager.summarizationState
        let selected = summarizationChoice == .localQwen
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                radioIndicator(selected: selected)
                    .padding(.top, 14)
                modelRow(
                    title: MeetingSummarizationEngine.qwen35_4b_q4.displayName,
                    subtitle: "Q4 quantized · ~2.4 GB · powers recap + Ask",
                    sizeBytes: MeetingSummarizationEngine.qwen35_4b_q4.approximateDownloadSizeBytes,
                    state: state,
                    leadingPadding: 0,
                    showsDivider: false,
                    onDownload: { Task { await modelManager.downloadSummarizationModel() } },
                    onDelete: { modelManager.deleteSummaryModel() }
                )
            }
            .padding(.leading, 24)

            if selected, state != .ready {
                Text(L10n.string("ui.not.downloaded.yet.recaps.use.basic..0928c5", default: "Not downloaded yet. Recaps use basic notes until this model is installed."))
                    .font(.system(size: 11))
                    .foregroundStyle(accent.opacity(0.85))
                    .padding(.leading, 52)
                    .padding(.trailing, 24)
                    .padding(.bottom, 12)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
        }
        // Inner Download/Delete buttons keep their own gestures; the tap gesture
        // only fires on the rest of the row, so selecting never triggers a download.
        .contentShape(Rectangle())
        .onTapGesture {
            clipboardStore.settings.aiMeetingPreferAppleModel = false
        }
    }

    private func radioIndicator(selected: Bool) -> some View {
        ZStack {
            Circle()
                .strokeBorder(selected ? accent : Color.white.opacity(0.25), lineWidth: 1.5)
                .frame(width: 16, height: 16)
            if selected {
                Circle()
                    .fill(accent)
                    .frame(width: 8, height: 8)
            }
        }
    }

    private func availabilityBadge(usable: Bool) -> some View {
        let (label, color): (String, Color) = usable
            ? ("READY", Color(red: 0.30, green: 0.78, blue: 0.55))
            : ("UNAVAILABLE", Color.white.opacity(0.30))
        return HStack(spacing: 5) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.65))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.white.opacity(0.05)))
    }

    private func modelRow(
        title: String,
        subtitle: String,
        sizeBytes: Int64,
        state: MeetingModelDownloadState,
        leadingPadding: CGFloat = 24,
        showsDivider: Bool = true,
        onDownload: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                        stateBadge(state)
                    }
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer(minLength: 12)
                actionButton(state: state, onDownload: onDownload, onDelete: onDelete)
            }

            if case .downloading(let progress, let received) = state {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(accent)
                    HStack {
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))
                        Spacer()
                        Text("\(MeetingFormatters.byteCount(received)) / \(MeetingFormatters.byteCount(sizeBytes))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }

            if case .failed(let reason) = state {
                Text(reason)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.93, green: 0.38, blue: 0.48).opacity(0.85))
            }
        }
        .padding(.leading, leadingPadding)
        .padding(.trailing, 24)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
            }
        }
    }

    private func stateBadge(_ state: MeetingModelDownloadState) -> some View {
        let (label, color): (String, Color) = {
            switch state {
            case .ready: return ("READY", Color(red: 0.30, green: 0.78, blue: 0.55))
            case .missing: return ("NOT INSTALLED", Color.white.opacity(0.30))
            case .downloading: return ("DOWNLOADING", accent)
            case .failed: return ("FAILED", Color(red: 0.93, green: 0.38, blue: 0.48))
            }
        }()
        return HStack(spacing: 5) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.65))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.white.opacity(0.05)))
    }

    @ViewBuilder
    private func actionButton(
        state: MeetingModelDownloadState,
        onDownload: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) -> some View {
        switch state {
        case .ready:
            Button(action: onDelete) {
                Text(L10n.string("ui.delete", default: "Delete"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        case .missing, .failed:
            Button(action: onDownload) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 10, weight: .semibold))
                    Text(L10n.string("ui.download", default: "Download"))
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.black.opacity(0.85))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(accent))
            }
            .buttonStyle(.plain)
        case .downloading:
            EmptyView()
        }
    }

    private func subtitleFor(_ engine: MeetingTranscriptionEngine) -> String {
        switch engine {
        case .parakeetFlash, .parakeetV2:
            return "English · fast · ~650 MB · Apple Neural Engine"
        case .parakeetUnifiedStream:
            return "English · live streaming · ~731 MB · GPU"
        case .whisperSmallMultilingual:
            return "Multilingual · ~466 MB"
        }
    }

    private var privacyFootnote: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
            Text(L10n.string("ui.models.audio.transcripts.and.summari.d4139d", default: "Models, audio, transcripts, and summaries all stay on this Mac. No data is sent to Jack servers."))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(L10n.string("ui.done", default: "Done")) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.black.opacity(0.85))
                .padding(.horizontal, 18)
                .padding(.vertical, 7)
                .background(Capsule().fill(accent))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
    }
}
