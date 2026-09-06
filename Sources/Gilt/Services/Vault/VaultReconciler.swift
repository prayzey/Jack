import Foundation

/// Pure decision logic for two-way vault sync. Given the app-side body hash, the
/// vault file's hash (nil = file missing), and the last sync record, decide what
/// to do. No filesystem access — this is the testable core that determines data
/// safety, so it lives apart from the IO.
enum VaultReconciler {
    enum Decision: Equatable {
        case noChange
        case writeToVault    // app changed since last sync, file didn't
        case importToApp     // file changed since last sync, app didn't
        case conflict        // both changed to different content
        case fileDeleted     // a tracked file is gone from the vault
    }

    static func decide(appBodyHash: String, fileHash: String?, record: VaultSyncRecord?) -> Decision {
        guard let record else {
            // Never synced before: the app side is authoritative; write it out if
            // there's no file yet. (A pre-existing file with our id is handled by
            // the new-from-vault path, not here.)
            return fileHash == nil ? .writeToVault : .writeToVault
        }
        guard let fileHash else { return .fileDeleted }

        let appChanged = appBodyHash != record.lastSyncedContentHash
        let fileChanged = fileHash != record.lastSyncedContentHash

        switch (appChanged, fileChanged) {
        case (false, false): return .noChange
        case (true, false): return .writeToVault
        case (false, true): return .importToApp
        case (true, true):
            // Both edited since last sync. If they happen to match, no conflict.
            return appBodyHash == fileHash ? .noChange : .conflict
        }
    }

    /// "<folder>/<base> (conflict <timestamp>).md" — the sibling file that holds
    /// the app's version when both sides changed, so nothing is ever overwritten.
    static func conflictRelativePath(base: String, inFolder folder: String, timestamp: String) -> String {
        let dir = folder.isEmpty ? "" : folder + "/"
        return "\(dir)\(base) (conflict \(timestamp)).md"
    }
}
