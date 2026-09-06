import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import OSLog

/// Pastes a dictation result into the frontmost app.
///
/// Unlike Handy/Openwhisp — which clobber the user's clipboard with the
/// transcribed text — we *stash* the current pasteboard, write the transcript
/// just long enough to send Cmd+V, then restore. Jack is a clipboard manager,
/// so respecting the clipboard is the table stake.
@MainActor
final class DictationPasteService {
    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "DictationPaste")
    /// How long we hold the pasteboard hostage before restoring. Long enough
    /// for the target app to actually consume the paste, short enough to feel
    /// instant.
    private let restoreDelaySeconds: TimeInterval = 0.35

    /// Paste `text` into the frontmost non-Jack application. Cmd+V fires
    /// immediately; pasteboard restore runs in the background so dictation
    /// doesn't block on a 350ms hold (FluidVoice-style instant handoff).
    func paste(text: String, restorePasteboard: Bool = true) {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let pasteboard = NSPasteboard.general
        let previousItems = restorePasteboard ? snapshotPasteboard(pasteboard) : nil

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        postCmdV()

        guard restorePasteboard, let previousItems else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(self.restoreDelaySeconds * 1_000_000_000))
            self.restore(pasteboard: pasteboard, items: previousItems)
        }
    }

    /// Quietly write `text` to the pasteboard with no Cmd+V — used when
    /// auto-paste is disabled.
    func copyOnly(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - Pasteboard stash/restore

    private struct PasteboardSnapshot {
        let items: [[NSPasteboard.PasteboardType: Data]]
    }

    private func snapshotPasteboard(_ pasteboard: NSPasteboard) -> PasteboardSnapshot {
        var captured: [[NSPasteboard.PasteboardType: Data]] = []
        for item in pasteboard.pasteboardItems ?? [] {
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dict[type] = data
                }
            }
            if !dict.isEmpty {
                captured.append(dict)
            }
        }
        return PasteboardSnapshot(items: captured)
    }

    private func restore(pasteboard: NSPasteboard, items snapshot: PasteboardSnapshot?) {
        guard let snapshot, !snapshot.items.isEmpty else { return }
        pasteboard.clearContents()
        let pbItems: [NSPasteboardItem] = snapshot.items.map { dict in
            let item = NSPasteboardItem()
            for (type, data) in dict {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(pbItems)
    }

    // MARK: - Cmd+V synthesis

    // DANGER ZONE: Requires Accessibility permission. Won't work from
    // `swift run` / Xcode play button — only the packaged .app bundle has
    // the bundle identifier the Accessibility prompt remembers.
    private func postCmdV() {
        let stateIDs: [CGEventSourceStateID] = [.combinedSessionState, .hidSystemState]
        for stateID in stateIDs {
            guard let source = CGEventSource(stateID: stateID) else { continue }
            guard let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: true
            ), let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: false
            ) else { continue }

            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand
            keyDown.post(tap: .cgSessionEventTap)
            keyUp.post(tap: .cgSessionEventTap)
            logger.info("Dictation Cmd+V posted via stateID=\(stateID.rawValue)")
            return
        }
        logger.error("Dictation Cmd+V failed — no working CGEventSource")
    }
}
