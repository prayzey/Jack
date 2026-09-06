import Foundation
import OSLog

/// Verbose logger for meeting-feature downloads. Writes to BOTH:
///   1. stdout (visible when the binary is launched directly with a redirect)
///   2. OSLog under subsystem `Jack`, category `MeetingDownload`
///
/// The OSLog path is the reliable one. To stream live logs from any terminal
/// regardless of how the app was launched:
///   log stream --predicate 'subsystem == "Jack" AND category == "MeetingDownload"' --info
///
/// Or for a one-shot snapshot:
///   log show --predicate 'subsystem == "Jack" AND category == "MeetingDownload"' --info --last 5m
///
/// Every line gets a `[meeting]` prefix so users can grep the output cleanly.
enum MeetingDownloadLog {
    /// Throttle for progress messages — without this we'd flood the terminal
    /// with thousands of "X.XX%" lines per download.
    nonisolated(unsafe) private static var lastEmittedPercent: [String: Int] = [:]
    nonisolated(unsafe) private static var lastEmittedAt: [String: Date] = [:]
    private static let throttleLock = NSLock()

    /// Dedicated OSLog logger for download events. Use `info` level so
    /// messages survive without enabling debug-level capture.
    private static let osLogger = Logger(subsystem: AppBrand.logSubsystem, category: "MeetingDownload")

    static func log(_ message: String) {
        // `Date.ISO8601FormatStyle` is Sendable, unlike `ISO8601DateFormatter`,
        // so no per-call formatter allocation is needed under Swift 6.
        let timestamp = Date().ISO8601Format(.iso8601(timeZone: .gmt, includingFractionalSeconds: true))
        // Mirror to stdout when the binary is launched with a redirect.
        print("[meeting] \(timestamp) \(message)")
        fflush(stdout)
        // And always to OSLog so `log stream` picks it up regardless of how
        // the app was launched. Public-marked so the message isn't redacted
        // as `<private>` in default log capture.
        osLogger.info("\(message, privacy: .public)")
    }

    /// Emit a progress line, throttled to one update per whole-number percent
    /// per stream (keyed by `label`). Always emits 0% and 100% lines.
    static func progress(_ label: String, fraction: Double, totalBytes: Int64? = nil) {
        let percent = Int((fraction * 100).rounded())
        throttleLock.lock()
        let prevPercent = lastEmittedPercent[label] ?? -1
        let prevAt = lastEmittedAt[label] ?? .distantPast
        let now = Date()
        let isMajor = percent == 0 || percent == 100 || percent != prevPercent
        let isFresh = now.timeIntervalSince(prevAt) > 0.5
        guard isMajor && isFresh else { throttleLock.unlock(); return }
        lastEmittedPercent[label] = percent
        lastEmittedAt[label] = now
        throttleLock.unlock()

        var line = "\(label) \(percent)% (\(String(format: "%.3f", fraction)))"
        if let totalBytes {
            let received = Int64(fraction * Double(totalBytes))
            line += " — \(byteString(received)) / \(byteString(totalBytes))"
        }
        log(line)
    }

    static func resetCounter(_ label: String) {
        throttleLock.lock()
        lastEmittedPercent.removeValue(forKey: label)
        lastEmittedAt.removeValue(forKey: label)
        throttleLock.unlock()
    }

    private static func byteString(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
