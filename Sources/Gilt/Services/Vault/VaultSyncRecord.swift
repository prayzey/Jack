import Foundation

/// Per-note vault sync bookkeeping. Stored in `NotesLibraryState` keyed by
/// `noteID.uuidString` so it rides the existing atomic JSON write (one
/// transaction with the notes themselves — no torn state across two files).
///
/// It records where a note's `.md` file lives and the last-synced fingerprint,
/// which lets the reconciler tell "the app changed" from "the file changed" from
/// "both changed (conflict)" — and lets app-side writes be recognized as their
/// own echo when the watcher reports them (the feedback-loop guard).
struct VaultSyncRecord: Codable, Equatable, Sendable {
    /// Last vault-relative path we wrote or read for this note ("<folder>/<name>.md").
    var vaultRelativePath: String
    /// Hash of the app-form body at the last successful sync (both directions).
    var lastSyncedContentHash: String
    /// File modification date we last observed (cheap pre-check before hashing).
    var lastSyncedFileModified: Date?
    /// When the app last wrote this file — used to recognize our own writes when
    /// the watcher fires, so a Phase 1 write can't trigger a Phase 2 import.
    var lastWrittenByApp: Date?

    init(
        vaultRelativePath: String,
        lastSyncedContentHash: String,
        lastSyncedFileModified: Date? = nil,
        lastWrittenByApp: Date? = nil
    ) {
        self.vaultRelativePath = vaultRelativePath
        self.lastSyncedContentHash = lastSyncedContentHash
        self.lastSyncedFileModified = lastSyncedFileModified
        self.lastWrittenByApp = lastWrittenByApp
    }
}
