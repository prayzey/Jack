import AppKit
import Foundation
import UniformTypeIdentifiers

enum NoteImageAttachmentStore {
    static let fileExtension = "png"
    static let minimumDisplayEdge: CGFloat = 64

    static func noteDirectory(noteID: UUID, root: URL) -> URL {
        root
            .appendingPathComponent(noteID.uuidString.lowercased(), isDirectory: true)
    }

    static func fileURL(imageID: UUID, noteID: UUID, root: URL) -> URL {
        noteDirectory(noteID: noteID, root: root)
            .appendingPathComponent("\(imageID.uuidString.lowercased()).\(fileExtension)")
    }

    @discardableResult
    static func save(
        imageData: Data,
        imageID: UUID = UUID(),
        noteID: UUID,
        root: URL,
        fileManager: FileManager = .default
    ) -> UUID? {
        guard let pngData = normalizedPNGData(from: imageData) else { return nil }

        let directory = noteDirectory(noteID: noteID, root: root)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = fileURL(imageID: imageID, noteID: noteID, root: root)
            try pngData.write(to: destination, options: .atomic)
            return imageID
        } catch {
            return nil
        }
    }

    static func load(
        imageID: UUID,
        noteID: UUID,
        root: URL,
        fileManager: FileManager = .default
    ) -> Data? {
        let url = fileURL(imageID: imageID, noteID: noteID, root: root)
        return fileManager.fileExists(atPath: url.path) ? try? Data(contentsOf: url) : nil
    }

    static func loadedDisplayImage(from imageData: Data) -> NSImage? {
        if let rep = NSBitmapImageRep(data: imageData) {
            let pixelSize = NSSize(width: max(rep.pixelsWide, 1), height: max(rep.pixelsHigh, 1))
            let image = NSImage(size: pixelSize)
            image.addRepresentation(rep)
            return image
        }

        guard let fallback = NSImage(data: imageData) else { return nil }
        let size = displaySize(for: fallback)
        guard size.width > 1, size.height > 1 else { return nil }
        return fallback
    }

    static func displaySize(for image: NSImage) -> NSSize {
        if let rep = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first {
            return NSSize(width: max(rep.pixelsWide, 1), height: max(rep.pixelsHigh, 1))
        }
        return NSSize(width: max(image.size.width, 1), height: max(image.size.height, 1))
    }

    static func fittedDisplaySize(for image: NSImage, maxWidth: CGFloat) -> NSSize {
        let source = displaySize(for: image)
        guard source.width > 0, source.height > 0 else {
            return NSSize(width: minimumDisplayEdge, height: minimumDisplayEdge)
        }

        let safeMaxWidth = max(maxWidth, minimumDisplayEdge)
        var width = source.width
        var height = source.height

        if width > safeMaxWidth {
            let scale = safeMaxWidth / width
            width = safeMaxWidth
            height = height * scale
        }

        let upscale = max(minimumDisplayEdge / width, minimumDisplayEdge / height, 1)
        if upscale > 1 {
            width *= upscale
            height *= upscale
        }

        return NSSize(width: width, height: height)
    }

    static func removeNoteAttachments(
        noteID: UUID,
        root: URL,
        fileManager: FileManager = .default
    ) {
        let directory = noteDirectory(noteID: noteID, root: root)
        try? fileManager.removeItem(at: directory)
    }

    static func normalizedPNGData(from imageData: Data) -> Data? {
        guard let image = loadedDisplayImage(from: imageData) else { return nil }
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}
