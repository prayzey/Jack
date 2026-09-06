import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

extension ClipboardStore {
    private enum ClipboardWritePayload {
        case image(Data)
        case text(String)
    }

    // MARK: - Clipboard IO

    func browserActionPlan(primaryID: UUID) -> ClipBrowserActionPlan? {
        ClipActionService.planBrowserAction(for: clipsForContextAction(primaryID: primaryID))
    }

    func emailActionPlan(primaryID: UUID) -> ClipEmailActionPlan? {
        ClipActionService.planEmailAction(for: clipsForContextAction(primaryID: primaryID))
    }

    func openInBrowser(primaryID: UUID) {
        let targetClips = clipsForContextAction(primaryID: primaryID)
        let didOpen = ClipActionService.shared.openInBrowser(clips: targetClips)
        logState("openInBrowser items=\(targetClips.count) success=\(didOpen)")
    }

    func sendAsEmail(primaryID: UUID) {
        let targetClips = clipsForContextAction(primaryID: primaryID)
        let didOpen = ClipActionService.shared.sendAsEmail(clips: targetClips)
        logState("sendAsEmail items=\(targetClips.count) success=\(didOpen)")
    }

    @discardableResult
    func browseStorageFolderInFinder() -> Bool {
        let didOpen = NSWorkspace.shared.open(storageFolderURL)
        logState("browseStorageFolderInFinder path=\(storageFolderPath) success=\(didOpen)")
        return didOpen
    }

    /// Copy currently selected clips to clipboard without pasting or hiding the window.
    func copySelectionOnly() {
        let current = filteredClips
        let selection = current.filter { selectedClipIDs.contains($0.clipID) }
        guard !selection.isEmpty else { return }
        copyToClipboard(clips: selection, autoPaste: false)
        logState("copySelectionOnly copied \(selection.count) items")
    }

    func copyToClipboard(clips: [ClipItemModel], autoPaste: Bool = false, forcePlainText: Bool = false) {
        guard !clips.isEmpty else { return }
        guard let payload = preferredPasteboardPayload(for: clips, forcePlainText: forcePlainText) else {
            logState("copyToClipboard skipped — no transferable payload")
            return
        }

        sessionCopyCount += 1
        let startedAt = DispatchTime.now()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let didWrite: Bool
        switch payload {
        case .image(let imageData):
            let item = NSPasteboardItem()
            item.setData(imageData, forType: .png)
            if let tiffData = NSImage(data: imageData)?.tiffRepresentation {
                item.setData(tiffData, forType: .tiff)
            }
            didWrite = pasteboard.writeObjects([item])
            logState("copyToClipboard wrote image data (\(imageData.count) bytes)")
        case .text(let textPayload):
            didWrite = pasteboard.setString(textPayload, forType: .string)
            logState("copyToClipboard wrote text payload (\(textPayload.count) chars)")
        }

        guard didWrite else {
            logState("copyToClipboard FAILED — pasteboard rejected payload")
            Breadcrumb.record("copyToClipboard FAILED pasteboard rejected items=\(clips.count)")
            return
        }

        suppressedPasteboardChangeCount = pasteboard.changeCount
        logPerf("copyToClipboard", startedAt: startedAt, details: "items=\(clips.count)")

        if autoPaste {
            sessionPasteCount += 1
            Breadcrumb.record("paste items=\(clips.count) total=\(sessionPasteCount)")
            Analytics.clipPasted(type: clips.first?.clipType.rawValue ?? "unknown")
            pasteIntoActiveApp()
        } else {
            Breadcrumb.record("copy items=\(clips.count) total=\(sessionCopyCount)")
        }
    }

    private func preferredPasteboardPayload(
        for clips: [ClipItemModel],
        forcePlainText: Bool = false
    ) -> ClipboardWritePayload? {
        if !forcePlainText && settings.alwaysPlainText == false,
           clips.count == 1,
           clips[0].clipType == .image,
           let imageData = clips[0].imageData {
            return .image(imageData)
        }

        guard let textPayload = Self.buildPlainTextPayload(for: clips) else {
            return nil
        }
        return .text(textPayload)
    }

    static func buildPlainTextPayload(for clips: [ClipItemModel]) -> String? {
        let values = clips.compactMap { clip -> String? in
            let value = clip.textValue ?? clip.urlValue ?? clip.previewText
            guard value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                return nil
            }
            return value
        }
        guard !values.isEmpty else { return nil }
        return values.joined(separator: "\n")
    }

    // DANGER ZONE: Requires macOS Accessibility permission (granted to the .app bundle).
    // Will silently fail if run from `swift run` or Xcode play button (bare binary, no
    // bundle ID). For testing paste, build via scripts/build-app.sh && open Jack.app.
    // The CGEvent Cmd+V simulation below requires the target app to be frontmost and active.
    private func pasteIntoActiveApp() {
        guard settings.pasteToActiveApp else {
            logState("pasteIntoActiveApp skipped — pasteToActiveApp disabled")
            sessionPasteFailCount += 1
            Breadcrumb.record("paste SKIPPED reason=pasteToActiveApp-disabled")
            return
        }

        guard AccessibilityService.isTrusted() else {
            logState(
                "pasteIntoActiveApp skipped — Accessibility not granted "
                    + "bundleID=\(AccessibilityService.bundleIdentifierText) "
                    + "executable=\(AccessibilityService.executablePath)"
            )
            sessionPasteFailCount += 1
            Breadcrumb.record("paste SKIPPED reason=no-accessibility-permission")
            // Without this the double-tap looks like it did nothing — the clip
            // is on the clipboard but the simulated Cmd+V never fires.
            DispatchQueue.main.async { [weak self] in
                self?.presentAccessibilityPasteAlertIfNeeded()
            }
            return
        }

        let targetApp = resolvedPasteTargetApp()
        logState("pasteIntoActiveApp target=\(targetApp?.localizedName ?? "nil") bundleID=\(targetApp?.bundleIdentifier ?? "nil")")

        DispatchQueue.main.async { [self] in
            AppWindowManager.shared.hideImmediatelyForPaste(targetApp: targetApp)
            pollForActivation(targetApp: targetApp, attempts: 0)
        }
    }

    /// Returns true exactly once per session so the blocked-paste alert can't
    /// nag the user on every double-tap while permission is missing.
    func consumeAccessibilityPasteAlertPresentation() -> Bool {
        guard hasShownAccessibilityPasteAlert == false else { return false }
        hasShownAccessibilityPasteAlert = true
        return true
    }

    // Standalone NSAlert by design — the tray window is a dock-level strip, so
    // sheets attached to it render squashed (see Window Presentation Rules).
    private func presentAccessibilityPasteAlertIfNeeded() {
        guard consumeAccessibilityPasteAlertPresentation() else { return }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = String(
            format: L10n.string(
                "paste.accessibilityAlert.title",
                default: "Allow %@ to paste into other apps"
            ),
            AppBrand.displayName
        )
        alert.informativeText = String(
            format: L10n.string(
                "paste.accessibilityAlert.body",
                default: "Your clip was copied, but macOS blocks automatic pasting until you allow %@ in System Settings under Privacy & Security, Accessibility. You can still paste it yourself with Cmd+V."
            ),
            AppBrand.displayName
        )
        alert.addButton(withTitle: L10n.string(
            "paste.accessibilityAlert.openSettings",
            default: "Open System Settings"
        ))
        alert.addButton(withTitle: L10n.string(
            "paste.accessibilityAlert.notNow",
            default: "Not Now"
        ))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModalInFront() == .alertFirstButtonReturn {
            AccessibilityService.openSettings()
        }
    }

    /// Poll every 10ms for the target app to become active before posting Cmd+V.
    /// Max 15 attempts = 150ms timeout, then posts anyway.
    private func pollForActivation(targetApp: NSRunningApplication?, attempts: Int) {
        let maxAttempts = 15
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let targetPID = targetApp?.processIdentifier
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let isActive = if let targetPID {
            frontmostPID == targetPID
        } else {
            frontmostPID != selfPID
        }

        if isActive || attempts >= maxAttempts {
            if attempts >= maxAttempts {
                logState("pasteIntoActiveApp activation timeout after \(attempts * 10)ms — posting Cmd+V anyway")
            } else {
                logState("pasteIntoActiveApp target active after \(attempts * 10)ms")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [self] in
                postCmdV()
            }
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [self] in
            pollForActivation(targetApp: targetApp, attempts: attempts + 1)
        }
    }

    /// Simulate Cmd+V keypress via CGEvent, posted at hardware level for reliability.
    /// Retries once with `.hidSystemState` if `.combinedSessionState` fails (can happen
    /// after sleep/wake or system permission dialogs invalidate the session event source).
    private func postCmdV() {
        let stateIDs: [CGEventSourceStateID] = [.combinedSessionState, .hidSystemState]
        for stateID in stateIDs {
            guard let source = CGEventSource(stateID: stateID) else {
                logState("postCmdV CGEventSource(\(stateID.rawValue)) creation failed — trying next")
                Breadcrumb.record("postCmdV CGEventSource(\(stateID.rawValue)) creation failed")
                continue
            }

            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
                logState("postCmdV CGEvent creation failed for stateID=\(stateID.rawValue)")
                Breadcrumb.record("postCmdV CGEvent creation failed stateID=\(stateID.rawValue)")
                continue
            }

            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand
            keyDown.post(tap: .cgSessionEventTap)
            keyUp.post(tap: .cgSessionEventTap)
            sessionPasteSuccessCount += 1
            logState("postCmdV SUCCESS — Cmd+V posted via stateID=\(stateID.rawValue)")
            Breadcrumb.record("postCmdV SUCCESS stateID=\(stateID.rawValue) pastes=\(sessionPasteSuccessCount)/\(sessionPasteCount)")
            return
        }

        sessionPasteFailCount += 1
        logState("postCmdV FAILED — all CGEventSource strategies exhausted, accessibility=\(AccessibilityService.isTrusted())")
        Breadcrumb.record("postCmdV FAILED all-strategies-exhausted")
    }

    private func resolvedPasteTargetApp() -> NSRunningApplication? {
        if let previous = AppWindowManager.shared.previousApp, previous.isTerminated == false {
            return previous
        }

        let selfPID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.first {
            $0.isActive && $0.processIdentifier != selfPID
        }
    }
}
