import AppKit
import Combine
import SwiftUI

/// Bridges the dictation coordinator and the recent-clips tray to the live
/// `NSTextView` inside the compose window.
///
/// The window manager owns one instance for the app's lifetime, so the text
/// the user composed survives closing and reopening the window — the live
/// editor is recreated on each show, but the controller keeps a snapshot.
///
/// All mutations go through `NSTextView`'s `shouldChangeText` / `didChangeText`
/// pair so a single Cmd+Z undoes a dictation insert or a clip insert the same
/// way it undoes typing.
@MainActor
final class DictationComposeController: ObservableObject {
    /// True whenever the editor holds non-whitespace text. Drives the enabled
    /// state of the Copy / Paste / Clear controls in the compose chrome.
    @Published private(set) var hasText: Bool = false
    /// Live character count for the footer. Republished on every edit.
    @Published private(set) var characterCount: Int = 0

    /// The live editor. Weak so closing the window can release the view
    /// hierarchy; the controller (and its `savedText` snapshot) outlives it.
    private weak var textView: NSTextView?
    /// Snapshot of the editor's text, refreshed on every change, so reopening
    /// the window restores what the user was composing.
    private var savedText: String = ""

    /// Called by `ComposeTextEditorView` when its `NSTextView` is created.
    func registerEditor(_ textView: NSTextView) {
        self.textView = textView
        // Restore text from a previous open of the window.
        if !savedText.isEmpty, textView.string != savedText {
            textView.string = savedText
        }
        refreshHasText()
    }

    /// Called by the editor's delegate on every change so the snapshot and the
    /// `hasText` flag stay in sync with what's on screen.
    func editorDidChange() {
        savedText = textView?.string ?? savedText
        refreshHasText()
    }

    var currentText: String { textView?.string ?? savedText }

    // MARK: - Insertion

    /// Insert dictated text at the caret. Adds a single leading space when the
    /// caret butts up against a non-space character so consecutive dictation
    /// bursts don't run together ("hello" + "world" → "hello world"). Casing
    /// and punctuation are already handled by the dictation pipeline, so we
    /// touch neither here.
    func insertDictation(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        insert(spacedIfNeeded(trimmed))
    }

    /// Insert a clipboard item verbatim at the caret. No smart spacing — a URL
    /// or code snippet must land exactly as it was copied.
    func insertClip(_ text: String) {
        guard !text.isEmpty else { return }
        insert(text)
    }

    func clear() {
        replaceAll(with: "")
    }

    // MARK: - Private

    private func spacedIfNeeded(_ text: String) -> String {
        guard let textView else { return text }
        let caret = textView.selectedRange().location
        guard caret > 0 else { return text }
        let ns = textView.string as NSString
        guard caret <= ns.length else { return text }
        let previous = ns.substring(with: NSRange(location: caret - 1, length: 1))
        if let scalar = previous.unicodeScalars.first,
           CharacterSet.whitespacesAndNewlines.contains(scalar) {
            return text
        }
        return " " + text
    }

    private func insert(_ string: String) {
        guard let textView else {
            // No live editor (window closed mid-flight) — keep the text in the
            // snapshot so nothing is lost when the window reopens.
            savedText += string
            refreshHasText()
            return
        }
        let range = textView.selectedRange()
        if textView.shouldChangeText(in: range, replacementString: string) {
            textView.textStorage?.replaceCharacters(in: range, with: string)
            textView.didChangeText()
        }
        let caret = NSRange(location: range.location + (string as NSString).length, length: 0)
        textView.setSelectedRange(caret)
        textView.scrollRangeToVisible(caret)
        // Inserting from the clips tray steals first responder; hand it back so
        // the user can keep dictating/typing without clicking into the editor.
        textView.window?.makeFirstResponder(textView)
        editorDidChange()
    }

    private func replaceAll(with string: String) {
        guard let textView else {
            savedText = string
            refreshHasText()
            return
        }
        let full = NSRange(location: 0, length: (textView.string as NSString).length)
        if textView.shouldChangeText(in: full, replacementString: string) {
            textView.textStorage?.replaceCharacters(in: full, with: string)
            textView.didChangeText()
        }
        editorDidChange()
    }

    private func refreshHasText() {
        let text = currentText
        let newValue = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if newValue != hasText { hasText = newValue }
        let count = text.count
        if count != characterCount { characterCount = count }
    }
}
