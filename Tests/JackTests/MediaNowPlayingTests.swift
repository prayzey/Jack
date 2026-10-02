import XCTest
@testable import Gilt

final class MediaNowPlayingTests: XCTestCase {
    /// ASCII unit separator, the field delimiter the status scripts print.
    private let sep = "\u{1F}"

    func testSpotifyPlaying() throws {
        let output = "true\(sep)Blinding Lights\(sep)The Weeknd\(sep)https://i.scdn.co/image/ab67616d0000b273\n"
        let parsed = try XCTUnwrap(MediaNowPlaying.parse(output))
        XCTAssertEqual(parsed.track, NowPlayingTrack(title: "Blinding Lights", artist: "The Weeknd", isPlaying: true, artwork: nil))
        XCTAssertEqual(parsed.artworkKey, "https://i.scdn.co/image/ab67616d0000b273")
    }

    func testMusicPaused() throws {
        let output = "false\(sep)Clair de Lune\(sep)Claude Debussy\(sep)7A3F0C1D2E4B5A69\n"
        let parsed = try XCTUnwrap(MediaNowPlaying.parse(output))
        XCTAssertEqual(parsed.track, NowPlayingTrack(title: "Clair de Lune", artist: "Claude Debussy", isPlaying: false, artwork: nil))
        XCTAssertEqual(parsed.artworkKey, "7A3F0C1D2E4B5A69")
    }

    func testStoppedOrNotRunningIsAbsent() {
        for output in ["", "\n", "  \n"] {
            XCTAssertNil(MediaNowPlaying.parse(output), "output: \(output.debugDescription)")
        }
    }

    func testMetadataWithCommasQuotesAndNewlinesIsKeptVerbatim() throws {
        let title = "Hello, \"World\"\nPart 2"
        let artist = "Simon & Garfunkel, 'Live'"
        let parsed = try XCTUnwrap(MediaNowPlaying.parse("true\(sep)\(title)\(sep)\(artist)\(sep)ABC\n"))
        XCTAssertEqual(parsed.track.title, title)
        XCTAssertEqual(parsed.track.artist, artist)
        XCTAssertEqual(parsed.artworkKey, "ABC")
    }

    func testEmptyArtistAndMissingArtworkURL() throws {
        let parsed = try XCTUnwrap(MediaNowPlaying.parse("true\(sep)Advertisement\(sep)\(sep)missing value\n"))
        XCTAssertEqual(parsed.track.artist, "")
        XCTAssertEqual(parsed.artworkKey, "")
    }

    func testMalformedOutputIsRejected() {
        let outputs = [
            "true\(sep)Only a title",
            "true\(sep)T\(sep)A\(sep)key\(sep)extra",
            "maybe\(sep)T\(sep)A\(sep)key",
            "true\(sep)\(sep)Artist\(sep)key",
            "true, Title, Artist, key",
            "0:12: execution error: Can’t get current track. (-1728)",
        ]
        for output in outputs {
            XCTAssertNil(MediaNowPlaying.parse(output), "output: \(output.debugDescription)")
        }
    }

    func testErrorCodeFromOsascriptStderr() {
        XCTAssertEqual(MediaNowPlaying.errorCode(in: "6:53: execution error: Not authorized to send Apple events to Music. (-1743)\n"), -1743)
        XCTAssertEqual(MediaNowPlaying.errorCode(in: "12:40: execution error: Spotify got an error: Application isn’t running. (-600)"), -600)
        XCTAssertNil(MediaNowPlaying.errorCode(in: "osascript: couldn't launch"))
    }
}
