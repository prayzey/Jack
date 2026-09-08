import AppKit
import Carbon.HIToolbox
import Combine
import OSLog
import QuartzCore
import SwiftUI

/// Lightweight manager for the floating dictation caption window.
///
/// The panel keeps its height and bottom edge throughout a session. Only an
/// explicit resize changes its width; listening and processing share one card.
@MainActor
final class DictationOverlayWindowManager {
    static let shared = DictationOverlayWindowManager()

    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "DictationOverlay")
    private var panel: NSPanel?
    private var hostingView: NSHostingView<DictationOverlayView>?
    private var phaseObservation: AnyCancellable?
    private var themeObservation: AnyCancellable?
    private var widthObservation: AnyCancellable?
    private var hideTask: Task<Void, Never>?
    private var escapeGlobalMonitor: Any?
    private var escapeLocalMonitor: Any?
    private weak var coordinator: DictationCoordinator?
    private weak var store: DictationStore?
    private init() {}

    func bind(coordinator: DictationCoordinator, store: DictationStore) {
        self.coordinator = coordinator
        self.store = store

        widthObservation?.cancel()
        widthObservation = store.$settings.map(\.captionWidth).removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updatePanelWidth() }

        themeObservation?.cancel()
        themeObservation = store.$settings
            .map(\.pillTheme)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, let panel = self.panel, panel.isVisible else { return }
                self.repositionPanel(panel)
            }

        phaseObservation?.cancel()
        phaseObservation = coordinator.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in
                self?.handlePhaseChange(phase)
            }
    }

    private func handlePhaseChange(_ phase: DictationPhase) {
        switch phase {
        case .listening:
            hideTask?.cancel()
            hideTask = nil
            installEscapeMonitor()
            show()
        case .transcribing, .rewriting, .executing, .pasting:
            hideTask?.cancel()
            hideTask = nil
            installEscapeMonitor()
            show()
        case .done:
            removeEscapeMonitor()
            // A quick beat for the "Pasted" flash, then get out of the way.
            // Matches the coordinator's 0.5s done dwell before resetToIdle().
            scheduleHide(after: 0.45)
        case .failed:
            hideTask?.cancel()
            hideTask = nil
            installEscapeMonitor()
            show()
        case .idle:
            removeEscapeMonitor()
            scheduleHide(after: 0)
        }
    }

    // MARK: - Show / Hide

    private func show() {
        let panel = ensurePanel()
        let wasVisible = panel.isVisible
        if wasVisible {
            // A new session may arrive during the previous fade-out.
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0
                panel.animator().alphaValue = 1
            }
        } else {
            repositionPanel(panel)
        }
        if !wasVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.22
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
                panel.animator().alphaValue = 1
            }
        }
    }

    private func scheduleHide(after delay: TimeInterval) {
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if Task.isCancelled { return }
            guard let self, let panel = self.panel, panel.isVisible else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.12
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            } completionHandler: { [weak panel] in
                Task { @MainActor [weak self, weak panel] in
                    guard self?.coordinator?.phase == .idle else { return }
                    panel?.orderOut(nil)
                }
            }
        }
    }

    // MARK: - Panel construction

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        guard let coordinator else {
            preconditionFailure("DictationOverlayWindowManager.show called before bind(coordinator:store:)")
        }
        guard let store else {
            preconditionFailure("DictationOverlayWindowManager.show called before bind(coordinator:store:)")
        }

        let view = DictationOverlayView(
            coordinator: coordinator,
            store: store
        ) { [weak coordinator] in
            // The overlay button finishes the dictation (stop → transcribe →
            // paste). Cancel-and-discard stays on the Escape key.
            coordinator?.stopSession()
        }
        let hostingView = NSHostingView(rootView: view)
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.autoresizingMask = [.width, .height]
        let initialSize = DictationCaptionLayout.sessionPanelSize
        hostingView.frame = NSRect(origin: .zero, size: initialSize)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)))
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        panel.ignoresMouseEvents = false
        panel.contentView = hostingView

        self.panel = panel
        self.hostingView = hostingView
        return panel
    }

    /// Place the fixed-size panel above the dock. Height never changes mid-session.
    private func repositionPanel(_ panel: NSPanel) {
        guard let hostingView else { return }

        guard let screen = screenForCursor() else { return }
        var panelSize = DictationCaptionLayout.sessionPanelSize
        panelSize.width = DictationCaptionLayout.clampedCaptionWidth(
            store?.settings.captionWidth ?? 360, availableWidth: screen.visibleFrame.width
        ) + DictationCaptionLayout.shadowMargin * 2
        hostingView.setFrameSize(panelSize)
        panel.setContentSize(panelSize)

        let screenFrame = screen.visibleFrame
        let leftX = screenFrame.midX - panelSize.width / 2
        let bottomEdge = screenFrame.minY + 48
        let frame = NSRect(
            x: leftX,
            y: bottomEdge,
            width: panelSize.width,
            height: panelSize.height
        )
        panel.setFrame(frame, display: true)
    }

    private func updatePanelWidth() {
        guard let panel, panel.isVisible else { return }
        let screen = panel.screen?.visibleFrame
        let width = DictationCaptionLayout.clampedCaptionWidth(
            store?.settings.captionWidth ?? 360, availableWidth: screen?.width ?? .greatestFiniteMagnitude
        ) + DictationCaptionLayout.shadowMargin * 2
        guard abs(panel.frame.width - width) > 0.5 else { return }
        var frame = panel.frame
        frame.origin.x += (frame.width - width) / 2
        frame.size.width = width
        if let screen { frame.origin.x = min(max(frame.minX, screen.minX), screen.maxX - width) }
        panel.setFrame(frame, display: true)
    }

    private func screenForCursor() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouse) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    // MARK: - Escape to cancel

    private func installEscapeMonitor() {
        guard escapeGlobalMonitor == nil, escapeLocalMonitor == nil else { return }

        escapeGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == UInt16(kVK_Escape) else { return }
            DispatchQueue.main.async {
                self?.handleEscapePressed()
            }
        }

        escapeLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == UInt16(kVK_Escape) else { return event }
            self?.handleEscapePressed()
            return nil
        }
    }

    private func removeEscapeMonitor() {
        if let escapeGlobalMonitor {
            NSEvent.removeMonitor(escapeGlobalMonitor)
            self.escapeGlobalMonitor = nil
        }
        if let escapeLocalMonitor {
            NSEvent.removeMonitor(escapeLocalMonitor)
            self.escapeLocalMonitor = nil
        }
    }

    private func handleEscapePressed() {
        guard let coordinator, coordinator.isActive else { return }
        coordinator.cancelSession()
    }
}
