import AppKit
import Foundation

extension ClipboardStore {
    // MARK: - Capture

    nonisolated static func shouldIgnorePasteboardChange(
        suppressedChangeCount: Int?,
        currentChangeCount: Int
    ) -> Bool {
        suppressedChangeCount == currentChangeCount
    }

    func ingest(captured: CapturedClip, changeCount: Int, precomputedHash: String? = nil) {
        let startedAt = DispatchTime.now()
        if Self.shouldIgnorePasteboardChange(
            suppressedChangeCount: suppressedPasteboardChangeCount,
            currentChangeCount: changeCount
        ) {
            suppressedPasteboardChangeCount = nil
            return
        }
        suppressedPasteboardChangeCount = nil
        sessionIngestCount += 1
        sessionIngestByType[captured.type.rawValue, default: 0] += 1
        Breadcrumb.record("ingest type=\(captured.type.rawValue) total=\(sessionIngestCount)")
        let app = NSWorkspace.shared.frontmostApplication
        let appName = app?.localizedName ?? "Unknown App"
        let bundleID = app?.bundleIdentifier

        appendCapturedClipboardToQuickNoteIfNeeded(captured, sourceBundleID: bundleID)

        let hash = precomputedHash ?? ContentFingerprint.fingerprint(
            type: captured.type,
            textValue: captured.textValue ?? captured.previewText,
            urlValue: captured.urlValue,
            imageData: captured.imageData
        )

        if !hash.isEmpty, let existingClipID = contentHashIndex[hash] {
            if let existingClip = clips.first(where: { $0.clipID == existingClipID }) {
                bumpClipToFront(existingClip, appName: appName, bundleID: bundleID)
                if existingClip.recognizedText == nil && existingClip.ocrStatusRaw != "processing" {
                    scheduleImageTextRecognitionIfNeeded(for: existingClip)
                }
                logPerf(
                    "ingest",
                    startedAt: startedAt,
                    details: "type=\(captured.type.rawValue) DUPLICATE bumped=\(shortClipID(existingClipID))",
                    thresholdMs: 0
                )
                return
            } else {
                contentHashIndex.removeValue(forKey: hash)
            }
        }

        guard let clipboardFolder = folders.first(where: { $0.folderID == ClipFolderModel.clipboardID }) else { return }

        let nextSortOrder = highestSortOrder + 1
        let clip = ClipItemModel(
            clipID: UUID(),
            typeRaw: captured.type.rawValue,
            title: captured.title,
            previewText: captured.previewText,
            textValue: captured.textValue,
            urlValue: captured.urlValue,
            imageData: deepCopyData(captured.imageData),
            recognizedText: nil,
            ocrStatusRaw: "none",
            ocrUpdatedAt: nil,
            ocrErrorCode: nil,
            sourceAppName: appName,
            sourceBundleID: bundleID,
            createdAt: Date(),
            contentHash: hash,
            sortOrder: nextSortOrder,
            folders: [clipboardFolder]
        )
        highestSortOrder = nextSortOrder

        modelContext.insert(clip)
        registerClipInHashIndex(clip)

        let classification = ContentClassifier.classify(item: clip)
        clip.contentTags = classification.contentTags
        clip.isSensitive = classification.isSensitive
        clip.detectedLanguage = classification.detectedLanguage

        if clip.clipType == .text,
           classification.contentTags.contains(.colorValue),
           let text = clip.textValue ?? clip.previewText as String?,
           text.trimmingCharacters(in: .whitespacesAndNewlines).count < 100 {
            clip.typeRaw = ClipType.color.rawValue
        }

        if classification.isSensitive,
           settings.smartCategories.autoExpireSensitive,
           let seconds = settings.smartCategories.sensitiveExpiry.seconds {
            clip.sensitiveExpiresAt = Date().addingTimeInterval(seconds)
        }

        for category in classification.matchedCategories where settings.smartCategories.isEnabled(category) {
            let smartFolder = ensureSmartFolderExists(for: category)
            guard smartFolder.isAutoCategorizationLocked == false else { continue }
            if !clip.folders.contains(where: { $0.folderID == smartFolder.folderID }) {
                clip.folders.append(smartFolder)
            }
        }

        clips.insert(clip, at: 0)
        Analytics.clipCaptured(type: clip.clipType.rawValue)
        scheduleIngestSave()

        fetchLinkMetadataIfNeeded(for: clip)
        scheduleImageTextRecognitionIfNeeded(for: clip)
        scheduleAIClipEnrichmentIfNeeded(for: clip)
        pruneByRetention(force: false)
        logPerf(
            "ingest",
            startedAt: startedAt,
            details: "type=\(captured.type.rawValue) clips=\(clips.count) folders=\(clip.folders.count)",
            thresholdMs: 0
        )
    }

    /// Bump an existing duplicate clip to the front of the history.
    /// Updates its timestamp, sort order, and source app so it behaves as if it was freshly copied.
    private func bumpClipToFront(_ clip: ClipItemModel, appName: String, bundleID: String?) {
        if clip.isPinned {
            clip.sourceAppName = appName
            clip.sourceBundleID = bundleID
            clip.createdAt = Date()
            scheduleIngestSave()
            invalidateFilteredClips(reason: "duplicate-pinned")
            logState("bumpClipToFront pinned clip=\(shortClipID(clip.clipID)) app=\(appName)")
            return
        }

        let nextSortOrder = highestSortOrder + 1
        clip.createdAt = Date()
        clip.sortOrder = nextSortOrder
        clip.sourceAppName = appName
        clip.sourceBundleID = bundleID
        highestSortOrder = nextSortOrder

        if let index = clips.firstIndex(where: { $0.clipID == clip.clipID }) {
            clips.remove(at: index)
        }
        clips.insert(clip, at: 0)
        scheduleIngestSave()
        logState("bumpClipToFront clip=\(shortClipID(clip.clipID)) app=\(appName)")
    }

    nonisolated static func nextSortOrder(
        forPinned pinned: Bool,
        clips: [ClipItemModel],
        highestSortOrder: Int
    ) -> Int {
        let currentMax = if pinned {
            max(highestSortOrder, clips.map(\.sortOrder).max() ?? 0)
        } else {
            clips
                .filter { $0.isPinned == false }
                .map(\.sortOrder)
                .max() ?? 0
        }
        return currentMax + 1
    }

    func nextSortOrder(forPinned pinned: Bool) -> Int {
        Self.nextSortOrder(forPinned: pinned, clips: clips, highestSortOrder: highestSortOrder)
    }
}
