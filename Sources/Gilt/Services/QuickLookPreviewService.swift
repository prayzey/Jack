import AppKit
import Foundation
@preconcurrency import QuickLookUI

struct QuickLookPreviewPayload {
    let url: URL
    let isTemporary: Bool
}

@MainActor
enum QuickLookPreviewFileBuilder {
    private static let folderName = "JackQuickLookPreview"

    static func payload(for clip: ClipItemModel) -> QuickLookPreviewPayload? {
        if let fileURL = existingFileURL(from: clip), FileManager.default.fileExists(atPath: fileURL.path) {
            return QuickLookPreviewPayload(url: fileURL, isTemporary: false)
        }

        switch clip.clipType {
        case .image:
            guard let imageData = clip.imageData,
                  let pngData = ImageClipActionService.convert(imageData: imageData, to: .png)
            else { return nil }
            return writeTemporaryData(
                pngData,
                named: "clip-\(clip.clipID.uuidString).png"
            )
        case .text, .link, .audio, .color:
            let text = clip.textValue ?? clip.urlValue ?? clip.previewText
            guard !text.isEmpty else { return nil }
            guard let data = text.data(using: .utf8) else { return nil }
            return writeTemporaryData(
                data,
                named: "clip-\(clip.clipID.uuidString).txt"
            )
        }
    }

    private static func existingFileURL(from clip: ClipItemModel) -> URL? {
        guard let raw = clip.urlValue,
              let url = URL(string: raw),
              url.isFileURL
        else { return nil }
        return url
    }

    private static func writeTemporaryData(_ data: Data, named fileName: String) -> QuickLookPreviewPayload? {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent(folderName, isDirectory: true)
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(fileName)
            try data.write(to: url, options: .atomic)
            return QuickLookPreviewPayload(url: url, isTemporary: true)
        } catch {
            return nil
        }
    }
}

@MainActor
final class QuickLookPreviewService: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookPreviewService()

    nonisolated(unsafe) private var activePayloads: [QuickLookPreviewPayload] = []

    private override init() {}

    func preview(clip: ClipItemModel) -> Bool {
        guard let payload = QuickLookPreviewFileBuilder.payload(for: clip) else { return false }
        activePayloads = [payload]

        guard let panel = QLPreviewPanel.shared() else {
            cleanupTemporaryFiles()
            return false
        }

        panel.dataSource = self
        panel.delegate = self
        // Keep Quick Look above the dock-level tray window.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 2)
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        activePayloads.count
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard activePayloads.indices.contains(index) else { return nil }
        return activePayloads[index].url as NSURL
    }

    nonisolated func previewPanelWillClose(_ panel: QLPreviewPanel!) {
        cleanupTemporaryFiles()
    }

    nonisolated private func cleanupTemporaryFiles() {
        let temporaryURLs = activePayloads.filter(\.isTemporary).map(\.url)
        for url in temporaryURLs {
            try? FileManager.default.removeItem(at: url)
        }
        activePayloads = []
    }
}
