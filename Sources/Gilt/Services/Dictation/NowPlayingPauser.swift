import AppKit
import Foundation
import OSLog

/// Sends pause/play to the system Now Playing target (YouTube in a browser,
/// Music, Spotify, most sites that use the Media Session API). Zoom and
/// Google Meet typically are not that target, so a meeting keeps going.
@MainActor
protocol NowPlayingControlling: AnyObject {
    func pause()
    func play()
}

/// Pauses Now Playing when dictation starts and resumes it only if we were
/// the ones who paused it.
@MainActor
final class NowPlayingPauser {
    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "NowPlayingPauser")
    private let transport: NowPlayingControlling
    private var didPause = false
    private var inFlight: Task<Void, Never>?

    init(transport: NowPlayingControlling = MediaKeyNowPlayingController()) {
        self.transport = transport
    }

    /// Always send pause. Reading Now Playing state from Jack's own process
    /// is a lie on macOS 15.4+ (the daemon rejects unentitled apps and
    /// reports "not playing"), which made the first version skip this call.
    func pauseIfPlaying() async {
        await inFlight?.value
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            self.transport.pause()
            self.didPause = true
            self.logger.info("Sent pause to Now Playing")
        }
        inFlight = task
        await task.value
    }

    /// Resume only when this session paused something.
    func resumeIfNeeded() async {
        await inFlight?.value
        guard didPause else { return }
        transport.play()
        didPause = false
        logger.info("Sent play to Now Playing")
    }
}

/// Posts the same play/pause event as the keyboard media key.
///
/// In-process `MediaRemote.framework` calls are a silent no-op starting in
/// macOS 15.4, so we do not use them.
final class MediaKeyNowPlayingController: NowPlayingControlling {
    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "NowPlayingPauser")

    func pause() {
        MediaKeyBridge.postPlayPause()
        logger.info("Posted media-key pause")
    }

    func play() {
        MediaKeyBridge.postPlayPause()
        logger.info("Posted media-key play")
    }
}

/// Keyboard play/pause (`NX_KEYTYPE_PLAY`). Same event class Control Center
/// and the F8 media key use. Not `key code 100`, which is just the F8 glyph.
private enum MediaKeyBridge {
    private static let playPauseKey: Int32 = 16

    static func postPlayPause() {
        post(down: true)
        Thread.sleep(forTimeInterval: 0.015)
        post(down: false)
    }

    private static func post(down: Bool) {
        let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
        let data1 = Int((playPauseKey << 16) | ((down ? 0xA : 0xB) << 8))
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        ) else { return }
        event.cgEvent?.post(tap: .cghidEventTap)
    }
}
