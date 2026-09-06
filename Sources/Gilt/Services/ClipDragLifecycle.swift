import AppKit
import Foundation

extension Notification.Name {
    static let clipDragDidStart = Notification.Name("Jack.clipDragDidStart")
    static let clipDragDidEnd = Notification.Name("Jack.clipDragDidEnd")
}

@MainActor
enum ClipDragLifecycle {
    private static var mouseReleaseRecoveryID: UUID?

    static func begin() {
        mouseReleaseRecoveryID = nil
        if NSApp != nil {
            AppWindowManager.shared.setInternalDragActive(true)
        }
        NotificationCenter.default.post(name: .clipDragDidStart, object: nil)
    }

    static func beginWithMouseReleaseRecovery(
        isMousePressed: @escaping @MainActor () -> Bool = { NSEvent.pressedMouseButtons != 0 }
    ) {
        begin()
        let recoveryID = UUID()
        mouseReleaseRecoveryID = recoveryID
        pollForMouseRelease(recoveryID: recoveryID, isMousePressed: isMousePressed)
    }

    static func end() {
        mouseReleaseRecoveryID = nil
        if NSApp != nil {
            AppWindowManager.shared.setInternalDragActive(false)
        }
        NotificationCenter.default.post(name: .clipDragDidEnd, object: nil)
    }

    private static func pollForMouseRelease(
        recoveryID: UUID,
        isMousePressed: @escaping @MainActor () -> Bool
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard mouseReleaseRecoveryID == recoveryID else { return }

            if isMousePressed() {
                pollForMouseRelease(recoveryID: recoveryID, isMousePressed: isMousePressed)
            } else {
                end()
            }
        }
    }
}
