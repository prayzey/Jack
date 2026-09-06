import AppKit
import Foundation
import UniformTypeIdentifiers

enum StripDragItem: Equatable {
    case clip(UUID)
    case separator(UUID)

    init?(serializedValue: String) {
        if let clipID = UUID(uuidString: serializedValue) {
            self = .clip(clipID)
            return
        }

        let separatorPrefix = "separator:"
        guard serializedValue.hasPrefix(separatorPrefix) else { return nil }
        let rawID = String(serializedValue.dropFirst(separatorPrefix.count))
        guard let separatorID = UUID(uuidString: rawID) else { return nil }
        self = .separator(separatorID)
    }

    var id: UUID {
        switch self {
        case .clip(let id), .separator(let id):
            return id
        }
    }

    var serializedValue: String {
        switch self {
        case .clip(let id):
            return id.uuidString
        case .separator(let id):
            return "separator:\(id.uuidString)"
        }
    }
}

enum ClipDragItemProvider {
    // Anchor to `.data` so SwiftUI can resolve this UTI even when the running
    // binary lacks an Info.plist `UTExportedTypeDeclarations` entry (e.g. when
    // launched via `swift run` or Xcode's play button). Without a parent type,
    // SwiftUI's drop pipeline logs "Failed to instantiate a content type" and
    // rejects every conformance check, breaking clip-into-folder drops.
    static let internalDragType = UTType(
        exportedAs: "com.praisedev.gilt.strip-drag-item",
        conformingTo: .data
    )

    static func makeProvider(for clip: ClipItemModel) -> NSItemProvider {
        let provider = NSItemProvider()
        let suggestedBaseName = suggestedBaseName(for: clip)
        provider.suggestedName = suggestedBaseName

        registerInternalDragItem(.clip(clip.clipID), on: provider)
        registerExternalRepresentations(for: clip, on: provider)

        guard clip.clipType == .image,
              let imageData = clip.imageData,
              !imageData.isEmpty else {
            return provider
        }

        let filename = suggestedFilename(baseName: suggestedBaseName)

        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.png.identifier,
            visibility: .all
        ) { completion in
            completion(imageData, nil)
            return nil
        }

        provider.registerFileRepresentation(
            forTypeIdentifier: UTType.png.identifier,
            fileOptions: [],
            visibility: .all
        ) { completion in
            let fileURL = temporaryImageURL(filename: filename)

            do {
                try imageData.write(to: fileURL, options: .atomic)
                completion(fileURL, false, nil)
            } catch {
                completion(nil, false, error)
            }

            return nil
        }

        return provider
    }

    static func makeProvider(for separator: FolderSeparatorModel) -> NSItemProvider {
        let provider = NSItemProvider()
        let trimmedLabel = separator.label.trimmingCharacters(in: .whitespacesAndNewlines)
        provider.suggestedName = trimmedLabel.isEmpty ? L10n.string("folder.separator.default", default: "Section") : trimmedLabel
        registerInternalDragItem(.separator(separator.separatorID), on: provider)
        return provider
    }

    static func suggestedFilename(for clip: ClipItemModel) -> String {
        suggestedFilename(baseName: suggestedBaseName(for: clip))
    }

    private static func suggestedFilename(baseName: String) -> String {
        "\(baseName).png"
    }

    private static func temporaryImageURL(filename: String) -> URL {
        let uniquePrefix = UUID().uuidString
        let uniqueFilename = "\(uniquePrefix)-\(filename)"
        return FileManager.default.temporaryDirectory.appendingPathComponent(uniqueFilename)
    }

    private static func registerInternalDragItem(_ dragItem: StripDragItem, on provider: NSItemProvider) {
        // Keep Jack's internal drag token on a private UTType so external text fields
        // never mistake a UUID tracking value for the clip's real contents.
        provider.registerDataRepresentation(
            forTypeIdentifier: internalDragType.identifier,
            visibility: .ownProcess
        ) { completion in
            completion(dragItem.serializedValue.data(using: .utf8), nil)
            return nil
        }
    }

    private static func registerExternalRepresentations(for clip: ClipItemModel, on provider: NSItemProvider) {
        if let plainText = externalPlainText(for: clip) {
            provider.registerObject(plainText as NSString, visibility: .all)
        }

        guard clip.clipType == .link,
              let rawURL = clip.urlValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: rawURL) else {
            return
        }

        provider.registerObject(url as NSURL, visibility: .all)
    }

    private static func externalPlainText(for clip: ClipItemModel) -> String? {
        let value = clip.textValue ?? clip.urlValue ?? clip.previewText
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : value
    }

    private static func suggestedBaseName(for clip: ClipItemModel) -> String {
        let candidates = [
            clip.title,
            clip.previewText,
            "jack-image"
        ]

        let rawValue = candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "jack-image"

        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let sanitized = rawValue
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let collapsed = sanitized.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )

        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: " .-_"))
        return trimmed.isEmpty ? "jack-image" : String(trimmed.prefix(80))
    }
}
