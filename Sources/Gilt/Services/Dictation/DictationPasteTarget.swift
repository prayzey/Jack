import AppKit
import ApplicationServices
import OSLog

/// An ephemeral destination snapshot: the app that was frontmost when
/// dictation started and, when AX exposes one, its focused text field.
/// Never persisted, and holds none of the field's contents.
struct DictationPasteTarget: @unchecked Sendable {
    let pid: pid_t
    let element: AXUIElement?

    static func capture(pid: pid_t) -> DictationPasteTarget {
        DictationPasteTarget(pid: pid, element: AXFocusedElementReader.focusedTextElement(pid: pid))
    }

    /// Paste only where dictation started: the same app, and the same text
    /// field when both reads succeed. The field's text and caret are allowed
    /// to change, because editors that restyle or autosave, terminals with
    /// streaming output, and a previous paste landing late all change them
    /// without the user going anywhere. A failed AX read is not evidence of a
    /// move either: Electron apps answer only once their tree wakes up, and a
    /// busy main thread times out queries into Jack's own windows.
    @MainActor
    func isCurrent() async -> Bool {
        let logger = Logger(subsystem: AppBrand.logSubsystem, category: "DictationDelivery")
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
            logger.notice("Destination verification: frontmost app changed")
            return false
        }
        guard let element else { return true }
        let pid = pid
        guard let current = await Task.detached(operation: { Self.capture(pid: pid) }).value.element else {
            return true
        }
        let sameField = CFEqual(element, current)
        logger.notice("Destination verification: sameField=\(sameField, privacy: .public)")
        return sameField && NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
    }
}
