import AppKit
import SwiftUI

struct QuickNoteView: View {
    @EnvironmentObject private var store: ClipboardStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft = QuickNoteDraftPersistence()
    @State private var previousDraft = ""
    @State private var previousOffset: CGFloat = 0
    @State private var previousOpacity = 0.0
    @State private var editorOffset: CGFloat = 0
    @State private var editorOpacity = 1.0
    @State private var transitionTask: Task<Void, Never>?
    @State private var dropFeedback: QuickNoteDropFeedback?
    @State private var dropFeedbackTask: Task<Void, Never>?
    /// Live vertical scroll offset reported by the editor. Drives the fade of
    /// the top-anchored arrow controls and export menu. Held in an `@Observable`
    /// object (not plain `@State`) so scroll updates re-render only the chrome
    /// overlays that read it — never the editor/card body. See QuickNoteScrollState.
    @State private var scrollState = QuickNoteScrollState()
    @State private var pendingImageInsertionID: UUID?
    @State private var persistDraftTask: Task<Void, Never>?
    /// Controls the in-window notes browser (search + jump across all quick notes).
    @State private var isBrowserPresented = false
    /// Controls the in-window vault destination picker (choose which vault
    /// subfolder the current note saves into).
    @State private var isVaultPickerPresented = false

    var body: some View {
        GeometryReader { geometry in
            let appearance = store.settings.quickNoteAppearance
            let canvasInset = quickNoteWindowCanvasInset(for: geometry.size)

            ZStack {
                QuickNoteBackdropView()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                noteCard(appearance: appearance)
                    .padding(canvasInset)

                if isBrowserPresented {
                    QuickNoteBrowserOverlay(
                        isPresented: $isBrowserPresented,
                        notes: store.quickNotes,
                        currentNoteID: store.quickNoteActiveNoteID,
                        style: appearance.style,
                        onSelect: { jumpToNote($0) },
                        onCreate: { createAndOpenNote() },
                        onDelete: { deleteNoteFromBrowser($0) }
                    )
                    .padding(canvasInset)
                    .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius(for: appearance.style), style: .continuous))
                    .zIndex(10)
                }

                if isVaultPickerPresented {
                    QuickNoteVaultPickerOverlay(
                        isPresented: $isVaultPickerPresented,
                        style: appearance.style,
                        hasVault: store.hasNotesVault,
                        vaultDisplayPath: store.settings.notesVaultDisplayPath,
                        currentSelection: currentNote?.vaultRelativeFolder,
                        loadFolders: { await store.vaultSubfolders() },
                        onSelect: { assignVaultDestination($0) },
                        onChooseVault: { chooseVaultFolder() }
                    )
                    .padding(canvasInset)
                    .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius(for: appearance.style), style: .continuous))
                    .zIndex(11)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: isBrowserPresented) { _, presented in
            // Hand focus back to the editor when the browser closes so the
            // cursor is ready in the note without an extra click.
            if !presented {
                QuickNoteWindowManager.shared.focusEditor()
            }
        }
        .onChange(of: currentNote?.bodyMarkdown) { _, newValue in
            let resolvedBody = newValue ?? ""
            guard resolvedBody != draft.markdown else { return }
            draft.sync(note: currentNote)
        }
        .onAppear {
            syncDraft()
        }
        .onChange(of: store.quickNoteActiveNoteID) { _, _ in
            syncDraft()
        }
        .onDisappear {
            flushDraftPersist()
            transitionTask?.cancel()
            dropFeedbackTask?.cancel()
        }
    }

    private var currentNote: NoteItem? {
        guard let noteID = store.quickNoteActiveNoteID else { return nil }
        return store.note(with: noteID)
    }

    private var navigationState: QuickNoteNavigationState {
        quickNoteNavigationState(
            currentNoteID: store.quickNoteActiveNoteID,
            quickNotes: store.quickNotes
        )
    }

    /// 1-based position of the active note within the swipe order, for the
    /// browser button's "3/12" tracker. 0 when there's no resolvable note.
    private var quickNotePosition: Int {
        guard let currentID = store.quickNoteActiveNoteID,
              let index = store.quickNotes.firstIndex(where: { $0.noteID == currentID }) else {
            return 0
        }
        return index + 1
    }

    private func noteCard(appearance: QuickNoteAppearance) -> some View {
        let style = appearance.style
        let cornerRadius: CGFloat = style == .prismGlass ? 30 : 28
        let wallpaperImage = appearance.backgroundWallpaper
            .loadImage(customFilename: appearance.customWallpaperFilename)
        let hasLoadedWallpaper = wallpaperImage != nil
        let showsTemplateChrome = appearance.shouldRenderTemplateChrome(hasLoadedWallpaper: hasLoadedWallpaper)
        // Resolve ink from the actual rendered backdrop (wallpaper + style +
        // opacity), not just the style's default white/black. Light surfaces
        // like Paper need dark chrome icons; dark themes need light icons.
        let effectiveTextColor = quickNoteChromeInk(
            appearance: appearance,
            hasLoadedWallpaper: hasLoadedWallpaper
        )

        return ZStack(alignment: .topLeading) {
            QuickNoteCardBackground(appearance: appearance, cornerRadius: cornerRadius)

            if !previousDraft.isEmpty {
                transitionSnapshot(previousDraft, appearance: appearance, textColor: effectiveTextColor)
                    .offset(x: previousOffset)
                    .opacity(previousOpacity)
            }

            QuickNoteTextEditor(
                // Editor-origin writes go through the untracked draft holder +
                // the persist debounce; they must NOT touch SwiftUI state, or
                // every keystroke re-renders this whole view (see
                // QuickNoteDraftPersistence).
                text: Binding(
                    get: { draft.markdown },
                    set: { newValue in
                        draft.editorDidChange(newValue)
                        scheduleDraftPersist(newValue)
                    }
                ),
                // Tracked read: external content replacement bumps the
                // revision, which is what re-runs this body (and therefore
                // updateNSView) so the editor picks up the new text.
                contentRevision: draft.revision,
                pendingImageInsertionID: $pendingImageInsertionID,
                noteID: store.quickNoteActiveNoteID,
                attachmentsRoot: store.noteImageAttachmentsRoot,
                style: style,
                typography: QuickNoteTypographyConfig(
                    fontFamily: appearance.fontFamily,
                    fontWeight: appearance.fontWeight,
                    fontPointSize: appearance.resolvedFontPointSize,
                    lineHeightMultiplier: CGFloat(appearance.lineHeightMultiplier),
                    letterSpacing: CGFloat(appearance.letterSpacing),
                    paragraphSpacing: CGFloat(appearance.paragraphSpacing),
                    customFontPostScriptName: appearance.customFontPostScriptName
                ),
                textColorOverride: appearance.customTextColorHex != nil || appearance.autoTextColorOnWallpaper
                    ? effectiveTextColor
                    : nil,
                reverseSwipeDirection: store.settings.reverseQuickNoteSwipeDirection,
                onNavigate: { step in
                    navigate(by: step)
                },
                onImageImport: { imageData in
                    handleIncomingImage(imageData)
                },
                onImageInsertionResult: { imageID, didInsert in
                    handleImageInsertionResult(imageID: imageID, didInsert: didInsert)
                },
                onScrollOffsetChange: { offset in
                    // Writes to the @Observable scroll state, which only the
                    // chrome overlays observe — keystroke/scroll never rebuild
                    // the editor or themed card through here.
                    scrollState.offset = offset
                }
            )
            // Fade scrolled text into the card before it reaches the top chrome.
            .mask(QuickNoteEditorTopFadeMask(fadeHeight: style.editorInsets.height))
            .offset(x: editorOffset)
            .opacity(editorOpacity)
            .background(Color.clear)
        }
        .overlay {
            if showsTemplateChrome {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(style.cardBorderColor, lineWidth: style == .prismGlass ? 1.2 : 0.9)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
            }
        }
        .overlay(alignment: .top) {
            QuickNoteHeaderChrome(
                scrollState: scrollState,
                style: style,
                navigationControlsStyle: store.settings.quickNoteNavigationControlsStyle,
                navigationState: navigationState,
                onNavigate: navigate(by:),
                foregroundColor: effectiveTextColor
            )
        }
        .overlay(alignment: .topTrailing) {
            QuickNoteExportChrome(
                scrollState: scrollState,
                note: currentNote,
                tint: effectiveTextColor,
                browsePosition: quickNotePosition,
                browseTotal: store.quickNotes.count,
                onBrowse: { presentBrowser() },
                vaultDestination: currentNote?.vaultRelativeFolder,
                hasVault: store.hasNotesVault,
                onChooseDestination: { presentVaultPicker() }
            )
        }
        .overlay(alignment: .trailing) {
            if style == .obsidian && showsTemplateChrome {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.98, green: 0.42, blue: 0.28),
                                Color(red: 0.78, green: 0.16, blue: 0.14)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 4)
                    .padding(.vertical, 22)
                    .padding(.trailing, 14)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let dropFeedback {
                QuickNoteDropFeedbackView(feedback: dropFeedback)
                    .padding(.trailing, 20)
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(alignment: .top) {
            if let toast = store.aiToast {
                AIToastView(toast: toast) { store.dismissAIToast() }
                    .padding(.top, 12)
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: store.aiToast)
    }

    private func transitionSnapshot(
        _ text: String,
        appearance: QuickNoteAppearance,
        textColor: Color
    ) -> some View {
        let style = appearance.style
        // Shares the live editor's insets so the cross-fade doesn't shift layout.
        let insets = style.editorInsets
        // Match the live editor's font choice so the cross-fade doesn't shift layout.
        let nsFont = resolveQuickNoteFont(
            family: appearance.fontFamily,
            weight: appearance.fontWeight,
            pointSize: appearance.resolvedFontPointSize,
            customPostScriptName: appearance.customFontPostScriptName
        )

        // The outgoing card is a faded ghost that slides off in ~0.22s and is
        // never scrolled, so laying out the full body of a long note is wasted
        // work that stalls the animation start. A leading slice is visually
        // identical for the brief cross-fade. Slice first, then strip image
        // refs and formatting tags — the ghost shows the note's *rendered*
        // text, not raw markdown flashing mid-swipe.
        let ghostSource = text.count > 1500 ? String(text.prefix(1500)) : text
        let ghostText = QuickNoteBodyRenderer.plainPreviewText(from: ghostSource)
        return ScrollView {
            Text(ghostText.isEmpty ? " " : ghostText)
                .font(Font(nsFont as CTFont))
                .kerning(CGFloat(appearance.letterSpacing))
                .foregroundStyle(textColor.opacity(style == .paper ? 0.36 : 0.30))
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .lineSpacing(max(0, (appearance.lineHeightMultiplier - 1.0) * Double(nsFont.pointSize)))
                .padding(.top, insets.height)
                .padding(.leading, insets.width)
                .padding(.trailing, 30)
                .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .allowsHitTesting(false)
    }

    /// Corner radius of the visible note card. In-window overlays (browser,
    /// vault picker) clip to this so their dim scrim matches the card silhouette
    /// instead of bleeding into the window's transparent margin. Mirrors the
    /// value computed in `noteCard`.
    private func cardCornerRadius(for style: QuickNoteStyle) -> CGFloat {
        style == .prismGlass ? 30 : 28
    }

    private func syncDraft() {
        persistDraftTask?.cancel()
        draft.sync(note: currentNote)
    }

    private func scheduleDraftPersist(_ markdown: String) {
        guard let noteID = draft.noteID else { return }
        persistDraftTask?.cancel()
        // 60 ms (was 220 ms) is short enough that `jack restart` / pkill -x
        // (SIGTERM, which does NOT fire applicationWillTerminate) can't beat
        // the persist with freshly-typed text. Still long enough to coalesce
        // a typing burst (~16 ms per key) into ~3-4 keys per write.
        persistDraftTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            store.updateNoteBody(noteID, markdown: markdown)
        }
    }

    private func flushDraftPersist() {
        persistDraftTask?.cancel()
        guard let request = draft.flushRequest else { return }
        store.updateNoteBody(request.noteID, markdown: request.markdown)
    }

    private func handleIncomingImage(_ imageData: Data) {
        guard let noteID = store.quickNoteActiveNoteID else { return }

        Task { @MainActor in
            let choice = await QuickNoteImageImportPrompt.present(
                hostWindow: QuickNoteWindowManager.shared.hostWindow,
                ocrAvailable: store.settings.enableImageTextRecognition
            )
            guard !Task.isCancelled else { return }

            switch choice {
            case .cancelled:
                return
            case .embedImage:
                guard let imageID = store.saveQuickNoteImageAttachment(noteID, imageData: imageData) else {
                    showDropFeedback(.failed)
                    return
                }
                pendingImageInsertionID = imageID
            case .extractText:
                processDroppedImageOCR(imageData, noteID: noteID)
            }
        }
    }

    private func handleImageInsertionResult(imageID: UUID, didInsert: Bool) {
        if didInsert {
            flushDraftPersist()
            showDropFeedback(.imageEmbedded)
            return
        }

        guard let noteID = store.quickNoteActiveNoteID else {
            showDropFeedback(.failed)
            return
        }

        let imageBlock = QuickNoteImageMarkdown.imageBlock(imageID: imageID)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if store.appendTextToQuickNote(noteID, text: imageBlock, syncMirror: true) {
            persistDraftTask?.cancel()
            draft.sync(note: store.note(with: noteID))
            showDropFeedback(.imageEmbedded)
        } else {
            showDropFeedback(.failed)
        }
    }

    private func processDroppedImageOCR(_ imageData: Data, noteID: UUID) {
        guard shouldProcessQuickNoteDroppedImageOCR(settings: store.settings) else {
            showDropFeedback(.disabled)
            return
        }
        showDropFeedback(.recognizing, autoClear: false)

        Task { @MainActor in
            let outcome = await ImageTextRecognitionService.shared.recognize(
                imageData: imageData,
                configuration: store.quickNoteImageOCRConfiguration()
            )
            guard !Task.isCancelled else { return }

            switch outcome {
            case .success(let recognizedText):
                guard let recognizedText else {
                    showDropFeedback(.empty)
                    return
                }

                if store.appendTextToQuickNote(noteID, text: recognizedText, syncMirror: true) {
                    persistDraftTask?.cancel()
                    draft.sync(note: store.note(with: noteID))
                    showDropFeedback(.success)
                } else {
                    showDropFeedback(.empty)
                }
            case .skipped, .failed:
                showDropFeedback(.failed)
            }
        }
    }

    private func showDropFeedback(_ feedback: QuickNoteDropFeedback, autoClear: Bool = true) {
        dropFeedbackTask?.cancel()

        withAnimation(.easeOut(duration: 0.18)) {
            dropFeedback = feedback
        }

        guard autoClear else { return }
        dropFeedbackTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.18)) {
                dropFeedback = nil
            }
        }
    }

    private func navigate(by step: Int) {
        guard let currentID = store.quickNoteActiveNoteID else { return }
        flushDraftPersist()
        // Save the outgoing note's text, but defer the clipboard-history mirror
        // (a SwiftData save + clip refresh) off the swipe — it resyncs on window
        // close. Doing it here is heavy work right as the slide should start,
        // which is what made swiping feel sticky.
        store.updateNoteBody(currentID, markdown: draft.markdown, syncMirror: false)
        guard let targetNoteID = targetNoteID(from: currentID, step: step) else { return }

        if reduceMotion {
            commitNavigation(from: currentID, to: targetNoteID)
            return
        }

        transitionTask?.cancel()
        transitionTask = Task { @MainActor in
            let outgoingOffset: CGFloat = step > 0
                ? -QuickNoteSwipeMotion.travelDistance
                : QuickNoteSwipeMotion.travelDistance
            let incomingStart = -outgoingOffset

            previousDraft = draft.markdown
            previousOffset = 0
            previousOpacity = QuickNoteSwipeMotion.outgoingOpacity

            commitNavigation(from: currentID, to: targetNoteID)
            editorOffset = incomingStart
            editorOpacity = QuickNoteSwipeMotion.incomingOpacity

            withAnimation(
                .spring(
                    response: QuickNoteSwipeMotion.springResponse,
                    dampingFraction: QuickNoteSwipeMotion.springDampingFraction
                )
            ) {
                previousOffset = outgoingOffset
                previousOpacity = 0
                editorOffset = 0
                editorOpacity = 1
            }

            try? await Task.sleep(for: QuickNoteSwipeMotion.cleanupDelay)
            guard !Task.isCancelled else { return }
            previousDraft = ""
        }
    }

    private func targetNoteID(from currentID: UUID, step: Int) -> UUID? {
        let quickNotes = store.quickNotes
        guard let currentIndex = quickNotes.firstIndex(where: { $0.noteID == currentID }) else { return nil }

        let nextIndex = currentIndex + step
        if quickNotes.indices.contains(nextIndex) {
            return quickNotes[nextIndex].noteID
        }

        if step > 0 {
            return store.createNote(origin: .quickNote).noteID
        }

        return nil
    }

    private func commitNavigation(from currentID: UUID, to targetNoteID: UUID) {
        store.cleanupQuickNoteIfNeeded(currentID)
        store.quickNoteActiveNoteID = targetNoteID
        syncDraft()
    }

    // MARK: - Notes browser

    /// Persist the in-flight draft so the browser shows fresh titles/snippets,
    /// then reveal the list.
    private func presentVaultPicker() {
        withAnimation(.easeOut(duration: 0.16)) {
            isVaultPickerPresented = true
        }
    }

    /// Record which vault subfolder the current note belongs to. Phase 0 only
    /// stores the choice on the note; nothing is written to disk.
    private func assignVaultDestination(_ relativeFolder: String?) {
        guard let noteID = store.quickNoteActiveNoteID else { return }
        store.setNoteVaultDestination(noteID, relativeFolder: relativeFolder)
    }

    /// Open the system folder picker to choose the vault root, from the
    /// destination picker's empty state (when no vault is set yet).
    private func chooseVaultFolder() {
        if let url = NoteVaultBookmarkService.pickVaultFolder() {
            store.setNotesVault(url: url)
        }
    }

    private func presentBrowser() {
        flushDraftPersist()
        if let currentID = store.quickNoteActiveNoteID {
            store.updateNoteBody(currentID, markdown: draft.markdown, syncMirror: true)
        }
        withAnimation(.easeOut(duration: 0.16)) {
            isBrowserPresented = true
        }
    }

    /// Jump straight to a note chosen in the browser. Reuses the same save +
    /// empty-note cleanup path as swipe navigation, minus the slide animation.
    private func jumpToNote(_ targetID: UUID) {
        guard let currentID = store.quickNoteActiveNoteID else {
            store.quickNoteActiveNoteID = targetID
            syncDraft()
            return
        }
        guard targetID != currentID else { return }
        flushDraftPersist()
        store.updateNoteBody(currentID, markdown: draft.markdown, syncMirror: true)
        commitNavigation(from: currentID, to: targetID)
    }

    /// Create a fresh quick note from the browser and open it.
    private func createAndOpenNote() {
        if let currentID = store.quickNoteActiveNoteID {
            flushDraftPersist()
            store.updateNoteBody(currentID, markdown: draft.markdown, syncMirror: true)
            let newNote = store.createNote(origin: .quickNote)
            commitNavigation(from: currentID, to: newNote.noteID)
        } else {
            let newNote = store.createNote(origin: .quickNote)
            store.quickNoteActiveNoteID = newNote.noteID
            syncDraft()
        }
        isBrowserPresented = false
    }

    /// Delete a note from the browser. If it was the active note, fall back to
    /// the newest remaining quick note (or a fresh blank one) so the editor is
    /// never left pointing at a deleted note.
    private func deleteNoteFromBrowser(_ targetID: UUID) {
        let wasCurrent = targetID == store.quickNoteActiveNoteID
        let fallbackID = wasCurrent
            ? store.quickNotes.last(where: { $0.noteID != targetID })?.noteID
            : nil

        store.deleteNote(targetID)
        guard wasCurrent else { return }

        if let fallbackID {
            store.quickNoteActiveNoteID = fallbackID
        } else {
            store.quickNoteActiveNoteID = store.createNote(origin: .quickNote).noteID
        }
        syncDraft()
    }
}

/// Resolves Quick Note chrome + editor ink from custom override, auto
/// backdrop contrast, or the style default — same layering logic as the menu
/// bar popover so icons stay readable on light Paper and dark Obsidian alike.
@MainActor
func quickNoteChromeInk(
    appearance: QuickNoteAppearance,
    hasLoadedWallpaper: Bool
) -> Color {
    if let hex = appearance.customTextColorHex, !hex.isEmpty {
        return Color(hex: hex)
    }
    if appearance.autoTextColorOnWallpaper {
        let luminance = appearance.estimatedPopoverBackdropLuminance()
        return ReadableInk.textColor(forBackdropLuminance: luminance)
    }
    return appearance.style.textColor
}
