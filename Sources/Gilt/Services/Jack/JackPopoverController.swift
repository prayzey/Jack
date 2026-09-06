import AppKit
import SwiftUI

/// Hosts the tabbed Jack popover (`JackPopoverView`) in a borderless window
/// anchored above Jack, shown when the user clicks the parked character.
///
/// Mirrors `PulseCharacterMessagePopoverController`'s windowing and dismiss-
/// monitor pattern; the differences are the hosted view (chat + reminders) and
/// that the selected tab lives here so live content rebuilds don't reset the
/// user's pick.
@MainActor
final class JackPopoverController {
    /// Callbacks the popover needs from its owner: how to read the latest
    /// reminders (to refresh after a mutation), how to turn Jack off, and how to
    /// add / delete reminders. Bundled so `present` stays readable.
    struct Actions {
        let remindersProvider: () -> [PulseReminder]
        let onTurnOff: () -> Void
        let onAddReminder: (PulseReminder) -> Void
        let onDeleteReminder: (UUID) -> Void
    }

    private final class PopoverWindow: NSWindow {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
    }

    private weak var attachedPerformer: PulseCharacterPerformer?
    private var window: NSWindow?
    private var hostingView: NSHostingView<AnyView>?
    private var clickOutsideMonitor: Any?
    private var escapeKeyMonitor: Any?

    private var reminders: [PulseReminder] = []
    private var chatStore: JackChatStore?
    private var selectedTab: JackPopoverTab = .chat
    private var actions: Actions?

    var isVisible: Bool { window?.isVisible ?? false }

    func isAttached(to performer: PulseCharacterPerformer) -> Bool {
        attachedPerformer === performer && isVisible
    }

    func present(
        attachedTo performer: PulseCharacterPerformer,
        chatStore: JackChatStore,
        defaultTab: JackPopoverTab,
        actions: Actions
    ) {
        if attachedPerformer !== performer {
            attachedPerformer?.setPopoverPresented(false)
        }
        attachedPerformer = performer
        performer.setPopoverPresented(true)
        self.chatStore = chatStore
        self.actions = actions
        reminders = actions.remindersProvider()
        selectedTab = defaultTab

        if window == nil { createWindow() }
        renderContent()
        updatePosition()
        window?.orderFrontRegardless()
        window?.makeKey()
        installDismissMonitors()
    }

    func close() {
        removeDismissMonitors()
        window?.orderOut(nil)
        attachedPerformer?.setPopoverPresented(false)
        attachedPerformer = nil
    }

    private func createWindow() {
        let width: CGFloat = 380
        let height: CGFloat = 500

        let window = PopoverWindow(
            contentRect: CGRect(x: 0, y: 0, width: width, height: height),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 10)
        window.collectionBehavior = [.moveToActiveSpace, .stationary]
        window.appearance = NSAppearance(named: .darkAqua)

        let container = NSView(frame: CGRect(x: 0, y: 0, width: width, height: height))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.97).cgColor
        container.layer?.cornerRadius = 18
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor

        let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
        hostingView.frame = CGRect(x: 0, y: 0, width: width, height: height)
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)
        self.hostingView = hostingView

        window.contentView = container
        self.window = window
    }

    /// Rebuild the hosted SwiftUI tree. Called on present and whenever the user
    /// taps a tab or mutates a reminder — `selectedTab` and `reminders` are owned
    /// here so the rebuild keeps the pick and reflects the latest list.
    private func renderContent() {
        // chatStore is assigned in present() before the first render; renderContent
        // is only reachable afterwards (tab taps / reminder mutations).
        guard let chatStore else { return }
        hostingView?.rootView = AnyView(
            JackPopoverView(
                reminders: reminders,
                selectedTab: selectedTab,
                onSelectTab: { [weak self] tab in
                    self?.selectedTab = tab
                    self?.renderContent()
                },
                chatStore: chatStore,
                onTurnOff: { [weak self] in self?.actions?.onTurnOff() },
                onAddReminder: { [weak self] reminder in
                    self?.actions?.onAddReminder(reminder)
                    self?.refreshReminders()
                },
                onDeleteReminder: { [weak self] id in
                    self?.actions?.onDeleteReminder(id)
                    self?.refreshReminders()
                }
            )
        )
    }

    /// Re-read the reminders after an add/delete and re-render so the list in the
    /// popover stays in sync without closing it.
    private func refreshReminders() {
        reminders = actions?.remindersProvider() ?? []
        renderContent()
    }

    private func updatePosition() {
        guard let window, let performer = attachedPerformer else { return }
        let performerFrame = performer.currentFrame
        guard performerFrame != .zero else { return }

        let screenFrame = NSScreen.main?.frame ?? performerFrame.insetBy(dx: -200, dy: -200)
        var x = performerFrame.midX - (window.frame.width / 2)
        x = max(screenFrame.minX + 8, min(x, screenFrame.maxX - window.frame.width - 8))

        // Anchor just above Jack's head; clamp so the popover never runs off the
        // top of the screen.
        let proposedY = performerFrame.maxY + 8
        let y = min(proposedY, screenFrame.maxY - window.frame.height - 8)
        window.setFrameOrigin(CGPoint(x: x, y: y))
    }

    private func installDismissMonitors() {
        removeDismissMonitors()

        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, let window else { return }
            let mouseLocation = NSEvent.mouseLocation
            let performerFrame = self.attachedPerformer?.currentFrame ?? .zero
            if !window.frame.contains(mouseLocation) && !performerFrame.contains(mouseLocation) {
                self.close()
            }
        }

        escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.close()
                return nil
            }
            return event
        }
    }

    private func removeDismissMonitors() {
        if let clickOutsideMonitor {
            NSEvent.removeMonitor(clickOutsideMonitor)
            self.clickOutsideMonitor = nil
        }
        if let escapeKeyMonitor {
            NSEvent.removeMonitor(escapeKeyMonitor)
            self.escapeKeyMonitor = nil
        }
    }
}
