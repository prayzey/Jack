import SwiftUI

/// Dashboard view for the meetings tab — the landing surface when no specific
/// meeting is selected. Matches the workspace's editorial pattern: gold
/// eyebrow + bold title at the top, hairline-divided rows underneath.
struct MeetingDashboardView: View {
    @ObservedObject var meetingStore: MeetingStore
    let accent: Color
    let onNew: () -> Void
    let onOpenModels: () -> Void
    let onSelect: (UUID) -> Void
    let onDelete: (UUID) -> Void

    @State private var editingID: UUID?
    @State private var renameDraft: String = ""
    @FocusState private var renameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 28)
                .padding(.top, 26)
                .padding(.bottom, 18)

            if meetingStore.sessions.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 26)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(meetingStore.sessions) { session in
                            row(session)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 26)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string("ui.meetings", default: "MEETINGS"))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(2.4)
                    .foregroundStyle(accent.opacity(0.85))
                Text(L10n.string("meeting.dashboard.title", default: "Meeting memory"))
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .tracking(-0.4)
            }
            Spacer(minLength: 12)
            actions
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button(action: onOpenModels) {
                HStack(spacing: 6) {
                    Image(systemName: "cpu")
                        .font(.system(size: 11, weight: .semibold))
                    Text(L10n.string("meeting.button.models", default: "Models"))
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.8))
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

            Button(action: onNew) {
                HStack(spacing: 6) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text(L10n.string("meeting.button.newMeeting", default: "New Meeting"))
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.black.opacity(0.85))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(accent)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Row

    private func row(_ session: MeetingSession) -> some View {
        let isEditing = editingID == session.meetingID
        return HStack(spacing: 10) {
            if isEditing {
                // No select Button while editing — the TextField needs the clicks.
                rowBody(session, editing: true)
            } else {
                Button {
                    onSelect(session.meetingID)
                } label: {
                    rowBody(session, editing: false)
                }
                .buttonStyle(.plain)
            }

            Menu {
                Button {
                    beginRename(session)
                } label: {
                    Label(L10n.string("ui.rename", default: "Rename"), systemImage: "pencil")
                }
                Button(role: .destructive) {
                    onDelete(session.meetingID)
                } label: {
                    Label(L10n.string("ui.delete.meeting", default: "Delete Meeting"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 28, height: 28)
            .fixedSize()
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
        }
        .contextMenu {
            Button {
                beginRename(session)
            } label: {
                Label(L10n.string("ui.rename", default: "Rename"), systemImage: "pencil")
            }
            Button(role: .destructive) {
                onDelete(session.meetingID)
            } label: {
                Label(L10n.string("ui.delete.meeting", default: "Delete Meeting"), systemImage: "trash")
            }
        }
    }

    private func rowBody(_ session: MeetingSession, editing: Bool) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(accent.opacity(0.18))
                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                if editing {
                    TextField(session.displayTitle, text: $renameDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .focused($renameFocused)
                        .onSubmit { commitRename() }
                        .onChange(of: renameFocused) { _, focused in
                            if !focused { commitRename() }
                        }
                        .onAppear { renameFocused = true }
                } else {
                    Text(session.displayTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(formattedDate(session.createdAt))
                    if let duration = MeetingFormatters.shortDuration(session.durationSeconds) {
                        Text("·")
                        Text(duration)
                    }
                    Text("·")
                    Text(stateLabel(session.state))
                }
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            if !editing {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .contentShape(Rectangle())
    }

    private func beginRename(_ session: MeetingSession) {
        renameDraft = session.title
        editingID = session.meetingID
    }

    private func commitRename() {
        guard let id = editingID else { return }
        meetingStore.renameSession(id, to: renameDraft)
        editingID = nil
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(accent.opacity(0.7))
                .symbolRenderingMode(.hierarchical)

            Text(L10n.string("ui.no.meetings.yet", default: "No meetings yet"))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .tracking(-0.2)

            Text("Capture your first session. Jack listens, transcribes, and lets you ask questions afterwards. Audio and notes stay on this Mac.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 360)

            Button(action: onNew) {
                HStack(spacing: 6) {
                    Image(systemName: "mic.fill").font(.system(size: 11, weight: .semibold))
                    Text(L10n.string("ui.start.a.meeting", default: "Start a meeting"))
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.black.opacity(0.85))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Capsule().fill(accent))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private func stateLabel(_ state: MeetingSessionState) -> String {
        switch state {
        case .draft: return "Draft"
        case .recording: return "Recording"
        case .paused: return "Paused"
        case .processing: return "Processing"
        case .ready: return "Saved"
        case .failed: return "Failed"
        }
    }
}
