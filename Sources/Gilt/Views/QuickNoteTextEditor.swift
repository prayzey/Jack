import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
func makeQuickNoteEditorTextView() -> QuickNoteEditorTextView {
    let textStorage = NSTextStorage()
    let layoutManager = NSLayoutManager()
    // Force contiguous layout. TextKit defaults a scroll-view text view to
    // non-contiguous layout: it lays out only the visible rect and leaves the
    // document view's height an estimate, so lines added below the fold — e.g.
    // while holding Return to push text down — clip until a full relayout
    // (hide/show, which re-runs applyMarkdown → ensureLayout). Contiguous
    // layout keeps the view's height exact on every edit. Quick notes are
    // short, so the extra layout cost is negligible.
    layoutManager.allowsNonContiguousLayout = false
    let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
    textContainer.widthTracksTextView = true
    textContainer.lineFragmentPadding = 0

    textStorage.addLayoutManager(layoutManager)
    layoutManager.addTextContainer(textContainer)

    return QuickNoteEditorTextView(frame: .zero, textContainer: textContainer)
}

struct QuickNoteTypographyConfig: Equatable {
    var fontFamily: QuickNoteFontFamily
    var fontWeight: QuickNoteFontWeight
    var fontPointSize: CGFloat
    var lineHeightMultiplier: CGFloat
    var letterSpacing: CGFloat
    var paragraphSpacing: CGFloat
    var customFontPostScriptName: String?

    static let defaultConfig = QuickNoteTypographyConfig(
        fontFamily: .monospaced,
        fontWeight: .regular,
        fontPointSize: 16,
        lineHeightMultiplier: 1.15,
        letterSpacing: 0,
        paragraphSpacing: 6,
        customFontPostScriptName: nil
    )
}

@MainActor
func resolveQuickNoteFont(
    family: QuickNoteFontFamily,
    weight: QuickNoteFontWeight,
    pointSize: CGFloat,
    customPostScriptName: String?
) -> NSFont {
    let nsWeight = weight.nsFontWeight
    switch family {
    case .system:
        return NSFont.systemFont(ofSize: pointSize, weight: nsWeight)
    case .rounded:
        let base = NSFont.systemFont(ofSize: pointSize, weight: nsWeight)
        if let descriptor = base.fontDescriptor.withDesign(.rounded),
           let font = NSFont(descriptor: descriptor, size: pointSize) {
            return font
        }
        return base
    case .serif:
        let base = NSFont.systemFont(ofSize: pointSize, weight: nsWeight)
        if let descriptor = base.fontDescriptor.withDesign(.serif),
           let font = NSFont(descriptor: descriptor, size: pointSize) {
            return font
        }
        return base
    case .monospaced:
        return NSFont.monospacedSystemFont(ofSize: pointSize, weight: nsWeight)
    case .atkinsonHyperlegible:
        let psName = nsWeight.rawValue >= NSFont.Weight.semibold.rawValue
            ? "AtkinsonHyperlegible-Bold"
            : "AtkinsonHyperlegible-Regular"
        return NSFont(name: psName, size: pointSize)
            ?? NSFont.systemFont(ofSize: pointSize, weight: nsWeight)
    case .instrumentSans:
        let psName: String
        switch weight {
        case .light, .regular: psName = "InstrumentSans-Regular"
        case .medium: psName = "InstrumentSans-Medium"
        case .semibold: psName = "InstrumentSans-SemiBold"
        case .bold: psName = "InstrumentSans-Bold"
        }
        return NSFont(name: psName, size: pointSize)
            ?? NSFont.systemFont(ofSize: pointSize, weight: nsWeight)
    case .jetBrainsMono:
        let psName: String
        switch weight {
        case .light, .regular: psName = "JetBrainsMono-Regular"
        case .medium: psName = "JetBrainsMono-Medium"
        case .semibold: psName = "JetBrainsMono-SemiBold"
        case .bold: psName = "JetBrainsMono-Bold"
        }
        return NSFont(name: psName, size: pointSize)
            ?? NSFont.monospacedSystemFont(ofSize: pointSize, weight: nsWeight)
    case .custom:
        if let psName = customPostScriptName,
           let font = NSFont(name: psName, size: pointSize) {
            // Apply weight via NSFontManager when the file ships a single master.
            if weight != .regular {
                let mgr = NSFontManager.shared
                let trait: NSFontTraitMask = nsWeight.rawValue >= NSFont.Weight.semibold.rawValue
                    ? .boldFontMask
                    : []
                if !trait.isEmpty,
                   let bolded = mgr.font(withFamily: font.familyName ?? psName, traits: trait, weight: 9, size: pointSize) {
                    return bolded
                }
            }
            return font
        }
        return NSFont.systemFont(ofSize: pointSize, weight: nsWeight)
    }
}

struct QuickNoteTextEditor: NSViewRepresentable {
    @Binding var text: String
    /// Monotonic revision from the draft holder. Keystrokes deliberately don't
    /// invalidate any SwiftUI state, so when the note's content is replaced
    /// from outside the editor (note switch, auto-append) the bumped revision —
    /// read in `QuickNoteView.body` — is what forces this representable to
    /// update and run `applyMarkdown`. Never read directly; do not remove.
    var contentRevision: Int = 0
    @Binding var pendingImageInsertionID: UUID?
    var noteID: UUID?
    var attachmentsRoot: URL
    var style: QuickNoteStyle
    var typography: QuickNoteTypographyConfig
    /// When non-nil, overrides the style's default text colour — used for
    /// the user-picked custom colour and the wallpaper-aware auto pick.
    var textColorOverride: Color?
    var reverseSwipeDirection: Bool
    var onNavigate: (Int) -> Void
    var onImageImport: (Data) -> Void = { _ in }
    var onImageInsertionResult: (UUID, Bool) -> Void = { _, _ in }
    /// Reports the vertical scroll offset of the editor content (>= 0).
    /// Used by the surrounding view to fade out top-anchored chrome
    /// once the user scrolls past the very first line.
    var onScrollOffsetChange: (CGFloat) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            noteID: noteID,
            attachmentsRoot: attachmentsRoot
        )
    }

    func makeNSView(context: Context) -> QuickNoteEditorScrollView {
        let scrollView = QuickNoteEditorScrollView()
        let textView = makeQuickNoteEditorTextView()

        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        context.coordinator.applyMarkdown(
            text,
            style: style,
            typography: typography,
            textColorOverride: textColorOverride,
            fallbackWidth: scrollView.bounds.width
        )
        textView.backgroundColor = NSColor.clear
        textView.drawsBackground = false
        textView.isRichText = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [NSView.AutoresizingMask.width]
        textView.textContainerInset = style.editorInsets
        textView.minSize = NSSize.zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        if let textContainer = textView.textContainer {
            textContainer.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
            textContainer.widthTracksTextView = true
            textContainer.lineFragmentPadding = 0
        }

        textView.onNavigate = onNavigate
        textView.onImageImport = onImageImport

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scrollView.documentView = textView
        scrollView.quickNoteTextView = textView
        scrollView.onNavigate = onNavigate
        scrollView.reverseSwipeDirection = reverseSwipeDirection
        scrollView.onScrollOffsetChange = onScrollOffsetChange
        scrollView.installScrollOffsetObserver()

        DispatchQueue.main.async { [weak scrollView] in
            guard let scrollView else { return }
            _ = scrollView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ nsView: QuickNoteEditorScrollView, context: Context) {
        nsView.onNavigate = onNavigate
        nsView.reverseSwipeDirection = reverseSwipeDirection
        nsView.onScrollOffsetChange = onScrollOffsetChange
        nsView.quickNoteTextView?.onNavigate = onNavigate
        nsView.quickNoteTextView?.onImageImport = onImageImport

        context.coordinator.noteID = noteID
        context.coordinator.attachmentsRoot = attachmentsRoot
        context.coordinator.textView = nsView.quickNoteTextView

        if let textView = nsView.quickNoteTextView {
            let insets = style.editorInsets
            if textView.textContainerInset != insets {
                textView.textContainerInset = insets
            }

            if context.coordinator.lastAppliedMarkdown != text {
                context.coordinator.applyMarkdown(
                    text,
                    style: style,
                    typography: typography,
                    textColorOverride: textColorOverride,
                    fallbackWidth: nsView.bounds.width
                )
            } else {
                context.coordinator.applyStyleIfNeeded(
                    style: style,
                    typography: typography,
                    textColorOverride: textColorOverride
                )
            }
        }

        if let imageID = pendingImageInsertionID,
           context.coordinator.markPendingImageInsertionHandled(imageID) {
            let inserted = context.coordinator.insertEmbeddedImage(
                imageID,
                style: style,
                typography: typography,
                textColorOverride: textColorOverride,
                fallbackWidth: nsView.bounds.width
            )
            if pendingImageInsertionID == imageID {
                pendingImageInsertionID = nil
            }
            onImageInsertionResult(imageID, inserted)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String
        var noteID: UUID?
        var attachmentsRoot: URL
        weak var textView: QuickNoteEditorTextView?
        var lastAppliedMarkdown = ""
        private var handledPendingImageInsertionIDs: Set<UUID> = []
        private var lastStyleSignature = ""

        init(
            text: Binding<String>,
            noteID: UUID?,
            attachmentsRoot: URL
        ) {
            _text = text
            self.noteID = noteID
            self.attachmentsRoot = attachmentsRoot
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let markdown = QuickNoteBodyRenderer.markdown(from: textView.attributedString())
            guard markdown != text else { return }
            lastAppliedMarkdown = markdown
            text = markdown
        }

        func markPendingImageInsertionHandled(_ imageID: UUID) -> Bool {
            handledPendingImageInsertionIDs.insert(imageID).inserted
        }

        func applyMarkdown(
            _ markdown: String,
            style: QuickNoteStyle,
            typography: QuickNoteTypographyConfig,
            textColorOverride: Color?,
            fallbackWidth: CGFloat
        ) {
            guard let textView else { return }
            let selectedRange = textView.selectedRange()
            let baseAttributes = baseTextAttributes(
                style: style,
                typography: typography,
                textColorOverride: textColorOverride
            )
            let maxImageWidth = QuickNoteTextLayoutSupport.resolvedMaxImageWidth(
                for: textView,
                fallbackWidth: fallbackWidth
            )
            let rendered: NSAttributedString
            if let noteID {
                rendered = QuickNoteBodyRenderer.attributedString(
                    from: markdown,
                    noteID: noteID,
                    attachmentsRoot: attachmentsRoot,
                    baseAttributes: baseAttributes,
                    maxImageWidth: maxImageWidth
                )
            } else {
                rendered = NSAttributedString(string: markdown, attributes: baseAttributes)
            }

            textView.breakUndoCoalescing()
            textView.textStorage?.setAttributedString(rendered)
            // Replacing the whole content invalidates every range the undo
            // stack recorded; keeping them lets Cmd+Z replay another note's
            // edits into this one at stale offsets. Drop the stack instead.
            textView.undoManager?.removeAllActions()
            textView.typingAttributes = baseAttributes
            // The saved selection came from different content; clamp it so a
            // shorter replacement can't park the cursor out of bounds.
            let location = min(selectedRange.location, rendered.length)
            let length = min(selectedRange.length, rendered.length - location)
            textView.setSelectedRange(NSRange(location: location, length: length))
            lastAppliedMarkdown = markdown
            lastStyleSignature = styleSignature(
                style: style,
                typography: typography,
                textColorOverride: textColorOverride
            )
            QuickNoteTextLayoutSupport.invalidateLayout(in: textView)
        }

        func applyStyleIfNeeded(
            style: QuickNoteStyle,
            typography: QuickNoteTypographyConfig,
            textColorOverride: Color?
        ) {
            let signature = styleSignature(
                style: style,
                typography: typography,
                textColorOverride: textColorOverride
            )
            guard signature != lastStyleSignature, let textView else { return }
            lastStyleSignature = signature

            let baseAttributes = baseTextAttributes(
                style: style,
                typography: typography,
                textColorOverride: textColorOverride
            )
            textView.font = baseAttributes[.font] as? NSFont
            textView.textColor = baseAttributes[.foregroundColor] as? NSColor
            textView.insertionPointColor = NSColor(style.insertionColor)
            textView.defaultParagraphStyle = baseAttributes[.paragraphStyle] as? NSParagraphStyle
            textView.selectedTextAttributes = [
                .backgroundColor: NSColor(style.insertionColor.opacity(0.22)),
                .foregroundColor: baseAttributes[.foregroundColor] as? NSColor ?? .white
            ]
            textView.typingAttributes = baseAttributes
            QuickNoteBodyRenderer.refreshNonAttachmentAttributes(
                in: textView.textStorage,
                baseAttributes: baseAttributes
            )
        }

        @discardableResult
        func insertEmbeddedImage(
            _ imageID: UUID,
            style: QuickNoteStyle,
            typography: QuickNoteTypographyConfig,
            textColorOverride: Color?,
            fallbackWidth: CGFloat
        ) -> Bool {
            guard let textView, let noteID else { return false }
            guard let imageData = NoteImageAttachmentStore.load(
                imageID: imageID,
                noteID: noteID,
                root: attachmentsRoot
            ),
            let image = NoteImageAttachmentStore.loadedDisplayImage(from: imageData) else { return false }

            let baseAttributes = baseTextAttributes(
                style: style,
                typography: typography,
                textColorOverride: textColorOverride
            )
            let attachment = QuickNoteImageTextAttachment(
                imageID: imageID,
                image: image,
                maxWidth: QuickNoteTextLayoutSupport.resolvedMaxImageWidth(
                    for: textView,
                    fallbackWidth: fallbackWidth
                )
            )
            let fragment = NSMutableAttributedString(attachment: attachment)
            fragment.insert(NSAttributedString(string: "\n\n", attributes: baseAttributes), at: 0)
            fragment.append(NSAttributedString(string: "\n\n", attributes: baseAttributes))

            let selectedRange = textView.selectedRange()
            // Route through shouldChangeText/didChangeText so the insertion is
            // a proper undoable edit — a raw storage mutation leaves the undo
            // stack pointing at stale ranges and Cmd+Z corrupts the note.
            guard textView.shouldChangeText(in: selectedRange, replacementString: fragment.string) else {
                return false
            }
            textView.textStorage?.beginEditing()
            textView.textStorage?.replaceCharacters(in: selectedRange, with: fragment)
            textView.textStorage?.endEditing()
            textView.didChangeText()
            textView.typingAttributes = baseAttributes
            QuickNoteTextLayoutSupport.invalidateLayout(in: textView)

            let markdown = QuickNoteBodyRenderer.markdown(from: textView.attributedString())
            lastAppliedMarkdown = markdown
            text = markdown
            return true
        }

        private func styleSignature(
            style: QuickNoteStyle,
            typography: QuickNoteTypographyConfig,
            textColorOverride: Color?
        ) -> String {
            var parts: [String] = []
            parts.append(style.rawValue)
            parts.append(typography.fontFamily.rawValue)
            parts.append(typography.fontWeight.rawValue)
            parts.append(String(describing: typography.fontPointSize))
            parts.append(String(describing: typography.lineHeightMultiplier))
            parts.append(String(describing: typography.letterSpacing))
            parts.append(String(describing: typography.paragraphSpacing))
            parts.append(typography.customFontPostScriptName ?? "")
            if let textColorOverride {
                parts.append(String(describing: textColorOverride))
            }
            return parts.joined(separator: "|")
        }

        private func baseTextAttributes(
            style: QuickNoteStyle,
            typography: QuickNoteTypographyConfig,
            textColorOverride: Color?
        ) -> [NSAttributedString.Key: Any] {
            let font = resolveQuickNoteFont(
                family: typography.fontFamily,
                weight: typography.fontWeight,
                pointSize: typography.fontPointSize,
                customPostScriptName: typography.customFontPostScriptName
            )
            let textColor = NSColor(textColorOverride ?? style.textColor)

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineHeightMultiple = max(typography.lineHeightMultiplier, 0.5)
            paragraphStyle.paragraphSpacing = max(typography.paragraphSpacing, 0)
            paragraphStyle.lineBreakMode = .byWordWrapping

            return [
                .font: font,
                .foregroundColor: textColor,
                .kern: typography.letterSpacing,
                .paragraphStyle: paragraphStyle
            ]
        }
    }
}

final class QuickNoteEditorScrollView: NSScrollView {
    weak var quickNoteTextView: QuickNoteEditorTextView?
    var onNavigate: (Int) -> Void = { _ in }
    var reverseSwipeDirection = false
    var onScrollOffsetChange: (CGFloat) -> Void = { _ in }

    private var horizontalCarry: CGFloat = 0
    private var hasTriggeredSwipe = false
    // Lower threshold = the note flips with less finger travel, so the swipe
    // feels immediate instead of "delayed." Still high enough that an ordinary
    // diagonal scroll inside the text doesn't accidentally page to another note.
    private let swipeThreshold: CGFloat = 26
    private var hasInstalledScrollObserver = false
    private var lastReportedOffset: CGFloat = -1

    /// Wire up live scroll-offset reporting. Called once after the document view
    /// is set so the clip view exists and can flip on bounds notifications.
    func installScrollOffsetObserver() {
        guard !hasInstalledScrollObserver else { return }
        hasInstalledScrollObserver = true

        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleClipViewBoundsChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: contentView
        )

        // Report the initial offset so the caller starts in sync (0 on a fresh load).
        reportCurrentOffset()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleClipViewBoundsChange(_ notification: Notification) {
        reportCurrentOffset()
    }

    private func reportCurrentOffset() {
        let offset = max(0, contentView.bounds.origin.y)
        // Skip duplicate callbacks when the bounds notification fires for non-scroll reasons
        // (resize, content size change) without an actual scroll delta.
        guard abs(offset - lastReportedOffset) > 0.5 || lastReportedOffset < 0 else { return }
        lastReportedOffset = offset
        onScrollOffsetChange(offset)
    }

    override func scrollWheel(with event: NSEvent) {
        if shouldHandleHorizontalSwipe(event) {
            handleHorizontalSwipe(event)
            return
        }

        resetHorizontalSwipeIfNeeded(for: event)
        super.scrollWheel(with: event)
    }

    private func shouldHandleHorizontalSwipe(_ event: NSEvent) -> Bool {
        let horizontal = normalizedFingerDeltaX(for: event)
        let vertical = event.scrollingDeltaY
        return abs(horizontal) > abs(vertical) && abs(horizontal) > 0.5
    }

    private func handleHorizontalSwipe(_ event: NSEvent) {
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            horizontalCarry = 0
            hasTriggeredSwipe = false
        }

        guard event.momentumPhase.isEmpty else {
            resetHorizontalSwipeIfNeeded(for: event)
            return
        }

        horizontalCarry += normalizedFingerDeltaX(for: event)

        guard !hasTriggeredSwipe, abs(horizontalCarry) >= swipeThreshold else {
            resetHorizontalSwipeIfNeeded(for: event)
            return
        }

        hasTriggeredSwipe = true
        // Keep the default mapping aligned with the product gesture:
        // finger-left advances to the next/new note, and the settings toggle
        // can flip that if a specific trackpad or user preference feels opposite.
        let forwardStep = horizontalCarry > 0 ? 1 : -1
        onNavigate(reverseSwipeDirection ? -forwardStep : forwardStep)
        resetHorizontalSwipeIfNeeded(for: event)
    }

    private func resetHorizontalSwipeIfNeeded(for event: NSEvent) {
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) || event.momentumPhase.contains(.ended) {
            horizontalCarry = 0
            hasTriggeredSwipe = false
        }
    }

    private func normalizedFingerDeltaX(for event: NSEvent) -> CGFloat {
        event.isDirectionInvertedFromDevice ? -event.scrollingDeltaX : event.scrollingDeltaX
    }
}

final class QuickNoteEditorTextView: NSTextView {
    private static let supportedDroppedImageTypes: [NSPasteboard.PasteboardType] = [
        .fileURL,
        NSPasteboard.PasteboardType(UTType.png.identifier),
        NSPasteboard.PasteboardType(UTType.tiff.identifier),
        NSPasteboard.PasteboardType(UTType.jpeg.identifier),
        NSPasteboard.PasteboardType(UTType.heic.identifier),
        NSPasteboard.PasteboardType(UTType.gif.identifier)
    ]

    var onNavigate: (Int) -> Void = { _ in }
    var onImageImport: (Data) -> Void = { _ in }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        registerForDraggedTypes(Self.supportedDroppedImageTypes)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes(Self.supportedDroppedImageTypes)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if Self.droppedImageData(from: sender.draggingPasteboard) != nil {
            return .copy
        }

        return super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let imageData = Self.droppedImageData(from: sender.draggingPasteboard) else {
            return super.performDragOperation(sender)
        }

        onImageImport(imageData)
        return true
    }

    override func paste(_ sender: Any?) {
        if let imageData = Self.droppedImageData(from: NSPasteboard.general) {
            onImageImport(imageData)
            return
        }
        // Notes are Markdown-backed: the editor derives ALL styling (font, colour,
        // spacing) from the note's theme via typingAttributes, never from pasted
        // rich-text runs. A normal rich-text paste drags in the source app's own
        // foreground/background colours — copying from a dark-themed editor like
        // Cursor paints that editor's dark background behind the text. Force a
        // plain-text paste so pasted content adopts the note's own typography and
        // can never carry a foreign background box. pasteAsPlainText inserts using
        // the current typingAttributes and still participates in undo.
        pasteAsPlainText(sender)
    }

    override func insertNewline(_ sender: Any?) {
        super.insertNewline(sender)
        convertCompletedHorizontalRuleLineIfNeeded()
    }

    /// Forced contiguous layout (see makeQuickNoteEditorTextView) is NOT
    /// enough: TextKit stays lazy after processEditing, so an edit that shifts
    /// lines down — Enter mid-document is the canonical case — leaves every
    /// line below the cursor unlaid (`firstUnlaidCharacterIndex` stops right
    /// after the edit). Those lines vanish on screen until an unrelated full
    /// relayout (close/reopen). Every edit path funnels through
    /// `didChangeText`, so ensure the whole document is laid out here and
    /// re-fit the frame to the now-exact height. Quick notes are short; the
    /// full layout cost is negligible (same trade as contiguous layout).
    override func didChangeText() {
        super.didChangeText()
        if let layoutManager, let textContainer {
            layoutManager.ensureLayout(for: textContainer)
            sizeToFit()
        }
    }

    /// Notion-style: pressing Return at the end of a line consisting only of
    /// dashes/asterisks/underscores swaps that line for a horizontal-rule
    /// attachment. This lives in `insertNewline` — NOT in `textDidChange` —
    /// so it can only fire on an actual Return keystroke. It used to run on
    /// every text change with just a "cursor sits after a newline" check,
    /// which made Backspace at a line start silently convert a literal "---"
    /// two lines up.
    private func convertCompletedHorizontalRuleLineIfNeeded() {
        guard let storage = textStorage else { return }
        let plain = storage.string as NSString
        let cursor = selectedRange().location
        // Need at least "---\n" before the cursor.
        guard cursor >= 4, cursor <= plain.length else { return }

        let newlineIdx = cursor - 1
        guard plain.substring(with: NSRange(location: newlineIdx, length: 1)) == "\n" else { return }

        // Walk backward to the start of the line that ended at `newlineIdx`.
        var lineStart = newlineIdx
        while lineStart > 0 {
            let prev = plain.substring(with: NSRange(location: lineStart - 1, length: 1))
            if prev == "\n" { break }
            lineStart -= 1
        }

        let lineLength = newlineIdx - lineStart
        guard lineLength > 0 else { return }
        let lineText = plain.substring(with: NSRange(location: lineStart, length: lineLength))
        guard QuickNoteBodyRenderer.isHorizontalRuleLine(lineText) else { return }

        // Skip if the line already carries an attachment (defensive guard).
        if storage.attribute(.attachment, at: lineStart, effectiveRange: nil) != nil {
            return
        }

        let width = QuickNoteTextLayoutSupport.resolvedMaxImageWidth(
            for: self,
            fallbackWidth: bounds.width
        )
        let tint = textColor ?? .labelColor
        let attachment = QuickNoteHorizontalRuleAttachment(width: width, color: tint)
        let replacement = NSAttributedString(attachment: attachment)
        let replaceRange = NSRange(location: lineStart, length: lineLength)

        // Route through shouldChangeText/didChangeText so the conversion is a
        // proper undoable edit: one Cmd+Z restores the dashes instead of
        // replaying stale ranges and corrupting the note.
        guard shouldChangeText(in: replaceRange, replacementString: replacement.string) else { return }
        storage.beginEditing()
        storage.replaceCharacters(in: replaceRange, with: replacement)
        storage.endEditing()
        didChangeText()
        // Swapping the 3-char "---" run for a 1-char rule attachment changes the
        // line height, and under forced contiguous layout (see
        // testEditorUsesContiguousLayout) the lines BELOW the new rule are left
        // unlaid by didChangeText() alone — they vanish until an unrelated
        // relayout. Force a full glyph/layout invalidation here, mirroring
        // insertEmbeddedImage, so content below the rule stays visible.
        QuickNoteTextLayoutSupport.invalidateLayout(in: self)

        // Keep the cursor where it was — right after the trailing newline —
        // adjusted for the length delta (dashes removed → 1-char attachment).
        let delta = replacement.length - replaceRange.length
        setSelectedRange(NSRange(location: max(0, cursor + delta), length: 0))
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let step = quickNoteCommandNavigationStep(
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags
        ) {
            onNavigate(step)
            return true
        }

        if applyInlineFormattingShortcut(event) {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    /// ⌘B / ⌘I / ⌘U toggle bold / italic / underline on the current selection,
    /// or on subsequent typing when nothing is selected. The change flows through
    /// `didChangeText()` so the delegate persists it as `<b>/<i>/<u>` tags.
    private func applyInlineFormattingShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command else { return false }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "b": toggleInlineTrait(.bold); return true
        case "i": toggleInlineTrait(.italic); return true
        case "u": toggleInlineTrait(.underline); return true
        default: return false
        }
    }

    private func toggleInlineTrait(_ trait: QuickNoteInlineFormatting.Traits) {
        guard let textStorage else { return }
        let range = selectedRange()

        // No selection: flip the trait on typing attributes so the next typed
        // characters carry it (matches how every rich editor behaves).
        guard range.length > 0 else {
            let enabled = QuickNoteInlineFormatting.traits(from: typingAttributes).contains(trait)
            typingAttributes = attributesToggling(trait, on: !enabled, in: typingAttributes)
            return
        }

        // Turn the trait off only when the whole selection already has it;
        // otherwise apply it to the entire selection.
        let turnOn = !selectionFullyHasTrait(trait, in: range)
        guard shouldChangeText(in: range, replacementString: nil) else { return }

        var updates: [(NSRange, [NSAttributedString.Key: Any])] = []
        textStorage.enumerateAttributes(in: range, options: []) { attrs, subRange, _ in
            updates.append((subRange, attributesToggling(trait, on: turnOn, in: attrs)))
        }
        textStorage.beginEditing()
        for (subRange, attrs) in updates {
            textStorage.setAttributes(attrs, range: subRange)
        }
        textStorage.endEditing()
        didChangeText()
    }

    private func selectionFullyHasTrait(_ trait: QuickNoteInlineFormatting.Traits, in range: NSRange) -> Bool {
        guard let textStorage else { return false }
        var all = true
        textStorage.enumerateAttributes(in: range, options: []) { attrs, _, stop in
            if !QuickNoteInlineFormatting.traits(from: attrs).contains(trait) {
                all = false
                stop.pointee = true
            }
        }
        return all
    }

    private func attributesToggling(
        _ trait: QuickNoteInlineFormatting.Traits,
        on: Bool,
        in attrs: [NSAttributedString.Key: Any]
    ) -> [NSAttributedString.Key: Any] {
        var result = attrs
        if trait == .underline {
            if on {
                result[.underlineStyle] = NSUnderlineStyle.single.rawValue
            } else {
                result.removeValue(forKey: .underlineStyle)
            }
            return result
        }

        let current = QuickNoteInlineFormatting.traits(from: attrs)
        let bold = trait == .bold ? on : current.contains(.bold)
        let italic = trait == .italic ? on : current.contains(.italic)
        let baseFont = (attrs[.font] as? NSFont) ?? font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        result[.font] = QuickNoteInlineFormatting.styledFont(base: baseFont, bold: bold, italic: italic)
        return result
    }

    private static func droppedImageData(from pasteboard: NSPasteboard) -> Data? {
        if let imageData = directImageData(from: pasteboard) {
            return imageData
        }

        guard let fileURL = droppedFileURL(from: pasteboard) else { return nil }
        guard isSupportedImageFile(fileURL) else { return nil }
        return try? Data(contentsOf: fileURL)
    }

    private static func directImageData(from pasteboard: NSPasteboard) -> Data? {
        for type in supportedDroppedImageTypes where type != .fileURL {
            if let data = pasteboard.data(forType: type), data.isEmpty == false {
                return data
            }
        }
        return nil
    }

    private static func droppedFileURL(from pasteboard: NSPasteboard) -> URL? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
           let firstURL = urls.first {
            return firstURL
        }

        guard let fileURLString = pasteboard.string(forType: .fileURL) else { return nil }
        return URL(string: fileURLString)
    }

    private static func isSupportedImageFile(_ url: URL) -> Bool {
        guard let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
            return false
        }
        return contentType.conforms(to: .image)
    }
}


extension QuickNoteStyle {
    /// Text-container insets for the live editor. The transition snapshot in
    /// QuickNoteView must use these same values or the cross-fade shifts layout.
    var editorInsets: NSSize {
        switch self {
        case .cleanCanvas:
            return NSSize(width: 34, height: 56)
        case .paper:
            return NSSize(width: 40, height: 68)
        case .obsidian:
            return NSSize(width: 32, height: 56)
        case .midnightGrid:
            return NSSize(width: 34, height: 58)
        case .prismGlass:
            return NSSize(width: 34, height: 56)
        case .aurora:
            return NSSize(width: 34, height: 56)
        case .sunset:
            return NSSize(width: 34, height: 58)
        case .terminal:
            return NSSize(width: 30, height: 54)
        case .sakura:
            return NSSize(width: 38, height: 64)
        case .oceanic:
            return NSSize(width: 34, height: 56)
        case .parchment:
            return NSSize(width: 40, height: 66)
        case .cyberpunk:
            return NSSize(width: 32, height: 54)
        case .sage:
            return NSSize(width: 34, height: 58)
        case .graphite:
            return NSSize(width: 34, height: 56)
        case .lavender:
            return NSSize(width: 34, height: 58)
        case .blueprint:
            return NSSize(width: 34, height: 58)
        }
    }
}
