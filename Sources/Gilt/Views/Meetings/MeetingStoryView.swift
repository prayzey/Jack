import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Story tab — essay-style recap of a meeting.
///
/// While the meeting is live the controller appends one new paragraph every
/// five minutes via `MeetingStoryService` / `QwenLocalLLM`. The text view in
/// this surface is fully editable; user edits are persisted on a debounce and
/// fed back into the next iteration as locked context so the model never
/// overwrites them.
///
/// Design rules (per the §09 mockup and CLAUDE.md anti-AI-slop guidance):
///   - no pills, no decorative dots, no left-border accents
///   - prose lives in a centered reading column with a serif body font
///   - status text is plain typography, no animated indicators
struct MeetingStoryView: View {
    let meetingID: UUID
    let accent: Color

    @EnvironmentObject private var controller: MeetingSessionController
    @EnvironmentObject private var meetingStore: MeetingStore

    @State private var draft: String = ""
    @State private var saveTask: Task<Void, Never>?
    @State private var lastSavedAt: Date?
    @State private var regenerating: Bool = false
    @State private var copyFeedback: Bool = false

    private static let autosaveDebounce: Duration = .milliseconds(800)
    private static let readingColumnWidth: CGFloat = 640

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 28)
                .padding(.top, 18)
                .padding(.bottom, 12)

            content
        }
        .onAppear { draft = controller.storyText }
        .onChange(of: controller.storyText) { _, newValue in
            // Pull in auto-extends and external updates without clobbering
            // an in-flight user edit. If the user has unsaved local changes
            // the controller-side text will catch up after the autosave
            // window closes.
            if newValue != draft, saveTask == nil {
                draft = newValue
            }
        }
        .onChange(of: meetingID) { _, _ in
            draft = controller.storyText
            saveTask?.cancel()
            saveTask = nil
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            statusText
            Spacer()
            actions
        }
    }

    private var statusText: some View {
        Text(statusLine)
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.45))
    }

    private var statusLine: String {
        let wordCount = wordCount(draft)
        let paragraphCount = paragraphCount(draft)
        if wordCount == 0 {
            if controller.isWritingStory { return "Writing the first paragraph" }
            return "Nothing written yet"
        }
        var parts: [String] = []
        parts.append("\(paragraphCount) " + (paragraphCount == 1 ? "paragraph" : "paragraphs"))
        parts.append("\(wordCount) " + (wordCount == 1 ? "word" : "words"))
        if controller.isWritingStory {
            parts.append("writing")
        } else if let savedAt = lastSavedAt {
            parts.append("saved \(relativeTime(savedAt))")
        }
        return parts.joined(separator: "   ")
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button(action: regenerate) {
                HStack(spacing: 6) {
                    Image(systemName: regenerating ? "arrow.triangle.2.circlepath" : "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                    Text(regenerating ? "Writing" : "Regenerate")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white.opacity((regenerating || controller.transcript.isEmpty) ? 0.35 : 0.8))
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
            .disabled(regenerating || controller.transcript.isEmpty)

            exportMenu
        }
    }

    private var exportMenu: some View {
        Menu {
            Button(L10n.string("ui.markdown.md", default: "Markdown (.md)")) { exportToFile(extension: "md") }
            Button(L10n.string("ui.plain.text.txt", default: "Plain text (.txt)")) { exportToFile(extension: "txt") }
            Divider()
            Button(copyFeedback ? "Copied" : "Copy to clipboard") { copyToClipboard() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 11, weight: .semibold))
                Text(L10n.string("ui.export", default: "Export"))
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.black.opacity(0.85))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(draft.isEmpty ? accent.opacity(0.4) : accent)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(draft.isEmpty)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if draft.isEmpty && !controller.isWritingStory {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            essayEditor
        }
    }

    private var essayEditor: some View {
        GeometryReader { geo in
            ScrollView {
                StoryTextEditor(text: $draft)
                    .frame(width: min(Self.readingColumnWidth, geo.size.width - 56))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 28)
                    .padding(.top, 6)
                    .padding(.bottom, 48)
            }
            .scrollIndicators(.hidden)
        }
        .onChange(of: draft) { _, _ in scheduleAutosave() }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.string("ui.this.meeting.hasn.t.been.written.up.yet", default: "This meeting hasn't been written up yet."))
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .foregroundStyle(.white.opacity(0.7))

            if controller.transcript.isEmpty {
                Text("It will be written automatically every five minutes while you record, in flowing prose. You can also write it yourself in this space, and the model will pick up where you left off.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineSpacing(3)
                    .frame(maxWidth: 480, alignment: .leading)
            } else {
                Text(L10n.string("ui.there.s.a.transcript.ready.use.regen.083aee", default: "There's a transcript ready. Use Regenerate to draft the full essay now, or start writing below."))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineSpacing(3)
                    .frame(maxWidth: 480, alignment: .leading)

                Button(action: regenerate) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .semibold))
                        Text(L10n.string("ui.write.it.now", default: "Write it now"))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.black.opacity(0.85))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(accent))
                }
                .buttonStyle(.plain)
                .disabled(regenerating)
                .padding(.top, 6)
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 40)
        .frame(maxWidth: Self.readingColumnWidth + 56, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Actions

    private var session: MeetingSession? {
        meetingStore.session(for: meetingID)
    }

    private func scheduleAutosave() {
        saveTask?.cancel()
        let snapshot = draft
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: Self.autosaveDebounce)
            if Task.isCancelled { return }
            controller.updateStoryText(snapshot)
            lastSavedAt = Date()
            saveTask = nil
        }
    }

    private func regenerate() {
        regenerating = true
        Task {
            await controller.regenerateStory()
            await MainActor.run {
                draft = controller.storyText
                lastSavedAt = Date()
                regenerating = false
            }
        }
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(draft, forType: .string)
        copyFeedback = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            copyFeedback = false
        }
    }

    private func exportToFile(extension ext: String) {
        // Force any pending autosave through before exporting, so the file on
        // disk matches what's in the editor.
        controller.updateStoryText(draft)

        let panel = NSSavePanel()
        let baseName = (session?.displayTitle ?? "Meeting")
            .replacingOccurrences(of: "/", with: "-")
        panel.nameFieldStringValue = "\(baseName).\(ext)"
        if let utType = UTType(filenameExtension: ext) {
            panel.allowedContentTypes = [utType]
        }
        panel.canCreateDirectories = true
        if panel.runModalInFront() == .OK, let url = panel.url {
            try? draft.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Formatting helpers

    private func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    private func paragraphCount(_ text: String) -> Int {
        text
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
    }

    private func relativeTime(_ date: Date) -> String {
        MeetingFormatters.relativeDateString(date)
    }
}

/// NSTextView-backed editor for the story body. SwiftUI's `TextEditor` does
/// not let us set line spacing, custom serif font, and content insets all at
/// once on macOS, so we drop down to AppKit. The view is intentionally
/// chromeless — no border, no background — so the reading column blends into
/// the workspace surface.
private struct StoryTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder

        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        configure(textView)
        textView.delegate = context.coordinator
        textView.string = text
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        // Only push text in from SwiftUI when the model genuinely diverged
        // from what's on screen. Replacing the string on every redraw kills
        // the cursor position.
        if textView.string != text {
            let selectedRange = textView.selectedRange()
            textView.string = text
            // Best-effort cursor restore — clamp to new length.
            let clamped = NSRange(
                location: min(selectedRange.location, text.utf16.count),
                length: 0
            )
            textView.setSelectedRange(clamped)
        }
    }

    private func configure(_ textView: NSTextView) {
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 8)
        textView.font = Self.bodyFont
        textView.textColor = NSColor.white.withAlphaComponent(0.92)
        textView.insertionPointColor = NSColor.white.withAlphaComponent(0.85)
        textView.isAutomaticQuoteSubstitutionEnabled = true
        textView.isAutomaticDashSubstitutionEnabled = false  // hard ban on em-dashes
        textView.isAutomaticSpellingCorrectionEnabled = true
        textView.isContinuousSpellCheckingEnabled = true
        textView.isAutomaticTextReplacementEnabled = false
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.white.withAlphaComponent(0.85),
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]

        // Generous line spacing — this is a reading column.
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 6
        paragraph.paragraphSpacing = 12
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes = [
            .font: Self.bodyFont,
            .foregroundColor: NSColor.white.withAlphaComponent(0.92),
            .paragraphStyle: paragraph
        ]
    }

    private static var bodyFont: NSFont {
        // Iowan Old Style ships with macOS and reads well at body sizes.
        // Fall back to the serif system font on the off-chance it's missing.
        if let f = NSFont(name: "Iowan Old Style", size: 16) { return f }
        return NSFont(descriptor: NSFont.systemFont(ofSize: 16).fontDescriptor.withDesign(.serif) ?? NSFont.systemFont(ofSize: 16).fontDescriptor, size: 16) ?? NSFont.systemFont(ofSize: 16)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        init(text: Binding<String>) { _text = text }
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if text != textView.string {
                text = textView.string
            }
        }
    }
}
