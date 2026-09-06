import UniformTypeIdentifiers
import XCTest
@testable import Gilt

@MainActor
final class FolderTabsDropTypesTests: XCTestCase {
    func testFolderTabsAcceptInternalClipDragsAndFolderTextDrags() {
        let acceptedTypes = FolderTabsView.acceptedDropTypes

        XCTAssertTrue(acceptedTypes.contains(ClipDragItemProvider.internalDragType))
        XCTAssertTrue(acceptedTypes.contains(.plainText))
    }

    func testDirectFolderClipDropsOnlyAcceptInternalClipDrags() {
        let acceptedTypes = FolderTabsView.directClipDropTypes

        XCTAssertEqual(acceptedTypes, [ClipDragItemProvider.internalDragType])
        XCTAssertFalse(acceptedTypes.contains(.plainText))
    }
}
