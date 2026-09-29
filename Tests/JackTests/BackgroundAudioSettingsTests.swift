import XCTest
@testable import Gilt

/// Pins the pause-vs-duck setting and the Now Playing pause/resume rules.
@MainActor
final class BackgroundAudioSettingsTests: XCTestCase {

    func testPauseModeSurvivesRoundTrip() throws {
        var settings = DictationSettings()
        settings.duckOtherAudio = true
        settings.backgroundAudioMode = .pauseMedia

        let decoded = try JSONDecoder().decode(
            DictationSettings.self,
            from: JSONEncoder().encode(settings)
        )

        XCTAssertTrue(decoded.duckOtherAudio)
        XCTAssertEqual(decoded.backgroundAudioMode, .pauseMedia)
    }

    func testLegacySettingsDefaultToLowerVolume() throws {
        let settings = try JSONDecoder().decode(
            DictationSettings.self,
            from: Data(#"{ "duckOtherAudio": true, "duckAmount": 0.8 }"#.utf8)
        )

        XCTAssertTrue(settings.duckOtherAudio)
        XCTAssertEqual(settings.duckAmount, 0.8, accuracy: 0.001)
        XCTAssertEqual(settings.backgroundAudioMode, .lowerVolume)
    }

    func testPauserResumesOnlyWhatItPaused() async {
        let transport = FakeNowPlayingController()
        let pauser = NowPlayingPauser(transport: transport)

        await pauser.pauseIfPlaying()
        XCTAssertEqual(transport.commands, [.pause])

        await pauser.resumeIfNeeded()
        XCTAssertEqual(transport.commands, [.pause, .play])
    }

    func testPauserDoesNotResumeWhenNothingWasPaused() async {
        let transport = FakeNowPlayingController()
        let pauser = NowPlayingPauser(transport: transport)

        await pauser.resumeIfNeeded()

        XCTAssertTrue(transport.commands.isEmpty)
    }

    func testPauseCopyLocalizes() {
        XCTAssertEqual(
            L10n.string("ui.pause.media", default: "Pause", locale: Locale(identifier: "de")),
            "Pausieren"
        )
        XCTAssertEqual(
            L10n.string("ui.pause.media", default: "Pause", locale: Locale(identifier: "es")),
            "Pausar"
        )
    }
}

@MainActor
private final class FakeNowPlayingController: NowPlayingControlling {
    enum Command: Equatable {
        case pause
        case play
    }

    private(set) var commands: [Command] = []

    func pause() {
        commands.append(.pause)
    }

    func play() {
        commands.append(.play)
    }
}
