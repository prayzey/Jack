import AppKit
import OSLog
import QuartzCore
import SwiftUI

private let quickNoteLog = Logger(subsystem: AppBrand.logSubsystem, category: "QuickNote")

let quickNoteWindowSize = NSSize(width: 560, height: 420)
let quickNoteMinimumWindowSize = NSSize(width: 320, height: 220)

/// Transparent margin between the Quick Note window frame and the visible
/// card. Resize chrome hugs this inner rect so side grabs land on the rounded
/// card edge users actually aim for.
func quickNoteWindowCanvasInset(for size: CGSize) -> CGFloat {
    let basedOnWindow = min(size.width, size.height) * 0.055
    return min(max(basedOnWindow, 30), 46)
}

@MainActor
protocol QuickNoteActivatingWindow: AnyObject {
    var canBecomeKey: Bool { get }
    var isKeyWindow: Bool { get }
    func orderFrontRegardless()
    func makeKey()
}

extension NSWindow: QuickNoteActivatingWindow {}

@MainActor
func activateQuickNoteWindow(
    _ window: QuickNoteActivatingWindow,
    appIsActive: Bool,
    activateApp: () -> Void
) {
    // Borderless floating windows can appear without actually taking keyboard
    // focus when we open them over another app. Activate first, then order
    // front, then make key so the editor focus request lands on a real key window.
    if appIsActive == false {
        activateApp()
    }
    window.orderFrontRegardless()
    if window.canBecomeKey, window.isKeyWindow == false {
        window.makeKey()
    }
}

@MainActor
func quickNoteEditor(in rootView: NSView?) -> QuickNoteEditorTextView? {
    guard let rootView else { return nil }
    if let editor = rootView as? QuickNoteEditorTextView {
        return editor
    }

    for subview in rootView.subviews {
        if let editor = quickNoteEditor(in: subview) {
            return editor
        }
    }

    return nil
}

private final class QuickNoteBorderlessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
func quickNoteWindowLevel() -> NSWindow.Level {
    NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 3)
}

@MainActor
func configureQuickNoteWindow(_ window: NSWindow) {
    window.isReleasedWhenClosed = false
    // Quick Note is dragged from its custom header region, not by the whole
    // background, so editing near the edges never yanks the window around.
    window.isMovableByWindowBackground = false
    // Keep Quick Note above the Settings preview window when the shortcut opens
    // it while Settings is already visible.
    window.level = quickNoteWindowLevel()
    window.backgroundColor = .clear
    window.isOpaque = false
    window.hasShadow = false
    window.minSize = quickNoteMinimumWindowSize
    // Keep the rendered content on screen while our hand-rolled resize handles
    // drive setFrame each drag frame. Without this AppKit clears + repaints the
    // borderless window every frame, which is what makes corner resizes feel
    // like the window stalls/jumps behind the cursor.
    window.preservesContentDuringLiveResize = true
    // Cursor rects on the edge chrome need mouse-moved delivery even when the
    // interior is click-through to the editor underneath.
    window.acceptsMouseMovedEvents = true
    window.title = "Quick Note"
}

func quickNoteTargetFrame(
    placement: QuickNoteOpenPosition,
    mouseLocation: NSPoint,
    visibleFrame: NSRect,
    windowSize: NSSize = quickNoteWindowSize
) -> NSRect {
    let inset: CGFloat = 16
    let minX = visibleFrame.minX + inset
    let maxX = max(minX, visibleFrame.maxX - windowSize.width - inset)
    let minY = visibleFrame.minY + inset
    let maxY = max(minY, visibleFrame.maxY - windowSize.height - inset)

    switch placement {
    case .centered:
        return NSRect(
            x: visibleFrame.midX - windowSize.width / 2,
            y: visibleFrame.midY - windowSize.height / 2,
            width: windowSize.width,
            height: windowSize.height
        )
    case .mouse:
        return NSRect(
            x: min(max(mouseLocation.x - windowSize.width / 2, minX), maxX),
            y: min(max(mouseLocation.y - windowSize.height / 2, minY), maxY),
            width: windowSize.width,
            height: windowSize.height
        )
    }
}

/// Decide which quick note `show()` should open.
///
/// Resumes the note the user last had active (so closing and reopening the
/// Quick Note lands back where they left off, not on the newest note), falling
/// back to the newest quick note, and finally `nil` meaning "no note exists yet,
/// create a fresh one." Pure so the resume-vs-newest policy is unit-testable.
func resolveQuickNoteToShow(activeID: UUID?, quickNotes: [NoteItem]) -> UUID? {
    if let activeID, quickNotes.contains(where: { $0.noteID == activeID }) {
        return activeID
    }
    // `quickNotes` is ordered oldest-first, so the last entry is the newest —
    // the same note `newestQuickNote()` returns.
    return quickNotes.last?.noteID
}

@MainActor
final class QuickNoteWindowManager: NSObject, NSWindowDelegate {
    static let shared = QuickNoteWindowManager()

    private weak var store: ClipboardStore?
    private var window: NSWindow?
    var hostWindow: NSWindow? { window }
    private var isAnimating = false
    private let animationTickCoalescingQueue = DispatchQueue(
        label: "Jack.QuickNoteWindowManager.AnimationTickCoalescing",
        qos: .userInteractive
    )
    nonisolated(unsafe) private var animationTickScheduled = false
    private var animationDisplayLink: CVDisplayLink?
    private weak var animationWindow: NSWindow?
    private var animationMotion: QuickNoteWindowMotion?
    private var animationStartTime: CFTimeInterval = 0
    private var animationCompletion: (@MainActor () -> Void)?

    func configure(store: ClipboardStore) {
        self.store = store
        installTerminationObserver()
        installSIGTERMHandler()
    }

    private var terminationObserver: NSObjectProtocol?
    private var sigtermSource: DispatchSourceSignal?

    /// `jack restart` (and any external `pkill -x`/SIGTERM) does NOT fire
    /// `applicationWillTerminate` — that notification only goes through
    /// `NSApplication.terminate(_:)`. Without a signal trap, a SIGTERM that
    /// arrives in the 60 ms persist debounce window leaves the editor's
    /// freshly-typed text on the floor.
    ///
    /// `DispatchSource.makeSignalSource` is the async-signal-safe pattern:
    /// libdispatch handles delivery on a normal queue, so our handler can call
    /// Swift code freely. We route through `NSApp.terminate(_:)` so the
    /// existing teardown chain runs — that's what fires `willTerminate`
    /// (where our flush observer lives) *and* runs the AppDelegate's
    /// `applicationWillTerminate` which unregisters Carbon global hotkeys.
    /// Skipping the chain (e.g. calling `exit()`) leaks the hotkey
    /// registration and the next launch can't re-bind Option+A.
    private func installSIGTERMHandler() {
        guard sigtermSource == nil else { return }
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            quickNoteLog.info("SIGTERM received — invoking NSApp.terminate to flush draft + unregister hotkeys")
            NSApp.terminate(nil)
        }
        source.resume()
        sigtermSource = source
    }

    /// Persist the editor's draft when the app quits. Without this, a user who
    /// types in Quick Note and then hits ⌘Q (or otherwise quits before the
    /// 220 ms persist debounce fires) loses their note on next launch. The
    /// hide-path flush only catches close-via-hotkey; ⌘Q goes straight to
    /// `applicationWillTerminate` without calling our `hide()`.
    private func installTerminationObserver() {
        guard terminationObserver == nil else { return }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                QuickNoteWindowManager.shared.flushDraftOnTerminate()
            }
        }
    }

    private func flushDraftOnTerminate() {
        guard let store, let noteID = store.quickNoteActiveNoteID else {
            quickNoteLog.info("flushDraftOnTerminate: no active note, nothing to persist")
            return
        }
        guard let window else {
            quickNoteLog.info("flushDraftOnTerminate: no window, nothing to persist")
            return
        }
        guard let editor = quickNoteEditor(in: window.contentView) else {
            quickNoteLog.info("flushDraftOnTerminate: editor missing for noteID=\(noteID.uuidString, privacy: .public)")
            return
        }
        let markdown = QuickNoteBodyRenderer.markdown(from: editor.attributedString())
        quickNoteLog.info("flushDraftOnTerminate noteID=\(noteID.uuidString, privacy: .public) chars=\(markdown.count)")
        store.updateNoteBody(noteID, markdown: markdown)
    }

    func toggle() {
        guard !isAnimating else { return }

        guard let window else {
            show()
            return
        }
        if window.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard let store, !isAnimating else { return }
        let noteID: UUID
        if let resolved = resolveQuickNoteToShow(
            activeID: store.quickNoteActiveNoteID,
            quickNotes: store.quickNotes
        ) {
            noteID = resolved
            quickNoteLog.info("show: opening quickNote id=\(resolved.uuidString, privacy: .public) resumedActive=\(resolved == store.quickNoteActiveNoteID) totalQuickNotes=\(store.quickNotes.count)")
        } else {
            let created = store.createNote(origin: .quickNote)
            noteID = created.noteID
            quickNoteLog.info("show: created fresh quickNote id=\(created.noteID.uuidString, privacy: .public)")
        }
        store.quickNoteActiveNoteID = noteID

        let windowSize = NSSize(
            width: store.settings.quickNoteWindowWidth,
            height: store.settings.quickNoteWindowHeight
        )

        let window = self.window ?? {
            let newWindow = QuickNoteBorderlessWindow(
                contentRect: NSRect(origin: .zero, size: windowSize),
                styleMask: [.borderless, .resizable],
                backing: .buffered,
                defer: false
            )
            configureQuickNoteWindow(newWindow)
            newWindow.delegate = self
            self.window = newWindow
            return newWindow
        }()

        window.level = quickNoteWindowLevel()

        let rootView = window.contentView ?? {
            let container = NSView(frame: NSRect(origin: .zero, size: window.frame.size))
            container.autoresizingMask = [.width, .height]
            window.contentView = container
            return container
        }()

        // Reuse the existing Quick Note surface when reopening. Tear-down + rebuild
        // used to wipe the NSTextView on every show(), which always scrolled back
        // to the top — close and reopen should land where the user left off.
        let hasContentSurface = rootView.subviews.contains { !($0 is WindowEdgeResizeChromeNSView) }
        if !hasContentSurface {
            let host = NSHostingView(
                rootView: QuickNoteView()
                    .environmentObject(store)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
            host.autoresizingMask = [.width, .height]
            host.wantsLayer = true
            host.layer?.backgroundColor = NSColor.clear.cgColor
            rootView.addSubview(host, positioned: .below, relativeTo: nil)
            host.frame = rootView.bounds
        }

        WindowEdgeResizeChromeInstaller.install(
            on: rootView,
            minSize: quickNoteMinimumWindowSize,
            edgeThickness: 24,
            topEdgeThickness: 14,
            cornerSize: 36,
            usesDynamicQuickNoteCanvasInset: true,
            usesDynamicTopDragGap: true,
            onResizeFinished: { [weak store] frame in
                store?.settings.quickNoteWindowWidth = frame.width
                store?.settings.quickNoteWindowHeight = frame.height
            }
        )

        let mouseLocation = NSEvent.mouseLocation
        let screen = Self.screenContainingPoint(mouseLocation) ?? NSScreen.main ?? NSScreen.screens.first
        let targetFrame: NSRect
        if let screen {
            targetFrame = quickNoteTargetFrame(
                placement: store.settings.quickNoteOpenPosition,
                mouseLocation: mouseLocation,
                visibleFrame: screen.visibleFrame,
                windowSize: windowSize
            )
        } else {
            targetFrame = NSRect(origin: window.frame.origin, size: windowSize)
        }

        let motion = QuickNoteWindowMotion.make(
            style: store.settings.quickNoteOpenAnimation,
            phase: .show,
            anchorFrame: targetFrame
        )
        isAnimating = true
        window.alphaValue = motion.startAlpha
        window.setFrame(motion.fromFrame, display: false)
        activateQuickNoteWindow(window, appIsActive: NSApp.isActive) {
            NSApp.activate(ignoringOtherApps: true)
        }
        requestEditorFocus(in: window, reason: "show")
        startAnimation(window: window, motion: motion) { [weak self] in
            self?.isAnimating = false
            guard let window = self?.window else { return }
            self?.requestEditorFocus(in: window, reason: "show-animation-complete")
        }
    }

    private func hide() {
        guard let window, window.isVisible, !isAnimating else { return }

        let activeNoteID = store?.quickNoteActiveNoteID
        if let activeNoteID {
            // Flush the editor's current text *before* the hide animation +
            // cleanup runs. The QuickNoteView's persist debounce (220 ms) can
            // outlive a fast close animation (160–220 ms): without this sync
            // capture, `cleanupQuickNoteIfNeeded` can see an empty body and
            // delete a note the user just typed in.
            flushActiveEditorDraft(noteID: activeNoteID, window: window)
            store?.finalizeNoteEdits(activeNoteID)
        }

        isAnimating = true
        let style = store?.settings.quickNoteCloseAnimation ?? .slide
        let motion = QuickNoteWindowMotion.make(
            style: style,
            phase: .hide,
            anchorFrame: window.frame
        )
        startAnimation(window: window, motion: motion) { [weak self, weak window] in
            guard let self, let window else { return }

            window.orderOut(nil)
            window.alphaValue = 1

            if let activeNoteID, let store = self.store {
                let bodyChars = store.note(with: activeNoteID)?.bodyMarkdown.count ?? -1
                quickNoteLog.info("hide.cleanup noteID=\(activeNoteID.uuidString, privacy: .public) preCleanupBodyChars=\(bodyChars)")
                store.cleanupQuickNoteIfNeeded(activeNoteID)
                let stillThere = store.note(with: activeNoteID) != nil
                quickNoteLog.info("hide.cleanup result: noteStillExists=\(stillThere)")
                // Intentionally keep `quickNoteActiveNoteID` pointing at this
                // note so the next show() resumes here instead of jumping to the
                // newest note. If cleanup deleted an empty note, deleteNote()
                // has already cleared the active ID for us.
            }

            self.isAnimating = false
        }
    }

    private func startAnimation(
        window: NSWindow,
        motion: QuickNoteWindowMotion,
        completion: @escaping @MainActor () -> Void
    ) {
        stopAnimationDisplayLink()

        animationWindow = window
        animationMotion = motion
        animationStartTime = CACurrentMediaTime()
        animationCompletion = completion
        animationTickCoalescingQueue.sync {
            animationTickScheduled = false
        }

        window.setFrame(motion.fromFrame, display: false)
        window.alphaValue = motion.startAlpha

        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let link else {
            window.setFrame(motion.toFrame, display: true)
            window.alphaValue = motion.endAlpha
            Task { @MainActor in
                completion()
            }
            return
        }

        animationDisplayLink = link

        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, _ -> CVReturn in
            QuickNoteWindowManager.shared.enqueueDisplayLinkTick()
            return kCVReturnSuccess
        }

        CVDisplayLinkSetOutputCallback(link, callback, nil)
        CVDisplayLinkStart(link)
    }

    nonisolated private func enqueueDisplayLinkTick() {
        let shouldSchedule = animationTickCoalescingQueue.sync { () -> Bool in
            if animationTickScheduled {
                return false
            }
            animationTickScheduled = true
            return true
        }
        guard shouldSchedule else { return }

        DispatchQueue.main.async { @MainActor in
            QuickNoteWindowManager.shared.displayLinkTick()
            QuickNoteWindowManager.shared.animationTickCoalescingQueue.sync {
                QuickNoteWindowManager.shared.animationTickScheduled = false
            }
        }
    }

    private func displayLinkTick() {
        guard
            let window = animationWindow,
            let motion = animationMotion
        else {
            stopAnimationDisplayLink()
            return
        }

        let elapsed = CACurrentMediaTime() - animationStartTime
        let rawProgress = min(elapsed / motion.duration, 1.0)

        window.setFrame(motion.interpolatedFrame(for: rawProgress), display: false)
        window.alphaValue = motion.interpolatedAlpha(for: rawProgress)

        guard rawProgress >= 1 else { return }

        // Capture the completion before stopAnimationDisplayLink() clears it —
        // otherwise the show/hide handler never runs and `isAnimating` is stuck
        // true, silently dropping every subsequent toggle().
        let completion = animationCompletion
        stopAnimationDisplayLink()
        window.setFrame(motion.toFrame, display: true)
        window.alphaValue = motion.endAlpha
        completion?()
    }

    private func stopAnimationDisplayLink() {
        if let link = animationDisplayLink {
            CVDisplayLinkStop(link)
            animationDisplayLink = nil
        }
        animationWindow = nil
        animationMotion = nil
        animationCompletion = nil
        animationTickCoalescingQueue.sync {
            animationTickScheduled = false
        }
    }

    private static func screenContainingPoint(_ point: NSPoint) -> NSScreen? {
        NSScreen.screens.first(where: { $0.frame.contains(point) })
    }

    private func requestEditorFocus(in window: NSWindow, reason: String) {
        DispatchQueue.main.async { [weak window] in
            guard let window else { return }
            guard let editor = quickNoteEditor(in: window.contentView) else {
                return
            }

            _ = window.makeFirstResponder(editor)
        }
    }

    /// Return keyboard focus to the note editor. Used after in-window overlays
    /// (e.g. the notes browser) close their own first responder, so the cursor
    /// lands back in the text without the user having to click.
    func focusEditor() {
        guard let window else { return }
        requestEditorFocus(in: window, reason: "external-focus-request")
    }

    func windowWillClose(_ notification: Notification) {
        stopAnimationDisplayLink()
        isAnimating = false
        guard let store, let noteID = store.quickNoteActiveNoteID else { return }
        if let window = notification.object as? NSWindow {
            flushActiveEditorDraft(noteID: noteID, window: window)
        }
        store.finalizeNoteEdits(noteID)
        store.cleanupQuickNoteIfNeeded(noteID)
        store.quickNoteActiveNoteID = nil
    }

    /// Read the latest text out of the on-screen Quick Note editor and persist
    /// it to the store synchronously. Called before any cleanup path that might
    /// inspect or delete an empty note — the SwiftUI side debounces persists by
    /// 220 ms, so without this capture a rapid close can race the debounce and
    /// drop a freshly-typed note.
    private func flushActiveEditorDraft(noteID: UUID, window: NSWindow) {
        guard let store else {
            quickNoteLog.info("flushActiveEditorDraft: store missing")
            return
        }
        guard let editor = quickNoteEditor(in: window.contentView) else {
            quickNoteLog.info("flushActiveEditorDraft: editor missing noteID=\(noteID.uuidString, privacy: .public)")
            return
        }
        let markdown = QuickNoteBodyRenderer.markdown(from: editor.attributedString())
        let storeBody = store.note(with: noteID)?.bodyMarkdown ?? "<no-such-note>"
        quickNoteLog.info("flushActiveEditorDraft noteID=\(noteID.uuidString, privacy: .public) editorChars=\(markdown.count) storeChars=\(storeBody.count)")
        store.updateNoteBody(noteID, markdown: markdown)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        let window = notification.object as? NSWindow
        if let window {
            requestEditorFocus(in: window, reason: "window-did-become-key")
            // Snap back to full opacity when the user returns to the note.
            // Skip while the show/hide CVDisplayLink is mid-animation —
            // it owns alphaValue end-to-end and a competing animator would
            // create a visible "fight" at the start of the show curve.
            if !isAnimating {
                animateUnfocusedAlpha(window: window, to: 1.0)
            }
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard
            let window = notification.object as? NSWindow,
            let settings = store?.settings,
            settings.quickNoteDimWhenUnfocused,
            !isAnimating
        else { return }
        animateUnfocusedAlpha(window: window, to: CGFloat(settings.quickNoteUnfocusedAlpha))
    }

    /// Animates window alpha for the focus-dim effect — kept separate from
    /// the show/hide display-link animation so the two paths can't interfere.
    private func animateUnfocusedAlpha(window: NSWindow, to alpha: CGFloat) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.allowsImplicitAnimation = true
            window.animator().alphaValue = alpha
        }
    }

    // NOTE: deliberately no `windowDidResize` persistence. `setFrame` fires
    // that delegate on every frame — both during a user resize AND during the
    // show/hide CVDisplayLink animation. Persisting here wrote the entire
    // settings struct to disk + forced a full SwiftUI re-render per frame
    // (visible stutter), and the animation's intermediate frames corrupted the
    // saved window size. The final size is now persisted exactly once on
    // mouse-up via WindowFrameResizeHandle.onResizeFinished -> persistQuickNoteFrame.
}
