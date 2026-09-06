import SwiftUI

/// Summary tab — the meeting recap. Workspace pattern throughout: gold
/// eyebrow, bold headline, then sections rendered as plain typography blocks
/// rather than nested cards. Hairline dividers separate the sections.
struct MeetingSummaryView: View {
    let meetingID: UUID
    let accent: Color

    @EnvironmentObject private var controller: MeetingSessionController
    @EnvironmentObject private var meetingStore: MeetingStore
    @State private var regenerating = false
    @State private var polishing = false
    @State private var copyFeedback = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                    .padding(.horizontal, 28)
                    .padding(.top, 18)
                    .padding(.bottom, 18)

                if let summary = controller.summary {
                    if !summary.bullets.isEmpty {
                        section(title: "Quick notes") {
                            ForEach(Array(summary.bullets.enumerated()), id: \.offset) { _, bullet in
                                bulletRow(bullet)
                            }
                        }
                    }

                    if !summary.decisions.isEmpty {
                        section(title: "Decisions") {
                            ForEach(summary.decisions) { decision in
                                bulletRow(decision.text)
                            }
                        }
                    }

                    if !summary.actionItems.isEmpty {
                        section(title: "Action items") {
                            ForEach(summary.actionItems) { item in
                                actionItemRow(item)
                            }
                        }
                    }

                    if !summary.followUpQuestions.isEmpty {
                        section(title: "Follow-up questions") {
                            ForEach(summary.followUpQuestions) { question in
                                bulletRow(question.text)
                            }
                        }
                    }
                } else {
                    emptyState
                        .padding(.horizontal, 28)
                        .padding(.vertical, 40)
                }
            }
            .padding(.bottom, 26)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .lastTextBaseline) {
                Text(L10n.string("meeting.summary.headline.label", default: "RECAP"))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(2.4)
                    .foregroundStyle(accent.opacity(0.85))
                Spacer()
                actions
            }
            Text(headline)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white.opacity(0.95))
                .tracking(-0.3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            if let rolling = controller.summary?.rollingNotes,
               !rolling.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(rolling)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
    }

    private var headline: String {
        let h = controller.summary?.headline ?? ""
        return h.isEmpty ? "Summary not generated yet" : h
    }

    private var actions: some View {
        HStack(spacing: 8) {
            iconChip(
                icon: "doc.on.doc",
                label: copyFeedback ? "Copied" : "Copy",
                action: copy
            )
            polishMenu
            iconChip(
                icon: regenerating ? "arrow.triangle.2.circlepath" : "sparkles",
                label: regenerating ? "Thinking…" : "Regenerate",
                disabled: regenerating || controller.transcript.isEmpty,
                action: regenerate
            )
        }
    }

    /// Lets the user re-cast the summary's prose (headline + rolling notes)
    /// in any of the dictation Style × Level voices. We deliberately don't
    /// polish bullets or action items — they're already structured and we
    /// don't want to spend a Qwen call per row. Headline + notes are the
    /// parts where prose quality is most visible.
    private var polishMenu: some View {
        Menu {
            ForEach(DictationStyle.allCases) { style in
                Section(style.displayName) {
                    ForEach(DictationLevel.allCases.filter { $0 != .none }) { level in
                        Button("\(style.displayName) · \(level.displayName)") {
                            polish(style: style, level: level)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: polishing ? "arrow.triangle.2.circlepath" : "wand.and.stars")
                    .font(.system(size: 11, weight: .semibold))
                Text(polishing ? "Polishing…" : "Polish")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(polishCanFire ? 0.8 : 0.35))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(!polishCanFire)
    }

    private var polishCanFire: Bool {
        guard !polishing, !regenerating, let summary = controller.summary else { return false }
        // No prose to polish? Disable.
        let hasHeadline = !summary.headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasNotes = !summary.rollingNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasHeadline || hasNotes
    }

    private func iconChip(
        icon: String,
        label: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                Text(label).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(disabled ? 0.35 : 0.8))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    // MARK: - Sections

    /// Granola-style section: a bold `# Heading` followed by clean rows.
    /// Deliberately no per-row hairline dividers — those read as "too many
    /// lines" and turn the recap into a stack of boxes. Hierarchy comes from
    /// the bold heading, generous section spacing, and line spacing instead.
    @ViewBuilder
    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("#")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.25))
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }
            VStack(alignment: .leading, spacing: 3) {
                content()
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 26)
    }

    private func bulletRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Circle()
                .fill(.white.opacity(0.4))
                .frame(width: 4, height: 4)
                .padding(.top, 8)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.85))
                .lineSpacing(4)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }

    private func actionItemRow(_ item: MeetingActionItem) -> some View {
        Button {
            toggle(item)
        } label: {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(
                        item.isCompleted
                            ? Color(red: 0.30, green: 0.78, blue: 0.55)
                            : .white.opacity(0.35)
                    )
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.text)
                        .font(.system(size: 14))
                        .strikethrough(item.isCompleted)
                        .foregroundStyle(.white.opacity(item.isCompleted ? 0.45 : 0.85))
                        .lineSpacing(4)
                        .multilineTextAlignment(.leading)
                    if let owner = item.owner {
                        Text(owner)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
                Spacer(minLength: 8)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(accent.opacity(0.6))
                .symbolRenderingMode(.hierarchical)
            Text(L10n.string("meeting.summary.empty.title", default: "No summary yet"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text(L10n.string("meeting.summary.empty.body", default: "Finish the meeting and Jack will generate a recap. You can regenerate any time."))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func copy() {
        guard let summary = controller.summary else { return }
        var lines: [String] = []
        if !summary.headline.isEmpty { lines.append(summary.headline) }
        if !summary.bullets.isEmpty {
            lines.append("")
            lines.append("Quick notes")
            lines += summary.bullets.map { "• \($0)" }
        }
        if !summary.decisions.isEmpty {
            lines.append("")
            lines.append("Decisions")
            lines += summary.decisions.map { "✓ \($0.text)" }
        }
        if !summary.actionItems.isEmpty {
            lines.append("")
            lines.append("Action items")
            lines += summary.actionItems.map { "[ ] \($0.text)" }
        }
        if !summary.followUpQuestions.isEmpty {
            lines.append("")
            lines.append("Follow-up questions")
            lines += summary.followUpQuestions.map { "? \($0.text)" }
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        copyFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copyFeedback = false }
    }

    private func regenerate() {
        regenerating = true
        Task {
            await controller.regenerateSummary()
            regenerating = false
        }
    }

    private func polish(style: DictationStyle, level: DictationLevel) {
        guard var summary = controller.summary else { return }
        polishing = true
        Task {
            let qwenDir = MeetingAppSupportLocator.summarizationModelFolder(
                engine: .qwen35_4b_q4,
                in: MeetingAppSupportLocator.modelsRoot(in: MeetingAppSupportLocator.meetingsRoot())
            )
            let engine = DictationStyleEngine(cacheDirectory: qwenDir)
            if !summary.headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                summary.headline = await engine.process(
                    rawTranscript: summary.headline,
                    style: style,
                    level: level
                )
            }
            if !summary.rollingNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                summary.rollingNotes = await engine.process(
                    rawTranscript: summary.rollingNotes,
                    style: style,
                    level: level
                )
            }
            summary.lastUpdatedAt = Date()
            await MainActor.run {
                meetingStore.saveSummary(summary, for: meetingID)
                controller.selectMeeting(meetingID)
                polishing = false
            }
        }
    }

    private func toggle(_ item: MeetingActionItem) {
        guard var summary = controller.summary,
              let index = summary.actionItems.firstIndex(where: { $0.id == item.id }) else { return }
        summary.actionItems[index].isCompleted.toggle()
        meetingStore.saveSummary(summary, for: meetingID)
        controller.selectMeeting(meetingID)
    }
}
