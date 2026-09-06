import AVFoundation
import Foundation
import OSLog
import SwiftOGG

/// Decodes Ogg-encapsulated Opus audio — the format WhatsApp, Telegram, and
/// Signal export voice notes as — into an `.m4a` file that Apple's audio stack
/// (and therefore WhisperKit / FluidAudio) can read.
///
/// Why this type exists: both transcription engines load audio through
/// `AVAudioFile(forReading:)`, and AVFoundation on macOS cannot parse the Ogg
/// container. Every other common format (.m4a/.mp3/.wav/.caf/.aiff/.aac) flows
/// straight into the engines untouched; Ogg-Opus is the one format that needs
/// this pre-decode hop.
///
/// Keeping the SwiftOGG dependency walled off behind this single type means the
/// rest of the feature has no compile/link coupling to the Opus libraries — if
/// we ever swap decoders, only this file changes.
enum OpusAudioDecoder {
    /// File extensions we treat as Ogg-Opus and route through SwiftOGG. `.oga`
    /// is the audio-only Ogg extension some exporters use; `.ogg` can in theory
    /// carry Vorbis, but voice-note exporters (WhatsApp et al.) always use Opus,
    /// and SwiftOGG will surface a decode error if a stray Vorbis file shows up.
    static let oggOpusExtensions: Set<String> = ["opus", "ogg", "oga"]

    /// Whether `url` is an Ogg-Opus file that AVFoundation can't read directly
    /// and therefore must be transcoded before transcription.
    static func needsDecoding(_ url: URL) -> Bool {
        oggOpusExtensions.contains(url.pathExtension.lowercased())
    }

    /// Converts an Ogg-Opus file to a temporary `.m4a` and returns its URL.
    ///
    /// The caller owns the returned file and is responsible for deleting it once
    /// transcription finishes (see `AudioFileTranscriptionService`, which wraps
    /// this in a `defer`).
    static func decodeToTemporaryM4A(_ source: URL) throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("jack-opus-\(UUID().uuidString).m4a")
        try OGGConverter.convertOpusOGGToM4aFile(src: source, dest: destination)
        return destination
    }
}
