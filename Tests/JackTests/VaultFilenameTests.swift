import XCTest
@testable import Gilt

final class VaultFilenameTests: XCTestCase {
    func testSanitizeStripsIllegalCharactersAndCollapsesWhitespace() {
        XCTAssertEqual(VaultFilename.sanitize("My/Note:Title*?"), "My Note Title")
        XCTAssertEqual(VaultFilename.sanitize("  spaced   out  "), "spaced out")
        XCTAssertEqual(VaultFilename.sanitize("...dots..."), "dots")
    }

    func testSanitizeEmptyFallsBackToUntitled() {
        XCTAssertEqual(VaultFilename.sanitize(""), "Untitled Note")
        XCTAssertEqual(VaultFilename.sanitize("///"), "Untitled Note")
    }

    func testSanitizeCapsLength() {
        let long = String(repeating: "a", count: 200)
        XCTAssertEqual(VaultFilename.sanitize(long).count, VaultFilename.maxBaseLength)
    }

    func testResolveBuildsFolderRelativePath() {
        let path = VaultFilename.resolve(base: "Note", inFolder: "Projects/Q3", taken: [], ownPrevious: nil)
        XCTAssertEqual(path, "Projects/Q3/Note.md")
    }

    func testResolveRootFolder() {
        XCTAssertEqual(VaultFilename.resolve(base: "Note", inFolder: "", taken: [], ownPrevious: nil), "Note.md")
    }

    func testResolveDisambiguatesForeignCollisions() {
        let taken: Set<String> = ["projects/note.md", "projects/note 2.md"]
        let path = VaultFilename.resolve(base: "Note", inFolder: "Projects", taken: taken, ownPrevious: nil)
        XCTAssertEqual(path, "Projects/Note 3.md")
    }

    func testResolveKeepsOwnPathDespiteCollisionWithSelf() {
        let taken: Set<String> = ["projects/note.md"]
        let path = VaultFilename.resolve(
            base: "Note", inFolder: "Projects", taken: taken, ownPrevious: "Projects/Note.md"
        )
        XCTAssertEqual(path, "Projects/Note.md")
    }
}
