import XCTest
@testable import Gilt

final class VaultNoteSerializerTests: XCTestCase {
    private let jackID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let imageID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    private func frontmatter(updated: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> VaultNoteSerializer.Frontmatter {
        VaultNoteSerializer.Frontmatter(
            jackID: jackID,
            created: Date(timeIntervalSince1970: 1_600_000_000),
            updated: updated
        )
    }

    // MARK: - Round trip

    func testPlainBodyRoundTrips() {
        let appBody = "My Note\n\nSome body text\nwith two lines"
        let file = VaultNoteSerializer.fileContents(appBody: appBody, frontmatter: frontmatter())
        let parsed = VaultNoteSerializer.parseFile(file)

        XCTAssertEqual(parsed.jackID, jackID)
        XCTAssertEqual(parsed.appBody, appBody)
    }

    func testBodyWithUserFrontmatterRoundTrips() {
        let appBody = "---\ntags: roadmap, q1\nstatus: active\n---\n\n# Heading\n\nBody"
        let file = VaultNoteSerializer.fileContents(appBody: appBody, frontmatter: frontmatter())
        let parsed = VaultNoteSerializer.parseFile(file)

        XCTAssertEqual(parsed.jackID, jackID)
        XCTAssertEqual(parsed.appBody, appBody)
        // jack-id must be present in the written file's frontmatter.
        XCTAssertTrue(file.contains("jack-id: \(jackID.uuidString.lowercased())"))
        // User keys preserved.
        XCTAssertTrue(file.contains("tags: roadmap, q1"))
    }

    // MARK: - Image link rewriting

    func testImageRefsRewriteToVaultEmbedAndBack() {
        let appBody = "Look:\n\n\(QuickNoteImageMarkdown.imageReference(imageID: imageID))\n\nDone"
        let (vault, ids) = VaultNoteSerializer.vaultBody(fromAppBody: appBody)

        XCTAssertEqual(ids, [imageID])
        XCTAssertTrue(vault.contains("![[\(imageID.uuidString.lowercased()).png]]"))
        XCTAssertFalse(vault.contains("jack-image:"))

        let (restored, restoredIDs) = VaultNoteSerializer.appBody(fromVaultBody: vault)
        XCTAssertEqual(restoredIDs, [imageID])
        XCTAssertEqual(restored, appBody)
    }

    func testFileRoundTripPreservesImages() {
        let appBody = "Photo\n\n\(QuickNoteImageMarkdown.imageReference(imageID: imageID))"
        let file = VaultNoteSerializer.fileContents(appBody: appBody, frontmatter: frontmatter())
        XCTAssertTrue(file.contains("![[\(imageID.uuidString.lowercased()).png]]"))

        let parsed = VaultNoteSerializer.parseFile(file)
        XCTAssertEqual(parsed.appBody, appBody)
        XCTAssertEqual(parsed.imageIDs, [imageID])
    }

    // MARK: - Content hash

    func testContentHashIgnoresFrontmatterTimestamps() {
        let appBody = "Same body"
        let early = VaultNoteSerializer.fileContents(
            appBody: appBody, frontmatter: frontmatter(updated: Date(timeIntervalSince1970: 1))
        )
        let late = VaultNoteSerializer.fileContents(
            appBody: appBody, frontmatter: frontmatter(updated: Date(timeIntervalSince1970: 999_999))
        )
        // Files differ (timestamps), but the app-form body hash is identical, so
        // our own timestamp writes never look like an external change.
        XCTAssertNotEqual(early, late)
        let hashEarly = VaultNoteSerializer.contentHash(appBody: VaultNoteSerializer.parseFile(early).appBody)
        let hashLate = VaultNoteSerializer.contentHash(appBody: VaultNoteSerializer.parseFile(late).appBody)
        XCTAssertEqual(hashEarly, hashLate)
        XCTAssertEqual(hashEarly, VaultNoteSerializer.contentHash(appBody: appBody))
    }

    func testContentHashChangesWithBody() {
        XCTAssertNotEqual(
            VaultNoteSerializer.contentHash(appBody: "a"),
            VaultNoteSerializer.contentHash(appBody: "b")
        )
    }

    func testLegacyGiltIDIsAdoptedAndReserializedAsJackID() {
        // A file written by a pre-rename build carries `gilt-id`, not `jack-id`.
        let legacy = """
        ---
        gilt-id: \(jackID.uuidString.lowercased())
        tags: roadmap
        ---

        # Heading

        Body
        """
        let parsed = VaultNoteSerializer.parseFile(legacy)
        // Identity survives via the fallback, and the legacy key is not leaked
        // back into the app-form body as a user frontmatter key.
        XCTAssertEqual(parsed.jackID, jackID)
        XCTAssertFalse(parsed.appBody.contains("gilt-id"))
        XCTAssertTrue(parsed.appBody.contains("tags: roadmap"))

        // Re-serializing writes jack-id (self-heal) and drops the legacy key.
        let rewritten = VaultNoteSerializer.fileContents(
            appBody: parsed.appBody, frontmatter: frontmatter()
        )
        XCTAssertTrue(rewritten.contains("jack-id: \(jackID.uuidString.lowercased())"))
        XCTAssertFalse(rewritten.contains("gilt-id"))
        XCTAssertEqual(VaultNoteSerializer.parseFile(rewritten).jackID, jackID)
    }

    func testParseFileWithoutJackIDReturnsNil() {
        let parsed = VaultNoteSerializer.parseFile("# A vault-authored note\n\nNo frontmatter here")
        XCTAssertNil(parsed.jackID)
        XCTAssertEqual(parsed.appBody, "# A vault-authored note\n\nNo frontmatter here")
    }
}