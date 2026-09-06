import Foundation

func quickNoteMergedBody(existing: String, incoming: String) -> String {
    let trimmedIncoming = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmedIncoming.isEmpty == false else { return existing }

    let trimmedExisting = existing.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmedExisting.isEmpty == false else { return trimmedIncoming }

    if existing.hasSuffix("\n\n") {
        return existing + trimmedIncoming
    }

    if existing.last?.isNewline == true {
        return existing + "\n" + trimmedIncoming
    }

    return existing + "\n\n" + trimmedIncoming
}

func quickNoteAutoAppendText(
    from captured: CapturedClip,
    sourceBundleID: String?,
    appBundleID: String? = Bundle.main.bundleIdentifier
) -> String? {
    guard sourceBundleID != appBundleID else { return nil }

    switch captured.type {
    case .text:
        return captured.textValue ?? captured.previewText
    case .link:
        return captured.urlValue ?? captured.textValue ?? captured.previewText
    case .audio:
        return captured.textValue ?? captured.previewText
    case .image:
        return nil
    default:
        return captured.textValue ?? captured.previewText
    }
}

func shouldProcessQuickNoteDroppedImageOCR(settings: AppSettings) -> Bool {
    settings.enableImageTextRecognition
}

extension ClipboardStore {
    func imageOCRConfiguration() -> ImageOCRConfiguration {
        ImageOCRConfiguration(
            recognitionLevelRaw: settings.ocrRecognitionLevelRaw,
            minimumTextHeight: settings.ocrMinimumTextHeight,
            maxImageMegapixels: settings.ocrMaxImageMegapixels,
            maxImageBytes: settings.ocrMaxImageBytes,
            recognitionLanguages: settings.ocrRecognitionLanguages
        )
    }

    func quickNoteImageOCRConfiguration() -> ImageOCRConfiguration {
        ImageOCRConfiguration(
            recognitionLevelRaw: "accurate",
            minimumTextHeight: settings.ocrMinimumTextHeight,
            maxImageMegapixels: settings.ocrMaxImageMegapixels,
            maxImageBytes: settings.ocrMaxImageBytes,
            recognitionLanguages: settings.ocrRecognitionLanguages
        )
    }

    @discardableResult
    func appendTextToQuickNote(_ noteID: UUID, text: String, syncMirror: Bool = true) -> Bool {
        guard let note = note(with: noteID) else { return false }
        let mergedBody = quickNoteMergedBody(existing: note.bodyMarkdown, incoming: text)
        guard mergedBody != note.bodyMarkdown else { return false }
        updateNoteBody(noteID, markdown: mergedBody, syncMirror: syncMirror)
        return true
    }

    func saveQuickNoteImageAttachment(_ noteID: UUID, imageData: Data) -> UUID? {
        NoteImageAttachmentStore.save(
            imageData: imageData,
            noteID: noteID,
            root: noteImageAttachmentsRoot
        )
    }

    func removeNoteImageAttachments(for noteID: UUID) {
        NoteImageAttachmentStore.removeNoteAttachments(
            noteID: noteID,
            root: noteImageAttachmentsRoot
        )
    }

    func appendCapturedClipboardToQuickNoteIfNeeded(_ captured: CapturedClip, sourceBundleID: String?) {
        guard settings.quickNoteAutoPasteFromClipboard else { return }
        guard let noteID = quickNoteActiveNoteID else { return }
        guard let text = quickNoteAutoAppendText(from: captured, sourceBundleID: sourceBundleID) else { return }
        _ = appendTextToQuickNote(noteID, text: text, syncMirror: true)
    }
}
