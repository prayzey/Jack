import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Maps to the macOS Screen Recording (a.k.a. "Screen & System Audio Recording"
/// on macOS 15+) permission. We surface this in Settings > Advanced > Permissions
/// so users can see at a glance whether System Audio capture for meetings will
/// work, and jump directly to the right pane when it doesn't.
enum ScreenRecordingPermissionStatus: Equatable {
    case notDetermined
    case authorized
    case denied
    case unknown

    var isGranted: Bool { self == .authorized }
}

enum ScreenRecordingPermissionService {
    /// macOS does not expose a non-blocking authorization status enum for screen
    /// capture the way it does for microphone (`AVCaptureDevice.authorizationStatus`).
    /// `CGPreflightScreenCaptureAccess()` is the closest stable signal: it
    /// returns `true` only if the calling process is already authorized in TCC,
    /// and `false` otherwise (notDetermined and denied collapse to the same
    /// result). We treat `false` as "not granted" — the UI then offers the
    /// "Open Settings" action which lands on the right pane regardless.
    static func currentStatus() -> ScreenRecordingPermissionStatus {
        CGPreflightScreenCaptureAccess() ? .authorized : .denied
    }

    /// Requests Screen Recording access. On first call this triggers the macOS
    /// permission prompt; on subsequent calls (already denied) it's a no-op.
    /// The result is whether access is currently granted after the call.
    ///
    /// Note: `CGRequestScreenCaptureAccess()` returns immediately — granting in
    /// System Settings doesn't update the running process; the user must
    /// relaunch the app for the new permission to take effect. We still
    /// surface the prompt so first-time users get the system dialog.
    @discardableResult
    static func requestAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    /// Opens System Settings to the Screen Recording privacy pane. On macOS 15+
    /// the pane is labelled "Screen & System Audio Recording" but the URL
    /// scheme is unchanged.
    static func openSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
