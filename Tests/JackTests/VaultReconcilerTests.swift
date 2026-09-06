import XCTest
@testable import Gilt

/// The reconciler decides what two-way sync does, so this truth table is the
/// guardrail against silent overwrites / data loss.
final class VaultReconcilerTests: XCTestCase {
    private func record(hash: String) -> VaultSyncRecord {
        VaultSyncRecord(vaultRelativePath: "Notes/A.md", lastSyncedContentHash: hash)
    }

    func testNoRecordWritesToVault() {
        XCTAssertEqual(
            VaultReconciler.decide(appBodyHash: "a", fileHash: nil, record: nil),
            .writeToVault
        )
        XCTAssertEqual(
            VaultReconciler.decide(appBodyHash: "a", fileHash: "a", record: nil),
            .writeToVault
        )
    }

    func testMissingFileIsDeleted() {
        XCTAssertEqual(
            VaultReconciler.decide(appBodyHash: "a", fileHash: nil, record: record(hash: "a")),
            .fileDeleted
        )
    }

    func testNeitherChangedIsNoChange() {
        XCTAssertEqual(
            VaultReconciler.decide(appBodyHash: "synced", fileHash: "synced", record: record(hash: "synced")),
            .noChange
        )
    }

    func testAppOnlyChangedWritesToVault() {
        XCTAssertEqual(
            VaultReconciler.decide(appBodyHash: "new", fileHash: "synced", record: record(hash: "synced")),
            .writeToVault
        )
    }

    func testFileOnlyChangedImportsToApp() {
        XCTAssertEqual(
            VaultReconciler.decide(appBodyHash: "synced", fileHash: "edited", record: record(hash: "synced")),
            .importToApp
        )
    }

    func testBothChangedDifferentlyIsConflict() {
        XCTAssertEqual(
            VaultReconciler.decide(appBodyHash: "appedit", fileHash: "fileedit", record: record(hash: "synced")),
            .conflict
        )
    }

    func testBothChangedToSameContentIsNoChange() {
        // Converged independently to identical content — not a real conflict.
        XCTAssertEqual(
            VaultReconciler.decide(appBodyHash: "same", fileHash: "same", record: record(hash: "synced")),
            .noChange
        )
    }

    func testConflictPathFormat() {
        let path = VaultReconciler.conflictRelativePath(base: "My Note", inFolder: "Projects", timestamp: "2026-06-19 143000")
        XCTAssertEqual(path, "Projects/My Note (conflict 2026-06-19 143000).md")
    }

    func testConflictPathRootFolder() {
        let path = VaultReconciler.conflictRelativePath(base: "Note", inFolder: "", timestamp: "t")
        XCTAssertEqual(path, "Note (conflict t).md")
    }
}
