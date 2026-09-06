import AppKit
import Foundation

extension ClipboardStore {
    /// Whether a dropped/opened file is something the transcription feature can
    /// handle. Used by drop targets and the open panel to filter before kicking
    /// off a job. Thin alias over the service so there's one source of truth.
    nonisolated static func isTranscribableAudioFile(_ url: URL) -> Bool {
        AudioFileTranscriptionService.isSupportedAudioFile(url)
    }

    /// Surfaces a finished transcript as a text clip at the top of the Clipboard
    /// folder, selected and ready to copy.
    ///
    /// Unlike `ingest`, this never writes to the pasteboard: the transcript is
    /// offered in history but we don't clobber whatever the user currently has
    /// copied. It mirrors `ingest`'s classification + smart-folder routing so a
    /// transcript behaves like any other captured text clip.
    @discardableResult
    func addTranscriptClip(text: String, fileName: String, durationSeconds: Double) -> UUID? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let clipboardFolder = folders.first(where: { $0.folderID == ClipFolderModel.clipboardID }) else {
            return nil
        }

        let hash = ContentFingerprint.fingerprint(
            type: .text,
            textValue: trimmed,
            urlValue: nil,
            imageData: nil
        )

        let nextSortOrder = highestSortOrder + 1
        let clip = ClipItemModel(
            typeRaw: ClipType.text.rawValue,
            title: "Transcript",
            previewText: trimmed,
            textValue: trimmed,
            sourceAppName: Self.transcriptSourceLabel(fileName: fileName),
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

        for category in classification.matchedCategories where settings.smartCategories.isEnabled(category) {
            let smartFolder = ensureSmartFolderExists(for: category)
            guard smartFolder.isAutoCategorizationLocked == false else { continue }
            if !clip.folders.contains(where: { $0.folderID == smartFolder.folderID }) {
                clip.folders.append(smartFolder)
            }
        }

        clips.insert(clip, at: 0)
        scheduleIngestSave()

        // Jump to the Clipboard folder and select the new clip so the result is
        // visible no matter which folder the user was viewing when they dropped.
        selectedFolderID = ClipFolderModel.clipboardID
        invalidateFilteredClips(reason: "transcript")
        selectSingle(clip.clipID)
        return clip.clipID
    }

    /// Label shown where a card normally shows the source app — we use the
    /// voice-note file name (sans extension) so the user can tell transcripts
    /// apart at a glance.
    private static func transcriptSourceLabel(fileName: String) -> String {
        let base = (fileName as NSString).deletingPathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return base.isEmpty ? "Voice Note" : base
    }
}
