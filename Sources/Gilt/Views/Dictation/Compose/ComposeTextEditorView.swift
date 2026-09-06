import AppKit
import SwiftUI

/// Plain-text editing surface for the compose window, backed by `NSTextView`
/// so dictation results and clipboard items can be inserted at the caret with
/// full undo support — something SwiftUI's `TextEditor` can't expose.
///
/// It registers its `NSTextView` with the shared `DictationComposeController`
/// on creation; all insertion is driven imperatively through that controller.
struct ComposeTextEditorView: NSViewRepresentable {
    @ObservedObject var controller: DictationComposeController

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: 15)
        textView.textColor = NSColor.white.withAlphaComponent(0.92)
        textView.insertionPointColor = NSColor.white.withAlphaComponent(0.9)
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 14, height: 14)
        // The composed text is the deliverable — keep it verbatim. Smart
        // quotes / dashes would silently rewrite URLs and code the user pastes
        // in from the clips tray.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = false

        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        controller.registerEditor(textView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}

    /// `NSTextViewDelegate` is `@MainActor`-annotated in the AppKit SDK, so a
    /// plain `NSObject` coordinator can touch main-actor state directly here —
    /// same pattern as `QuickNoteTextEditor.Coordinator`.
    final class Coordinator: NSObject, NSTextViewDelegate {
        let controller: DictationComposeController

        init(controller: DictationComposeController) {
            self.controller = controller
        }

        func textDidChange(_ notification: Notification) {
            controller.editorDidChange()
        }
    }
}
