import Foundation

/// Whether macOS lets Jack capture other apps' audio ("System Audio
/// Recording"), which per-app volume needs.
///
/// There's no public API to ask. This uses TCC's own preflight call, looked up
/// at runtime the way AudioCap (BSD 2-Clause) does, so a macOS without it just
/// reports `.unknown` and the mixer falls back to probing with a silent tap.
/// Jack ships outside the App Store, so the private lookup is acceptable.
enum AudioCapturePermission {
    enum Status { case authorized, denied, unknown }

    static func status() -> Status {
        guard let preflight else { return .unknown }
        switch preflight("kTCCServiceAudioCapture" as CFString, nil) {
        case 0: return .authorized
        case 1: return .denied
        default: return .unknown
        }
    }

    private typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int

    private static let preflight: Preflight? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW),
              let symbol = dlsym(handle, "TCCAccessPreflight")
        else { return nil }
        return unsafeBitCast(symbol, to: Preflight.self)
    }()
}
