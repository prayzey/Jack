import XCTest
@testable import Gilt

@MainActor
final class MeetingStorageTests: XCTestCase {
    private var tempRoot: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("JackMeetingTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRoot)
        tempRoot = nil
        try await super.tearDown()
    }

    private func makeStore() -> MeetingStore {
        MeetingStore(meetingsRoot: tempRoot)
    }

    func testRoundTripSessionAndTranscript() throws {
        let store = makeStore()
        let session = store.createSession(
            title: "Launch sync",
            language: .english
        )

        let chunkA = MeetingTranscriptChunk(
            startTimeSeconds: 0,
            endTimeSeconds: 4,
            text: "We agreed to ship Thursday.",
            engineRaw: MeetingTranscriptionEngine.parakeetV2.rawValue
        )
        let chunkB = MeetingTranscriptChunk(
            startTimeSeconds: 4,
            endTimeSeconds: 8,
            text: "Action item: marketing draft.",
            engineRaw: MeetingTranscriptionEngine.parakeetV2.rawValue
        )
        store.appendTranscriptChunk(chunkA, to: session.meetingID)
        store.appendTranscriptChunk(chunkB, to: session.meetingID)

        let loaded = store.loadTranscript(for: session.meetingID)
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded.map(\.text), [
            "We agreed to ship Thursday.",
            "Action item: marketing draft."
        ])
    }

    func testReplaceTranscriptOverwritesPreviousFile() throws {
        let store = makeStore()
        let session = store.createSession(
            title: "Test",
            language: .english
        )
        for i in 0..<3 {
            store.appendTranscriptChunk(
                MeetingTranscriptChunk(
                    startTimeSeconds: Double(i) * 4,
                    endTimeSeconds: Double(i) * 4 + 4,
                    text: "Line \(i)",
                    engineRaw: MeetingTranscriptionEngine.parakeetV2.rawValue
                ),
                to: session.meetingID
            )
        }

        let replacement = [
            MeetingTranscriptChunk(
                startTimeSeconds: 0,
                endTimeSeconds: 12,
                text: "Cleaned transcript.",
                engineRaw: MeetingTranscriptionEngine.parakeetV2.rawValue
            )
        ]
        store.replaceTranscript(replacement, for: session.meetingID)
        let loaded = store.loadTranscript(for: session.meetingID)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.text, "Cleaned transcript.")
    }

    func testSummaryAndAskHistoryRoundTrip() throws {
        let store = makeStore()
        let session = store.createSession(
            title: "Sync",
            language: .english
        )

        let summary = MeetingSummary(
            meetingID: session.meetingID,
            headline: "Synced on launch",
            bullets: ["Ship Thursday"],
            decisions: [MeetingDecision(text: "Move price tier to $19")],
            actionItems: [MeetingActionItem(text: "Send announcement Friday")],
            followUpQuestions: [MeetingFollowUpQuestion(text: "What about EU pricing?")],
            rollingNotes: "Discussion on launch + pricing"
        )
        store.saveSummary(summary, for: session.meetingID)
        XCTAssertEqual(store.loadSummary(for: session.meetingID)?.headline, "Synced on launch")

        let history = [
            MeetingQuestion(
                meetingID: session.meetingID,
                question: "What did we decide?",
                answer: "Move price tier."
            )
        ]
        store.saveAskHistory(history, for: session.meetingID)
        XCTAssertEqual(store.loadAskHistory(for: session.meetingID).count, 1)
        XCTAssertEqual(store.loadAskHistory(for: session.meetingID).first?.question, "What did we decide?")
    }

    func testRenameSessionTrimsTitleAndPersists() throws {
        let store = makeStore()
        let session = store.createSession(title: "Untitled", language: .english)

        let renamed = store.renameSession(session.meetingID, to: "  Weekly Sync  ")
        XCTAssertEqual(renamed?.title, "Weekly Sync")
        XCTAssertEqual(store.session(for: session.meetingID)?.title, "Weekly Sync")

        // Reopening from disk must see the new title (rename hit persistence).
        let reopened = MeetingStore(meetingsRoot: tempRoot)
        XCTAssertEqual(reopened.session(for: session.meetingID)?.title, "Weekly Sync")
    }

    func testRenameSessionToBlankRestoresDateFallback() throws {
        let store = makeStore()
        let session = store.createSession(title: "Has Name", language: .english)

        let renamed = store.renameSession(session.meetingID, to: "   ")
        XCTAssertEqual(renamed?.title, "")
        // Empty title is valid — displayTitle falls back to a non-empty date.
        XCTAssertFalse(renamed?.displayTitle.isEmpty ?? true)
    }

    func testRenameSessionDoesNotReorderList() throws {
        let store = makeStore()
        let older = store.createSession(title: "Older", language: .english)
        let newer = store.createSession(title: "Newer", language: .english)

        // Reopen from disk to prove timestamp serialization preserves the order.
        let reopened = MeetingStore(meetingsRoot: tempRoot)
        XCTAssertEqual(reopened.sessions.first?.meetingID, newer.meetingID)

        // Renaming the older meeting must not bump it above the newer one.
        reopened.renameSession(older.meetingID, to: "Older Renamed")
        XCTAssertEqual(reopened.sessions.first?.meetingID, newer.meetingID)
    }

    func testDeleteSessionRemovesAllArtifacts() throws {
        let store = makeStore()
        let session = store.createSession(
            title: "Doomed",
            language: .german
        )
        store.appendTranscriptChunk(
            MeetingTranscriptChunk(
                startTimeSeconds: 0,
                endTimeSeconds: 4,
                text: "Test",
                engineRaw: MeetingTranscriptionEngine.whisperSmallMultilingual.rawValue
            ),
            to: session.meetingID
        )

        let folder = MeetingAppSupportLocator.sessionFolder(
            meetingID: session.meetingID,
            in: store.sessionsRoot
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))

        store.deleteSession(session.meetingID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertNil(store.session(for: session.meetingID))
    }
}
