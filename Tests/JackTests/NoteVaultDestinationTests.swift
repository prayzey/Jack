import XCTest
@testable import Gilt

/// Verifies the per-note vault destination field and the vault settings fields
/// survive Codable round-trips (including legacy blobs missing the new keys),
/// and that destination normalization behaves.
final class NoteVaultDestinationTests: XCTestCase {
    func testNoteItemRoundTripsVaultFolder() throws {
        var note = NoteItem(folderID: UUID(), origin: .quickNote)
        note.vaultRelativeFolder = "Projects/Q3"

        let data = try JSONEncoder().encode(note)
        let decoded = try JSONDecoder().decode(NoteItem.self, from: data)

        XCTAssertEqual(decoded.vaultRelativeFolder, "Projects/Q3")
    }

    func testLegacyNoteWithoutVaultFolderDecodesToNil() throws {
        // Simulate a note persisted before the field existed: encode, strip the
        // key, decode. Missing key must default to nil ("not synced").
        let note = NoteItem(folderID: UUID(), origin: .quickNote)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(note)) as! [String: Any]
        json.removeValue(forKey: "vaultRelativeFolder")
        let data = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(NoteItem.self, from: data)

        XCTAssertNil(decoded.vaultRelativeFolder)
    }

    func testAppSettingsRoundTripsVaultFields() throws {
        var settings = AppSettings()
        settings.notesVaultBookmark = Data([0x01, 0x02, 0x03])
        settings.notesVaultDisplayPath = "/Users/me/Vault"

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.notesVaultBookmark, Data([0x01, 0x02, 0x03]))
        XCTAssertEqual(decoded.notesVaultDisplayPath, "/Users/me/Vault")
    }

    func testAppSettingsWithoutVaultFieldsDecodeToNil() throws {
        // A default AppSettings has nil vault fields, which encodeIfPresent omits
        // entirely — so this also covers decoding a pre-feature settings blob.
        let settings = AppSettings()

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertNil(decoded.notesVaultBookmark)
        XCTAssertNil(decoded.notesVaultDisplayPath)
    }

    func testNormalizedVaultFolder() {
        XCTAssertNil(ClipboardStore.normalizedVaultFolder(nil))
        XCTAssertNil(ClipboardStore.normalizedVaultFolder(""))
        XCTAssertNil(ClipboardStore.normalizedVaultFolder("   "))
        XCTAssertNil(ClipboardStore.normalizedVaultFolder("/"))
        XCTAssertEqual(ClipboardStore.normalizedVaultFolder("  Projects/Q3  "), "Projects/Q3")
        XCTAssertEqual(ClipboardStore.normalizedVaultFolder("/Projects/"), "Projects")
    }
}
