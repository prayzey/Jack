import SwiftUI

/// Contextual section content embedded inside `WorkspaceSidebarView`.
///
/// Formerly the standalone middle column in the three-pane layout; now lives
/// as a content-only view inside the sidebar's ScrollView. Shows folders +
/// items for whichever section is active (clipboard, tasks, pulse, meetings).
/// The row types are re-used from `WorkspaceSidebarView.swift`.
///
/// Design rationale:
/// - This view intentionally does NOT wrap its content in a ScrollView or
///   apply outer padding — the sidebar owns scrolling and spacing. Keeping
///   it content-only lets the sidebar control the rhythm above (nav strip,
///   search) and below (this section).
struct WorkspaceListColumn: View {
    @EnvironmentObject private var store: ClipboardStore

    private var goldAccent: Color { Color(red: 0.83, green: 0.66, blue: 0.26) }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            switch store.workspaceSession.selectedSidebarSection {
            case .clipboard: clipboardSection
            case .tasks:     tasksSection
            case .meetings:  meetingsSection
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
    }

    // MARK: - Section content

    private var clipboardSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Folders")
            ForEach(store.visibleFolders) { folder in
                ClipFolderSidebarRow(folder: folder)
            }
            // The always-on "Recent" feed was removed — it grew into a long,
            // repetitive list. Clips now surface only when the user actively
            // searches, so the search field stays useful without cluttering the
            // sidebar by default.
            let query = store.workspaceSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !query.isEmpty {
                sectionTitle("Results")
                let results = Array(store.workspaceFilteredClips.prefix(40))
                if results.isEmpty {
                    Text(L10n.string("ui.no.matching.clips", default: "No matching clips."))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.48))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 6)
                } else {
                    ForEach(results, id: \.clipID) { clip in
                        ClipSidebarRow(clip: clip)
                    }
                }
            }
        }
    }

    private var tasksSection: some View {
        // The Tasks section lists the user's Kanban *boards* (Work, Personal, …),
        // each opening in its own tab — not the tasks of one board, which would
        // just duplicate the board's Todo column.
        WorkspaceBoardsSection()
    }

    private var meetingsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Meetings")
            let recent = MeetingHub.shared.store.sessions.prefix(40)
            if recent.isEmpty {
                Text(L10n.string("ui.no.meetings.yet.open.the.meetings.ta.b4c4d3", default: "No meetings yet. Open the Meetings tab to start one."))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.48))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 6)
            } else {
                ForEach(Array(recent), id: \.meetingID) { meeting in
                    Button {
                        store.openMeetingsInWorkspace()
                        MeetingHub.shared.focusMeeting(meeting.meetingID)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "waveform")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(goldAccent.opacity(0.78))
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(meeting.displayTitle)
                                    .lineLimit(1)
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.88))
                                if let duration = MeetingFormatters.shortDuration(meeting.durationSeconds) {
                                    Text(duration)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.white.opacity(0.48))
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionTitle(_ title: String) -> some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(.white.opacity(0.42))
            Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)
        }
        .padding(.top, 4)
        .padding(.horizontal, 4)
    }
}

