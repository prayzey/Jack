import XCTest
@testable import Gilt

final class ClipSearchFilterTests: XCTestCase {
    func testFilterWithoutQueryReturnsOnlySelectedFolderSorted() {
        let selectedFolder = makeFolder(name: "Selected")
        let otherFolder = makeFolder(name: "Other")

        let olderSameOrder = makeClip(
            previewText: "older",
            sortOrder: 1,
            createdAt: Date(timeIntervalSince1970: 100),
            folders: [selectedFolder]
        )
        let newerSameOrder = makeClip(
            previewText: "newer",
            sortOrder: 1,
            createdAt: Date(timeIntervalSince1970: 200),
            folders: [selectedFolder]
        )
        let highestOrder = makeClip(
            previewText: "highest",
            sortOrder: 3,
            createdAt: Date(timeIntervalSince1970: 50),
            folders: [selectedFolder]
        )
        let otherFolderClip = makeClip(
            previewText: "other",
            sortOrder: 99,
            createdAt: Date(timeIntervalSince1970: 300),
            folders: [otherFolder]
        )

        let result = ClipSearchFilter.filter(
            clips: [olderSameOrder, newerSameOrder, highestOrder, otherFolderClip],
            selectedFolderID: selectedFolder.folderID,
            searchText: ""
        )

        XCTAssertEqual(
            result.map(\.clipID),
            [highestOrder.clipID, newerSameOrder.clipID, olderSameOrder.clipID]
        )
    }

    func testFilterWithQueryStaysScopedToSelectedFolder() {
        let selectedFolder = makeFolder(name: "Selected")
        let otherFolder = makeFolder(name: "Other")

        let selectedMatch = makeClip(
            previewText: "well clinic note",
            folders: [selectedFolder]
        )
        let otherMatch = makeClip(
            previewText: "well clinic note",
            folders: [otherFolder]
        )

        let result = ClipSearchFilter.filter(
            clips: [selectedMatch, otherMatch],
            selectedFolderID: selectedFolder.folderID,
            searchText: "well"
        )

        XCTAssertEqual(result.map(\.clipID), [selectedMatch.clipID])
    }

    func testPinnedClipsAlwaysSortBeforeUnpinnedClips() {
        let selectedFolder = makeFolder(name: "Selected")

        let newestUnpinned = makeClip(
            previewText: "newest unpinned",
            sortOrder: 99,
            createdAt: Date(timeIntervalSince1970: 500),
            isPinned: false,
            folders: [selectedFolder]
        )
        let olderPinned = makeClip(
            previewText: "older pinned",
            sortOrder: 1,
            createdAt: Date(timeIntervalSince1970: 100),
            isPinned: true,
            folders: [selectedFolder]
        )
        let newerPinned = makeClip(
            previewText: "newer pinned",
            sortOrder: 3,
            createdAt: Date(timeIntervalSince1970: 200),
            isPinned: true,
            folders: [selectedFolder]
        )

        let result = ClipSearchFilter.filter(
            clips: [newestUnpinned, olderPinned, newerPinned],
            selectedFolderID: selectedFolder.folderID,
            searchText: ""
        )

        XCTAssertEqual(
            result.map(\.clipID),
            [newerPinned.clipID, olderPinned.clipID, newestUnpinned.clipID]
        )
    }

    func testVisibleClipsUsesFullFolderContentsForNonClipboardFolders() {
        let clipboardFolder = makeFolder(
            id: ClipFolderModel.clipboardID,
            name: "Clipboard"
        )
        let codeFolder = makeFolder(name: "Code")

        let newestClipboardClip = makeClip(
            previewText: "recent clipboard item",
            sortOrder: 500,
            folders: [clipboardFolder]
        )
        let olderCodeClip = makeClip(
            previewText: "func greet() {}",
            sortOrder: 10,
            folders: [codeFolder]
        )

        link(newestClipboardClip, to: clipboardFolder)
        link(olderCodeClip, to: codeFolder)

        let result = ClipSearchFilter.visibleClips(
            windowClips: [newestClipboardClip],
            selectedFolder: codeFolder,
            searchText: ""
        )

        XCTAssertEqual(result.map(\.clipID), [olderCodeClip.clipID])
    }

    func testTypePrefixFilterStillScopesToSelectedFolder() {
        let selectedFolder = makeFolder(name: "Selected")
        let otherFolder = makeFolder(name: "Other")

        let selectedLink = makeClip(
            typeRaw: ClipType.link.rawValue,
            previewText: "selected link",
            folders: [selectedFolder]
        )
        _ = makeClip(
            typeRaw: ClipType.text.rawValue,
            previewText: "selected text",
            folders: [selectedFolder]
        )
        let otherLink = makeClip(
            typeRaw: ClipType.link.rawValue,
            previewText: "other link",
            folders: [otherFolder]
        )

        let result = ClipSearchFilter.filter(
            clips: [selectedLink, otherLink],
            selectedFolderID: selectedFolder.folderID,
            searchText: "type:link"
        )

        XCTAssertEqual(result.map(\.clipID), [selectedLink.clipID])
    }

    func testFilterMatchesRecognizedTextForImageClips() {
        let selectedFolder = makeFolder(name: "Selected")
        let imageClip = ClipItemModel(
            typeRaw: ClipType.image.rawValue,
            title: "Image",
            previewText: "Image clip",
            imageData: Data([0x89, 0x50, 0x4E, 0x47]),
            recognizedText: "Invoice total 42 dollars",
            sourceAppName: "Tests",
            folders: [selectedFolder]
        )

        let result = ClipSearchFilter.filter(
            clips: [imageClip],
            selectedFolderID: selectedFolder.folderID,
            searchText: "invoice"
        )

        XCTAssertEqual(result.map(\.clipID), [imageClip.clipID])
    }

    func testMergeBackfillResultsAppendsOnlyOlderMatchesMissingFromVisibleWindow() {
        let selectedFolder = makeFolder(name: "Selected")
        let visibleMatch = makeClip(
            previewText: "visible match",
            sortOrder: 100,
            folders: [selectedFolder]
        )
        let olderBackfillMatch = makeClip(
            previewText: "older backfill match",
            sortOrder: 10,
            folders: [selectedFolder]
        )

        let result = ClipSearchFilter.mergeBackfillResults(
            visibleClips: [visibleMatch],
            backfillClips: [visibleMatch, olderBackfillMatch],
            selectedFolderID: selectedFolder.folderID
        )

        XCTAssertEqual(result.map(\.clipID), [visibleMatch.clipID, olderBackfillMatch.clipID])
    }

    func testMergeBackfillResultsStillRespectsSelectedFolderScope() {
        let selectedFolder = makeFolder(name: "Selected")
        let otherFolder = makeFolder(name: "Other")
        let visibleMatch = makeClip(
            previewText: "visible match",
            sortOrder: 100,
            folders: [selectedFolder]
        )
        let wrongFolderBackfill = makeClip(
            previewText: "wrong folder backfill",
            sortOrder: 50,
            folders: [otherFolder]
        )

        let result = ClipSearchFilter.mergeBackfillResults(
            visibleClips: [visibleMatch],
            backfillClips: [wrongFolderBackfill],
            selectedFolderID: selectedFolder.folderID
        )

        XCTAssertEqual(result.map(\.clipID), [visibleMatch.clipID])
    }

    func testNextPinnedSortOrderUsesHighestGlobalSortOrder() {
        let pinnedClip = makeClip(
            previewText: "already pinned",
            sortOrder: 1,
            isPinned: true,
            folders: []
        )
        let newestUnpinnedClip = makeClip(
            previewText: "newest unpinned",
            sortOrder: 500,
            isPinned: false,
            folders: []
        )

        let nextSortOrder = ClipboardStore.nextSortOrder(
            forPinned: true,
            clips: [pinnedClip, newestUnpinnedClip],
            highestSortOrder: 500
        )

        XCTAssertEqual(nextSortOrder, 501)
    }

    func testNextUnpinnedSortOrderIgnoresPinnedSortOrders() {
        let pinnedClip = makeClip(
            previewText: "pinned",
            sortOrder: 900,
            isPinned: true,
            folders: []
        )
        let newestUnpinnedClip = makeClip(
            previewText: "newest unpinned",
            sortOrder: 120,
            isPinned: false,
            folders: []
        )

        let nextSortOrder = ClipboardStore.nextSortOrder(
            forPinned: false,
            clips: [pinnedClip, newestUnpinnedClip],
            highestSortOrder: 900
        )

        XCTAssertEqual(nextSortOrder, 121)
    }

    func testProvisionalBackfillMatchesKeepsOnlyDatabaseFieldHits() {
        let folder = makeFolder(name: "Clipboard")
        let previewHit = makeClip(previewText: "sparkle release notes", folders: [folder])
        let appHit = makeClip(previewText: "unrelated", folders: [folder])
        appHit.sourceAppName = "Sparkle"
        // Matches only on textValue, the DB backfill predicate does not search
        // that field, so the provisional pass must not resurrect it either.
        let textValueOnlyHit = makeClip(previewText: "unrelated", folders: [folder])
        textValueOnlyHit.textValue = "sparkle hidden in full text"
        let miss = makeClip(previewText: "nothing here", folders: [folder])

        let kept = ClipSearchFilter.provisionalBackfillMatches(
            [previewHit, appHit, textValueOnlyHit, miss],
            query: "sparkle"
        )

        XCTAssertEqual(Set(kept.map(\.clipID)), Set([previewHit.clipID, appHit.clipID]))
        XCTAssertTrue(ClipSearchFilter.provisionalBackfillMatches([previewHit], query: "   ").isEmpty)
    }

    private func makeFolder(
        id: UUID = UUID(),
        name: String
    ) -> ClipFolderModel {
        ClipFolderModel(folderID: id, name: name)
    }

    private func makeClip(
        typeRaw: String = ClipType.text.rawValue,
        previewText: String,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        isPinned: Bool = false,
        folders: [ClipFolderModel]
    ) -> ClipItemModel {
        ClipItemModel(
            typeRaw: typeRaw,
            title: previewText,
            previewText: previewText,
            sourceAppName: "Tests",
            createdAt: createdAt,
            sortOrder: sortOrder,
            isPinned: isPinned,
            folders: folders
        )
    }

    private func link(_ clip: ClipItemModel, to folder: ClipFolderModel) {
        if !clip.folders.contains(where: { $0.folderID == folder.folderID }) {
            clip.folders.append(folder)
        }
        if !folder.clips.contains(where: { $0.clipID == clip.clipID }) {
            folder.clips.append(clip)
        }
    }
}
