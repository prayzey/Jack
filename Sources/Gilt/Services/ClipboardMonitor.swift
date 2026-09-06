import AppKit
import Foundation
import OSLog

@MainActor
final class ClipboardMonitor {
    // Readable by tests (@testable) to assert start() never leaks a prior poll
    // timer; the setter stays private so only the monitor manages its lifecycle.
    private(set) var timer: Timer?
    private var lastChangeCount: Int
    private let onCapture: (CapturedClip, Int, String) -> Void

    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "ClipboardMonitor")
    private let perfLoggingEnabled = ProcessInfo.processInfo.environment["GILT_DEBUG_LOGS"] == "1"

    // Stats tracked across the session for periodic summary
    private var pollCount: Int = 0
    private var captureCount: Int = 0
    private var missCount: Int = 0
    private var lastStatsDump: Date = Date()

    init(onCapture: @escaping (CapturedClip, Int, String) -> Void) {
        self.onCapture = onCapture
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        logPerf("start changeCount=\(NSPasteboard.general.changeCount)")
        // Idempotent: invalidate any existing poll timer before scheduling a new
        // one. start() is called again on every trial-refresh tick (~60s, via
        // evaluateTrialState -> syncMonitorWithAccessState). Without this, each
        // call orphaned a still-firing 0.6s repeating timer on the run loop —
        // the run loop retains repeating timers, so thousands accumulated over
        // days, each polling the pasteboard, until the main thread was pegged
        // just arming timers. Do not remove.
        timer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.pollPasteboard()
            }
        }
        timer.tolerance = 0.1
        self.timer = timer
    }

    func stop() {
        logPerf("stop pollCount=\(pollCount) captures=\(captureCount) misses=\(missCount)")
        timer?.invalidate()
        timer = nil
    }

    private func pollPasteboard() async {
        pollCount += 1
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else {
            dumpStatsIfNeeded()
            return
        }
        lastChangeCount = pasteboard.changeCount

        let startedAt = DispatchTime.now()
        guard let capture = CapturedClip.fromPasteboard(pasteboard) else {
            missCount += 1
            logPerf("poll changeDetected but parse returned nil (\(elapsedMs(since: startedAt))ms)")
            return
        }
        captureCount += 1
        let dataSize = capture.imageData?.count ?? capture.textValue?.utf8.count ?? 0
        logPerf("poll captured type=\(capture.type.rawValue) dataSize=\(dataSize)B parseTime=\(elapsedMs(since: startedAt))ms")
        let hash = await ContentFingerprint.fingerprintAsync(
            type: capture.type,
            textValue: capture.textValue ?? capture.previewText,
            urlValue: capture.urlValue,
            imageData: capture.imageData
        )
        onCapture(capture, pasteboard.changeCount, hash)
    }

    /// Dump aggregate stats every 60s so we can spot poll health issues
    private func dumpStatsIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastStatsDump) >= 60 else { return }
        lastStatsDump = now
        logPerf("stats polls=\(pollCount) captures=\(captureCount) misses=\(missCount)")
    }

    private func elapsedMs(since start: DispatchTime) -> String {
        let delta = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
        return String(format: "%.2f", Double(delta) / 1_000_000)
    }

    private func logPerf(_ message: String) {
        guard perfLoggingEnabled else { return }
        logger.debug("\(message, privacy: .public)")
    }
}

struct CapturedClip: Sendable {
    let type: ClipType
    let title: String
    let previewText: String
    let textValue: String?
    let urlValue: String?
    let imageData: Data?

    private static let parseLogger = Logger(subsystem: AppBrand.logSubsystem, category: "ClipboardParse")
    private static let parseLoggingEnabled = ProcessInfo.processInfo.environment["GILT_DEBUG_LOGS"] == "1"
    private static let audioFileExtensions: Set<String> = [
        "aac", "aiff", "flac", "m4a", "mp3", "ogg", "wav"
    ]

    /// Reads the current pasteboard and produces a typed CapturedClip.
    ///
    /// **Classification order matters.** macOS pasteboard items can carry multiple representations
    /// simultaneously (e.g., a browser puts both URL and string types). We check types in
    /// priority order: image > URL > plain string. This means:
    ///   - Copying a URL from a browser → arrives with NSPasteboardTypeURL → becomes `.link`
    ///   - Copying the same URL text from a text editor → only plain string → also becomes `.link`
    ///     (via `webLinkCapture`, which normalizes bare domains like "example.com")
    ///   - Typing "wow.md" in Notes → only plain string → `webLinkCapture` must NOT match this
    ///     as a URL, even though .md is a valid TLD. See `looksLikeFilename()` guard in
    ///     `ClipActionService.normalizeWebURL`.
    ///
    /// Because the same content can end up as either .link or .text depending on the source app,
    /// any content-aware rendering (creative previews, smart categorization) must handle both
    /// ClipType paths. See `CreativeTextPattern.detect()` comments for the rendering side.
    static func fromPasteboard(_ pasteboard: NSPasteboard) -> CapturedClip? {
        let startedAt = DispatchTime.now()

        if let pngData = pasteboard.data(forType: .png) {
            logParse("png size=\(pngData.count)B", since: startedAt)
            return CapturedClip(
                type: .image,
                title: "Image",
                previewText: "Image clip",
                textValue: nil,
                urlValue: nil,
                imageData: Data(pngData)
            )
        }

        if let tiffData = pasteboard.data(forType: .tiff),
           let image = NSImage(data: tiffData),
           let pngData = image.pngData() {
            logParse("tiff->png tiffSize=\(tiffData.count)B pngSize=\(pngData.count)B", since: startedAt)
            return CapturedClip(
                type: .image,
                title: "Image",
                previewText: "Image clip",
                textValue: nil,
                urlValue: nil,
                imageData: pngData
            )
        }

        if let urlString = pasteboard.string(forType: .URL),
           let url = URL(string: urlString),
           url.scheme?.isEmpty == false {
            if let audioCapture = audioCapture(from: url, fallbackText: urlString) {
                return audioCapture
            }
            return CapturedClip(
                type: .link,
                title: "Link",
                previewText: url.host ?? urlString,
                textValue: urlString,
                urlValue: urlString,
                imageData: nil
            )
        }

        if let text = pasteboard.string(forType: .string), text.isEmpty == false {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { return nil }
            if let audioCapture = audioCapture(fromPathLikeText: trimmed) {
                return audioCapture
            }
            if let linkCapture = webLinkCapture(fromText: trimmed) {
                return linkCapture
            }
            return CapturedClip(
                type: .text,
                title: "Text",
                previewText: trimmed,
                textValue: trimmed,
                urlValue: nil,
                imageData: nil
            )
        }

        return nil
    }

    static func audioCapture(fromPathLikeText text: String) -> CapturedClip? {
        guard text.contains(" ") == false else { return nil }
        let candidate = URL(fileURLWithPath: text)
        guard isAudioFileURL(candidate) else { return nil }
        return CapturedClip(
            type: .audio,
            title: "Audio",
            previewText: audioPreviewText(for: candidate, fallback: text),
            textValue: text,
            urlValue: candidate.isFileURL ? nil : candidate.absoluteString,
            imageData: nil
        )
    }

    static func webLinkCapture(fromText text: String) -> CapturedClip? {
        guard let normalizedURL = ClipActionService.normalizeWebURL(text) else { return nil }
        let displayText = normalizedURL.host(percentEncoded: false) ?? normalizedURL.absoluteString
        return CapturedClip(
            type: .link,
            title: "Link",
            previewText: displayText,
            textValue: normalizedURL.absoluteString,
            urlValue: normalizedURL.absoluteString,
            imageData: nil
        )
    }

    private static func audioCapture(from url: URL, fallbackText: String) -> CapturedClip? {
        guard isAudioFileURL(url) else { return nil }
        return CapturedClip(
            type: .audio,
            title: "Audio",
            previewText: audioPreviewText(for: url, fallback: fallbackText),
            textValue: fallbackText,
            urlValue: url.isFileURL ? nil : url.absoluteString,
            imageData: nil
        )
    }

    private static func isAudioFileURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext.isEmpty == false && audioFileExtensions.contains(ext)
    }

    private static func audioPreviewText(for url: URL, fallback: String) -> String {
        let filename = url.deletingPathExtension().lastPathComponent
        return filename.isEmpty ? fallback : filename
    }

    private static func logParse(_ message: String, since start: DispatchTime) {
        guard parseLoggingEnabled else { return }
        let delta = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
        let ms = String(format: "%.2f", Double(delta) / 1_000_000)
        let logMsg = "parse \(message) time=\(ms)ms"
        parseLogger.debug("\(logMsg, privacy: .public)")
    }
}
