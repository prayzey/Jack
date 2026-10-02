import AppKit
import Combine
import OSLog
import SwiftUI

/// The speaker item in the menu bar and the panel it opens.
///
/// Deliberately not a SwiftUI `MenuBarExtra`: its window doesn't follow
/// content height changes. Expanding "Other apps" grew it upward past the
/// menu bar, and collapsing left it tall with the content centered in an
/// empty band. This panel stays pinned under the icon and grows downward.
@MainActor
final class SoundMenuBarController: NSObject {
    static let shared = SoundMenuBarController()

    let mixer = SoundMixer()
    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "SoundMenuBar")

    private static let panelWidth: CGFloat = 340
    /// Space between the menu bar and the panel, like system menu bar panels.
    private static let menuBarGap: CGFloat = 5

    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var hostingView: NSHostingView<SoundMenuView>?
    private var contentHeight: CGFloat = 0
    private var monitors: [Any] = []
    private var cancellables: Set<AnyCancellable> = []
    private var isLaunched = false
    private var wantsItem = false
    private var isOpen = false
    /// The panel doesn't take focus, so this app stays in front while it's
    /// open. Only a switch to a different app should close it.
    private var frontmostAtOpen: NSRunningApplication?
    /// The icon's frame on the display that was clicked, captured on open.
    private var anchor: NSRect?
    private var scrollMonitor: Any?
    private weak var store: ClipboardStore?

    func bind(to store: ClipboardStore) {
        self.store = store
        mixer.bind(to: store)
        store.$settings
            .map(\.showSoundControlsInMenuBar)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                MainActor.assumeIsolated {
                    self?.wantsItem = enabled
                    self?.applyState()
                    // The browser extension connects whenever sound controls are on.
                    if enabled { BrowserTabBridge.shared.start() } else { BrowserTabBridge.shared.stop() }
                }
            }
            .store(in: &cancellables)
        // The icon's waves follow the system volume.
        mixer.$masterVolume.combineLatest(mixer.$isMasterMuted)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.updateIcon() } }
            .store(in: &cancellables)
        // Jack dances while he's on screen and the setting is on; the mixer
        // only listens to the whole Mac while that's true.
        store.$settings
            .map { $0.soundJackDances && $0.jackSettings.isVisible }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] wanted in MainActor.assumeIsolated { self?.mixer.wantsSystemLevel = wanted } }
            .store(in: &cancellables)
        mixer.meters.$systemLevel
            .removeDuplicates()
            .sink { [weak store] level in
                MainActor.assumeIsolated { store?.jackPresenceController.setMusicLevel(level) }
            }
            .store(in: &cancellables)
        // Another app coming forward (System Settings after "Sound
        // Settings…", or ⌘-Tab) closes the panel, like a menu.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(otherAppActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    /// `NSStatusBar` is only reliable once the app has finished launching.
    func finishLaunchSetup() {
        isLaunched = true
        applyState()
    }

    private func applyState() {
        guard isLaunched else { return }
        guard wantsItem, #available(macOS 14.2, *) else {
            closePanel("turned off")
            statusItem.map(NSStatusBar.system.removeStatusItem)
            statusItem = nil
            scrollMonitor.map(NSEvent.removeMonitor)
            scrollMonitor = nil
            return
        }
        guard statusItem?.button == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // A named item keeps its own position and visibility across launches
        // instead of sharing macOS's "Item-N" slots with Jack's other icons.
        item.autosaveName = "JackSoundControls"
        item.isVisible = true
        guard let button = item.button else {
            NSStatusBar.system.removeStatusItem(item)
            // The first request right after launch can come back without a
            // button; try again shortly.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                MainActor.assumeIsolated { self?.applyState() }
            }
            return
        }
        button.target = self
        button.action = #selector(iconClicked)
        button.setAccessibilityLabel(L10n.string("ui.sound", default: "Sound"))
        statusItem = item
        updateIcon()
        // Scrolling over the icon changes the volume, like a volume knob.
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, let button = self.statusItem?.button, event.window === button.window else { return event }
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 300 : event.scrollingDeltaY / 30
            self.mixer.nudgeMasterVolume(by: event.isDirectionInvertedFromDevice ? -delta : delta)
            return nil
        }
        // Build the panel now so it has measured itself before the first click.
        if panel == nil { _ = makePanel() }
    }

    private func updateIcon() {
        statusItem?.button?.image = NSImage(
            systemSymbolName: mixer.menuBarSymbol,
            accessibilityDescription: L10n.string("ui.sound", default: "Sound")
        )
    }

    // MARK: - Panel

    /// Click opens the panel; ⌥-click mutes or unmutes the Mac without it.
    @objc private func iconClicked() {
        if NSEvent.modifierFlags.contains(.option) {
            mixer.toggleMasterMute()
            return
        }
        if isOpen { closePanel("icon") } else { openPanel() }
    }

    private func openPanel() {
        let panel = panel ?? makePanel()
        isOpen = true
        frontmostAtOpen = NSWorkspace.shared.frontmostApplication
        anchor = iconFrame(near: NSEvent.mouseLocation)
        // Lay out now so app-list changes made while closed report their
        // height before the panel is placed.
        hostingView?.layoutSubtreeIfNeeded()
        place(panel, animated: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
        statusItem?.button?.highlight(true)
        installDismissMonitors()
        mixer.setPanelVisible(true)
        MediaNowPlaying.shared.startPolling()
    }

    private func closePanel(_ reason: String = "") {
        guard let panel, isOpen else { return }
        logger.debug("Closing sound panel: \(reason, privacy: .public)")
        isOpen = false
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        statusItem?.button?.highlight(false)
        mixer.setPanelVisible(false)
        MediaNowPlaying.shared.stopPolling()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                // Reopened during the fade: keep it.
                if !self.isOpen { panel.orderOut(nil) }
            }
        })
    }

    private func makePanel() -> NSPanel {
        let panel = SoundPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        // isFloatingPanel resets the level to .floating, so set it first;
        // .popUpMenu keeps the panel above other floating windows, like a menu.
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.onEscape = { [weak self] in self?.closePanel("escape") }

        let background = NSVisualEffectView()
        background.material = .menu
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true

        let hostingView = NSHostingView(rootView: SoundMenuView(
            mixer: mixer,
            meters: mixer.meters,
            nowPlaying: .shared,
            tabs: .shared,
            callModeEnabled: Binding(
                get: { [weak self] in self?.store?.settings.soundCallModeEnabled ?? true },
                set: { [weak self] in self?.store?.settings.soundCallModeEnabled = $0 }
            ),
            onHeightChange: { [weak self] height in self?.contentHeightChanged(height) },
            onDismiss: { [weak self] in self?.closePanel("dismiss") },
            onOpenSettings: { [weak self] in
                self?.closePanel("settings")
                NSApp.activate(ignoringOtherApps: true)
                SettingsNavigation.openSettings(tabRawValue: SettingsTab.menuBar.rawValue)
            }
        ))
        // The panel sizes itself from the reported height; letting the
        // hosting view resize the window too would fight that.
        hostingView.sizingOptions = []
        hostingView.autoresizingMask = [.width, .height]
        hostingView.frame = background.bounds
        background.addSubview(hostingView)
        panel.contentView = background
        // First layout reports the content height through onHeightChange.
        hostingView.layoutSubtreeIfNeeded()

        self.panel = panel
        self.hostingView = hostingView
        return panel
    }

    private func contentHeightChanged(_ height: CGFloat) {
        guard abs(height - contentHeight) > 0.5 else { return }
        contentHeight = height
        if let panel, isOpen { place(panel, animated: true) }
    }

    /// Pins the panel's top edge just under the icon and lets the height
    /// change at the bottom, clamped to the screen.
    private func place(_ panel: NSPanel, animated: Bool) {
        guard let iconFrame = anchor,
              let screen = NSScreen.screens.first(where: { $0.frame.intersects(iconFrame) })
        else { return }
        let visible = screen.visibleFrame
        let top = iconFrame.minY - Self.menuBarGap
        // SwiftUI only reports height changes, so this is the last known
        // height; before the very first report, open at a typical size and
        // let the report animate it into place.
        let height = min(contentHeight > 0 ? contentHeight : 180, top - visible.minY - 8)
        let x = min(max(iconFrame.minX, visible.minX + 8), visible.maxX - Self.panelWidth - 8)
        let frame = NSRect(x: x, y: top - height, width: Self.panelWidth, height: height)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    /// Closes on a click anywhere outside the panel.
    private func installDismissMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        let global = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
            MainActor.assumeIsolated {
                // The menu bar icon may live outside Jack's process, so its
                // own click shows up here; let the button toggle instead.
                guard let self, !self.isOverIcon(NSEvent.mouseLocation) else { return }
                self.closePanel("click in another app")
            }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak self] event in
            // The panel's own pop-up menus (output picker, right-click) are
            // separate windows above it; clicking in them isn't "outside".
            let inMenu = (event.window?.level.rawValue ?? 0) >= NSWindow.Level.popUpMenu.rawValue
            if let self, !inMenu, event.window !== self.panel, event.window !== self.statusItem?.button?.window {
                self.closePanel("click in another Jack window")
            }
            return event
        }
        monitors = [global, local].compactMap { $0 }
    }

    @objc private func otherAppActivated(_ notification: Notification) {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        if app != .current, app != frontmostAtOpen { closePanel("\(app?.bundleIdentifier ?? "app") activated") }
    }

    private func isOverIcon(_ point: NSPoint) -> Bool {
        iconFrame(near: point)?.contains(point) == true
    }

    /// Every display's menu bar shows the icon, but its window lives on only
    /// one of them. Menu bar items are right-aligned, so the copy on the
    /// display under the pointer sits at the same distance from that
    /// display's top-right corner.
    private func iconFrame(near point: NSPoint) -> NSRect? {
        guard let button = statusItem?.button, let window = button.window,
              let home = window.screen
        else { return nil }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }),
              screen != home,
              point.y > screen.frame.maxY - 60 // pointer is up in that display's menu bar
        else { return frame }
        return frame.offsetBy(dx: screen.frame.maxX - home.frame.maxX, dy: screen.frame.maxY - home.frame.maxY)
    }
}

/// Borderless panels can't become key by default, which would leave Escape
/// with nowhere to go.
private final class SoundPanel: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}
