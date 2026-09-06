import Foundation

/// Phase 1 of Obsidian vault sync: notes that have a `vaultRelativeFolder` are
/// written out as `.md` files (gilt frontmatter + image export). Debounced and
/// run off the main thread; the in-app note model is the source of truth here.
/// Phase 2 (import) and Phase 3 (conflicts/deletes) build on these records.
extension ClipboardStore {
    /// Vault-level folder holding exported note images, referenced from notes as
    /// Obsidian embeds `![[<uuid>.png]]`. `nonisolated` so off-main reconcile/IO
    /// can read it.
    nonisolated static let vaultAssetsFolder = "_jack-assets"

    // MARK: - Scheduling

    /// Debounced: queue a note for vault export, coalescing rapid edits.
    func scheduleVaultSync(for noteID: UUID) {
        guard hasNotesVault else { return }
        pendingVaultSyncNoteIDs.insert(noteID)
        pendingVaultSyncWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingVaultSyncWorkItem = nil
            let ids = self.pendingVaultSyncNoteIDs
            self.pendingVaultSyncNoteIDs = []
            for id in ids { self.syncNoteToVault(id) }
        }
        pendingVaultSyncWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    /// Export every note that has a vault destination — used right after a vault
    /// is chosen so already-assigned notes populate it.
    func syncAllNotesToVault() {
        guard hasNotesVault else { return }
        for note in notes where note.vaultRelativeFolder != nil {
            syncNoteToVault(note.noteID)
        }
    }

    /// Flush pending vault writes synchronously (app termination).
    func flushPendingVaultWrites() {
        guard pendingVaultSyncWorkItem != nil || !pendingVaultSyncNoteIDs.isEmpty else { return }
        pendingVaultSyncWorkItem?.cancel()
        pendingVaultSyncWorkItem = nil
        let ids = pendingVaultSyncNoteIDs
        pendingVaultSyncNoteIDs = []
        for id in ids { syncNoteToVault(id, synchronous: true) }
    }

    // MARK: - Per-note export

    func syncNoteToVault(_ noteID: UUID, synchronous: Bool = false) {
        guard hasNotesVault,
              let bookmark = settings.notesVaultBookmark,
              let note = notes.first(where: { $0.noteID == noteID }),
              let folder = note.vaultRelativeFolder else { return }

        let appBody = note.bodyMarkdown
        let contentHash = VaultNoteSerializer.contentHash(appBody: appBody)
        let existing = vaultSyncRecords[noteID]

        // Destination path follows the title for a readable Obsidian tree; the
        // note's identity is its jack-id, not the filename.
        let base = VaultFilename.sanitize(note.displayTitle)
        let taken = Set(vaultSyncRecords
            .filter { $0.key != noteID }
            .map { $0.value.vaultRelativePath.lowercased() })
        let targetPath = VaultFilename.resolve(
            base: base, inFolder: folder, taken: taken, ownPrevious: existing?.vaultRelativePath
        )

        // Skip if content and location already match the last sync.
        if let existing,
           existing.lastSyncedContentHash == contentHash,
           existing.vaultRelativePath.caseInsensitiveCompare(targetPath) == .orderedSame {
            return
        }

        let frontmatter = VaultNoteSerializer.Frontmatter(
            jackID: noteID, created: note.createdAt, updated: note.updatedAt
        )
        let fileContents = VaultNoteSerializer.fileContents(appBody: appBody, frontmatter: frontmatter)
        let (_, imageIDs) = VaultNoteSerializer.vaultBody(fromAppBody: appBody)
        let images: [VaultWriter.ImageCopy] = imageIDs.map { id in
            VaultWriter.ImageCopy(
                sourcePath: NoteImageAttachmentStore
                    .fileURL(imageID: id, noteID: noteID, root: noteImageAttachmentsRoot).path,
                vaultRelativePath: "\(Self.vaultAssetsFolder)/\(id.uuidString.lowercased()).png"
            )
        }
        let plan = VaultWriter.Plan(
            noteID: noteID,
            targetRelativePath: targetPath,
            previousRelativePath: existing?.vaultRelativePath,
            fileContents: fileContents,
            images: images
        )

        if synchronous {
            if let result = writeVaultPlan(plan, bookmark: bookmark) {
                applyVaultWriteResult(result, contentHash: contentHash)
            }
        } else {
            Task.detached(priority: .utility) {
                guard let result = ClipboardStore.writeVaultPlan(plan, bookmark: bookmark) else { return }
                await MainActor.run { self.applyVaultWriteResult(result, contentHash: contentHash) }
            }
        }
    }

    /// Run a write plan inside a security-scoped session. `nonisolated` so it can
    /// run on the detached task; returns nil if the vault is unreachable.
    nonisolated static func writeVaultPlan(_ plan: VaultWriter.Plan, bookmark: Data) -> VaultWriter.Result? {
        NoteVaultBookmarkService.withVaultAccess(bookmark) { url -> VaultWriter.Result? in
            try? VaultWriter.apply(plan, vaultURL: url)
        } ?? nil
    }

    private func writeVaultPlan(_ plan: VaultWriter.Plan, bookmark: Data) -> VaultWriter.Result? {
        ClipboardStore.writeVaultPlan(plan, bookmark: bookmark)
    }

    func applyVaultWriteResult(_ result: VaultWriter.Result, contentHash: String) {
        vaultSyncRecords[result.noteID] = VaultSyncRecord(
            vaultRelativePath: result.writtenRelativePath,
            lastSyncedContentHash: contentHash,
            lastSyncedFileModified: result.fileModified,
            lastWrittenByApp: Date()
        )
        persistNotesLibrary()
    }

    // MARK: - Removal (clear destination / delete note)

    /// Trash the vault file for a note and drop its sync record. Non-destructive
    /// — Trash is recoverable. Used when a destination is cleared or the note is
    /// deleted in the app.
    func removeVaultFile(for noteID: UUID) {
        guard let bookmark = settings.notesVaultBookmark,
              let record = vaultSyncRecords[noteID] else {
            vaultSyncRecords[noteID] = nil
            return
        }
        let path = record.vaultRelativePath
        vaultSyncRecords[noteID] = nil
        persistNotesLibrary()
        Task.detached(priority: .utility) {
            _ = NoteVaultBookmarkService.withVaultAccess(bookmark) { url in
                VaultWriter.trash(relativePath: path, vaultURL: url)
            }
        }
    }
}
