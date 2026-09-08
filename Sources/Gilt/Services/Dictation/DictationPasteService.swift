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
    nonisolated static let noHistoryType = NSPasteboard.PasteboardType("dev.novor.jack.dictation.no-history")
    /// How long we hold the pasteboard hostage before restoring. Long enough
    /// for the target app to actually consume the paste, short enough to feel
    /// instant.
    private let restoreDelaySeconds: TimeInterval = 0.35
    private let pasteboard: NSPasteboard
    private let postPaste: @MainActor () -> Bool
    private let targetIsCurrent: @MainActor (DictationPasteTarget) async -> Bool

    init(
        pasteboard: NSPasteboard = .general,
        postPaste: @escaping @MainActor () -> Bool = DictationPasteService.postCmdV,
        targetIsCurrent: @escaping @MainActor (DictationPasteTarget) async -> Bool = { await $0.isCurrent() }
    ) {
        self.pasteboard = pasteboard
        self.postPaste = postPaste
        self.targetIsCurrent = targetIsCurrent
    }

    /// Paste `text` into the frontmost non-Jack application. Cmd+V fires
    /// immediately; pasteboard restore runs in the background so dictation
    /// doesn't block on a 350ms hold (FluidVoice-style instant handoff).
    @discardableResult
    func paste(text: String, restorePasteboard: Bool = true, target: DictationPasteTarget?) async -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        let mayPaste: Bool
        if let target { mayPaste = await targetIsCurrent(target) }
        else { mayPaste = false }
        guard !Task.isCancelled else { return false }
        guard mayPaste else {
            Logger(subsystem: AppBrand.logSubsystem, category: "DictationDelivery")
                .notice("Copied instead of pasting: destinationSnapshotPresent=\(target != nil, privacy: .public)")
            copyOnly(text, saveToHistory: !restorePasteboard)
            return false
        }

        let previousItems = restorePasteboard ? snapshotPasteboard(pasteboard) : nil

        copyOnly(text, saveToHistory: !restorePasteboard)
        let transcriptChangeCount = pasteboard.changeCount
        // If paste cannot be requested, leave the result available for Cmd+V.
        guard postPaste() else {
            Logger(subsystem: AppBrand.logSubsystem, category: "DictationDelivery")
                .notice("Copied instead of pasting: paste shortcut unavailable")
            return false
        }
        Logger(subsystem: AppBrand.logSubsystem, category: "DictationDelivery")
            .notice("Paste shortcut requested for the verified destination")

        guard restorePasteboard, let previousItems else { return true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(self.restoreDelaySeconds * 1_000_000_000))
            // A newer copy belongs to the user; never overwrite it with our snapshot.
            guard self.pasteboard.changeCount == transcriptChangeCount else { return }
            self.restore(pasteboard: pasteboard, items: previousItems)
        }
        return true
    }

    /// Quietly write `text` to the pasteboard with no Cmd+V — used when
    /// auto-paste is disabled.
    func copyOnly(_ text: String, saveToHistory: Bool = true) {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        if !saveToHistory { item.setData(Data(), forType: Self.noHistoryType) }
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
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
        guard let snapshot else { return }
        pasteboard.clearContents()
        let pbItems: [NSPasteboardItem] = snapshot.items.map { dict in
            let item = NSPasteboardItem()
            for (type, data) in dict {
                item.setData(data, forType: type)
            }
            return item
        }
        if !pbItems.isEmpty { pasteboard.writeObjects(pbItems) }
    }

    // MARK: - Cmd+V synthesis

    // DANGER ZONE: Requires Accessibility permission. Won't work from
    // `swift run` / Xcode play button — only the packaged .app bundle has
    // the bundle identifier the Accessibility prompt remembers.
    private static func postCmdV() -> Bool {
        guard AccessibilityService.isTrusted() else { return false }
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
            return true
        }
        return false
    }
}
