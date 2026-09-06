import Foundation
import OSLog

/// Phase 0 of the Obsidian-vault feature: choose a vault folder and record a
/// per-note destination. Strictly non-destructive — nothing here writes,
/// creates, moves, or deletes anything inside the vault. Writing `.md` files is
/// Phase 1.
extension ClipboardStore {
    private static let vaultLog = Logger(subsystem: AppBrand.logSubsystem, category: "NoteVault")

    /// Whether the user has chosen a vault folder.
    var hasNotesVault: Bool { settings.notesVaultBookmark != nil }

    /// Set (or clear, with `nil`) the vault subfolder a note belongs to. Phase 0
    /// only records the choice; no file is written. Empty/whitespace and stray
    /// slashes normalize to `nil` ("not synced").
    func setNoteVaultDestination(_ noteID: UUID, relativeFolder: String?) {
        guard let index = notes.firstIndex(where: { $0.noteID == noteID }) else { return }
        let resolved = Self.normalizedVaultFolder(relativeFolder)
        guard notes[index].vaultRelativeFolder != resolved else { return }
        notes[index].vaultRelativeFolder = resolved
        notes[index].updatedAt = Date()
        persistNotesLibrary()
        if resolved != nil {
            // New or changed destination: write (or move) the file.
            scheduleVaultSync(for: noteID)
        } else {
            // Cleared: stop syncing and trash the vault copy (recoverable).
            removeVaultFile(for: noteID)
        }
    }

    /// Choose the vault root: persist a security-scoped bookmark plus a cosmetic
    /// display path. Both live in `AppSettings`, so the assignment persists via
    /// the existing `settings.didSet` -> `persistSettings()`.
    func setNotesVault(url: URL) {
        guard let bookmark = try? NoteVaultBookmarkService.makeBookmark(for: url) else {
            Self.vaultLog.info("setNotesVault: failed to create bookmark for \(url.path, privacy: .public)")
            return
        }
        settings.notesVaultBookmark = bookmark
        settings.notesVaultDisplayPath = url.path
        // Export any already-assigned notes into the freshly chosen vault, then
        // watch it for external edits.
        syncAllNotesToVault()
        startVaultWatcher()
    }

    /// Forget the chosen vault. Per-note destinations stay recorded, so adding a
    /// vault back later restores them; they simply have no effect meanwhile.
    func clearNotesVault() {
        stopVaultWatcher()
        settings.notesVaultBookmark = nil
        settings.notesVaultDisplayPath = nil
    }

    /// Real subfolders of the chosen vault, for the destination picker. The disk
    /// scan runs off the main actor so a large vault never stalls the UI.
    /// Returns `[]` when no vault is set or the vault can't be reached (moved or
    /// deleted) — callers then show the appropriate empty state.
    func vaultSubfolders() async -> [String] {
        guard let bookmark = settings.notesVaultBookmark else { return [] }
        return await Task.detached(priority: .userInitiated) {
            NoteVaultBookmarkService.withVaultAccess(bookmark) { url in
                NoteVaultScanner().subfolderRelativePaths(under: url)
            } ?? []
        }.value
    }

    /// Normalize a user/picker-supplied folder string to the stored form:
    /// trimmed, no leading/trailing slashes, empty -> nil. Pure (nonisolated) so
    /// it can be unit-tested without the store or the main actor.
    nonisolated static func normalizedVaultFolder(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.isEmpty ? nil : trimmed
    }
}
