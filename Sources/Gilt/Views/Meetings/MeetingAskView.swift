import SwiftUI

/// "Ask the meeting" tab. Clean chat layout in the workspace palette — user
/// messages on the right with gold accent, AI responses on the left with
/// neutral tone, citation rows underneath each answer.
struct MeetingAskView: View {
    let meetingID: UUID
    let accent: Color

    @EnvironmentObject private var controller: MeetingSessionController
    @State private var draft: String = ""
    @State private var thinking = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            scrollArea
            if !controller.askHistory.isEmpty {
                suggestionsStrip
                    .padding(.horizontal, 28)
                    .padding(.bottom, 6)
            }
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
            inputBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // First time the user lands in Ask, kick off an initial generation
            // so they don't sit on the generic fallback list forever.
            controller.regenerateSuggestedQuestionsIfDue()
        }
    }

    private var scrollArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if controller.askHistory.isEmpty {
                        starterCard
                    } else {
                        ForEach(controller.askHistory) { question in
                            exchange(question)
                                .id(question.id)
                        }
                        if thinking { thinkingRow }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
            }
            .scrollIndicators(.hidden)
            .onChange(of: controller.askHistory.last?.id) { _, newValue in
                if let id = newValue {
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }
        }
    }

    /// Horizontal pill row of click-to-ask suggestions. Sits above the input
    /// once the user has started a conversation so fresh AI-generated
    /// questions stay one click away as the meeting progresses.
    private var suggestionsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(starterPrompts, id: \.self) { prompt in
                    Button {
                        draft = prompt
                        send()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(accent.opacity(0.85))
                            Text(prompt)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.8))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.05)))
                        .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var starterCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.string("ui.ask.this.meeting", default: "ASK THIS MEETING"))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(2.4)
                .foregroundStyle(accent.opacity(0.85))

            Text(L10n.string("ui.pull.answers.straight.out.of.the.transcript", default: "Pull answers straight out of the transcript"))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .tracking(-0.2)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(starterPrompts, id: \.self) { prompt in
                    Button {
                        draft = prompt
                        send()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(accent.opacity(0.85))
                            Text(prompt)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.8))
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)
        }
        .padding(.top, 4)
    }

    private var starterPrompts: [String] {
        // Live AI-generated suggestions, falling back to the generic starter
        // list for the first few seconds before Qwen has read enough.
        let dynamic = controller.suggestedQuestions
        return dynamic.isEmpty
            ? MeetingQuestionAnsweringService.defaultStarterQuestions
            : dynamic
    }

    private func exchange(_ question: MeetingQuestion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // User question on the right
            HStack {
                Spacer(minLength: 60)
                Text(question.question)
                    .font(.system(size: 13))
                    .foregroundStyle(.black.opacity(0.85))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(accent.opacity(0.92))
                    )
                    .frame(maxWidth: 520, alignment: .trailing)
            }

            // AI answer + citations on the left
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accent.opacity(0.85))
                    .frame(width: 28, height: 28)
                    .background(
                        Circle().fill(Color.white.opacity(0.05))
                    )
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    )

                VStack(alignment: .leading, spacing: 10) {
                    Text(question.answer)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.88))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !question.citations.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.string("ui.from.the.transcript", default: "FROM THE TRANSCRIPT"))
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(1.6)
                                .foregroundStyle(.white.opacity(0.4))
                            ForEach(question.citations.prefix(3)) { citation in
                                citationRow(citation)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .frame(maxWidth: 560, alignment: .leading)
                Spacer(minLength: 0)
            }
        }
    }

    private func citationRow(_ citation: MeetingAnswerCitation) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(citation.formattedRange)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
                .frame(minWidth: 80, alignment: .leading)
            Text(citation.snippet)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(2)
        }
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
        }
    }

    private var thinkingRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small).tint(accent)
            Text(L10n.string("meeting.ask.thinking", default: "Searching the transcript…"))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.leading, 38)
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                TextField("Ask about this meeting…", text: $draft)
                    .textFieldStyle(.plain)
                    .focused($inputFocused)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.9))
                    .onSubmit { send() }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        inputFocused ? accent.opacity(0.55) : Color.white.opacity(0.08),
                        lineWidth: inputFocused ? 1 : 0.5
                    )
            )

            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.black.opacity(0.85))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(accent)
                    )
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !thinking else { return }
        draft = ""
        thinking = true
        Task {
            await controller.askQuestion(text)
            thinking = false
        }
    }
}
