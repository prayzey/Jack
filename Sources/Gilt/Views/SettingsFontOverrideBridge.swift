import AppKit
import SwiftUI

struct SettingsFontOverrideBridge: NSViewRepresentable {
    let selection: ClipboardFont

    func makeNSView(context: Context) -> SettingsFontOverrideView {
        let view = SettingsFontOverrideView()
        view.selection = selection
        return view
    }

    func updateNSView(_ nsView: SettingsFontOverrideView, context: Context) {
        nsView.selection = selection
        nsView.scheduleFontRefresh()
    }
}

final class SettingsFontOverrideView: NSView {
    var selection: ClipboardFont = .sfPro

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleFontRefresh()
    }

    override func layout() {
        super.layout()
        scheduleFontRefresh()
    }

    func scheduleFontRefresh() {
        DispatchQueue.main.async { [weak self] in
            self?.applyFonts()
        }
    }

    private func applyFonts() {
        guard let rootView = window?.contentView else { return }
        applyFontsRecursively(in: rootView)
    }

    private func applyFontsRecursively(in view: NSView) {
        if let textField = view as? NSTextField, let font = textField.font {
            let forceMonospaced = font.fontDescriptor.symbolicTraits.contains(.monoSpace)
            if let updatedFont = BundledFontCatalog.appKitFont(
                for: selection,
                matching: font,
                forceMonospaced: forceMonospaced
            ), textField.font?.fontName != updatedFont.fontName || textField.font?.pointSize != updatedFont.pointSize {
                textField.font = updatedFont
            }
        }

        if let button = view as? NSButton, let font = button.font {
            let forceMonospaced = font.fontDescriptor.symbolicTraits.contains(.monoSpace)
            if let updatedFont = BundledFontCatalog.appKitFont(
                for: selection,
                matching: font,
                forceMonospaced: forceMonospaced
            ), button.font?.fontName != updatedFont.fontName || button.font?.pointSize != updatedFont.pointSize {
                button.font = updatedFont
            }
        }

        if let popupButton = view as? NSPopUpButton, let font = popupButton.font {
            if let updatedFont = BundledFontCatalog.appKitFont(for: selection, matching: font),
               popupButton.font?.fontName != updatedFont.fontName || popupButton.font?.pointSize != updatedFont.pointSize {
                popupButton.font = updatedFont
            }
        }

        if let textView = view as? NSTextView, let font = textView.font {
            let forceMonospaced = font.fontDescriptor.symbolicTraits.contains(.monoSpace)
            if let updatedFont = BundledFontCatalog.appKitFont(
                for: selection,
                matching: font,
                forceMonospaced: forceMonospaced
            ), textView.font?.fontName != updatedFont.fontName || textView.font?.pointSize != updatedFont.pointSize {
                textView.font = updatedFont
            }
        }

        for child in view.subviews {
            applyFontsRecursively(in: child)
        }
    }
}
