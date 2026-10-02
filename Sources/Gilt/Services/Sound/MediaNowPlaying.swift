import AppKit
import Combine
import OSLog

struct NowPlayingTrack: Equatable {
    var title: String
    var artist: String
    var isPlaying: Bool
    var artwork: NSImage?   // nil until loaded or if unavailable
}

/// Now playing for Spotify and Apple Music in the sound panel. Read through
/// AppleScript because macOS 15.4 blocks MediaRemote for third-party apps.
///
/// Scripts run in a child `osascript` process rather than `NSAppleScript`:
/// NSAppleScript isn't documented as thread-safe and `SpotifyControlService`
/// already uses it on the main thread, so running it on a second thread
/// would share the in-process AppleScript component across threads. A child
/// process also can't wedge Jack when a target app hangs, and macOS
/// attributes its Apple events to Jack, so the Automation prompt and grant
/// are Jack's. The cost is one short-lived process per query, only while
/// the panel is open.
@MainActor
final class MediaNowPlaying: ObservableObject {
    static let shared = MediaNowPlaying()
    static let supportedBundleIDs: Set<String> = ["com.spotify.client", "com.apple.Music"]
    /// Keyed by bundle ID. An app is absent when it isn't running, has nothing loaded, or Jack isn't allowed to ask it.
    @Published private(set) var tracks: [String: NowPlayingTrack] = [:]

    // Status scripts print "isPlaying␟title␟artist␟artworkKey" (␟ is ASCII 31),
    // or nothing when stopped. The artwork key is Spotify's artwork URL or
    // Music's persistent track ID.
    //
    // The `is running` guard covers an app quitting between the
    // NSRunningApplication check and the script: a `tell` would relaunch it.
    // It must be `not (… is running)`; `… is not running` parses as something
    // else, is always false, and launches the app.
    nonisolated static let spotifyStatusScript = """
        if not (application id "com.spotify.client" is running) then return ""
        tell application id "com.spotify.client"
            if player state is stopped then return ""
            set d to character id 31
            return ((player state is playing) as text) & d & name of current track & d & artist of current track & d & artwork url of current track
        end tell
        """
    nonisolated static let musicStatusScript = """
        if not (application id "com.apple.Music" is running) then return ""
        tell application id "com.apple.Music"
            if player state is stopped then return ""
            set d to character id 31
            return ((player state is playing) as text) & d & name of current track & d & artist of current track & d & persistent ID of current track
        end tell
        """
    /// Writes the current track's artwork, in its original JPEG/PNG bytes, to
    /// the file at argv 1, unless the track is no longer the one with
    /// persistent ID argv 2. A file because osascript can only print data as hex.
    nonisolated static let musicArtworkScript = """
        on run argv
            if not (application id "com.apple.Music" is running) then return
            tell application id "com.apple.Music"
                if persistent ID of current track is not item 2 of argv then return
                set d to raw data of artwork 1 of current track
            end tell
            set f to open for access (POSIX file (item 1 of argv)) with write permission
            try
                write d to f
            end try
            close access f
        end run
        """

    /// Errors worth retrying on the next poll: the app quit mid-query (-600,
    /// -609), was too busy to answer (-1712), or was between tracks (-1728).
    private static let transientErrorCodes: Set<Int> = [-600, -609, -1712, -1728]

    private let log = Logger(subsystem: AppBrand.logSubsystem, category: "MediaNowPlaying")
    /// Apps that denied Automation (-1743) or failed in a way retrying won't
    /// fix. Not asked again this session, so a denied user sees no more prompts.
    private var blocked: Set<String> = []
    /// Artwork key of the track each app is showing, so artwork loads once per track.
    private var artworkKeys: [String: String] = [:]
    private let artworkCache = NSCache<NSString, NSImage>()
    private var pollTask: Task<Void, Never>?

    private init() {
        artworkCache.countLimit = 30
    }

    #if DEBUG
    /// Sample tracks for snapshot tests.
    func loadPreview(_ tracks: [String: NowPlayingTrack]) {
        self.tracks = tracks
    }
    #endif

    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func playPause(_ bundleID: String) {
        send("playpause", to: bundleID)
    }

    func nextTrack(_ bundleID: String) {
        send("next track", to: bundleID)
    }

    /// Parses a status script's output. Returns nil when nothing is loaded or
    /// the output is malformed.
    nonisolated static func parse(_ output: String) -> (track: NowPlayingTrack, artworkKey: String)? {
        let fields = output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\u{1F}")
        guard fields.count == 4, let isPlaying = Bool(fields[0]), !fields[1].isEmpty else { return nil }
        // AppleScript prints a missing artwork URL (ads, local files) as "missing value".
        let artworkKey = fields[3] == "missing value" ? "" : fields[3]
        return (NowPlayingTrack(title: fields[1], artist: fields[2], isPlaying: isPlaying, artwork: nil), artworkKey)
    }

    /// The Apple event error number osascript ends its error line with, e.g.
    /// "… Not authorized to send Apple events to Music. (-1743)".
    nonisolated static func errorCode(in stderr: String) -> Int? {
        stderr.firstMatch(of: #/\((-?\d+)\)\s*$/#).flatMap { Int($0.1) }
    }

    struct ScriptError: Error {
        var code: Int?
        var message: String
    }

    /// One serial queue, so queries never overlap and at most one Automation
    /// prompt is up at a time. No timeout on purpose: the first query waits
    /// while macOS shows that prompt, and killing it would prompt again on the
    /// next poll.
    nonisolated private static let scriptQueue = DispatchQueue(label: "Jack.MediaNowPlaying.osascript")

    nonisolated static func runScript(_ source: String, arguments: [String] = []) async -> Result<String, ScriptError> {
        await withCheckedContinuation { continuation in
            scriptQueue.async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", source] + arguments
                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: .failure(ScriptError(code: nil, message: error.localizedDescription)))
                    return
                }
                // Read before waiting: osascript blocks on a full pipe and would never exit.
                let output = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                let errorOutput = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    continuation.resume(returning: .success(output))
                } else {
                    let message = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: .failure(ScriptError(code: errorCode(in: errorOutput), message: message)))
                }
            }
        }
    }

    nonisolated private static func musicArtwork(persistentID: String) async -> Data? {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("jack-artwork-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        guard case .success = await runScript(musicArtworkScript, arguments: [file.path, persistentID]) else { return nil }
        return try? Data(contentsOf: file)
    }

    // MARK: - Private

    /// Only ask an app that's already running: `tell application` launches it otherwise.
    private func canQuery(_ bundleID: String) -> Bool {
        Self.supportedBundleIDs.contains(bundleID)
            && !blocked.contains(bundleID)
            && !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    private func refresh() async {
        for bundleID in Self.supportedBundleIDs {
            await refresh(bundleID)
        }
    }

    private func refresh(_ bundleID: String) async {
        guard canQuery(bundleID) else { return setTrack(nil, for: bundleID) }
        let script = bundleID == "com.apple.Music" ? Self.musicStatusScript : Self.spotifyStatusScript
        switch await Self.runScript(script) {
        case .failure(let error):
            handle(error, from: bundleID)
        case .success(let output):
            guard let parsed = Self.parse(output) else { return setTrack(nil, for: bundleID) }
            var track = parsed.track
            let key = parsed.artworkKey
            if artworkKeys[bundleID] == key {
                // Same track: keep what's shown (nil while loading or if it failed).
                track.artwork = tracks[bundleID]?.artwork
            } else {
                artworkKeys[bundleID] = key
                track.artwork = artworkCache.object(forKey: key as NSString)
                if track.artwork == nil, !key.isEmpty { loadArtwork(key, for: bundleID) }
            }
            setTrack(track, for: bundleID)
        }
    }

    private func loadArtwork(_ key: String, for bundleID: String) {
        Task {
            let data: Data?
            if bundleID == "com.apple.Music" {
                data = await Self.musicArtwork(persistentID: key)
            } else if let url = URL(string: key), url.scheme == "https" || url.scheme == "http" {
                data = try? await URLSession.shared.data(from: url).0
            } else {
                data = nil
            }
            guard let data, let image = NSImage(data: data) else { return }
            artworkCache.setObject(image, forKey: key as NSString)
            if artworkKeys[bundleID] == key { tracks[bundleID]?.artwork = image }
        }
    }

    private func send(_ command: String, to bundleID: String) {
        guard canQuery(bundleID) else { return }
        let script = "if application id \"\(bundleID)\" is running then tell application id \"\(bundleID)\" to \(command)"
        Task {
            if case .failure(let error) = await Self.runScript(script) { handle(error, from: bundleID) }
            await refresh(bundleID)
        }
    }

    private func handle(_ error: ScriptError, from bundleID: String) {
        setTrack(nil, for: bundleID)
        if let code = error.code, Self.transientErrorCodes.contains(code) { return }
        blocked.insert(bundleID)
        log.error("Stopped reading now playing from \(bundleID, privacy: .public) for this session: \(error.message, privacy: .public)")
    }

    private func setTrack(_ track: NowPlayingTrack?, for bundleID: String) {
        // Forget the artwork key so a returning track picks its artwork up again.
        if track == nil { artworkKeys[bundleID] = nil }
        // Assigning even an equal value fires objectWillChange and redraws the panel every poll.
        if tracks[bundleID] != track { tracks[bundleID] = track }
    }
}
