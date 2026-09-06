import AppKit
import SwiftUI

@MainActor
final class PulseCharacterMessagePopoverController {
    private final class PopoverWindow: NSWindow {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
    }

    private weak var attachedPerformer: PulseCharacterPerformer?
    private var window: NSWindow?
    private var hostingView: NSHostingView<AnyView>?
    private var clickOutsideMonitor: Any?
    private var escapeKeyMonitor: Any?
    private var currentLocale: Locale = .autoupdatingCurrent

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    func isAttached(to performer: PulseCharacterPerformer) -> Bool {
        attachedPerformer === performer && isVisible
    }

    func present(
        attachedTo performer: PulseCharacterPerformer,
        message: PulseCharacterAmbientMessage,
        locale: Locale
    ) {
        if attachedPerformer !== performer {
            attachedPerformer?.setPopoverPresented(false)
        }
        attachedPerformer = performer
        performer.setPopoverPresented(true)
        currentLocale = locale

        if window == nil {
            createWindow()
        }

        updateContent(with: message)
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
        let width: CGFloat = 420
        let height: CGFloat = 240

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

        let hostingView = NSHostingView(
            rootView: AnyView(
                PulseCharacterMessagePopoverView(
                    message: PulseCharacterAmbientMessage(text: "", source: .inspiration)
                )
            )
        )
        hostingView.frame = CGRect(x: 0, y: 0, width: width, height: height)
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)
        self.hostingView = hostingView

        window.contentView = container
        self.window = window
    }

    private func updateContent(with message: PulseCharacterAmbientMessage) {
        hostingView?.rootView = AnyView(
            PulseCharacterMessagePopoverView(message: message)
                .environment(\.locale, currentLocale)
        )
    }

    private func updatePosition() {
        guard let window, let performer = attachedPerformer else { return }
        let performerFrame = performer.currentFrame
        guard performerFrame != .zero else { return }

        let screenFrame = NSScreen.main?.frame ?? performerFrame.insetBy(dx: -200, dy: -200)
        var x = performerFrame.midX - (window.frame.width / 2)
        x = max(screenFrame.minX + 8, min(x, screenFrame.maxX - window.frame.width - 8))

        let proposedY = performerFrame.maxY - 10
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
