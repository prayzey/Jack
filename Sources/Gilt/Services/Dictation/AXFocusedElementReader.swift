import ApplicationServices
import Foundation

/// Tiny AX helper: given a process ID, read the plain-text value of that
/// process's currently focused UI element.
///
/// Used by `CorrectionLearner` to watch what the user does to a freshly-pasted
/// dictation. We deliberately keep this *much* simpler than
/// `ScreenContextReader`:
///   - One element (the focused one), not a tree walk.
///   - Plain-string AXValue only — no NSAttributedString, no role inspection,
///     no children. If the field doesn't hand us a `String`, we give up.
    ///   - Bounded AX messaging and no secure fields.
///
/// **Why this isn't `@MainActor`.** Polling happens on a detached task that
/// runs every 1s — pinning to the main actor would block dictation UI on each
/// AX round-trip. AX is thread-safe for read attribute access, so we keep
/// this `nonisolated` and call freely from any context.
enum AXFocusedElementReader {
    /// Outcome of a single read. Distinguishing the three failure modes
    /// helps the caller decide whether to retry, give up, or surface a
    /// friendly error to the user.
    enum Result {
        /// Got a plain-text value back. May be empty (cleared field).
        case success(String)
        /// The app didn't expose a focused element via AX — usually means
        /// the user clicked away, the window closed, or the app is one of
        /// the few that hides text from AX.
        case noFocusedElement
        /// AX returned a value but not as a `String` — common in
        /// NSAttributedString-backed editors (rich text, web textareas in
        /// some browsers). We don't try to coerce; we just bail.
        case unsupportedValueType
    }

    /// Read the focused element's value from the app with the given pid.
    /// Safe to call from any thread.
    static func readFocusedTextValue(pid: pid_t) -> Result {
        guard let element = focusedTextElement(pid: pid) else { return .noFocusedElement }
        var rawValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &rawValue) == .success,
              let text = rawValue as? String else { return .unsupportedValueType }
        return .success(text)
    }

    static func focusedTextElement(pid: pid_t) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.15)

        var focused: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )
        // A .success result does not guarantee the value is an AXUIElement —
        // a misbehaving app can hand back another CF type. `as?` can't validate a
        // CoreFoundation type (it always succeeds), so compare CFTypeIDs explicitly;
        // a mismatch degrades to "no focused element" instead of crashing on the cast.
        guard err == .success,
              let value = focused,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        // swiftlint:disable:next force_cast
        let element = (value as! AXUIElement)
        AXUIElementSetMessagingTimeout(element, 0.15)
        var role: CFTypeRef?
        var subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        guard let role = role as? String,
              [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role),
              subrole as? String != kAXSecureTextFieldSubrole else { return nil }
        return element
    }
}
