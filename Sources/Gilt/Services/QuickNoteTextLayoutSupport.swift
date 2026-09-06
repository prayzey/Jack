import AppKit

@MainActor
enum QuickNoteTextLayoutSupport {
    static func resolvedMaxImageWidth(for textView: NSTextView, fallbackWidth: CGFloat = 420) -> CGFloat {
        let containerWidth = textView.textContainer?.containerSize.width ?? 0
        let viewWidth = textView.bounds.width
        let referenceWidth = max(containerWidth, viewWidth, fallbackWidth)
        return max(120, referenceWidth - 72)
    }

    static func invalidateLayout(in textView: NSTextView) {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        // Invalidate FIRST, ensure AFTER — the end state must be a fully
        // laid-out document. The previous ensure-then-invalidate order left
        // everything dirty on exit, deferring relayout to whenever drawing
        // happened to ask, which is exactly the lazy gap that lets lines
        // below an edit vanish until the note is closed and reopened.
        let length = textView.textStorage?.length ?? 0
        if length > 0 {
            let fullRange = NSRange(location: 0, length: length)
            layoutManager.invalidateGlyphs(forCharacterRange: fullRange, changeInLength: 0, actualCharacterRange: nil)
            layoutManager.invalidateLayout(forCharacterRange: fullRange, actualCharacterRange: nil)
        }
        layoutManager.ensureLayout(for: textContainer)
        textView.sizeToFit()
        textView.needsDisplay = true
    }
}
