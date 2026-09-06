import AppKit
import Carbon.HIToolbox
import SwiftUI

struct ShortcutRecorderField: NSViewRepresentable {
    @Binding var shortcut: GlobalShortcut
    var onShortcutChange: (GlobalShortcut) -> Void

    func makeNSView(context: Context) -> ShortcutCaptureTextField {
        let field = ShortcutCaptureTextField()
        field.onShortcutCapture = { captured in
            onShortcutChange(captured)
        }
        field.setShortcut(shortcut)
        return field
    }

    func updateNSView(_ nsView: ShortcutCaptureTextField, context: Context) {
        nsView.onShortcutCapture = { captured in
            onShortcutChange(captured)
        }
        nsView.setShortcut(shortcut)
    }
}

final class ShortcutCaptureTextField: NSTextField {
    var onShortcutCapture: ((GlobalShortcut) -> Void)?
    private var currentShortcut: GlobalShortcut = .default

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isEditable = false
        isBordered = true
        focusRingType = .default
        alignment = .right
        font = .systemFont(ofSize: NSFont.systemFontSize)
        lineBreakMode = .byTruncatingTail
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    func setShortcut(_ shortcut: GlobalShortcut) {
        currentShortcut = shortcut
        if stringValue != shortcut.displayString {
            stringValue = shortcut.displayString
        }
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            stringValue = "Type shortcut..."
        }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            stringValue = currentShortcut.displayString
        }
        return resigned
    }

    override func keyDown(with event: NSEvent) {
        let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let modifiers = ShortcutCaptureTextField.carbonModifiers(from: modifierFlags)

        guard modifiers != 0 || GlobalShortcut.isFunctionKey(UInt32(event.keyCode)) else {
            NSSound.beep()
            return
        }

        guard ShortcutCaptureTextField.isModifierKeyCode(event.keyCode) == false else {
            return
        }

        let captured = GlobalShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        currentShortcut = captured
        stringValue = captured.displayString
        onShortcutCapture?(captured)
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

    private static func isModifierKeyCode(_ keyCode: UInt16) -> Bool {
        let modifierCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        return modifierCodes.contains(keyCode)
    }
}
