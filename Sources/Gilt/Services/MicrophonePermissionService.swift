import AppKit
@preconcurrency import AVFoundation
import Foundation

enum MicrophonePermissionStatus: Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted
    case unknown

    var isGranted: Bool {
        self == .authorized
    }

    init(_ authorizationStatus: AVAuthorizationStatus) {
        switch authorizationStatus {
        case .notDetermined:
            self = .notDetermined
        case .authorized:
            self = .authorized
        case .denied:
            self = .denied
        case .restricted:
            self = .restricted
        @unknown default:
            self = .unknown
        }
    }
}

enum MicrophonePermissionService {
    static func currentStatus() -> MicrophonePermissionStatus {
        MicrophonePermissionStatus(AVCaptureDevice.authorizationStatus(for: .audio))
    }

    @discardableResult
    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            await MainActor.run {
                NSApp.activate(ignoringOtherApps: true)
            }
            return await AVCaptureDevice.requestAccess(for: .audio)
        @unknown default:
            return false
        }
    }

    static func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
