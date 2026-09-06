import SwiftUI

/// Full transcript tab for the meetings surface. Workspace-style: search bar
/// up top, hairline-divided rows underneath.
///
/// Doubles as the live reading surface while a meeting is recording — new
/// chunks appear here in real time and the scroll view sticks to the bottom
/// so the user is always reading the latest. (We used to render a second
/// streaming transcript inside the Live tab; that duplicated this view in a
/// worse layout, so it was removed.)
struct MeetingTranscriptView: View {
    @EnvironmentObject private var controller: MeetingSessionController
    let accent: Color
    @State private var searchText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
                .padding(.horizontal, 28)
                .padding(.top, 18)
                .padding(.bottom, 12)

            if filteredChunks.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(filteredChunks) { chunk in
                                MeetingChunkRow(chunk: chunk)
                                    .id(chunk.chunkID)
                                    .padding(.horizontal, 28)
                            }
                        }
                        .padding(.bottom, 26)
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: controller.transcript.last?.chunkID) { _, newID in
                        // Only auto-follow while live. Once the meeting is
                        // saved the user is reading at their own pace and we
                        // shouldn't yank them back to the bottom.
                        guard isLive, searchText.isEmpty, let id = newID else { return }
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo(id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var isLive: Bool {
        switch controller.phase {
        case .recording, .paused, .preparing, .finishing: return true
        default: return false
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                TextField("Search transcript", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 0.5))

            Spacer()

            Text("\(controller.transcript.count) chunks")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))

            Button(action: copyAll) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11, weight: .semibold))
                    Text(L10n.string("meeting.transcript.copy", default: "Copy"))
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
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.alignleft")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(accent.opacity(0.6))
                .symbolRenderingMode(.hierarchical)
            Text(emptyHeadline)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text(emptyBody)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyHeadline: String {
        if !searchText.isEmpty { return "No matching lines" }
        return isLive ? "Warming up the model" : "No transcript yet"
    }

    private var emptyBody: String {
        if !searchText.isEmpty { return "Try a different word from the meeting." }
        if isLive {
            return "Transcript lines will appear here as you speak."
        }
        return "Finish or replay a meeting to see its transcript here."
    }

    private var filteredChunks: [MeetingTranscriptChunk] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty { return controller.transcript }
        return controller.transcript.filter { $0.text.lowercased().contains(trimmed) }
    }

    private func copyAll() {
        let text = controller.transcript
            .map { "[\($0.formattedTimestamp)] \($0.text)" }
            .joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
