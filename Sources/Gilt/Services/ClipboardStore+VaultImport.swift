import Foundation

/// One note's external edit ready to apply to the app.
struct VaultImport: Sendable {
    let noteID: UUID
    let appBody: String
    let fileHash: String
    let fileModified: Date?
    let relativePath: String
}

/// What a reconcile pass found, split by required action.
struct VaultReconcileOutcome: Sendable {
    var imports: [VaultImport] = []
    var writeBacks: [UUID] = []
    var conflicts: [VaultImport] = []
    var deletedNoteIDs: [UUID] = []

    var isEmpty: Bool {
        imports.isEmpty && writeBacks.isEmpty && conflicts.isEmpty && deletedNoteIDs.isEmpty
    }
}

/// One tracked note's fingerprint, snapshotted on the main actor for the
/// off-main reconcile pass.
struct VaultReconcileItem: Sendable {
    let noteID: UUID
    let appBodyHash: String
    let record: VaultSyncRecord
}

/// Phase 2 (import external edits) + Phase 3 (conflicts, deletions) of vault sync.
extension ClipboardStore {
    // MARK: - Watcher lifecycle

    func startVaultWatcher() {
        guard let bookmark = settings.notesVaultBookmark else { return }
        stopVaultWatcher()
        guard let path = NoteVaultBookmarkService.withVaultAccess(bookmark, { $0.path }) else { return }
        let watcher = VaultWatcher(vaultPath: path) { [weak self] in
            Task { @MainActor in self?.reconcileVault(reason: "watcher") }
        }
        watcher.start()
        vaultWatcher = watcher
    }

    func stopVaultWatcher() {
        vaultWatcher?.stop()
        vaultWatcher = nil
    }

    // MARK: - Reconcile

    /// Compare every tracked note against its vault file and apply changes in
    /// both directions. Disk reads run off the main actor; results apply back on
    /// the main actor. Safe to call on launch, on foreground, and on watcher
    /// events — `isReconcilingVault` prevents overlap.
    func reconcileVault(reason: String) {
        guard let bookmark = settings.notesVaultBookmark, !vaultSyncRecords.isEmpty else { return }
        guard !isReconcilingVault else { return }
        isReconcilingVault = true

        let snapshot: [VaultReconcileItem] = notes.compactMap { note in
            guard let record = vaultSyncRecords[note.noteID] else { return nil }
            return VaultReconcileItem(
                noteID: note.noteID,
                appBodyHash: VaultNoteSerializer.contentHash(appBody: note.bodyMarkdown),
                record: record
            )
        }
        let root = noteImageAttachmentsRoot

        Task.detached(priority: .utility) {
            let outcome = ClipboardStore.reconcileFiles(snapshot: snapshot, bookmark: bookmark, attachmentsRoot: root)
            await MainActor.run {
                self.isReconcilingVault = false
                guard !outcome.isEmpty else { return }
                self.applyVaultImports(outcome)
            }
        }
    }

    nonisolated static func reconcileFiles(
        snapshot: [VaultReconcileItem],
        bookmark: Data,
        attachmentsRoot: URL
    ) -> VaultReconcileOutcome {
        NoteVaultBookmarkService.withVaultAccess(bookmark) { vaultURL -> VaultReconcileOutcome in
            var outcome = VaultReconcileOutcome()
            let fm = FileManager.default
            for item in snapshot {
                let fileURL = vaultURL.appendingPathComponent(item.record.vaultRelativePath)
                let fileText = try? String(contentsOf: fileURL, encoding: .utf8)
                let parsed = fileText.map { VaultNoteSerializer.parseFile($0) }
                let fileHash = parsed.map { VaultNoteSerializer.contentHash(appBody: $0.appBody) }
                let modified = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate
                let decision = VaultReconciler.decide(
                    appBodyHash: item.appBodyHash, fileHash: fileHash, record: item.record
                )
                switch decision {
                case .noChange:
                    break
                case .writeToVault:
                    outcome.writeBacks.append(item.noteID)
                case .importToApp:
                    if let parsed, let fileHash {
                        materializeImages(parsed.imageIDs, noteID: item.noteID, vaultURL: vaultURL, attachmentsRoot: attachmentsRoot, fileManager: fm)
                        outcome.imports.append(VaultImport(noteID: item.noteID, appBody: parsed.appBody, fileHash: fileHash, fileModified: modified, relativePath: item.record.vaultRelativePath))
                    }
                case .conflict:
                    if let parsed, let fileHash {
                        materializeImages(parsed.imageIDs, noteID: item.noteID, vaultURL: vaultURL, attachmentsRoot: attachmentsRoot, fileManager: fm)
                        outcome.conflicts.append(VaultImport(noteID: item.noteID, appBody: parsed.appBody, fileHash: fileHash, fileModified: modified, relativePath: item.record.vaultRelativePath))
                    }
                case .fileDeleted:
                    outcome.deletedNoteIDs.append(item.noteID)
                }
            }
            return outcome
        } ?? VaultReconcileOutcome()
    }

    /// Copy vault images referenced by an imported note into the app's local
    /// attachment store so the editor can render them.
    nonisolated static func materializeImages(
        _ imageIDs: [UUID], noteID: UUID, vaultURL: URL, attachmentsRoot: URL, fileManager: FileManager
    ) {
        for id in imageIDs {
            let dest = NoteImageAttachmentStore.fileURL(imageID: id, noteID: noteID, root: attachmentsRoot)
            guard !fileManager.fileExists(atPath: dest.path) else { continue }
            let source = vaultURL.appendingPathComponent("\(vaultAssetsFolder)/\(id.uuidString.lowercased()).png")
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try? fileManager.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fileManager.copyItem(at: source, to: dest)
        }
    }

    // MARK: - Apply

    func applyVaultImports(_ outcome: VaultReconcileOutcome) {
        for imp in outcome.imports { importVaultBody(imp) }
        for noteID in outcome.writeBacks { scheduleVaultSync(for: noteID) }
        handleVaultConflicts(outcome.conflicts)
        handleVaultDeletions(outcome.deletedNoteIDs)
    }

    /// Apply an external edit to a note WITHOUT re-triggering a vault write: we
    /// bypass `updateNoteBody` (so `scheduleVaultSync` isn't called) and close
    /// the feedback loop by setting the record's hash to the file's hash.
    private func importVaultBody(_ imp: VaultImport) {
        guard let index = notes.firstIndex(where: { $0.noteID == imp.noteID }) else { return }
        if notes[index].bodyMarkdown == imp.appBody {
            // Our own echo (we just wrote this) — refresh bookkeeping only.
            vaultSyncRecords[imp.noteID]?.lastSyncedContentHash = imp.fileHash
            vaultSyncRecords[imp.noteID]?.lastSyncedFileModified = imp.fileModified
            return
        }
        notes[index].bodyMarkdown = imp.appBody
        if notes[index].origin == .quickNote {
            notes[index].title = NoteMarkdown.displayTitle(for: imp.appBody)
        }
        notes[index].updatedAt = Date()
        vaultSyncRecords[imp.noteID] = VaultSyncRecord(
            vaultRelativePath: imp.relativePath,
            lastSyncedContentHash: imp.fileHash,
            lastSyncedFileModified: imp.fileModified,
            lastWrittenByApp: vaultSyncRecords[imp.noteID]?.lastWrittenByApp
        )
        persistNotesLibrary()
        refreshWorkspaceTitles()
    }

    // MARK: - Conflicts (keep-both, never lose data)

    private func handleVaultConflicts(_ conflicts: [VaultImport]) {
        guard !conflicts.isEmpty, let bookmark = settings.notesVaultBookmark else { return }
        let stamp = Self.conflictTimestamp()
        for c in conflicts {
            guard let index = notes.firstIndex(where: { $0.noteID == c.noteID }) else { continue }
            let appVersion = notes[index].bodyMarkdown

            // 1) Save the app's version as a sibling conflict file (fresh id so it
            //    isn't confused with the tracked note). Nothing is overwritten.
            let dir = (c.relativePath as NSString).deletingLastPathComponent
            let base = ((c.relativePath as NSString).lastPathComponent as NSString).deletingPathExtension
            let conflictPath = VaultReconciler.conflictRelativePath(base: base, inFolder: dir, timestamp: stamp)
            let frontmatter = VaultNoteSerializer.Frontmatter(jackID: UUID(), created: notes[index].createdAt, updated: Date())
            let contents = VaultNoteSerializer.fileContents(appBody: appVersion, frontmatter: frontmatter)
            let plan = VaultWriter.Plan(noteID: c.noteID, targetRelativePath: conflictPath, previousRelativePath: nil, fileContents: contents, images: [])
            Task.detached(priority: .utility) { _ = ClipboardStore.writeVaultPlan(plan, bookmark: bookmark) }

            // 2) Adopt the vault's version into the live note + refresh the record.
            notes[index].bodyMarkdown = c.appBody
            if notes[index].origin == .quickNote {
                notes[index].title = NoteMarkdown.displayTitle(for: c.appBody)
            }
            notes[index].updatedAt = Date()
            vaultSyncRecords[c.noteID] = VaultSyncRecord(
                vaultRelativePath: c.relativePath,
                lastSyncedContentHash: c.fileHash,
                lastSyncedFileModified: c.fileModified,
                lastWrittenByApp: vaultSyncRecords[c.noteID]?.lastWrittenByApp
            )
        }
        persistNotesLibrary()
        refreshWorkspaceTitles()
    }

    // MARK: - Deletions (conservative, non-destructive)

    /// A tracked vault file vanished. We never delete the app note — we just stop
    /// syncing it (drop the record + clear its destination), so a deleted file
    /// can't destroy the in-app note and the file won't be re-created.
    private func handleVaultDeletions(_ noteIDs: [UUID]) {
        guard !noteIDs.isEmpty else { return }
        for id in noteIDs {
            vaultSyncRecords[id] = nil
            if let index = notes.firstIndex(where: { $0.noteID == id }) {
                notes[index].vaultRelativeFolder = nil
            }
        }
        persistNotesLibrary()
    }

    private static func conflictTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmmss"
        return formatter.string(from: Date())
    }
}
