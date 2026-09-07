import AppKit
import ApplicationServices
import CryptoKit

/// An ephemeral destination snapshot. Never persisted; keep only a digest of
/// the field's contents so a later edit can prevent an unexpected paste.
struct DictationPasteTarget: @unchecked Sendable {
    let pid: pid_t
    let element: AXUIElement
    let valueDigest: SHA256.Digest
    let selection: CFRange?

    static func capture(pid: pid_t) -> DictationPasteTarget? {
        guard let element = AXFocusedElementReader.focusedTextElement(pid: pid) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let text = value as? String, text.utf8.count <= 1_000_000 else { return nil }
        var selected: CFTypeRef?
        var range = CFRange()
        let hasSelection = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selected) == .success
            && selected.map { CFGetTypeID($0) == AXValueGetTypeID() } == true
            && AXValueGetValue(selected as! AXValue, .cfRange, &range)
        return DictationPasteTarget(
            pid: pid, element: element, valueDigest: SHA256.hash(data: Data(text.utf8)),
            selection: hasSelection ? range : nil
        )
    }

    @MainActor
    func isCurrent() async -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return false }
        let current = await Task.detached { Self.capture(pid: pid) }.value
        guard let current else { return false }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
            && CFEqual(element, current.element)
            && valueDigest == current.valueDigest
            && selection?.location == current.selection?.location
            && selection?.length == current.selection?.length
    }
}
