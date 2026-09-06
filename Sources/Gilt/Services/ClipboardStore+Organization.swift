import Foundation
import SwiftData

extension ClipboardStore {
    // MARK: - Smart Folders

    /// Keep folder auto-organization and cleanup rules together so the main store file
    /// does not also have to carry long-term lifecycle and maintenance behavior.

    func ensureSmartFolderExists(for category: SmartCategory) -> ClipFolderModel {
        if activeSmartFolderIDs.contains(category.folderID),
           let existing = folders.first(where: { $0.folderID == category.folderID }) {
            return existing
        }

        if let existing = folders.first(where: { $0.smartCategoryRaw == category.rawValue }) {
            activeSmartFolderIDs.insert(existing.folderID)
            return existing
        }

        let folder = ClipFolderModel(
            folderID: category.folderID,
            name: category.folderName,
            colorRaw: category.folderColor.rawValue,
            colorModeRaw: FolderColorMode.fill.rawValue,
            isSystem: true,
            sortOrder: smartFolderInsertIndex(),
            smartCategoryRaw: category.rawValue
        )
        modelContext.insert(folder)
        activeSmartFolderIDs.insert(folder.folderID)
        save()
        refreshFolders()
        logState("created smart folder: \(category.folderName)")
        return folder
    }

    private func smartFolderInsertIndex() -> Int {
        (folders.map(\.sortOrder).max() ?? 0) + 1
    }

    /// One-time initial sort so smart folders appear in a logical order on first launch.
    /// After this runs, the user's manual order is left alone.
    func sortSmartFoldersOnce() {
        let migrationKey = "AuricSmartFoldersSorted"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        var nextSort = 1
        for category in SmartCategory.allCases {
            if let folder = folders.first(where: { $0.smartCategoryRaw == category.rawValue }) {
                folder.sortOrder = nextSort
                nextSort += 1
            }
        }

        let userFolders = folders
            .filter { !$0.isSmartFolder && $0.folderID != ClipFolderModel.clipboardID }
            .sorted { $0.sortOrder < $1.sortOrder }
        for folder in userFolders {
            folder.sortOrder = nextSort
            nextSort += 1
        }

        if !folders.isEmpty {
            save()
            refreshFolders()
        }
        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    func hideSmartCategory(_ category: SmartCategory) {
        settings.smartCategories.setEnabled(category, false)
    }

    func enableSmartCategory(_ category: SmartCategory) {
        settings.smartCategories.setEnabled(category, true)
    }

    func reconcileSmartCategorySettings(previous: SmartCategorySettings, current: SmartCategorySettings) {
        var removedAny = false
        for category in SmartCategory.allCases {
            let wasEnabled = previous.isEnabled(category)
            let isEnabled = current.isEnabled(category)
            guard wasEnabled != isEnabled else { continue }
            if isEnabled {
                _ = ensureSmartFolderExists(for: category)
                backfillSmartFolder(for: category)
            } else {
                removedAny = true
            }
        }

        if removedAny {
            removeDisabledSmartFolders()
        } else {
            refreshFolders()
            refreshClips()
        }
    }

    private func backfillSmartFolder(for category: SmartCategory) {
        let smartFolder = ensureSmartFolderExists(for: category)
        guard smartFolder.isAutoCategorizationLocked == false else { return }

        var changed = false
        for clip in clips {
            let classification = ContentClassifier.classify(item: clip)
            guard classification.matchedCategories.contains(category) else { continue }
            if !clip.folders.contains(where: { $0.folderID == smartFolder.folderID }) {
                clip.folders.append(smartFolder)
                changed = true
            }
        }

        if changed {
            save()
            refreshClips()
        }
    }

    func applySensitiveExpiryPolicyToExistingClips() {
        let now = Date()
        var changed = false
        for clip in clips where clip.isSensitive {
            let nextExpiry: Date?
            if settings.smartCategories.autoExpireSensitive,
               let seconds = settings.smartCategories.sensitiveExpiry.seconds {
                nextExpiry = now.addingTimeInterval(seconds)
            } else {
                nextExpiry = nil
            }

            if clip.sensitiveExpiresAt != nextExpiry {
                clip.sensitiveExpiresAt = nextExpiry
                changed = true
            }
        }

        if changed {
            save()
            refreshClips()
        }
    }

    func removeDisabledSmartFolders() {
        var changed = false
        for folder in folders where folder.isSmartFolder {
            guard let category = folder.smartCategory else { continue }
            if !settings.smartCategories.isEnabled(category) {
                for clip in folder.clips {
                    clip.folders.removeAll { $0.folderID == folder.folderID }
                }
                modelContext.delete(folder)
                activeSmartFolderIDs.remove(folder.folderID)
                changed = true
                logState("removed disabled smart folder: \(category.folderName)")
            }
        }

        if changed {
            save()
            refreshFolders()
            refreshClips()
            if !visibleFolders.contains(where: { $0.folderID == selectedFolderID }) {
                selectedFolderID = visibleFolders.first?.folderID ?? ClipFolderModel.clipboardID
            }
        }
    }

    func rebuildSmartFolderCache() {
        activeSmartFolderIDs = Set(folders.filter(\.isSmartFolder).map(\.folderID))
    }

    // MARK: - Content Hash Index

    /// Rebuild the in-memory hash -> clipID lookup from the full database.
    func rebuildContentHashIndex() {
        let startedAt = DispatchTime.now()
        let descriptor = FetchDescriptor<ClipItemModel>(
            sortBy: [SortDescriptor(\.sortOrder, order: .reverse)]
        )
        let allClips = (try? modelContext.fetch(descriptor)) ?? []
        var newestByHash: [String: (clipID: UUID, sortOrder: Int)] = [:]
        newestByHash.reserveCapacity(allClips.count)

        for clip in allClips where !clip.contentHash.isEmpty {
            if let existing = newestByHash[clip.contentHash],
               existing.sortOrder >= clip.sortOrder {
                continue
            }
            newestByHash[clip.contentHash] = (clip.clipID, clip.sortOrder)
        }

        contentHashIndex = newestByHash.mapValues(\.clipID)
        logPerf(
            "rebuildContentHashIndex",
            startedAt: startedAt,
            details: "indexed=\(contentHashIndex.count) allClips=\(allClips.count)"
        )
    }

    /// Register a clip's hash so future copies can detect duplicates in O(1).
    func registerClipInHashIndex(_ clip: ClipItemModel) {
        let hash = clip.contentHash
        guard !hash.isEmpty else { return }
        guard let existingID = contentHashIndex[hash] else {
            contentHashIndex[hash] = clip.clipID
            return
        }
        guard existingID != clip.clipID else { return }
        guard let existing = clips.first(where: { $0.clipID == existingID }) else {
            contentHashIndex[hash] = clip.clipID
            return
        }
        if existing.sortOrder <= clip.sortOrder {
            contentHashIndex[hash] = clip.clipID
        }
    }

    /// Remove a clip's hash and promote the next-newest matching survivor when needed.
    func removeClipFromHashIndex(_ clip: ClipItemModel) {
        let hash = clip.contentHash
        guard !hash.isEmpty else { return }
        guard let indexedID = contentHashIndex[hash] else { return }
        guard indexedID == clip.clipID else { return }

        if let replacement = clips
            .filter({ $0.clipID != clip.clipID && $0.contentHash == hash })
            .max(by: { $0.sortOrder < $1.sortOrder }) {
            contentHashIndex[hash] = replacement.clipID
        } else {
            contentHashIndex.removeValue(forKey: hash)
        }
    }

    /// Backfill hashes for older clips created before duplicate detection existed.
    func backfillContentHashes() {
        let startedAt = DispatchTime.now()
        let descriptor = FetchDescriptor<ClipItemModel>()
        let allClips = (try? modelContext.fetch(descriptor)) ?? []
        let needsBackfill = allClips.filter { clip in
            if clip.clipType == .image {
                return false
            }
            return clip.contentHash.isEmpty
        }
        guard !needsBackfill.isEmpty else { return }

        for clip in needsBackfill {
            clip.contentHash = ContentFingerprint.fingerprint(for: clip)
        }

        save()
        logState(
            "backfillContentHashes filled=\(needsBackfill.count) "
                + "elapsed=\(String(format: "%.1f", Self.quickElapsedMs(since: startedAt)))ms"
        )
    }

    func scheduleLegacyImageHashMigration() {
        guard legacyImageHashMigrationTask == nil else { return }
        legacyImageHashMigrationTask = Task { @MainActor [weak self] in
            await self?.migrateLegacyImageHashesIfNeeded()
            self?.legacyImageHashMigrationTask = nil
        }
    }

    private func migrateLegacyImageHashesIfNeeded() async {
        let startedAt = DispatchTime.now()
        let imageTypeRaw = ClipType.image.rawValue
        let descriptor = FetchDescriptor<ClipItemModel>(
            predicate: #Predicate<ClipItemModel> { $0.typeRaw == imageTypeRaw },
            sortBy: [SortDescriptor(\.sortOrder, order: .reverse)]
        )
        let imageClips = (try? modelContext.fetch(descriptor)) ?? []
        let legacyClips = imageClips.filter { !ContentFingerprint.isCurrentImageHash($0.contentHash) }
        guard !legacyClips.isEmpty else { return }

        var migratedCount = 0
        for clip in legacyClips {
            let newHash = await ContentFingerprint.fingerprintAsync(
                type: .image,
                textValue: clip.textValue ?? clip.previewText,
                urlValue: clip.urlValue,
                imageData: clip.imageData
            )
            guard !newHash.isEmpty, newHash != clip.contentHash else { continue }

            removeClipFromHashIndex(clip)
            clip.contentHash = newHash
            registerClipInHashIndex(clip)
            migratedCount += 1

            if migratedCount.isMultiple(of: 8) {
                save()
                await Task.yield()
            }
        }

        guard migratedCount > 0 else { return }
        save()
        rebuildContentHashIndex()
        refreshClips()
        logState(
            "migrateLegacyImageHashes count=\(migratedCount) "
                + "elapsed=\(String(format: "%.1f", Self.quickElapsedMs(since: startedAt)))ms"
        )
    }

    // MARK: - Sensitive Expiry

    func startSensitiveExpiryTimer() {
        let timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pruneSensitiveClips()
            }
        }
        timer.tolerance = 2.0
        sensitiveExpiryTimer = timer
    }

    private func pruneSensitiveClips() {
        let now = Date()
        let expired = clips.filter { clip in
            clip.isSensitive && clip.sensitiveExpiresAt != nil && clip.sensitiveExpiresAt! < now
        }
        guard !expired.isEmpty else { return }

        for clip in expired {
            cancelImageOCR(for: clip.clipID)
            removeClipFromHashIndex(clip)
            modelContext.delete(clip)
        }

        save()
        refreshClips()
        logState("pruned \(expired.count) expired sensitive clips")
    }

    // MARK: - Retention

    func pruneByRetention(force: Bool) {
        let now = Date()
        if force == false,
           let lastRetentionPruneAt,
           now.timeIntervalSince(lastRetentionPruneAt) < retentionPruneThrottleSeconds {
            return
        }
        lastRetentionPruneAt = now

        guard let maxAge = settings.historyRetention.maxAgeSeconds else {
            logState("pruneByRetention skipped (forever)")
            return
        }
        let cutoff = now.addingTimeInterval(-maxAge)
        logState("pruneByRetention window=\(settings.historyRetention.rawValue) cutoff=\(cutoff)")

        let descriptor = FetchDescriptor<ClipItemModel>(
            predicate: #Predicate<ClipItemModel> { $0.createdAt < cutoff }
        )
        guard let expired = try? modelContext.fetch(descriptor), !expired.isEmpty else { return }

        for clip in expired {
            cancelImageOCR(for: clip.clipID)
            removeClipFromHashIndex(clip)
            modelContext.delete(clip)
        }

        save()
        refreshClips()
        logState("pruned \(expired.count) clips by retention")
    }
}
