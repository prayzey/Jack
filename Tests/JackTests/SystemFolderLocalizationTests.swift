import XCTest
@testable import Gilt

final class SystemFolderLocalizationTests: XCTestCase {
    func testMigrationMarksClipboardDefaultNameAsLocalizedSystemName() {
        let folder = ClipFolderModel(
            folderID: ClipFolderModel.clipboardID,
            name: "Clipboard",
            isSystem: true
        )

        let changed = folder.migrateLocalizedSystemNameMetadataIfNeeded()

        XCTAssertTrue(changed)
        XCTAssertEqual(folder.name, "Clipboard")
        XCTAssertEqual(folder.usesLocalizedSystemName, true)
    }

    func testMigrationTreatsSpanishDefaultNameAsSameBuiltInFolder() {
        let folder = ClipFolderModel(
            folderID: ClipFolderModel.clipboardID,
            name: "Portapapeles",
            isSystem: true
        )

        let changed = folder.migrateLocalizedSystemNameMetadataIfNeeded()

        XCTAssertTrue(changed)
        XCTAssertEqual(folder.name, "Clipboard")
        XCTAssertEqual(folder.usesLocalizedSystemName, true)
    }

    func testMigrationPreservesCustomSystemFolderRename() {
        let folder = ClipFolderModel(
            folderID: ClipFolderModel.clipboardID,
            name: "Snippets",
            isSystem: true
        )

        let changed = folder.migrateLocalizedSystemNameMetadataIfNeeded()

        XCTAssertTrue(changed)
        XCTAssertEqual(folder.name, "Snippets")
        XCTAssertEqual(folder.usesLocalizedSystemName, false)
    }

    func testApplyDisplayNameOverrideTreatsLocalizedDefaultAsDefaultState() {
        let folder = ClipFolderModel(
            folderID: ClipFolderModel.clipboardID,
            name: "Clipboard",
            isSystem: true,
            usesLocalizedSystemName: false
        )

        let changed = folder.applyDisplayNameOverride("Portapapeles")

        XCTAssertTrue(changed)
        XCTAssertEqual(folder.name, "Clipboard")
        XCTAssertEqual(folder.usesLocalizedSystemName, true)
    }

    func testApplyDisplayNameOverrideStoresCustomSystemFolderRename() {
        let folder = ClipFolderModel(
            folderID: SmartCategory.code.folderID,
            name: "Code",
            isSystem: true,
            smartCategoryRaw: SmartCategory.code.rawValue,
            usesLocalizedSystemName: true
        )

        let changed = folder.applyDisplayNameOverride("Snippets")

        XCTAssertTrue(changed)
        XCTAssertEqual(folder.name, "Snippets")
        XCTAssertEqual(folder.usesLocalizedSystemName, false)
    }
}
