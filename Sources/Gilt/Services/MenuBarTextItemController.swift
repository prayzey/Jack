import AppKit
import Combine
import SwiftUI

/// Owns the AppKit-level `NSStatusItem` used when the user is in custom-text
/// menu bar mode. We drop out of SwiftUI's `MenuBarExtra` for this case
/// because we need behaviors `MenuBarExtra` does not expose:
///   - shift-click to clear (we need raw `NSEvent` modifier flags)
///   - drag-and-drop text onto the item (we need an `NSView` drag destination)
///   - an editable popover that responds to return/esc keys
///   - tooltips for truncated text
///   - markdown-styled `attributedTitle`
///
/// `MenuBarExtra` is still the source of truth for icon mode — see
/// `JackApp.body`. The two modes are mutually exclusive: when the user toggles
/// "Custom text" on, we tear down `MenuBarExtra` (via the inserted binding)
/// and bring up this controller's status item; when they toggle it off, we
/// do the reverse.
@MainActor
final class MenuBarTextItemController: NSObject {
    static let shared = MenuBarTextItemController()

    private var statusItem: NSStatusItem?
    private weak var store: ClipboardStore?
    private var settingsCancellable: AnyCancellable?
    private var popover: NSPopover?
    private var popoverEventMonitor: Any?
    private var activationRetryTask: Task<Void, Never>?

    /// Bind the controller to the live store and start reacting to settings
    /// changes. Calling twice is safe — we tear down any prior subscription.
    /// The first activation happens in `finishLaunchSetup()` once NSApp has
    /// finished launching; do not call `applyCurrentState()` here.
    func bind(to store: ClipboardStore) {
        self.store = store
        settingsCancellable?.cancel()
        settingsCancellable = store.$settings
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyCurrentState()
            }
    }

    /// Run after `applicationDidFinishLaunching` so `NSStatusBar` is ready.
    /// Retries when the first status-item request returns before the button
    /// exists — leaving a zombie item blocks later activation until toggled.
    func finishLaunchSetup() {
        applyCurrentState()
        scheduleActivationRetry(remainingAttempts: 4)
    }

    // MARK: - Activation lifecycle

    private func applyCurrentState() {
        guard let store else { return }
        let shouldBeActive = store.settings.showInMenuBar && store.settings.menuBarShowCustomText
        if shouldBeActive {
            activateIfNeeded()
            refreshLabel()
            if statusItem?.button != nil {
                activationRetryTask?.cancel()
                activationRetryTask = nil
            } else {
                scheduleActivationRetry(remainingAttempts: 4)
            }
        } else {
            deactivate()
        }
    }

    private func activateIfNeeded() {
        if let existing = statusItem {
            // A prior early launch attempt can leave a status item with no
            // button — treat that as "not active" and recreate on retry.
            if existing.button != nil { return }
            NSStatusBar.system.removeStatusItem(existing)
            statusItem = nil
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = item.button else {
            NSStatusBar.system.removeStatusItem(item)
            return
        }

        statusItem = item
        button.target = self
        button.action = #selector(handleClick(_:))
        // Need both left and right mouse up so we can react to either
        // (even though we currently only act on left + shift-left). This
        // also lets us register tracking for tooltips correctly.
        button.sendAction(on: [.leftMouseUp])
        button.registerForDraggedTypes([.string, .fileURL])
        attachDragDestination(to: button)
    }

    private func deactivate() {
        activationRetryTask?.cancel()
        activationRetryTask = nil
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
        closePopover()
    }

    private func scheduleActivationRetry(remainingAttempts: Int) {
        activationRetryTask?.cancel()
        guard remainingAttempts > 0 else { return }
        guard let store else { return }
        guard store.settings.showInMenuBar && store.settings.menuBarShowCustomText else { return }
        guard statusItem?.button == nil else { return }

        let attemptIndex = 5 - remainingAttempts
        let delayMs = UInt64(50 + attemptIndex * 100)
        activationRetryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(delayMs))
            guard let self, !Task.isCancelled else { return }
            self.applyCurrentState()
            if self.statusItem?.button == nil {
                self.scheduleActivationRetry(remainingAttempts: remainingAttempts - 1)
            }
        }
    }

    // MARK: - Label rendering

    private func refreshLabel() {
        guard let button = statusItem?.button, let store else { return }
        let raw = store.settings.menuBarCustomText.trimmingCharacters(in: .whitespacesAndNewlines)
        let display = Self.truncate(raw, maxLength: Self.maxDisplayLength)

        if raw.isEmpty {
            // Empty text shouldn't reach here (the binding logic flips the
            // controller off), but be defensive — fall back to a Jack glyph
            // so the user never sees a zero-width invisible status item.
            button.attributedTitle = NSAttributedString()
            button.image = Self.fallbackIconImage
            button.imagePosition = .imageOnly
            button.toolTip = AppBrand.displayName
        } else {
            button.image = nil
            button.imagePosition = .noImage
            button.attributedTitle = Self.makeAttributedTitle(
                from: display,
                colorHex: store.settings.menuBarTextColorHex
            )
            button.toolTip = raw.count > Self.maxDisplayLength ? raw : raw
        }
    }

    private static let maxDisplayLength = 30

    private static func truncate(_ string: String, maxLength: Int) -> String {
        guard string.count > maxLength else { return string }
        let endIndex = string.index(string.startIndex, offsetBy: maxLength - 1)
        return string[..<endIndex] + "\u{2026}"
    }

    /// Parses a small markdown subset (`**bold**`, `*italic*`, `~~strike~~`)
    /// and renders it with the menu bar's system font as the base. We can't
    /// trust `AttributedString(markdown:)`'s default font (varies by macOS
    /// version), so we re-stamp the font on every run based on the inline
    /// presentation intents we got from the parser.
    private static func makeAttributedTitle(from string: String, colorHex: String?) -> NSAttributedString {
        let baseFont = NSFont.menuBarFont(ofSize: 0)
        let textColor = resolvedMenuBarTextColor(hex: colorHex)

        guard let attributed = try? AttributedString(
            markdown: string,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) else {
            var attributes: [NSAttributedString.Key: Any] = [.font: baseFont]
            if let textColor {
                attributes[.foregroundColor] = textColor
            }
            return NSAttributedString(string: string, attributes: attributes)
        }

        let result = NSMutableAttributedString()
        for run in attributed.runs {
            let intents = run.inlinePresentationIntent ?? []
            var traits: NSFontDescriptor.SymbolicTraits = []
            if intents.contains(.stronglyEmphasized) { traits.insert(.bold) }
            if intents.contains(.emphasized) { traits.insert(.italic) }

            let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits)
            let runFont = NSFont(descriptor: descriptor, size: baseFont.pointSize) ?? baseFont

            var attributes: [NSAttributedString.Key: Any] = [.font: runFont]
            if let textColor {
                attributes[.foregroundColor] = textColor
            }
            if intents.contains(.strikethrough) {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }

            let slice = String(attributed[run.range].characters)
            result.append(NSAttributedString(string: slice, attributes: attributes))
        }
        return result
    }

    private static func resolvedMenuBarTextColor(hex: String?) -> NSColor? {
        guard let hex, !hex.isEmpty else { return nil }
        return NSColor(Color(hex: hex))
    }

    private static let fallbackIconImage: NSImage = {
        let image = NSImage(systemSymbolName: "circle.dotted", accessibilityDescription: AppBrand.displayName) ?? NSImage()
        image.isTemplate = true
        return image
    }()

    // MARK: - Click handling

    @objc private func handleClick(_ sender: Any) {
        let modifiers = NSApp.currentEvent?.modifierFlags ?? []
        if modifiers.contains(.shift) {
            clearText()
            return
        }
        togglePopover()
    }

    /// Shift-click semantic: wipe the text but stay in custom-text mode so
    /// the user can immediately drop new text in (via drag, Services, or by
    /// clicking the item to open the editor). If the user wants to switch
    /// back to the icon entirely they can use the Settings toggle.
    private func clearText() {
        store?.settings.menuBarCustomText = ""
        // Setting empty text will flip applyCurrentState() into deactivate
        // because of the empty-text guard, which is the desired UX: cleared =
        // icon comes back. The "Custom text" toggle in Settings stays on so
        // the next typed character keeps text mode active.
        store?.settings.menuBarShowCustomText = false
    }

    // MARK: - Popover (edit window)

    private func togglePopover() {
        if let popover, popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem?.button, let store else { return }
        let popover = self.popover ?? makePopover(store: store)
        self.popover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // Steal key window status so the text field is immediately editable
        // — without this the field appears but typing goes to whatever was
        // frontmost.
        popover.contentViewController?.view.window?.makeKey()
        installPopoverDismissMonitor()
    }

    private func makePopover(store: ClipboardStore) -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        // The system popover frame draws a vibrancy chrome we cannot
        // disable — but our SwiftUI content paints an opaque themed
        // background that fully covers it. We only need to ensure the
        // popover's appearance variant matches the themed body so the
        // exposed arrow tint doesn't clash.
        popover.appearance = NSAppearance(named: .darkAqua)
        let hosting = NSHostingController(
            rootView: MenuBarEditPopover(
                store: store,
                onCommit: { [weak self] in self?.closePopover() },
                onCancel: { [weak self] in self?.closePopover() }
            )
        )
        hosting.view.frame = NSRect(x: 0, y: 0, width: 320, height: 120)
        popover.contentViewController = hosting
        return popover
    }

    private func closePopover() {
        popover?.close()
        removePopoverDismissMonitor()
    }

    /// macOS sends popover.close() automatically for transient popovers on
    /// outside click, but we additionally want esc-anywhere to dismiss even
    /// when the popover isn't first responder for some reason.
    private func installPopoverDismissMonitor() {
        removePopoverDismissMonitor()
        popoverEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // 53 is the keyCode for Escape.
            if event.keyCode == 53 {
                self?.closePopover()
                return nil
            }
            return event
        }
    }

    private func removePopoverDismissMonitor() {
        if let monitor = popoverEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        popoverEventMonitor = nil
    }

    // MARK: - Drag and drop

    /// We add a child `MenuBarDragOverlay` view that registers drag types and
    /// forwards drops back to us, but returns `nil` from `hitTest` so the
    /// underlying button still receives mouse clicks normally. This is the
    /// cleanest way to add drag-destination behavior without subclassing
    /// `NSStatusBarButton` (which AppKit doesn't let us do).
    private func attachDragDestination(to button: NSStatusBarButton) {
        // Avoid stacking overlays if the controller activates twice.
        for sub in button.subviews where sub is MenuBarDragOverlay {
            sub.removeFromSuperview()
        }
        let overlay = MenuBarDragOverlay()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.onDropString = { [weak self] dropped in
            self?.acceptDroppedText(dropped)
        }
        overlay.onDropAudioFiles = { urls in
            // Already filtered to transcribable audio by the overlay.
            AudioTranscriptionCoordinator.shared.transcribe(fileURLs: urls, source: .menuBarDrop)
        }
        button.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: button.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])
    }

    fileprivate func acceptDroppedText(_ string: String) {
        let cleaned = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        store?.settings.menuBarShowCustomText = true
        store?.settings.menuBarCustomText = String(cleaned.prefix(200))
    }

    // MARK: - Services entry point

    /// Called by `AppDelegate.sendToJack(_:userData:error:)` when the user
    /// triggers the macOS Service or Share sheet entry that we register.
    /// Public so AppDelegate can route into us without exposing internals.
    func receiveServiceText(_ string: String) {
        acceptDroppedText(string)
    }
}

// MARK: - Drag overlay view

/// Sits over the status item button and intercepts drags. Accepts plain text
/// (sets the menu bar label) and audio files (kicks off transcription). Returns
/// nil from hitTest so mouse clicks pass through to the button untouched.
private final class MenuBarDragOverlay: NSView {
    var onDropString: ((String) -> Void)?
    var onDropAudioFiles: (([URL]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.string, .fileURL])
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Clicks fall through to the underlying NSStatusBarButton. Drag
        // operations are evaluated independently by the dragging session.
        return nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        // Audio file → accept (transcribe). Pure text → accept (set label).
        // A non-audio *file* drag is rejected and, crucially, never falls
        // through to the string path — otherwise the file's path string would
        // be pasted in as menu bar text.
        if !audioFileURLs(from: sender).isEmpty { return .copy }
        if !hasAnyFileURL(sender), canReadString(sender) { return .copy }
        return []
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let audio = audioFileURLs(from: sender)
        if !audio.isEmpty {
            onDropAudioFiles?(audio)
            return true
        }
        guard !hasAnyFileURL(sender),
              let strings = sender.draggingPasteboard.readObjects(forClasses: [NSString.self], options: nil) as? [String],
              let first = strings.first else {
            return false
        }
        onDropString?(first)
        return true
    }

    // MARK: - Drag inspection

    private func canReadString(_ sender: NSDraggingInfo) -> Bool {
        sender.draggingPasteboard.canReadObject(forClasses: [NSString.self], options: nil)
    }

    private func hasAnyFileURL(_ sender: NSDraggingInfo) -> Bool {
        !fileURLs(from: sender).isEmpty
    }

    private func audioFileURLs(from sender: NSDraggingInfo) -> [URL] {
        fileURLs(from: sender).filter { ClipboardStore.isTranscribableAudioFile($0) }
    }

    private func fileURLs(from sender: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) as? [URL] ?? []
    }
}

// MARK: - Popover SwiftUI content

/// One Thing-style edit popover. Return commits and closes, Escape cancels
/// and closes. A small footer gives the user explicit access back into
/// Settings + the rest of Jack's menu — without it, text mode would leave
/// the user with no way to reach Settings from the menu bar item (they
/// can only see the popover).
private struct MenuBarEditPopover: View {
    @ObservedObject var store: ClipboardStore
    let onCommit: () -> Void
    let onCancel: () -> Void

    @FocusState private var focused: Bool
    @Environment(\.openWindow) private var openWindow

    private var popoverAppearance: QuickNoteAppearance {
        store.settings.menuBarPopoverAppearance
    }

    private var effectiveTextColor: Color {
        store.settings.resolvedMenuBarPopoverTextColor(appearance: popoverAppearance)
    }

    private var fieldChromeFill: Color {
        effectiveTextColor.opacity(0.12)
    }

    private var fieldChromeBorder: Color {
        effectiveTextColor.opacity(0.22)
    }

    var body: some View {
        ZStack {
            // Opaque themed background — fully covers the system popover's
            // default vibrancy chrome.
            QuickNoteCardBackground(
                appearance: store.settings.menuBarPopoverAppearance,
                cornerRadius: 0
            )

            VStack(alignment: .leading, spacing: 10) {
                if store.settings.menuBarPopoverShowMessage {
                    messageView
                } else {
                    editorView
                }

                Divider()
                    .background(effectiveTextColor.opacity(0.18))
                    .padding(.vertical, 2)

                footer
            }
            .padding(16)
        }
        .frame(width: 320)
        .onAppear {
            // Only steal focus when there's actually a field to type in.
            if !store.settings.menuBarPopoverShowMessage {
                focused = true
            }
        }
    }

    // MARK: - Editor mode (default)

    /// Editable text field bound to the menu bar text. Return commits and
    /// closes, esc cancels.
    @ViewBuilder
    private var editorView: some View {
        Text(L10n.string("ui.menu.bar.text", default: "Menu bar text"))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(effectiveTextColor.opacity(0.65))
            .tracking(0.6)
            .textCase(.uppercase)

        TextField(
            "Type something…",
            text: $store.settings.menuBarCustomText
        )
        .textFieldStyle(.plain)
        .font(.system(size: 14))
        .foregroundStyle(effectiveTextColor)
        .tint(effectiveTextColor)
        .focused($focused)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(fieldChromeFill))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(fieldChromeBorder, lineWidth: 0.5))
        .onSubmit { onCommit() }
        .onKeyPress(.escape) {
            onCancel()
            return .handled
        }

        HStack(spacing: 8) {
            Text(L10n.string("ui.press.return.to.save.esc.to.close", default: "Press return to save, esc to close"))
                .font(.system(size: 11))
                .foregroundStyle(effectiveTextColor.opacity(0.55))
            Spacer()
            Text("\(store.settings.menuBarCustomText.count)/30")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(
                    store.settings.menuBarCustomText.count > 30
                        ? .red
                        : effectiveTextColor.opacity(0.55)
                )
        }
    }

    // MARK: - Message mode

    /// Static, read-only message — what the user typed in
    /// Settings → Menu Bar → Popover Display. Decoupled from the menu bar
    /// text so the user can keep a short label in the bar and a longer
    /// reminder/quote/affirmation here.
    @ViewBuilder
    private var messageView: some View {
        let raw = store.settings.menuBarPopoverMessage
            .trimmingCharacters(in: .whitespacesAndNewlines)

        Text(L10n.string("ui.message", default: "Message"))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(effectiveTextColor.opacity(0.65))
            .tracking(0.6)
            .textCase(.uppercase)

        if raw.isEmpty {
            Text(L10n.string("ui.set.a.message.in.settings.menu.bar.p.44fbc3", default: "Set a message in Settings → Menu Bar → Popover Display."))
                .font(.system(size: 13))
                .italic()
                .foregroundStyle(effectiveTextColor.opacity(0.45))
                .padding(.vertical, 4)
        } else if let attributed = try? AttributedString(
            markdown: raw,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .full
            )
        ) {
            Text(attributed)
                .font(.system(size: 14))
                .foregroundStyle(effectiveTextColor.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.vertical, 4)
        } else {
            Text(raw)
                .font(.system(size: 14))
                .foregroundStyle(effectiveTextColor.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.vertical, 4)
        }
    }

    // MARK: - Footer (escape hatches)

    /// Without this row the user would be stuck — clicking the menu bar item
    /// only reveals this popover and there's no way to get to Settings or
    /// other Jack actions from there. Mirrors the most-used items from the
    /// icon-mode MenuBarExtra menu.
    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                openSettingsToMenuBarTab()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape")
                    Text(CommonCopy.settings())
                }
                .font(.system(size: 12))
                .foregroundStyle(effectiveTextColor.opacity(0.9))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .help("Open Menu Bar settings")

            Spacer()

            Menu {
                Button("Show \(AppBrand.displayName)") {
                    onCommit()
                    NSApp.activate(ignoringOtherApps: true)
                    AppWindowManager.shared.toggleWindow(source: "menu-bar-text-popover")
                }
                Button(AppMenuCopy.openMeetings()) {
                    onCommit()
                    NSApp.activate(ignoringOtherApps: true)
                    store.openMeetingsInWorkspace()
                    store.settings.viewMode = .workspace
                    AppWindowManager.shared.toggleWindow(source: "menu-bar-text-popover-meetings")
                }
                Button(store.settings.jackSettings.isVisible ? "Hide Jack" : "Summon Jack") {
                    onCommit()
                    if store.settings.jackSettings.isVisible {
                        store.settings.jackSettings.presenceMode = .off
                    } else {
                        store.settings.jackSettings.presenceMode = .alwaysOn
                    }
                }

                Divider()

                viewModeMenu

                Divider()

                Button(L10n.string("ui.check.for.updates", default: "Check for Updates…")) {
                    onCommit()
                    AppUpdater.shared.checkForUpdates()
                }
                .disabled(!AppUpdater.shared.isConfigured)

                Divider()

                Button("Quit \(AppBrand.displayName)") {
                    NSApplication.shared.terminate(nil)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "ellipsis.circle")
                    Text(L10n.string("ui.more", default: "More"))
                }
                .font(.system(size: 12))
                .foregroundStyle(effectiveTextColor.opacity(0.9))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More Jack actions")
        }
    }

    @ViewBuilder
    private var viewModeMenu: some View {
        Menu(L10n.string("ui.view.mode", default: "View Mode")) {
            ForEach(ViewMode.allCases) { mode in
                Button {
                    onCommit()
                    store.settings.viewMode = mode
                } label: {
                    if store.settings.viewMode == mode {
                        Label(mode.label, systemImage: "checkmark")
                    } else {
                        Text(mode.label)
                    }
                }
            }
        }
    }

    private func openSettingsToMenuBarTab() {
        onCommit()
        NSApp.activate(ignoringOtherApps: true)
        SettingsNavigation.requestTab(rawValue: SettingsTab.menuBar.rawValue)
        AppWindowManager.shared.prepareForSettingsPresentation(source: "menu-bar-text-popover")
        openWindow(id: SettingsNavigation.windowID)
    }
}
