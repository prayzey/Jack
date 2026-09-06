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
///   - No timeouts. The single AX call is bounded by macOS internally (a few
///     ms in the normal case, ~50ms on a slow Electron app).
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
        let appElement = AXUIElementCreateApplication(pid)

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
            return .noFocusedElement
        }
        // swiftlint:disable:next force_cast
        let element = (value as! AXUIElement)

        var rawValue: CFTypeRef?
        let valueErr = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &rawValue
        )
        // No value attribute at all — buttons, images, anything non-textual.
        guard valueErr == .success, let raw = rawValue else {
            return .noFocusedElement
        }

        if let str = raw as? String {
            return .success(str)
        }
        // Rich-text editors sometimes back the value with an
        // NSAttributedString. We could `.string` it out, but the bigger
        // problem is that diffing rich-text edits reliably is its own
        // project — skip for v1.
        if raw is NSAttributedString {
            return .unsupportedValueType
        }
        return .unsupportedValueType
    }
}
