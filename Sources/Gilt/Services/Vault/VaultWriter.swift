import Foundation

/// Performs the actual disk writes for vault sync. Stateless and `Sendable`-safe
/// so it runs off the main actor inside `NoteVaultBookmarkService.withVaultAccess`.
/// All inputs are value snapshots built on the main actor.
enum VaultWriter {
    /// A source image PNG to copy into the vault. The filename is the image's
    /// UUID, so identical names mean identical bytes (copy only if missing).
    struct ImageCopy: Sendable {
        let sourcePath: String
        let vaultRelativePath: String
    }

    struct Plan: Sendable {
        let noteID: UUID
        let targetRelativePath: String
        let previousRelativePath: String?
        let fileContents: String
        let images: [ImageCopy]
    }

    struct Result: Sendable {
        let noteID: UUID
        let writtenRelativePath: String
        let fileModified: Date?
    }

    /// Write the note file atomically, copy any new images, and remove our own
    /// previously-written file if the note moved (title/destination change).
    /// Creates intermediate directories lazily.
    static func apply(_ plan: Plan, vaultURL: URL, fileManager: FileManager = .default) throws -> Result {
        let targetURL = vaultURL.appendingPathComponent(plan.targetRelativePath)
        try fileManager.createDirectory(
            at: targetURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(plan.fileContents.utf8).write(to: targetURL, options: .atomic)

        for image in plan.images {
            let dest = vaultURL.appendingPathComponent(image.vaultRelativePath)
            guard !fileManager.fileExists(atPath: dest.path) else { continue }
            let source = URL(fileURLWithPath: image.sourcePath)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try? fileManager.createDirectory(
                at: dest.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? fileManager.copyItem(at: source, to: dest)
        }

        // The note moved: remove OUR old file (safe — it's the copy we wrote, and
        // the new copy already landed above).
        if let previous = plan.previousRelativePath,
           previous.caseInsensitiveCompare(plan.targetRelativePath) != .orderedSame {
            try? fileManager.removeItem(at: vaultURL.appendingPathComponent(previous))
        }

        let modified = (try? targetURL.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate
        return Result(noteID: plan.noteID, writtenRelativePath: plan.targetRelativePath, fileModified: modified)
    }

    /// Move a vault file to the system Trash — non-destructive deletion used
    /// when a note's destination is cleared or the note is deleted in the app.
    static func trash(relativePath: String, vaultURL: URL, fileManager: FileManager = .default) {
        let url = vaultURL.appendingPathComponent(relativePath)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try? fileManager.trashItem(at: url, resultingItemURL: nil)
    }

    /// Read the app-equivalent content hash + modification date of a vault file,
    /// without importing it. Used by the reconciler (Phase 2) to detect changes.
    static func fileFingerprint(relativePath: String, vaultURL: URL, fileManager: FileManager = .default) -> (hash: String, modified: Date?)? {
        let url = vaultURL.appendingPathComponent(relativePath)
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        let parsed = VaultNoteSerializer.parseFile(text)
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return (VaultNoteSerializer.contentHash(appBody: parsed.appBody), modified)
    }
}
