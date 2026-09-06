import XCTest
@testable import Gilt

/// End-to-end test of the two-way reconcile IO path against a real temp vault
/// (write a note file, then detect external edits / conflicts / writebacks).
/// Uses a real security-scoped bookmark but no `ClipboardStore`, so it never
/// touches the user's actual notes.
final class VaultReconcileIntegrationTests: XCTestCase {
    private var vault: URL!
    private var attachments: URL!
    private var bookmark: Data!
    private let fm = FileManager.default
    private let noteID = UUID()
    private let relativePath = "Inbox/Title.md"

    override func setUpWithError() throws {
        vault = fm.temporaryDirectory.appendingPathComponent("VaultReconcile-\(UUID().uuidString)", isDirectory: true)
        attachments = fm.temporaryDirectory.appendingPathComponent("VaultAttach-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: vault, withIntermediateDirectories: true)
        try fm.createDirectory(at: attachments, withIntermediateDirectories: true)
        bookmark = try NoteVaultBookmarkService.makeBookmark(for: vault)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: vault)
        try? fm.removeItem(at: attachments)
    }

    /// Write the initial synced file and return the snapshot item for it.
    private func seedSyncedNote(appBody: String) throws -> VaultReconcileItem {
        let frontmatter = VaultNoteSerializer.Frontmatter(jackID: noteID, created: Date(), updated: Date())
        let contents = VaultNoteSerializer.fileContents(appBody: appBody, frontmatter: frontmatter)
        let plan = VaultWriter.Plan(
            noteID: noteID, targetRelativePath: relativePath, previousRelativePath: nil,
            fileContents: contents, images: []
        )
        _ = try VaultWriter.apply(plan, vaultURL: vault)
        let hash = VaultNoteSerializer.contentHash(appBody: appBody)
        return VaultReconcileItem(
            noteID: noteID,
            appBodyHash: hash,
            record: VaultSyncRecord(vaultRelativePath: relativePath, lastSyncedContentHash: hash)
        )
    }

    private func overwriteFile(appBody: String) throws {
        let frontmatter = VaultNoteSerializer.Frontmatter(jackID: noteID, created: Date(), updated: Date())
        let contents = VaultNoteSerializer.fileContents(appBody: appBody, frontmatter: frontmatter)
        try Data(contents.utf8).write(to: vault.appendingPathComponent(relativePath), options: .atomic)
    }

    private func reconcile(_ item: VaultReconcileItem) -> VaultReconcileOutcome {
        ClipboardStore.reconcileFiles(snapshot: [item], bookmark: bookmark, attachmentsRoot: attachments)
    }

    func testNoExternalChangeIsEmpty() throws {
        let item = try seedSyncedNote(appBody: "Title\n\nOriginal")
        XCTAssertTrue(reconcile(item).isEmpty)
    }

    func testExternalEditIsImported() throws {
        let item = try seedSyncedNote(appBody: "Title\n\nOriginal")
        try overwriteFile(appBody: "Title\n\nEdited in Obsidian")

        let outcome = reconcile(item)
        XCTAssertEqual(outcome.imports.count, 1)
        XCTAssertEqual(outcome.imports.first?.appBody, "Title\n\nEdited in Obsidian")
        XCTAssertTrue(outcome.conflicts.isEmpty)
    }

    func testAppOnlyChangeIsWriteBack() throws {
        var item = try seedSyncedNote(appBody: "Title\n\nOriginal")
        // Simulate the app having changed since last sync (file untouched).
        item = VaultReconcileItem(
            noteID: noteID,
            appBodyHash: VaultNoteSerializer.contentHash(appBody: "Title\n\nApp edit"),
            record: item.record
        )
        let outcome = reconcile(item)
        XCTAssertEqual(outcome.writeBacks, [noteID])
        XCTAssertTrue(outcome.imports.isEmpty)
    }

    func testBothChangedIsConflict() throws {
        var item = try seedSyncedNote(appBody: "Title\n\nOriginal")
        try overwriteFile(appBody: "Title\n\nFile edit")
        item = VaultReconcileItem(
            noteID: noteID,
            appBodyHash: VaultNoteSerializer.contentHash(appBody: "Title\n\nApp edit"),
            record: item.record
        )
        let outcome = reconcile(item)
        XCTAssertEqual(outcome.conflicts.count, 1)
        XCTAssertEqual(outcome.conflicts.first?.appBody, "Title\n\nFile edit")
        XCTAssertTrue(outcome.imports.isEmpty)
    }

    func testDeletedFileIsReported() throws {
        let item = try seedSyncedNote(appBody: "Title\n\nOriginal")
        try fm.removeItem(at: vault.appendingPathComponent(relativePath))

        let outcome = reconcile(item)
        XCTAssertEqual(outcome.deletedNoteIDs, [noteID])
    }
}
