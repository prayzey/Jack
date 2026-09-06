import AppKit
import Foundation

extension ClipboardStore {
    // MARK: - Enrichment

    /// Link metadata, OCR, icon caching, and small save queues all support "enriching"
    /// clips after capture, so they stay together here instead of inflating the main store file.

    func iconForBundle(_ bundleID: String?) -> NSImage? {
        guard let bundleID, !bundleID.isEmpty else { return nil }
        let cacheKey = bundleID as NSString
        if let cached = appIconCache.object(forKey: cacheKey) {
            return cached
        }
        if missingIconBundleIDs.contains(bundleID) {
            return nil
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            missingIconBundleIDs.insert(bundleID)
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        appIconCache.setObject(icon, forKey: cacheKey)
        return icon
    }

    func suggestedActions(for item: ClipItemModel) -> [SuggestedAction] {
        let signature = suggestedActionSignature(for: item)
        if let cached = suggestedActionCache[item.clipID], cached.signature == signature {
            return cached.actions
        }
        let computed = ContentClassifier.suggestedActions(for: item)
        suggestedActionCache[item.clipID] = SuggestedActionCacheEntry(signature: signature, actions: computed)
        if suggestedActionCache.count > maxSuggestedActionCacheSize {
            suggestedActionCache.removeAll(keepingCapacity: true)
        }
        return computed
    }

    func fetchLinkMetadataIfNeeded(for item: ClipItemModel) {
        guard item.clipType == .link, let rawURL = item.urlValue else { return }
        if hasHydratedLinkMetadata(item) { return }

        let clipID = item.clipID
        guard !inFlightLinkMetadataClipIDs.contains(clipID) else { return }
        inFlightLinkMetadataClipIDs.insert(clipID)
        let startedAt = DispatchTime.now()
        Task { [weak self] in
            let metadata = await LinkMetadataService.shared.metadata(for: rawURL)
            await MainActor.run { [weak self] in
                guard let self else { return }
                defer { self.inFlightLinkMetadataClipIDs.remove(clipID) }
                guard let metadata else {
                    if item.linkThumbnailURLString == nil {
                        item.linkThumbnailURLString = ""
                        self.scheduleMetadataSave()
                    }
                    self.logPerf(
                        "linkMetadata",
                        startedAt: startedAt,
                        details: "clip=\(self.shortClipID(clipID)) result=miss",
                        thresholdMs: 0
                    )
                    return
                }
                guard self.clips.contains(where: { $0.clipID == clipID }) else { return }
                var changed = false

                if item.linkPageTitle != metadata.pageTitle {
                    item.linkPageTitle = metadata.pageTitle
                    changed = true
                }
                if let newFavicon = metadata.faviconURL?.absoluteString, item.linkFaviconURLString != newFavicon {
                    item.linkFaviconURLString = newFavicon
                    changed = true
                }
                let thumbURL = metadata.thumbnailURL?.absoluteString ?? ""
                if item.linkThumbnailURLString != thumbURL {
                    item.linkThumbnailURLString = thumbURL
                    changed = true
                }
                if let thumbData = metadata.thumbnailData, item.linkThumbnailData == nil {
                    item.linkThumbnailData = thumbData
                    changed = true
                }
                if let desc = metadata.pageDescription, item.linkDescriptionText != desc {
                    item.linkDescriptionText = desc
                    changed = true
                }
                if let platform = metadata.platform?.rawValue, item.linkPlatformRaw != platform {
                    item.linkPlatformRaw = platform
                    changed = true
                }
                if let duration = metadata.videoDuration, item.linkVideoDuration != duration {
                    item.linkVideoDuration = duration
                    changed = true
                }

                if changed {
                    self.scheduleMetadataSave()
                }
                self.logPerf(
                    "linkMetadata",
                    startedAt: startedAt,
                    details: "clip=\(self.shortClipID(clipID)) changed=\(changed) "
                        + "thumb=\(metadata.thumbnailData != nil) "
                        + "platform=\(metadata.platform?.rawValue ?? "nil")",
                    thresholdMs: 0
                )
            }
        }
    }

    func scheduleOCRForExistingImages(forceRefresh: Bool) {
        guard settings.enableImageTextRecognition else { return }

        for clip in clips where clip.clipType == .image {
            if forceRefresh {
                cancelImageOCR(for: clip.clipID)
                clip.recognizedText = nil
                clip.ocrStatusRaw = "none"
                clip.ocrErrorCode = nil
                clip.ocrUpdatedAt = nil
            }

            if clip.recognizedText == nil || clip.ocrStatusRaw != "done" || forceRefresh {
                scheduleImageTextRecognitionIfNeeded(for: clip)
            }
        }
    }

    func scheduleImageTextRecognitionIfNeeded(for item: ClipItemModel) {
        guard item.clipType == .image else { return }
        guard settings.enableImageTextRecognition else {
            item.ocrStatusRaw = "skipped"
            item.ocrErrorCode = "feature_disabled"
            item.ocrUpdatedAt = Date()
            scheduleMetadataSave()
            return
        }
        guard inFlightOCRTasks[item.clipID] == nil else { return }
        guard let imageData = deepCopyData(item.imageData), !imageData.isEmpty else {
            item.ocrStatusRaw = "failed"
            item.ocrErrorCode = "missing_image_data"
            item.ocrUpdatedAt = Date()
            scheduleMetadataSave()
            return
        }

        item.ocrStatusRaw = "processing"
        item.ocrErrorCode = nil
        item.ocrUpdatedAt = Date()
        scheduleMetadataSave()

        let clipID = item.clipID
        let config = imageOCRConfiguration()
        let task = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            let outcome = await ImageTextRecognitionService.shared.recognize(
                imageData: imageData,
                configuration: config
            )
            guard !Task.isCancelled else { return }
            self.inFlightOCRTasks.removeValue(forKey: clipID)
            self.applyImageOCROutcome(outcome, to: clipID)
        }
        inFlightOCRTasks[clipID] = task
    }

    private func applyImageOCROutcome(_ outcome: ImageOCROutcome, to clipID: UUID) {
        guard let clip = clips.first(where: { $0.clipID == clipID }) else { return }
        clip.ocrUpdatedAt = Date()

        switch outcome {
        case .success(let recognizedText):
            clip.recognizedText = recognizedText
            clip.ocrStatusRaw = "done"
            clip.ocrErrorCode = nil
        case .skipped(let code):
            clip.ocrStatusRaw = "skipped"
            clip.ocrErrorCode = code
        case .failed(let code):
            clip.ocrStatusRaw = "failed"
            clip.ocrErrorCode = code
        }

        scheduleMetadataSave()
        invalidateFilteredClips(reason: "ocr")
    }

    func cancelImageOCR(for clipID: UUID) {
        inFlightOCRTasks.removeValue(forKey: clipID)?.cancel()
    }

    func cancelAllImageOCRTasks() {
        for task in inFlightOCRTasks.values {
            task.cancel()
        }
        inFlightOCRTasks.removeAll()
    }

    func scheduleMetadataSave() {
        pendingMetadataSaveCount += 1
        pendingMetadataSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let updates = self.pendingMetadataSaveCount
            self.pendingMetadataSaveCount = 0
            self.pendingMetadataSaveWorkItem = nil
            let startedAt = DispatchTime.now()
            self.save()
            self.logPerf("metadataSaveBatch", startedAt: startedAt, details: "updates=\(updates)", thresholdMs: 0)
        }
        pendingMetadataSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    func scheduleIngestSave() {
        pendingIngestSaveCount += 1
        if pendingIngestBatchStartedAt == nil {
            pendingIngestBatchStartedAt = DispatchTime.now()
        }

        pendingIngestSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let count = self.pendingIngestSaveCount
            self.pendingIngestSaveCount = 0
            self.pendingIngestSaveWorkItem = nil
            let queueStartedAt = self.pendingIngestBatchStartedAt
            self.pendingIngestBatchStartedAt = nil

            let startedAt = DispatchTime.now()
            self.save()
            let queuedMs = queueStartedAt.map { self.elapsedMilliseconds(since: $0) } ?? 0
            self.logPerf(
                "ingestSaveBatch",
                startedAt: startedAt,
                details: "clips=\(count) queued=\(String(format: "%.2f", queuedMs))ms",
                thresholdMs: 0
            )
        }
        pendingIngestSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: workItem)
    }

    func installWillTerminateObserver() {
        willTerminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.flushPendingSaves(reason: "app-will-terminate")
                self?.stopMaintenanceTimers()
            }
        }
    }

    private func flushPendingSaves(reason: String) {
        pendingMetadataSaveWorkItem?.cancel()
        pendingMetadataSaveWorkItem = nil
        pendingIngestSaveWorkItem?.cancel()
        pendingIngestSaveWorkItem = nil

        // Notes use their own debounced writer — a pending work item here means
        // an edit hasn't hit disk yet, so it must be flushed before quit.
        if pendingNotesPersistWorkItem != nil {
            pendingNotesPersistWorkItem?.cancel()
            pendingNotesPersistWorkItem = nil
            // Synchronous: the encode+write runs off-main, but on termination we
            // must block until the bytes land or the last edit is lost.
            persistNotesLibraryNow(synchronous: true)
        }
        // Also flush any pending vault export so an edit made right before quit
        // reaches the user's vault.
        flushPendingVaultWrites()

        let pendingMetadata = pendingMetadataSaveCount
        let pendingIngest = pendingIngestSaveCount
        pendingMetadataSaveCount = 0
        pendingIngestSaveCount = 0
        pendingIngestBatchStartedAt = nil

        guard pendingMetadata > 0 || pendingIngest > 0 else { return }
        let startedAt = DispatchTime.now()
        save()
        logPerf(
            "flushPendingSaves",
            startedAt: startedAt,
            details: "reason=\(reason) metadata=\(pendingMetadata) ingest=\(pendingIngest)",
            thresholdMs: 0
        )
    }

    /// Rebuffer a Data into a plain, self-owned Swift Data before it crosses an
    /// ownership boundary. Two callers depend on this:
    /// - ingest: pasteboard Data can be a bridged NSData subclass or a slice
    ///   retaining a larger backing buffer; `imageData` is SwiftData
    ///   `.externalStorage`, which must own its bytes outright. Do not remove
    ///   the copy on the ingest path to save a memcpy — it runs once per image
    ///   copy and guards against external-storage corruption.
    /// - OCR: copies the model's bytes so background recognition never reads
    ///   from a SwiftData-faulted buffer off the main actor.
    func deepCopyData(_ data: Data?) -> Data? {
        guard let data else { return nil }
        return data.withUnsafeBytes { Data($0) }
    }

    func hasHydratedLinkMetadata(_ item: ClipItemModel) -> Bool {
        guard item.clipType == .link else { return false }

        let hasPrimaryMetadata =
            item.linkPageTitle != nil
            || item.linkDescriptionText != nil
            || item.linkPlatformRaw != nil
        let hasFavicon = item.linkFaviconURLString != nil
        let thumbnailReady: Bool

        if let thumbnailState = item.linkThumbnailURLString {
            thumbnailReady = thumbnailState.isEmpty || item.linkThumbnailData != nil
        } else {
            thumbnailReady = false
        }

        return hasPrimaryMetadata && hasFavicon && thumbnailReady
    }

    func migrateURLOnlyTextClipsToLinksIfNeeded() {
        var changed = false

        for clip in clips where clip.clipType == .text {
            let sourceText = (clip.textValue ?? clip.previewText).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let normalizedURL = ClipActionService.normalizeWebURL(sourceText) else { continue }

            let previousType = clip.clipType
            let previousURL = clip.urlValue
            clip.typeRaw = ClipType.link.rawValue
            clip.title = "Link"
            clip.previewText = normalizedURL.host(percentEncoded: false) ?? normalizedURL.absoluteString
            clip.textValue = normalizedURL.absoluteString
            clip.urlValue = normalizedURL.absoluteString
            clip.contentHash = ""
            clearLinkMetadata(for: clip)
            refreshDerivedState(for: clip, previousType: previousType, previousURL: previousURL)
            changed = true
        }

        guard changed else { return }
        save()
        refreshClips()
        logState("migrated URL-only text clips into link cards")
    }
}
