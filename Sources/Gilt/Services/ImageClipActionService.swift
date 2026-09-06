import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class ImageClipActionService {
    static let shared = ImageClipActionService()

    private var activeSharingPicker: NSSharingServicePicker?
    private var lastExportedFileURL: URL?

    private init() {}

    func exportImage(
        _ imageData: Data,
        as format: ImageExportFormat,
        suggestedBaseName: String
    ) {
        guard let convertedData = Self.convert(imageData: imageData, to: format) else {
            showErrorAlert("Could not convert this image to \(format.displayName).")
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export Image"
        panel.nameFieldStringValue = "\(sanitizeFilenameBase(suggestedBaseName)).\(format.fileExtension)"
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard panel.runModalInFront() == .OK, let destinationURL = panel.url else { return }

        do {
            try convertedData.write(to: destinationURL, options: .atomic)
            lastExportedFileURL = destinationURL
        } catch {
            showErrorAlert("Could not save exported file. \(error.localizedDescription)")
        }
    }

    func copyImage(_ imageData: Data, as format: ImageExportFormat) {
        guard let convertedData = Self.convert(imageData: imageData, to: format) else {
            showErrorAlert("Could not convert this image to \(format.displayName) for copying.")
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let item = NSPasteboardItem()
        item.setData(convertedData, forType: format.pasteboardType)

        _ = pasteboard.writeObjects([item])
    }

    func quickShareImage(_ imageData: Data) {
        guard let image = NSImage(data: imageData) else {
            showErrorAlert("Could not prepare this image for sharing.")
            return
        }

        guard let contentView = NSApp.keyWindow?.contentView else {
            showErrorAlert("Could not find a window to present the share sheet.")
            return
        }

        let mouseScreenPoint = NSEvent.mouseLocation
        let mousePointInWindow = contentView.convert(mouseScreenPoint, from: nil)
        let anchorRect = NSRect(origin: mousePointInWindow, size: CGSize(width: 1, height: 1))

        let picker = NSSharingServicePicker(items: [image])
        activeSharingPicker = picker
        picker.show(relativeTo: anchorRect, of: contentView, preferredEdge: .minY)
    }

    func revealLastExportedFile() {
        guard let fileURL = lastExportedFileURL,
              FileManager.default.fileExists(atPath: fileURL.path)
        else {
            showErrorAlert("No exported file found yet. Export an image first.")
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    var hasLastExportedFile: Bool {
        guard let fileURL = lastExportedFileURL else { return false }
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    static func convert(imageData: Data, to format: ImageExportFormat) -> Data? {
        guard let image = NSImage(data: imageData) else { return nil }
        return convert(image: image, to: format)
    }

    static func convert(image: NSImage, to format: ImageExportFormat) -> Data? {
        switch format {
        case .png:
            return bitmapRepresentation(from: image)?.representation(using: .png, properties: [:])
        case .jpeg:
            return bitmapRepresentation(from: image)?.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
        case .tiff:
            return image.tiffRepresentation
        case .pdf:
            return pdfRepresentation(from: image)
        }
    }

    private static func bitmapRepresentation(from image: NSImage) -> NSBitmapImageRep? {
        guard let tiffData = image.tiffRepresentation,
              let imageRep = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }
        return imageRep
    }

    private static func pdfRepresentation(from image: NSImage) -> Data? {
        let bounds = NSRect(origin: .zero, size: image.size)
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else { return nil }

        var mediaBox = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        context.beginPDFPage(nil)

        NSGraphicsContext.saveGraphicsState()
        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = graphicsContext
        image.draw(in: bounds)
        NSGraphicsContext.restoreGraphicsState()

        context.endPDFPage()
        context.closePDF()

        return pdfData as Data
    }

    private func sanitizeFilenameBase(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = "image-export"
        let base = trimmed.isEmpty ? fallback : trimmed
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return base.components(separatedBy: invalid).joined(separator: "-")
    }

    private func showErrorAlert(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Image Action"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModalInFront()
    }
}

enum ImageExportFormat: CaseIterable {
    case png
    case jpeg
    case tiff
    case pdf

    var displayName: String {
        switch self {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        case .tiff: return "TIFF"
        case .pdf: return "PDF"
        }
    }

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .tiff: return "tiff"
        case .pdf: return "pdf"
        }
    }

    var contentType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .tiff: return .tiff
        case .pdf: return .pdf
        }
    }

    var pasteboardType: NSPasteboard.PasteboardType {
        NSPasteboard.PasteboardType(contentType.identifier)
    }
}
