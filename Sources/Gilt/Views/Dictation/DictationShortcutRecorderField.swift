import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Like `ShortcutRecorderField` but accepts **any** macOS key — including the
/// modifiers themselves (Right Option, Fn, Caps Lock), the extended cluster
/// (Help/Home/End/PgUp/PgDn/ForwardDelete), and the function row beyond F12.
///
/// Differences from `ShortcutRecorderField`:
///   - Doesn't require a modifier in addition to the key — a naked Right
///     Option press records as the "hold Right Option" trigger.
///   - Listens to `flagsChanged` so the user can record a pure modifier
///     binding by tapping it once.
struct DictationShortcutRecorderField: NSViewRepresentable {
    @Binding var shortcut: DictationShortcut
    /// When set, the field shows this grey prompt instead of a key name —
    /// used when the binding holds a fallback value but the user hasn't
    /// actually chosen a key yet (e.g. ask-the-screen enabled but unbound).
    /// Passing nil means "render the bound shortcut normally."
    var placeholder: String? = nil
    var onCapture: (DictationShortcut) -> Void

    func makeNSView(context: Context) -> DictationShortcutCaptureTextField {
        let field = DictationShortcutCaptureTextField()
        field.onCapture = { captured in onCapture(captured) }
        field.placeholderPrompt = placeholder
        field.setShortcut(shortcut)
        return field
    }

    func updateNSView(_ nsView: DictationShortcutCaptureTextField, context: Context) {
        nsView.onCapture = { captured in onCapture(captured) }
        nsView.placeholderPrompt = placeholder
        nsView.setShortcut(shortcut)
    }
}

final class DictationShortcutCaptureTextField: NSTextField {
    var onCapture: ((DictationShortcut) -> Void)?
    /// Non-nil while the field should display a grey "unset" prompt rather
    /// than a real key name. Cleared the moment the user records a key.
    var placeholderPrompt: String?
    private var currentShortcut: DictationShortcut = .default
    private var flagsMonitorTrigger: DictationTriggerKind = .pushToTalk

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isEditable = false
        isBordered = true
        focusRingType = .default
        alignment = .right
        font = .systemFont(ofSize: NSFont.systemFontSize)
        lineBreakMode = .byTruncatingTail
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    func setShortcut(_ shortcut: DictationShortcut) {
        currentShortcut = shortcut
        flagsMonitorTrigger = shortcut.trigger
        // While editing (first responder) we always show the "Press any key…"
        // hint set in becomeFirstResponder — don't clobber it here.
        guard window?.firstResponder !== self else { return }
        if let prompt = placeholderPrompt {
            // Unset state: empty value + grey placeholder string.
            if !stringValue.isEmpty { stringValue = "" }
            placeholderString = prompt
        } else if stringValue != shortcut.displayString {
            stringValue = shortcut.displayString
        }
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            stringValue = "Press any key…"
        }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            // If the user focused but never recorded a key, fall back to the
            // grey prompt rather than the placeholder/default key name.
            if let prompt = placeholderPrompt {
                stringValue = ""
                placeholderString = prompt
            } else {
                stringValue = currentShortcut.displayString
            }
        }
        return resigned
    }

    override func keyDown(with event: NSEvent) {
        let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let modifiers = Self.carbonModifiers(from: modifierFlags)
        let captured = DictationShortcut(
            keyCode: UInt32(event.keyCode),
            modifiers: modifiers,
            trigger: flagsMonitorTrigger
        )
        commit(captured)
    }

    /// Pure-modifier presses arrive here. We accept a single tap as "bind to
    /// this modifier" using whichever trigger style the user has selected.
    override func flagsChanged(with event: NSEvent) {
        let keyCode = UInt32(event.keyCode)
        guard DictationKeyNames.isModifierKeyCode(keyCode) else { return }

        // Make sure this is a *press*, not a release: at least one bit in
        // `modifierFlags` must be set when a modifier is going down.
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isPress = flags.rawValue != 0

        guard isPress else { return }
        let captured = DictationShortcut(
            keyCode: keyCode,
            modifiers: 0,
            trigger: flagsMonitorTrigger
        )
        commit(captured)
    }

    private func commit(_ shortcut: DictationShortcut) {
        currentShortcut = shortcut
        // The user just chose a real key, so the unset prompt no longer applies.
        placeholderPrompt = nil
        placeholderString = nil
        stringValue = shortcut.displayString
        onCapture?(shortcut)
        window?.makeFirstResponder(nil)
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var output: UInt32 = 0
        if flags.contains(.command) { output |= UInt32(cmdKey) }
        if flags.contains(.shift) { output |= UInt32(shiftKey) }
        if flags.contains(.option) { output |= UInt32(optionKey) }
        if flags.contains(.control) { output |= UInt32(controlKey) }
        return output
    }
}
