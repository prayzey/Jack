import AppKit
import Foundation
import OSLog

/// Lightweight Spotify playback control via AppleScript. No API keys or
/// account linking — works when the Spotify Mac app is installed.
enum SpotifyControlCommand: String, CaseIterable {
    case play
    case pause
    case skip
    case currentTrack
}

enum SpotifyControlResult: Equatable {
    case success(message: String)
    case spotifyNotInstalled
    case notRunning
    case scriptFailed(String)
}

enum SpotifyVoiceParser {
    static func parse(_ transcript: String) -> SpotifyControlCommand? {
        let cleaned = TranscriptCleaner
            .clean(transcript)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !cleaned.isEmpty else { return nil }

        if cleaned.contains("what's playing")
            || cleaned.contains("whats playing")
            || cleaned.contains("current song")
            || cleaned.contains("current track")
            || cleaned.contains("now playing") {
            return .currentTrack
        }
        if cleaned.contains("skip")
            || cleaned.contains("next song")
            || cleaned.contains("next track") {
            return .skip
        }
        if cleaned == "pause"
            || cleaned.hasPrefix("pause ")
            || cleaned.contains("stop music")
            || cleaned.contains("stop playing") {
            return .pause
        }
        if cleaned == "play"
            || cleaned.hasPrefix("play ")
            || cleaned.contains("resume")
            || cleaned.contains("start music")
            || cleaned.contains("start playing") {
            return .play
        }
        return nil
    }
}

@MainActor
enum SpotifyControlService {
    private static let log = Logger(subsystem: AppBrand.logSubsystem, category: "SpotifyControl")
    private static let bundleID = "com.spotify.client"

    static var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    static func run(_ command: SpotifyControlCommand) -> SpotifyControlResult {
        guard isInstalled else { return .spotifyNotInstalled }

        let script: String
        switch command {
        case .play:
            script = "tell application \"Spotify\" to play"
        case .pause:
            script = "tell application \"Spotify\" to pause"
        case .skip:
            script = "tell application \"Spotify\" to next track"
        case .currentTrack:
            script = """
            tell application "Spotify"
                if player state is not playing then
                    return "Nothing is playing right now."
                end if
                set trackName to name of current track
                set artistName to artist of current track
                return trackName & " by " & artistName
            end tell
            """
        }

        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            return .scriptFailed("Couldn't build AppleScript.")
        }
        let output = appleScript.executeAndReturnError(&error)
        if let error {
            let message = (error[NSAppleScript.errorMessage] as? String) ?? "Spotify command failed."
            if message.localizedCaseInsensitiveContains("not running") {
                return .notRunning
            }
            log.error("Spotify AppleScript failed: \(message, privacy: .public)")
            return .scriptFailed(message)
        }

        switch command {
        case .play:
            return .success(message: "Playing in Spotify.")
        case .pause:
            return .success(message: "Paused Spotify.")
        case .skip:
            return .success(message: "Skipped to the next track.")
        case .currentTrack:
            let text = output.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            return .success(message: text?.isEmpty == false ? text! : "Nothing is playing right now.")
        }
    }
}