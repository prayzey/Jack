import Foundation

/// Something a sound command can act on: an app, or a browser tab.
struct SoundTarget: Equatable {
    enum Kind: Equatable { case app, tab }

    let id: String
    let name: String
    let kind: Kind
    /// Other words that should find it, like a tab's site ("youtube").
    var aliases: [String] = []
}

/// A sound command typed into Jack's chat or the command palette:
/// "mute chrome", "zoom to 30%", "turn spotify down", "solo music",
/// "what's playing". Parsing is deterministic so it never needs the AI model.
enum SoundCommand: Equatable {
    case setVolume(SoundTarget, Double)
    case mute(SoundTarget)
    case unmute(SoundTarget)
    case solo(SoundTarget)
    case lower(SoundTarget)
    case raise(SoundTarget)
    case whatsPlaying

    /// How far "turn it down" or "louder" moves the volume.
    static let step = 0.2

    static func parse(_ text: String, targets: [SoundTarget]) -> SoundCommand? {
        let lowered = text.lowercased()
        let words = lowered
            .replacingOccurrences(of: "’", with: "'")
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'%")).inverted)
            .filter { !$0.isEmpty }
        let joined = " " + words.joined(separator: " ") + " "

        if ["what's playing", "what is playing", "whats playing", "what's making noise",
            "what is making noise", "what's making sound", "what is making sound"].contains(where: joined.contains) {
            return .whatsPlaying
        }
        guard let target = bestTarget(in: joined, targets: targets) else { return nil }

        func has(_ phrases: String...) -> Bool { phrases.contains { joined.contains(" \($0) ") } }

        if has("unmute") { return .unmute(target) }
        if has("mute", "silence", "hush") { return .mute(target) }
        if has("solo", "only hear", "just hear") { return .solo(target) }
        if let percent = percentage(in: words, excluding: target) { return .setVolume(target, percent) }
        if has("down", "lower", "quieter", "softer", "too loud", "reduce") { return .lower(target) }
        if has("up", "louder", "raise", "too quiet", "increase", "boost") { return .raise(target) }
        return nil
    }

    /// The target whose name (or a distinctive word of it, like "chrome" in
    /// "Google Chrome") appears in the text. Longest match wins, so
    /// "apple music" beats "music" and a tab's site beats a stray word.
    private static func bestTarget(in joined: String, targets: [SoundTarget]) -> SoundTarget? {
        var best: (target: SoundTarget, score: Int)?
        for target in targets {
            let name = target.name.lowercased()
            let candidates = [name] + name.split(separator: " ").map(String.init).filter { $0.count >= 3 }
                + target.aliases.map { $0.lowercased() }
            for candidate in candidates where !candidate.isEmpty && !genericWords.contains(candidate) {
                guard joined.contains(" \(candidate) ") else { continue }
                // Apps beat tabs on a tie: "mute music" means the Music app.
                let score = candidate.count * 2 + (target.kind == .app ? 1 : 0)
                if score > (best?.score ?? 0) { best = (target, score) }
            }
        }
        return best?.target
    }

    /// Words too common to identify an app on their own.
    private static let genericWords: Set<String> = [
        "the", "and", "app", "for", "new", "tab", "volume", "sound", "audio", "music player",
    ]

    /// "40", "40%", "to 40 percent" → 0.4. Ignores numbers that are part of
    /// the app's name.
    private static func percentage(in words: [String], excluding target: SoundTarget) -> Double? {
        let nameWords = Set(target.name.lowercased().split(separator: " ").map(String.init))
        for word in words where !nameWords.contains(word) {
            let digits = word.hasSuffix("%") ? String(word.dropLast()) : word
            if let value = Int(digits), (0...100).contains(value) {
                return Double(value) / 100
            }
        }
        return nil
    }
}

/// Runs sound commands against the live mixer and browser tabs, and words
/// the reply Jack gives in chat.
@MainActor
enum SoundCommandRunner {
    /// Parses and runs `text`. nil when it isn't a sound command, so chat
    /// can hand it to the AI model instead.
    static func handle(_ text: String) -> String? {
        guard let command = SoundCommand.parse(text, targets: targets()) else { return nil }
        return run(command)
    }

    static func targets() -> [SoundTarget] {
        let mixer = SoundMenuBarController.shared.mixer
        let apps = (mixer.activeApps + mixer.quietApps).map { app in
            // "zoom.us" should answer to "zoom".
            SoundTarget(id: app.id, name: app.name, kind: .app, aliases: [siteName(app.name)])
        }
        let tabs = BrowserTabBridge.shared.tabs.map { tab in
            SoundTarget(id: tab.id, name: tab.title, kind: .tab, aliases: [siteName(tab.host)])
        }
        return apps + tabs
    }

    @discardableResult
    static func run(_ command: SoundCommand) -> String {
        let mixer = SoundMenuBarController.shared.mixer
        let tabs = BrowserTabBridge.shared

        func volume(of target: SoundTarget) -> Double {
            switch target.kind {
            case .app: return mixer.levels[target.id]?.volume ?? 1
            case .tab: return tabs.tabs.first { $0.id == target.id }?.volume ?? 1
            }
        }
        func setVolume(_ value: Double, _ target: SoundTarget) -> String {
            let clamped = max(0, min(1, value))
            switch target.kind {
            case .app: mixer.setVolume(clamped, for: target.id)
            case .tab: tabs.setVolume(clamped, for: target.id)
            }
            return String(format: L10n.string("sound.command.volume", default: "%@ is at %d%%."), target.name, Int((clamped * 100).rounded()))
        }
        func setMuted(_ muted: Bool, _ target: SoundTarget) -> String {
            switch target.kind {
            case .app: mixer.setMuted(muted, for: target.id)
            case .tab: tabs.setMuted(muted, for: target.id)
            }
            return String(
                format: muted ? L10n.string("sound.command.muted", default: "Muted %@.")
                    : L10n.string("sound.command.unmuted", default: "Unmuted %@."),
                target.name
            )
        }

        switch command {
        case .whatsPlaying:
            let tracks = MediaNowPlaying.shared.tracks
            let playing = mixer.activeApps.map { app in
                tracks[app.id].map { "\(app.name) (\($0.title) · \($0.artist))" } ?? app.name
            } + tabs.tabs.filter(\.isAudible).map(\.title)
            return playing.isEmpty
                ? L10n.string("sound.command.nothing.playing", default: "Nothing is playing right now.")
                : String(format: L10n.string("sound.command.playing", default: "Playing now: %@."),
                         ListFormatter.localizedString(byJoining: playing))
        case .setVolume(let target, let value):
            return setVolume(value, target)
        case .lower(let target):
            return setVolume(volume(of: target) - SoundCommand.step, target)
        case .raise(let target):
            return setVolume(volume(of: target) + SoundCommand.step, target)
        case .mute(let target):
            return setMuted(true, target)
        case .unmute(let target):
            return setMuted(false, target)
        case .solo(let target):
            guard target.kind == .app else {
                return L10n.string("sound.command.solo.tabs", default: "I can solo apps, but not single tabs yet.")
            }
            mixer.toggleSolo(target.id)
            return mixer.rules.soloAppID == target.id
                ? String(format: L10n.string("sound.command.solo.on", default: "Only %@ is playing now. Ask again to bring everything back."), target.name)
                : String(format: L10n.string("sound.command.solo.off", default: "Everything is playing again, not just %@."), target.name)
        }
    }

    /// "youtube.com" → "youtube", "zoom.us" → "zoom".
    private static func siteName(_ text: String) -> String {
        String(text.lowercased().split(separator: ".").first ?? "")
    }
}
