import XCTest
@testable import Gilt

/// Integration tests for the on-disk vault writer against a temp directory.
final class VaultWriterTests: XCTestCase {
    private var vault: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        vault = fm.temporaryDirectory.appendingPathComponent("VaultWriterTests-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: vault, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let vault { try? fm.removeItem(at: vault) }
    }

    func testWritesFileCreatingIntermediateFolders() throws {
        let plan = VaultWriter.Plan(
            noteID: UUID(),
            targetRelativePath: "Projects/Q3/Note.md",
            previousRelativePath: nil,
            fileContents: "---\njack-id: x\n---\n\nHello",
            images: []
        )
        let result = try VaultWriter.apply(plan, vaultURL: vault)

        let written = vault.appendingPathComponent("Projects/Q3/Note.md")
        XCTAssertTrue(fm.fileExists(atPath: written.path))
        XCTAssertEqual(try String(contentsOf: written, encoding: .utf8), "---\njack-id: x\n---\n\nHello")
        XCTAssertEqual(result.writtenRelativePath, "Projects/Q3/Note.md")
    }

    func testMoveRemovesPreviousFile() throws {
        let first = VaultWriter.Plan(
            noteID: UUID(), targetRelativePath: "A/Note.md", previousRelativePath: nil,
            fileContents: "v1", images: []
        )
        _ = try VaultWriter.apply(first, vaultURL: vault)
        XCTAssertTrue(fm.fileExists(atPath: vault.appendingPathComponent("A/Note.md").path))

        let moved = VaultWriter.Plan(
            noteID: UUID(), targetRelativePath: "B/Renamed.md", previousRelativePath: "A/Note.md",
            fileContents: "v2", images: []
        )
        _ = try VaultWriter.apply(moved, vaultURL: vault)

        XCTAssertFalse(fm.fileExists(atPath: vault.appendingPathComponent("A/Note.md").path))
        XCTAssertTrue(fm.fileExists(atPath: vault.appendingPathComponent("B/Renamed.md").path))
    }

    func testCopiesImageOnce() throws {
        // A source image on disk.
        let imageID = UUID()
        let sourceDir = fm.temporaryDirectory.appendingPathComponent("src-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: sourceDir) }
        let source = sourceDir.appendingPathComponent("\(imageID.uuidString.lowercased()).png")
        try Data("png-bytes".utf8).write(to: source)

        let rel = "_jack-assets/\(imageID.uuidString.lowercased()).png"
        let plan = VaultWriter.Plan(
            noteID: UUID(), targetRelativePath: "Note.md", previousRelativePath: nil,
            fileContents: "body", images: [.init(sourcePath: source.path, vaultRelativePath: rel)]
        )
        _ = try VaultWriter.apply(plan, vaultURL: vault)

        let copied = vault.appendingPathComponent(rel)
        XCTAssertTrue(fm.fileExists(atPath: copied.path))
        XCTAssertEqual(try Data(contentsOf: copied), Data("png-bytes".utf8))
    }

    func testFileFingerprintMatchesSerializerHash() throws {
        let jackID = UUID()
        let appBody = "Title\n\nBody content"
        let fm0 = VaultNoteSerializer.Frontmatter(jackID: jackID, created: Date(), updated: Date())
        let contents = VaultNoteSerializer.fileContents(appBody: appBody, frontmatter: fm0)
        let plan = VaultWriter.Plan(
            noteID: jackID, targetRelativePath: "Note.md", previousRelativePath: nil,
            fileContents: contents, images: []
        )
        _ = try VaultWriter.apply(plan, vaultURL: vault)

        let fingerprint = VaultWriter.fileFingerprint(relativePath: "Note.md", vaultURL: vault)
        XCTAssertEqual(fingerprint?.hash, VaultNoteSerializer.contentHash(appBody: appBody))
    }

    func testTrashRemovesFile() throws {
        let plan = VaultWriter.Plan(
            noteID: UUID(), targetRelativePath: "Doomed.md", previousRelativePath: nil,
            fileContents: "bye", images: []
        )
        _ = try VaultWriter.apply(plan, vaultURL: vault)
        XCTAssertTrue(fm.fileExists(atPath: vault.appendingPathComponent("Doomed.md").path))

        VaultWriter.trash(relativePath: "Doomed.md", vaultURL: vault)
        XCTAssertFalse(fm.fileExists(atPath: vault.appendingPathComponent("Doomed.md").path))
    }
}
