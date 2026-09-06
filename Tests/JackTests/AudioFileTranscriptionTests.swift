import AVFoundation
import Foundation
import XCTest
@testable import Gilt

final class AudioFileTranscriptionTests: XCTestCase {

    // MARK: - Supported-file detection

    func testNativeAudioFormatsAreSupported() {
        for ext in ["m4a", "mp3", "wav", "aiff", "caf", "aac", "mp4"] {
            let url = URL(fileURLWithPath: "/tmp/clip.\(ext)")
            XCTAssertTrue(
                AudioFileTranscriptionService.isSupportedAudioFile(url),
                "\(ext) should be transcribable"
            )
        }
    }

    func testOggOpusVoiceNotesAreSupported() {
        // WhatsApp/Telegram/Signal voice notes — the motivating case.
        for ext in ["opus", "ogg", "oga"] {
            let url = URL(fileURLWithPath: "/tmp/PTT-20260613-WA0001.\(ext)")
            XCTAssertTrue(
                AudioFileTranscriptionService.isSupportedAudioFile(url),
                "\(ext) should be transcribable"
            )
        }
    }

    func testDetectionIsCaseInsensitive() {
        XCTAssertTrue(AudioFileTranscriptionService.isSupportedAudioFile(URL(fileURLWithPath: "/tmp/A.M4A")))
        XCTAssertTrue(AudioFileTranscriptionService.isSupportedAudioFile(URL(fileURLWithPath: "/tmp/A.OPUS")))
    }

    func testNonAudioFilesAreRejected() {
        for ext in ["txt", "png", "pdf", "json", "mov.txt", ""] {
            let url = URL(fileURLWithPath: "/tmp/file.\(ext)")
            XCTAssertFalse(
                AudioFileTranscriptionService.isSupportedAudioFile(url),
                "\(ext) should NOT be transcribable"
            )
        }
    }

    func testStoreAliasMatchesService() {
        let url = URL(fileURLWithPath: "/tmp/note.opus")
        XCTAssertEqual(
            ClipboardStore.isTranscribableAudioFile(url),
            AudioFileTranscriptionService.isSupportedAudioFile(url)
        )
    }

    // MARK: - Opus decode routing

    func testOnlyOggOpusNeedsPreDecoding() {
        XCTAssertTrue(OpusAudioDecoder.needsDecoding(URL(fileURLWithPath: "/tmp/a.opus")))
        XCTAssertTrue(OpusAudioDecoder.needsDecoding(URL(fileURLWithPath: "/tmp/a.OGG")))
        // Formats AVFoundation reads natively must skip the decode hop.
        XCTAssertFalse(OpusAudioDecoder.needsDecoding(URL(fileURLWithPath: "/tmp/a.m4a")))
        XCTAssertFalse(OpusAudioDecoder.needsDecoding(URL(fileURLWithPath: "/tmp/a.mp3")))
        XCTAssertFalse(OpusAudioDecoder.needsDecoding(URL(fileURLWithPath: "/tmp/a.wav")))
    }

    // MARK: - Engine selection

    func testRecommendedEngineWinsWhenItsModelIsReady() {
        let engine = AudioFileTranscriptionService.preferredEngine(
            recommended: .whisperSmallMultilingual,
            recommendedReady: true,
            alternative: .parakeetV2,
            alternativeReady: true
        )
        XCTAssertEqual(engine, .whisperSmallMultilingual)
    }

    func testFallsBackToAlreadyDownloadedAlternative() {
        // Recommended model missing but the other is on disk — use what's there
        // instead of forcing a surprise ~500MB download.
        let engine = AudioFileTranscriptionService.preferredEngine(
            recommended: .whisperSmallMultilingual,
            recommendedReady: false,
            alternative: .parakeetV2,
            alternativeReady: true
        )
        XCTAssertEqual(engine, .parakeetV2)
    }

    func testFallsBackToRecommendedWhenNothingDownloaded() {
        let engine = AudioFileTranscriptionService.preferredEngine(
            recommended: .whisperSmallMultilingual,
            recommendedReady: false,
            alternative: .parakeetV2,
            alternativeReady: false
        )
        XCTAssertEqual(engine, .whisperSmallMultilingual)
    }

    func testLanguageRoutingMatchesMeetingRecommendation() {
        // English routes to the fast English engine; everything else to the
        // multilingual one — the file feature inherits this mapping.
        XCTAssertEqual(MeetingTranscriptionEngine.recommended(for: .english), .parakeetV2)
        XCTAssertEqual(MeetingTranscriptionEngine.recommended(for: .auto), .whisperSmallMultilingual)
        XCTAssertEqual(MeetingTranscriptionEngine.recommended(for: .german), .whisperSmallMultilingual)
    }

    // MARK: - Transcript assembly

    func testJoinChunksTrimsAndDropsEmptyChunks() {
        let chunks = [
            MeetingTranscriptChunk(startTimeSeconds: 0, endTimeSeconds: 1, text: "  Hello ", engineRaw: "whisper"),
            MeetingTranscriptChunk(startTimeSeconds: 1, endTimeSeconds: 2, text: "   ", engineRaw: "whisper"),
            MeetingTranscriptChunk(startTimeSeconds: 2, endTimeSeconds: 3, text: "world  ", engineRaw: "whisper")
        ]
        XCTAssertEqual(AudioFileTranscriptionService.joinChunks(chunks), "Hello world")
    }

    func testJoinChunksOnEmptyInputIsEmpty() {
        XCTAssertEqual(AudioFileTranscriptionService.joinChunks([]), "")
    }

    // MARK: - HUD stage flags

    func testTerminalStagesDriveHUDDismissal() {
        XCTAssertTrue(TranscriptionJob.Stage.completed(charCount: 10).isTerminal)
        XCTAssertTrue(TranscriptionJob.Stage.noSpeech.isTerminal)
        XCTAssertTrue(TranscriptionJob.Stage.failed(message: "x").isTerminal)
        XCTAssertFalse(TranscriptionJob.Stage.transcribing.isTerminal)
        XCTAssertFalse(TranscriptionJob.Stage.preparingModel(progress: 0.5).isTerminal)
    }

    func testFailureStagesGetTheLongerAutoHideWindow() {
        XCTAssertTrue(TranscriptionJob.Stage.failed(message: "x").isFailure)
        XCTAssertTrue(TranscriptionJob.Stage.noSpeech.isFailure)
        XCTAssertFalse(TranscriptionJob.Stage.completed(charCount: 1).isFailure)
    }

    // MARK: - Opus decode (real runtime integration)

    /// The motivating case, proven end to end: a real Ogg-Opus file (the format
    /// WhatsApp exports) decodes through SwiftOGG into an `.m4a` that Apple's
    /// audio stack — and therefore the transcription engines — can actually read.
    /// This is the one piece that can't be proven by types alone.
    func testDecodesRealOggOpusFixtureToReadableAudio() throws {
        let fixture = Self.fixtureURL("voice-note.opus")
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: fixture.path),
            "Missing Ogg-Opus fixture"
        )

        let decoded = try OpusAudioDecoder.decodeToTemporaryM4A(fixture)
        defer { try? FileManager.default.removeItem(at: decoded) }

        XCTAssertTrue(FileManager.default.fileExists(atPath: decoded.path))
        XCTAssertEqual(decoded.pathExtension, "m4a")

        // The real proof: AVFoundation opens the decoded file and finds audio.
        let file = try AVAudioFile(forReading: decoded)
        XCTAssertGreaterThan(file.length, 0, "Decoded audio should contain frames")
    }

    private static func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
    }
}
