import SwiftUI

/// The "you're in a specific meeting" surface inside the workspace. Renders
/// the title and switcher at the top (matching the workspace header pattern)
/// and swaps the content underneath: live capture, transcript, summary, ask.
struct MeetingDetailSurface: View {
    @EnvironmentObject private var meetingStore: MeetingStore
    @EnvironmentObject private var controller: MeetingSessionController
    let accent: Color
    let onClose: () -> Void
    let onOpenModels: () -> Void
    let onDelete: (UUID) -> Void

    @State private var tab: Tab = .summary
    @State private var titleDraft: String = ""
    @FocusState private var titleFocused: Bool

    enum Tab: String, CaseIterable, Identifiable {
        case live, transcript, summary, story, ask
        var id: String { rawValue }
        var label: String {
            switch self {
            case .live: return "Live"
            case .transcript: return "Transcript"
            case .summary: return "Summary"
            case .story: return "Story"
            case .ask: return "Ask"
            }
        }
    }

    private var meeting: MeetingSession? {
        guard let id = controller.currentMeetingID else { return nil }
        return meetingStore.session(for: id)
    }

    private var isLive: Bool {
        switch controller.phase {
        case .recording, .paused, .preparing, .finishing, .failed: return true
        default: return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 28)
                .padding(.top, 26)
                .padding(.bottom, 14)

            tabStrip
                .padding(.horizontal, 28)
                .padding(.bottom, 16)

            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { syncTab(); syncTitleDraft() }
        .onChange(of: controller.phase) { _, _ in syncTab() }
        .onChange(of: controller.currentMeetingID) { _, _ in syncTitleDraft() }
        // Reflect external title changes (e.g. auto-naming) unless the user is
        // mid-edit — clobbering the field while typing would eat keystrokes.
        .onChange(of: meeting?.title) { _, newValue in
            if !titleFocused { titleDraft = newValue ?? "" }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(L10n.string("meeting.card.type", default: "MEETING"))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(2.4)
                        .foregroundStyle(accent.opacity(0.85))
                    if let session = meeting, showStatePill(session.state) {
                        statePill(state: session.state)
                    }
                }
                // Editable title — click and type to rename, commit on Return
                // or focus loss. Placeholder is the date fallback so an empty
                // title still reads as the meeting's default name.
                TextField(meeting?.displayTitle ?? "Meeting", text: $titleDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .tracking(-0.4)
                    .lineLimit(1)
                    .focused($titleFocused)
                    .onSubmit { commitRename() }
                    .onChange(of: titleFocused) { _, focused in
                        if !focused { commitRename() }
                    }
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                if let session = meeting {
                    languageBadge(session.language)
                }
                iconButton(icon: "cpu", help: "Manage local models", action: onOpenModels)
                if let id = controller.currentMeetingID {
                    iconButton(icon: "trash", help: "Delete meeting") {
                        onDelete(id)
                    }
                }
                iconButton(icon: "chevron.left", help: "Back to all meetings", action: onClose)
            }
        }
    }

    private func iconButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func languageBadge(_ language: MeetingLanguage) -> some View {
        Text("\(language.flagEmoji)  \(language.displayName)")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 0.5))
    }

    // Only surface the pill for states that carry live information. A finished
    // ("SAVED") or untouched ("DRAFT") meeting needs no badge — the Granola-
    // style header stays clean, and the Live tab already signals recording.
    private func showStatePill(_ state: MeetingSessionState) -> Bool {
        switch state {
        case .recording, .paused, .processing, .failed: return true
        case .ready, .draft: return false
        }
    }

    private func syncTitleDraft() {
        titleDraft = meeting?.title ?? ""
    }

    private func commitRename() {
        guard let id = controller.currentMeetingID else { return }
        meetingStore.renameSession(id, to: titleDraft)
        // Echo the trimmed/persisted value back so the field matches storage.
        titleDraft = meetingStore.session(for: id)?.title ?? ""
    }

    private func statePill(state: MeetingSessionState) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(stateColor(state))
                .frame(width: 6, height: 6)
            Text(stateLabel(state))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(.white.opacity(0.65))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.white.opacity(0.06)))
    }

    private func stateLabel(_ state: MeetingSessionState) -> String {
        switch state {
        case .draft: return "DRAFT"
        case .recording: return "RECORDING"
        case .paused: return "PAUSED"
        case .processing: return "PROCESSING"
        case .ready: return "SAVED"
        case .failed: return "FAILED"
        }
    }

    private func stateColor(_ state: MeetingSessionState) -> Color {
        switch state {
        case .recording, .paused: return MeetingAccent.recording
        case .processing: return accent
        case .ready: return Color(red: 0.30, green: 0.78, blue: 0.55)
        case .failed: return Color(red: 0.93, green: 0.38, blue: 0.48)
        case .draft: return Color.white.opacity(0.45)
        }
    }

    // MARK: - Tab strip

    private var tabStrip: some View {
        HStack(spacing: 4) {
            ForEach(visibleTabs, id: \.self) { entry in
                tabButton(entry)
            }
            Spacer()
        }
    }

    private var visibleTabs: [Tab] {
        var entries: [Tab] = []
        if isLive { entries.append(.live) }
        entries.append(.transcript)
        entries.append(.summary)
        entries.append(.story)
        entries.append(.ask)
        return entries
    }

    private func tabButton(_ entry: Tab) -> some View {
        let active = tab == entry
        return Button { tab = entry } label: {
            HStack(spacing: 6) {
                if entry == .live {
                    Circle()
                        .fill(MeetingAccent.recording)
                        .frame(width: 6, height: 6)
                }
                Text(entry.label)
                    .font(.system(size: 12, weight: active ? .semibold : .regular))
            }
            .foregroundStyle(active ? .white : .white.opacity(0.55))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(active ? Color.white.opacity(0.10) : .clear)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        if let id = controller.currentMeetingID {
            switch tab {
            case .live:
                ActiveMeetingView(meetingID: id, accent: accent)
            case .transcript:
                MeetingTranscriptView(accent: accent)
            case .summary:
                MeetingSummaryView(meetingID: id, accent: accent)
            case .story:
                MeetingStoryView(meetingID: id, accent: accent)
            case .ask:
                MeetingAskView(meetingID: id, accent: accent)
            }
        }
    }

    private func syncTab() {
        if isLive {
            tab = .live
        } else if tab == .live {
            tab = .summary
        }
    }
}
