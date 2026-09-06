import Foundation
import SwiftUI

/// Recognized link platforms for rich preview rendering.
enum LinkPlatform: String, Sendable, Codable, CaseIterable {
    case youtube
    case youtubeMusic
    case spotify
    case appleMusic
    case appStore
    case playStore
    case github
    case twitter
    case reddit
    case soundcloud
    case vimeo
    case tidal
    case deezer

    /// Detect platform from a URL's host.
    static func detect(from url: URL) -> LinkPlatform? {
        guard let host = url.host(percentEncoded: false)?.lowercased() else { return nil }

        // Order matters: more specific hosts first
        if host.contains("music.youtube.com") { return .youtubeMusic }
        if host.contains("youtube.com") || host.contains("youtu.be") { return .youtube }
        if host.contains("open.spotify.com") || host.contains("spotify.com") { return .spotify }
        if host.contains("music.apple.com") { return .appleMusic }
        if host.contains("apps.apple.com") { return .appStore }
        if host.contains("play.google.com") { return .playStore }
        if host.contains("github.com") { return .github }
        if host.contains("twitter.com") || host.contains("x.com") { return .twitter }
        if host.contains("reddit.com") { return .reddit }
        if host.contains("soundcloud.com") { return .soundcloud }
        if host.contains("vimeo.com") { return .vimeo }
        if host.contains("tidal.com") || host.contains("listen.tidal.com") { return .tidal }
        if host.contains("deezer.com") { return .deezer }

        return nil
    }

    var displayName: String {
        switch self {
        case .youtube: return "YouTube"
        case .youtubeMusic: return "YT Music"
        case .spotify: return "Spotify"
        case .appleMusic: return "Apple Music"
        case .appStore: return L10n.string("linkPlatform.appStore.name", default: "App Store")
        case .playStore: return L10n.string("linkPlatform.playStore.name", default: "Play Store")
        case .github: return "GitHub"
        case .twitter: return "Twitter"
        case .reddit: return "Reddit"
        case .soundcloud: return "SoundCloud"
        case .vimeo: return "Vimeo"
        case .tidal: return "Tidal"
        case .deezer: return "Deezer"
        }
    }

    /// Header gradient colors — (r, g, b) tuples in 0…1
    var headerGradient: (start: (Double, Double, Double), end: (Double, Double, Double)) {
        switch self {
        case .youtube:
            return (start: (0.72, 0.08, 0.08), end: (0.88, 0.14, 0.14))
        case .youtubeMusic:
            return (start: (0.72, 0.08, 0.08), end: (0.88, 0.14, 0.14))
        case .spotify:
            return (start: (0.06, 0.50, 0.24), end: (0.10, 0.64, 0.32))
        case .appleMusic:
            return (start: (0.85, 0.12, 0.22), end: (0.95, 0.20, 0.28))
        case .appStore:
            return (start: (0.05, 0.40, 0.88), end: (0.12, 0.52, 0.96))
        case .playStore:
            return (start: (0.00, 0.40, 0.30), end: (0.08, 0.54, 0.40))
        case .github:
            return (start: (0.12, 0.14, 0.16), end: (0.20, 0.22, 0.26))
        case .twitter:
            return (start: (0.10, 0.52, 0.82), end: (0.16, 0.62, 0.90))
        case .reddit:
            return (start: (0.88, 0.20, 0.02), end: (0.96, 0.30, 0.08))
        case .soundcloud:
            return (start: (0.88, 0.26, 0.02), end: (0.96, 0.36, 0.06))
        case .vimeo:
            return (start: (0.06, 0.56, 0.80), end: (0.12, 0.68, 0.90))
        case .tidal:
            return (start: (0.00, 0.00, 0.00), end: (0.12, 0.12, 0.16))
        case .deezer:
            return (start: (0.60, 0.00, 0.88), end: (0.72, 0.08, 0.96))
        }
    }

    /// Accent color for selection borders — (r, g, b) in 0…1
    var accentColor: (r: Double, g: Double, b: Double) {
        switch self {
        case .youtube, .youtubeMusic: return (0.92, 0.18, 0.18)
        case .spotify: return (0.11, 0.72, 0.33)
        case .appleMusic: return (0.96, 0.22, 0.32)
        case .appStore: return (0.12, 0.55, 0.98)
        case .playStore: return (0.08, 0.56, 0.42)
        case .github: return (0.50, 0.54, 0.60)
        case .twitter: return (0.16, 0.62, 0.90)
        case .reddit: return (0.96, 0.30, 0.08)
        case .soundcloud: return (0.96, 0.36, 0.06)
        case .vimeo: return (0.12, 0.68, 0.90)
        case .tidal: return (0.50, 0.50, 0.56)
        case .deezer: return (0.72, 0.08, 0.96)
        }
    }

    /// SwiftUI Color for the accent
    var accentSwiftUIColor: Color {
        Color(red: accentColor.r, green: accentColor.g, blue: accentColor.b)
    }

}
