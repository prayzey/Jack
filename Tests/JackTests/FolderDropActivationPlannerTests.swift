import XCTest
@testable import Gilt

final class FolderDropActivationPlannerTests: XCTestCase {
    func testHandlesDropWhenLifecycleFlagIsAlreadyActive() {
        XCTAssertTrue(
            shouldHandleFolderTabsDrop(
                internalDragIsActive: true,
                payloadIsSupported: false
            )
        )
    }

    func testHandlesDropWhenPayloadIsSupportedBeforeLifecycleFlagArrives() {
        XCTAssertTrue(
            shouldHandleFolderTabsDrop(
                internalDragIsActive: false,
                payloadIsSupported: true
            )
        )
    }

    func testIgnoresDropWhenNeitherSignalMatches() {
        XCTAssertFalse(
            shouldHandleFolderTabsDrop(
                internalDragIsActive: false,
                payloadIsSupported: false
            )
        )
    }

    func testFolderDropClipIDAcceptsPlainClipUUIDPayload() {
        let clipID = UUID()

        XCTAssertEqual(folderDropClipID(from: clipID.uuidString), clipID)
    }

    func testFolderDropClipIDRejectsNonClipInternalPayloads() {
        XCTAssertNil(folderDropClipID(from: "separator:\(UUID().uuidString)"))
        XCTAssertNil(folderDropClipID(from: "usage:codex"))
        XCTAssertNil(folderDropClipID(from: "folder:\(UUID().uuidString)"))
    }
}
