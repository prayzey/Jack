import AppKit

enum QuickNoteImageImportChoice: Equatable {
    case embedImage
    case extractText
    case cancelled
}

@MainActor
enum QuickNoteImageImportPrompt {
    static func present(
        hostWindow: NSWindow?,
        ocrAvailable: Bool
    ) async -> QuickNoteImageImportChoice {
        let alert = NSAlert()
        alert.messageText = L10n.string(
            "quickNote.imageImport.title",
            default: "Add this image?"
        )
        alert.informativeText = L10n.string(
            "quickNote.imageImport.message",
            default: "Insert the image in your note, or extract any text from it."
        )
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.string(
            "quickNote.imageImport.embed",
            default: "Insert image"
        ))
        alert.addButton(withTitle: L10n.string(
            "quickNote.imageImport.ocr",
            default: "Extract text"
        ))
        alert.addButton(withTitle: L10n.string(
            "quickNote.imageImport.cancel",
            default: "Cancel"
        ))

        if ocrAvailable == false {
            alert.buttons[safe: 1]?.isEnabled = false
        }

        // Never beginSheetModal here: the Quick Note window is borderless and
        // fully transparent, so an attached sheet renders its backing band as a
        // black rectangle down the middle of the note. App-modal via
        // runModalInFront still floats the alert above the elevated window.
        hostWindow?.makeKeyAndOrderFront(nil)
        return choice(for: alert.runModalInFront())
    }

    private static func choice(for response: NSApplication.ModalResponse) -> QuickNoteImageImportChoice {
        switch response {
        case .alertFirstButtonReturn:
            return .embedImage
        case .alertSecondButtonReturn:
            return .extractText
        default:
            return .cancelled
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
