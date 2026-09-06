import XCTest
@testable import Gilt

/// Round-trip and migration tests for the persisted note JSON shape.
///
/// Two specific concerns:
/// 1. The new `sortOrder` field has to decode as `0` when the JSON came from a
///    build before the field existed — otherwise upgrading the app crashes
///    every existing user's notes library.
/// 2. The new `expandedNoteFolderIDs` on `WorkspaceSession` is optional in the
///    same way and must decode as `[]` when absent.
final class NoteModelCodingTests: XCTestCase {

    // MARK: - NoteItem migration

    func testLegacyNoteItemJSONDecodesWithZeroSortOrder() throws {
        // No `sortOrder` key — this is exactly what a pre-redesign notes.json
        // looks like on disk for existing users.
        let json = """
        {
          "noteID": "\(UUID().uuidString)",
          "folderID": "\(UUID().uuidString)",
          "title": "Legacy note",
          "bodyMarkdown": "hello",
          "createdAt": 754486800,
          "updatedAt": 754486800,
          "lastOpenedAt": 754486800,
          "isPinned": false,
          "isArchived": false,
          "origin": "workspace"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(NoteItem.self, from: json)
        XCTAssertEqual(decoded.sortOrder, 0)
        XCTAssertEqual(decoded.title, "Legacy note")
    }

    func testNewNoteItemRoundTripsSortOrder() throws {
        let note = NoteItem(
            folderID: UUID(),
            title: "Reordered",
            bodyMarkdown: "",
            origin: .workspace,
            sortOrder: 7
        )
        let encoded = try JSONEncoder().encode(note)
        let decoded = try JSONDecoder().decode(NoteItem.self, from: encoded)
        XCTAssertEqual(decoded.sortOrder, 7)
        XCTAssertEqual(decoded.title, "Reordered")
    }

    // MARK: - WorkspaceSession migration

    func testLegacyWorkspaceSessionDecodesWithEmptyExpandedIDs() throws {
        // Pre-tree-redesign payload — no `expandedNoteFolderIDs` field at all.
        let json = """
        {
          "tabs": [],
          "selectedSidebarSection": "notes"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(WorkspaceSession.self, from: json)
        XCTAssertEqual(decoded.expandedNoteFolderIDs, [])
        XCTAssertEqual(decoded.selectedSidebarSection, .clipboard)
    }

    func testWorkspaceSessionRoundTripsExpandedIDs() throws {
        let folderA = UUID()
        let folderB = UUID()
        let session = WorkspaceSession(
            tabs: [],
            selectedTabID: nil,
            selectedSidebarSection: .clipboard,
            expandedNoteFolderIDs: [folderA, folderB]
        )
        let encoded = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(WorkspaceSession.self, from: encoded)
        XCTAssertEqual(decoded.expandedNoteFolderIDs, [folderA, folderB])
    }

    // MARK: - Whole-library snapshot

    func testNotesLibraryStateMigratesEnd2End() throws {
        // Build the kind of JSON the shipped pre-redesign app would have
        // written to disk: NotesLibraryState with notes that have no
        // sortOrder and a workspaceSession with no expandedNoteFolderIDs.
        let folderID = UUID()
        let noteID = UUID()
        let json = """
        {
          "folders": [
            {
              "folderID": "\(folderID.uuidString)",
              "name": "Notes",
              "folderIconRaw": null,
              "colorRaw": "sapphire",
              "sortOrder": 0,
              "isSystem": true
            }
          ],
          "notes": [
            {
              "noteID": "\(noteID.uuidString)",
              "folderID": "\(folderID.uuidString)",
              "title": "Hello",
              "bodyMarkdown": "world",
              "createdAt": 754486800,
              "updatedAt": 754486800,
              "lastOpenedAt": 754486800,
              "isPinned": false,
              "isArchived": false,
              "origin": "workspace"
            }
          ],
          "workspaceSession": {
            "tabs": [],
            "selectedSidebarSection": "notes"
          },
          "kanbanBoardNoteID": null,
          "mirroredClipIDs": {}
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(NotesLibraryState.self, from: json)
        XCTAssertEqual(decoded.notes.count, 1)
        XCTAssertEqual(decoded.notes.first?.sortOrder, 0)
        XCTAssertEqual(decoded.workspaceSession.expandedNoteFolderIDs, [])
    }
}
