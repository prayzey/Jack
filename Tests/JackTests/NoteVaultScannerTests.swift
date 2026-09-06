import XCTest
@testable import Gilt

/// Verifies the read-only vault folder scanner used by the destination picker.
/// Runs against a real temp directory tree so the FileManager enumeration,
/// exclusions, depth/count caps, and sorting are exercised end to end.
final class NoteVaultScannerTests: XCTestCase {
    private var root: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("VaultScannerTests-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? fm.removeItem(at: root) }
    }

    private func mkdir(_ relative: String) throws {
        try fm.createDirectory(at: root.appendingPathComponent(relative), withIntermediateDirectories: true)
    }

    private func touch(_ relative: String) throws {
        let url = root.appendingPathComponent(relative)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
    }

    func testReturnsNestedSubfoldersExcludingMetadataAndFiles() throws {
        try mkdir("Projects")
        try mkdir("Projects/Q3")
        try mkdir("Archive")
        try mkdir(".obsidian/plugins")
        try mkdir(".trash")
        try mkdir(".git")
        try touch("Projects/note.md")
        try touch("loose.md")

        let result = NoteVaultScanner().subfolderRelativePaths(under: root)

        XCTAssertEqual(result, ["Archive", "Projects", "Projects/Q3"])
        XCTAssertFalse(result.contains { $0.contains(".obsidian") })
        XCTAssertFalse(result.contains { $0.contains(".trash") })
        XCTAssertFalse(result.contains { $0.contains(".git") })
        XCTAssertFalse(result.contains("loose.md"))
    }

    func testCaseInsensitiveSort() throws {
        try mkdir("banana")
        try mkdir("Apple")
        try mkdir("cherry")

        XCTAssertEqual(NoteVaultScanner().subfolderRelativePaths(under: root), ["Apple", "banana", "cherry"])
    }

    func testMissingRootReturnsEmpty() {
        let missing = root.appendingPathComponent("does-not-exist", isDirectory: true)
        XCTAssertEqual(NoteVaultScanner().subfolderRelativePaths(under: missing), [])
    }

    func testSkipsSymlinkedDirectories() throws {
        try mkdir("Real")
        let linkTarget = fm.temporaryDirectory.appendingPathComponent("VaultLinkTarget-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: linkTarget, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: linkTarget) }
        try fm.createSymbolicLink(at: root.appendingPathComponent("Linked"), withDestinationURL: linkTarget)

        let result = NoteVaultScanner().subfolderRelativePaths(under: root)

        XCTAssertEqual(result, ["Real"])
        XCTAssertFalse(result.contains("Linked"))
    }

    func testDepthCapIncludesBoundaryButPrunesDeeper() throws {
        try mkdir("a/b/c/d")

        let result = NoteVaultScanner().subfolderRelativePaths(under: root, maxDepth: 2)

        XCTAssertTrue(result.contains("a"))
        XCTAssertTrue(result.contains("a/b"))
        XCTAssertFalse(result.contains("a/b/c"))
        XCTAssertFalse(result.contains("a/b/c/d"))
    }

    func testResultCountCapRespected() throws {
        for i in 0..<10 { try mkdir("folder-\(i)") }

        XCTAssertEqual(NoteVaultScanner().subfolderRelativePaths(under: root, maxResults: 4).count, 4)
    }
}
