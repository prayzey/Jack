import AppKit
import OSLog
import SwiftUI
import UniformTypeIdentifiers

/// Real macOS vibrancy — wraps NSVisualEffectView for genuine desktop blur-through
struct VibrancyBackgroundView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.layer?.cornerRadius = cornerRadius
    }
}

private struct ClipCardFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

// INVARIANT: Never attach .sheet() or .fullScreenCover() to this view.
// ContentView lives inside the narrow bottom tray window (dock-level). SwiftUI sheets
// attach to their parent window, so they render squashed inside the tray instead of
// centered on screen. Use AppWindowManager to present standalone NSWindows instead.
struct ContentView: View {
    private static let clipStripLeadingAnchorID = "ClipStripLeadingAnchor"
    private static let clipStripTrailingAnchorID = "ClipStripTrailingAnchor"

    @EnvironmentObject private var store: ClipboardStore
    @Environment(\.openWindow) private var openWindow

    @FocusState private var searchFocused: Bool
    @FocusState private var containerFocused: Bool
    @State private var isSearchOpen = false
    @State private var deleteKeyMonitor: Any?
    @State private var dropTargetStripItemID: UUID?
    @State private var dropTargetPlacement: StripReorderPlacement?
    @State private var draggedStripItemID: UUID?
    @State private var stripItemFrames: [UUID: CGRect] = [:]
    @State private var stripDragRecoveryGeneration = 0
    @State private var clipStripViewportWidth: CGFloat = 0
    @State private var clipStripScrollView: NSScrollView?
    @State private var clipAutoScrollTimer: Timer?
    @State private var clipAutoScrollDirection: Int = 0
    @State private var clipAutoScrollProximity: CGFloat = 0
    @State private var clipAutoScrollLastTick: CFAbsoluteTime?
    @State private var clipStripJumpRequestCount = 0
    private let dragLogger = Logger(subsystem: AppBrand.logSubsystem, category: "ClipDrag")
    private let dragDebugLoggingEnabled = ProcessInfo.processInfo.environment["GILT_DEBUG_LOGS"] == "1"

    private func clipboardFont(size: CGFloat, weight: Font.Weight = .regular, forceMonospaced: Bool = false) -> Font {
        store.settings.clipboardUIFont(size: size, weight: weight, forceMonospaced: forceMonospaced)
    }

    @ViewBuilder
    private var aiToastOverlay: some View {
        if let toast = store.aiToast {
            AIToastView(toast: toast) { store.dismissAIToast() }
                .padding(.top, 10)
                .padding(.horizontal, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            resizeHandle
            topRail
            TrialNudgeBanner()
                .padding(.horizontal, 4)
            UpdateBanner()
                .padding(.horizontal, 4)
            clipsStrip
        }
        .padding(.horizontal, 14)
        .padding(.top, 0)
        .padding(.bottom, 12)
        .overlay {
            if store.appAccessState == .locked {
                LicenseGateView()
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
        .overlay(alignment: .top) { aiToastOverlay }
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: store.aiToast)
        .modifier(AuricBackground(store: store, cornerRadius: 16))
        .folderDeleteOverlay()
        .folderClearOverlay()
        .background(
            WindowAccessor { window in
                AppWindowManager.shared.bind(window: window)
            }
        )
        // Selection + preview clearing now handled immediately in ClipboardStore.selectedFolderID didSet
        .onReceive(NotificationCenter.default.publisher(for: .requestSearchFocus)) { _ in
            // Only focus if already expanded (user explicitly opened search).
            // Don't auto-expand on window show — let users click the icon.
            if searchExpanded {
                searchFocused = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .requestClipStripSnapToLatest)) { note in
            guard store.settings.scrollToLatestOnShow,
                  let window = note.object as? NSWindow,
                  window == clipStripScrollView?.window else { return }
            clipStripJumpRequestCount += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: SettingsNavigation.openSettingsNotification)) { _ in
            // ContentView is the one place that always holds `openWindow`, so it
            // opens Settings on behalf of AppKit contexts (e.g. the command palette).
            openWindow(id: SettingsNavigation.windowID)
        }
        .focusable()
        .focused($containerFocused)
        .focusEffectDisabled()
        .onKeyPress(.escape) {
            guard !searchExpanded else { return .ignored }
            // Dismiss preview first, then clear selection
            if store.previewingClipID != nil {
                DispatchQueue.main.async { store.previewingClipID = nil }
                return .handled
            }
            guard !store.selectedClipIDs.isEmpty else { return .ignored }
            DispatchQueue.main.async { store.clearSelection() }
            return .handled
        }
        .onKeyPress(.delete) {
            guard !store.selectedClipIDs.isEmpty else { return .ignored }
            DispatchQueue.main.async { store.deleteClips(store.selectedClipIDs) }
            return .handled
        }
        .onKeyPress(.deleteForward) {
            guard !store.selectedClipIDs.isEmpty else { return .ignored }
            DispatchQueue.main.async { store.deleteClips(store.selectedClipIDs) }
            return .handled
        }
        // macOS responder-chain delete handler — fires even when SwiftUI @FocusState
        // doesn't reflect actual first-responder status (e.g. after context menu dismissal).
        .onDeleteCommand {
            guard !store.selectedClipIDs.isEmpty else { return }
            store.deleteClips(store.selectedClipIDs)
        }
        .onKeyPress(.leftArrow) {
            guard !searchExpanded else { return .ignored }
            guard store.previewingClipID == nil else { return .ignored }
            DispatchQueue.main.async { store.navigateSelection(direction: -1) }
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard !searchExpanded else { return .ignored }
            guard store.previewingClipID == nil else { return .ignored }
            DispatchQueue.main.async { store.navigateSelection(direction: 1) }
            return .handled
        }
        .onKeyPress(.space) {
            guard !searchExpanded else { return .ignored }
            guard store.inlineEditingClipID == nil else { return .ignored }
            DispatchQueue.main.async { store.openPreviewForSelection() }
            return .handled
        }
        .onKeyPress(.return, phases: .down) { keyPress in
            guard !searchExpanded else { return .ignored }
            guard store.inlineEditingClipID == nil else { return .ignored }
            guard !store.selectedClipIDs.isEmpty else { return .ignored }
            let forcePlain = keyPress.modifiers.contains(.option)
            if let firstID = store.selectedClipIDs.first {
                store.loadSelectedOrSingleToClipboard(primaryID: firstID, autoPaste: true, forcePlainText: forcePlain)
            }
            return .handled
        }
        .onAppear {
            containerFocused = true
            installDeleteKeyMonitor()
        }
        .onDisappear {
            logDrag("content view disappeared; clearing drag state")
            removeDeleteKeyMonitor()
            stopClipAutoScroll()
            clipStripScrollView = nil
            AppWindowManager.shared.setInternalDragActive(false)
        }
        .onChange(of: searchFocused) { _, focused in
            if !focused { containerFocused = true }
        }
        .onChange(of: store.selectedClipIDs) { _, _ in
            // Re-grab keyboard focus after card click so Delete/arrow keys work
            if !searchFocused { containerFocused = true }
        }
        .onChange(of: store.selectedFolderID) { _, _ in
            // Keep tray-level key shortcuts active after folder tab switches.
            if !searchFocused { containerFocused = true }
        }
        .ignoresSafeArea(.all, edges: .top)
    }

    private var resizeHandle: some View {
        ZStack {
            // AppKit view handles all mouse tracking in screen coordinates
            AppKitResizeHandle()
                .frame(height: 24)

            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: 44, height: 4)
                .allowsHitTesting(false)
        }
    }

    private var searchExpanded: Bool {
        isSearchOpen || !store.searchText.isEmpty
    }

    private var topRail: some View {
        HStack(spacing: 10) {
            // Search icon — always visible, toggles search field
            Button {
                if searchExpanded {
                    dismissSearch()
                } else {
                    openSearch()
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Search field — slides in when active
            if searchExpanded {
                HStack(spacing: 6) {
                    ClipSearchTextField(
                        placeholder: "Search clips…",
                        font: clipboardFont(size: 13),
                        focus: $searchFocused,
                        onEscape: { dismissSearch() },
                        onSubmit: {
                            // Keep the field open; on Return, interpret the query when
                            // natural-language search is enabled.
                            if store.aiSearchAvailable { store.aiInterpretSearch() }
                        }
                    )

                    // Natural-language search — interpret the free-form query into filters
                    if store.aiSearchAvailable, !store.searchText.isEmpty {
                        Button {
                            store.aiInterpretSearch()
                        } label: {
                            Group {
                                if store.aiSearchInterpreting {
                                    ProgressView().controlSize(.mini)
                                } else {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                            }
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(store.aiSearchInterpreting)
                        .help(L10n.string("ai.search.help", default: "Interpret this search with on-device AI"))
                    }

                    // Result count badge
                    if !store.searchText.isEmpty {
                        Text("\(store.filteredClips.count)")
                            .font(clipboardFont(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                    }

                    // Clear / dismiss button
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.35))
                        .contentShape(Rectangle())
                        .onTapGesture { dismissSearch() }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(width: 200)
                .background(Capsule().fill(Color.white.opacity(0.10)))
                .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .leading)))
            }

            FolderTabsView()

            Spacer(minLength: 4)

            Button {
                jumpToLatestClip()
            } label: {
                Image(systemName: store.settings.newestTrayClipsOnRight ? "arrow.right.to.line" : "arrow.left.to.line")
                    .font(clipboardFont(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(store.filteredClips.isEmpty ? 0.35 : 0.78))
                    .frame(width: 16, height: 16)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .disabled(store.filteredClips.isEmpty)
            .help("Jump to newest")

            // Ellipsis menu
            Menu {
                Button {
                    SettingsNavigation.requestTab(rawValue: SettingsNavigation.foldersTabRawValue)
                    NSApp.activate(ignoringOtherApps: true)
                    AppWindowManager.shared.prepareForSettingsPresentation(source: "tray-manage-folders")
                    openWindow(id: SettingsNavigation.windowID)
                } label: {
                    Label(L10n.string("ui.manage.folders.in.settings", default: "Manage Folders in Settings…"), systemImage: "folder.badge.gearshape")
                }

                Button {
                    Analytics.feedbackTapped()
                    NSWorkspace.shared.open(AppBrand.feedbackURL)
                } label: {
                    Label(L10n.string("menu.sendFeedback", default: "Send Feedback…"), systemImage: "envelope")
                }

                Button {
                    NSWorkspace.shared.open(AppBrand.bugReportURL)
                } label: {
                    Label(L10n.string("menu.reportBug", default: "Report a Bug…"), systemImage: "ladybug")
                }

                Button {
                    NSWorkspace.shared.open(AppBrand.featureRequestURL)
                } label: {
                    Label(L10n.string("menu.requestFeature", default: "Request a Feature…"), systemImage: "star")
                }

                Divider()

                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    AppWindowManager.shared.prepareForSettingsPresentation(source: "tray-settings-menu")
                    openWindow(id: SettingsNavigation.windowID)
                } label: {
                    Label(CommonCopy.settings(), systemImage: "gearshape")
                }

                Divider()

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Label("Quit \(AppBrand.displayName)", systemImage: "power")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
        }
        .animation(.easeInOut(duration: 0.22), value: searchExpanded)
    }

    private func dismissSearch() {
        isSearchOpen = false
        store.searchText = ""
        searchFocused = false
    }

    private func openSearch() {
        isSearchOpen = true
        AppWindowManager.shared.focusForInput()
        DispatchQueue.main.async {
            searchFocused = true
        }
        // Re-assert focus once the field has fully appeared — the first async
        // pass can land before the expanded field is in the hierarchy.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard searchExpanded else { return }
            searchFocused = true
        }
    }

    private func jumpToLatestClip() {
        guard !store.filteredClips.isEmpty else { return }
        clipStripJumpRequestCount += 1
        containerFocused = true
    }

    // MARK: – AppKit Delete Key Monitor

    /// Install a local NSEvent monitor that catches Delete/Backspace at the AppKit level.
    /// This is the bulletproof fallback: `.onKeyPress(.delete)` requires SwiftUI focus which
    /// can silently break after context-menu dismissal, drag-drop, or other AppKit interactions
    /// that move first-responder away from the focusable container.
    private func installDeleteKeyMonitor() {
        guard deleteKeyMonitor == nil else { return }
        deleteKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak store] event in
            guard let store else { return event }

            // Only handle when our window is key (don't intercept Settings or other windows)
            guard event.window?.windowNumber == NSApp.keyWindow?.windowNumber,
                  NSApp.keyWindow?.title.contains("Settings") != true else {
                return event
            }

            let deleteChar = String(UnicodeScalar(NSDeleteCharacter)!)
            let deleteForwardChar = String(UnicodeScalar(NSDeleteFunctionKey)!)
            let chars = event.charactersIgnoringModifiers ?? ""

            // Only bare Delete or Fn+Delete (no Cmd/Ctrl/Option modifiers)
            let hasModifiers = event.modifierFlags.intersection([.command, .control, .option]) != []

            if !hasModifiers && (chars == deleteChar || chars == deleteForwardChar) {
                // Don't intercept when a text field has focus (search field, rename, etc.)
                if let responder = event.window?.firstResponder,
                   responder is NSTextView || responder is NSTextField {
                    return event
                }

                guard !store.selectedClipIDs.isEmpty else { return event }
                DispatchQueue.main.async {
                    store.deleteClips(store.selectedClipIDs)
                }
                return nil  // Swallow the event (also suppresses the system beep)
            }

            return event
        }
    }

    private func removeDeleteKeyMonitor() {
        if let monitor = deleteKeyMonitor {
            NSEvent.removeMonitor(monitor)
            deleteKeyMonitor = nil
        }
    }

    private var clipsStrip: some View {
        GeometryReader { geo in
            let cardHeight = max(0, geo.size.height - 20)
            let cardWidth = min(max(cardHeight * 1.26, 220), 340)

            ScrollViewReader { proxy in
                ZStack {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            Color.clear
                                .frame(width: 0, height: 1)
                                .id(Self.clipStripLeadingAnchorID)

                            ForEach(displayedStripItems) { stripItem in
                                stripItemView(stripItem, cardWidth: cardWidth, cardHeight: cardHeight)
                            }

                            Color.clear
                                .frame(width: 0, height: 1)
                                .id(Self.clipStripTrailingAnchorID)
                        }
                        .animation(
                            store.searchText.isEmpty
                                ? .interactiveSpring(response: 0.24, dampingFraction: 0.86)
                                : nil,
                            value: store.stripItemIDs
                        )
                        .padding(.vertical, 4)
                        .padding(.horizontal, 2)
                    }
                    .coordinateSpace(name: "ClipStripScroll")
                    .onDrop(of: [.plainText], delegate: makeStripDropDelegate())
                    .background(
                        GeometryReader { scrollGeo in
                            Color.clear
                                .onAppear {
                                    clipStripViewportWidth = scrollGeo.size.width
                                }
                                .onChange(of: scrollGeo.size.width) { _, newValue in
                                    clipStripViewportWidth = newValue
                                }
                        }
                    )
                    .background(
                        ClipStripScrollViewAccessor { scrollView in
                            if clipStripScrollView !== scrollView {
                                clipStripScrollView = scrollView
                            }
                        }
                    )
                    .onChange(of: clipStripJumpRequestCount) { _, _ in
                        snapClipStripToLatest(using: proxy)
                    }
                    .onChange(of: store.settings.newestTrayClipsOnRight) { _, _ in
                        snapClipStripToLatest(using: proxy)
                    }
                    .onPreferenceChange(ClipCardFramePreferenceKey.self) { frames in
                        guard draggedStripItemID != nil else {
                            if !stripItemFrames.isEmpty {
                                stripItemFrames = [:]
                            }
                            return
                        }
                        stripItemFrames = frames
                        updateClipAutoScrollState()
                    }
                    .onChange(of: dropTargetStripItemID) { oldValue, newValue in
                        if oldValue != newValue {
                            logDrag("drop target \(shortItemID(oldValue)) -> \(shortItemID(newValue))")
                        }
                        updateClipAutoScrollState()
                    }
                    .onChange(of: draggedStripItemID) { oldValue, newValue in
                        if oldValue != newValue {
                            logDrag(
                                "drag state \(shortItemID(oldValue)) -> \(shortItemID(newValue)) "
                                    + "appActive=\(NSApp.isActive) "
                                    + "theme=\(store.settings.backgroundTheme.rawValue) "
                                    + "wallpaper=\(store.settings.backgroundWallpaper.rawValue)"
                            )
                        }
                        if oldValue == nil, newValue != nil {
                            stripDragRecoveryGeneration += 1
                            ClipDragLifecycle.begin()
                        } else if oldValue != nil, newValue == nil {
                            stripDragRecoveryGeneration += 1
                            ClipDragLifecycle.end()
                        }
                        if newValue == nil {
                            dropTargetPlacement = nil
                            stripItemFrames = [:]
                            stopClipAutoScroll()
                        } else {
                            updateClipAutoScrollState()
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .clipDragDidEnd)) { _ in
                        draggedStripItemID = nil
                        dropTargetStripItemID = nil
                        dropTargetPlacement = nil
                        stripItemFrames = [:]
                        stopClipAutoScroll()
                    }
                    // NOTE: Removed auto-scroll-to-center on single selection.
                    // It fought with double-tap-to-paste — the first tap scrolled the
                    // card away, making the second tap miss.

                    // Preview overlay — replaces clip strip when active
                    if let previewID = store.previewingClipID,
                       let previewItem = store.filteredClips.first(where: { $0.clipID == previewID }) {
                        ClipPreviewOverlay(item: previewItem)
                            .environmentObject(store)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func stripItemView(_ stripItem: ClipStripItem, cardWidth: CGFloat, cardHeight: CGFloat) -> some View {
        switch stripItem {
        case .clip(let item, let index):
            clipCardInStrip(item: item, index: index, cardWidth: cardWidth, cardHeight: cardHeight)
        case .separator(let sep):
            separatorCardInStrip(separator: sep, cardHeight: cardHeight)
        }
    }

    private func clipCardInStrip(item: ClipItemModel, index: Int, cardWidth: CGFloat, cardHeight: CGFloat) -> some View {
        ClipCardView(
            item: item,
            cardWidth: cardWidth,
            cardHeight: cardHeight,
            onDragStarted: {
                logDrag(
                    "drag start clip=\(shortItemID(item.clipID)) "
                        + "selectedCount=\(store.selectedClipIDs.count) "
                        + "wallpaper=\(store.settings.backgroundWallpaper.rawValue)"
                )
                draggedStripItemID = item.clipID
                dropTargetStripItemID = nil
                dropTargetPlacement = nil
            }
        )
        .id(item.clipID)
        .environmentObject(store)
        .opacity(draggedStripItemID == item.clipID ? 0.45 : 1.0)
        .scaleEffect(draggedStripItemID == item.clipID ? 0.97 : 1.0)
        .animation(.easeOut(duration: 0.1), value: draggedStripItemID)
        .onAppear {
            if index >= store.filteredClips.count - 5 {
                store.loadMoreClips()
            }
        }
        .overlay(alignment: dropIndicatorAlignment(for: item.clipID)) {
            if shouldShowDropIndicator(for: item.clipID) {
                clipInsertionIndicator
                    .offset(x: dropIndicatorOffset(for: item.clipID))
                    .transition(.opacity)
            }
        }
        .background {
            if draggedStripItemID != nil {
                GeometryReader { cardGeo in
                    Color.clear.preference(
                        key: ClipCardFramePreferenceKey.self,
                        value: [item.clipID: cardGeo.frame(in: .named("ClipStripScroll"))]
                    )
                }
            }
        }
    }

    private func separatorCardInStrip(separator: FolderSeparatorModel, cardHeight: CGFloat) -> some View {
        SeparatorCardView(separator: separator, cardHeight: cardHeight)
            .id(separator.separatorID)
            .environmentObject(store)
            .opacity(draggedStripItemID == separator.separatorID ? 0.45 : 1.0)
            .scaleEffect(draggedStripItemID == separator.separatorID ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.1), value: draggedStripItemID)
            .overlay(alignment: dropIndicatorAlignment(for: separator.separatorID)) {
                if shouldShowDropIndicator(for: separator.separatorID) {
                    clipInsertionIndicator
                        .offset(x: dropIndicatorOffset(for: separator.separatorID))
                        .transition(.opacity)
                }
            }
            .background {
                if draggedStripItemID != nil {
                    GeometryReader { cardGeo in
                        Color.clear.preference(
                            key: ClipCardFramePreferenceKey.self,
                            value: [separator.separatorID: cardGeo.frame(in: .named("ClipStripScroll"))]
                        )
                    }
                }
            }
            .onDrag {
                logDrag("drag start separator=\(shortItemID(separator.separatorID))")
                draggedStripItemID = separator.separatorID
                dropTargetStripItemID = nil
                dropTargetPlacement = nil
                return ClipDragItemProvider.makeProvider(for: separator)
            }
    }

    private var clipInsertionIndicator: some View {
        Capsule()
            .fill(Color.white.opacity(0.88))
            .frame(width: 3, height: 42)
            .shadow(color: .white.opacity(0.5), radius: 4)
            .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 0)
            .modifier(PulseOpacity())
    }

    private func makeStripDropDelegate() -> StripReorderDropDelegate {
        StripReorderDropDelegate(
            isActive: { draggedStripItemID != nil },
            updateReorder: updateStripDropHover,
            finalizeDrop: finalizeStripDrop,
            clearDropTarget: clearStripDropTarget,
            scheduleDragStateRecovery: scheduleStripDragStateRecovery
        )
    }

    private func updateStripDropHover(_ location: CGPoint) {
        guard let draggedItem = currentDraggedStripItem(),
              let target = horizontalReorderTarget(
                  ids: store.stripItems.map(\.id),
                  frames: stripItemFrames,
                  draggedID: draggedItem.id,
                  locationX: location.x
              ) else {
            clearStripDropTarget()
            return
        }

        setDropTarget(target.targetID, placement: target.placement)

        withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.86)) {
            store.moveStripItem(
                draggedItem,
                relativeTo: target.targetID,
                placement: logicalStripPlacement(target.placement, newestOnRight: store.settings.newestTrayClipsOnRight)
            )
        }
    }

    private func finalizeStripDrop(_ location: CGPoint) -> Bool {
        let previousTarget = shortItemID(dropTargetStripItemID)
        guard let draggedItem = currentDraggedStripItem(),
              let target = horizontalReorderTarget(
                  ids: store.stripItems.map(\.id),
                  frames: stripItemFrames,
                  draggedID: draggedItem.id,
                  locationX: location.x
              ) else {
            clearStripDragState(animated: true)
            logDrag("drop ignored target=nil previousTarget=\(previousTarget)")
            return false
        }

        stopClipAutoScroll()
        withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.86)) {
            store.moveStripItem(
                draggedItem,
                relativeTo: target.targetID,
                placement: logicalStripPlacement(target.placement, newestOnRight: store.settings.newestTrayClipsOnRight)
            )
        }
        clearStripDragState(animated: true)
        logDrag(
            "drop accepted dragged=\(shortItemID(draggedItem.id)) "
                + "\(target.placement == .before ? "before" : "after")=\(shortItemID(target.targetID)) "
                + "previousTarget=\(previousTarget)"
        )
        return true
    }

    private func currentDraggedStripItem() -> StripDragItem? {
        guard let draggedStripItemID else { return nil }
        guard let draggedItem = store.stripItems.first(where: { $0.id == draggedStripItemID }) else {
            return nil
        }

        switch draggedItem {
        case .clip(let clip, _):
            return .clip(clip.clipID)
        case .separator(let separator):
            return .separator(separator.separatorID)
        }
    }

    private func setDropTarget(_ targetID: UUID?, placement: StripReorderPlacement?) {
        guard dropTargetStripItemID != targetID || dropTargetPlacement != placement else { return }

        let previousTarget = shortItemID(dropTargetStripItemID)
        dropTargetStripItemID = targetID
        dropTargetPlacement = placement

        let nextTarget = shortItemID(targetID)
        if previousTarget != nextTarget {
            logDrag("drop target \(previousTarget) -> \(nextTarget)")
        }
        if let targetID, let placement {
            logDrag(
                "hover target=\(shortItemID(targetID)) placement=\(placement == .before ? "before" : "after") "
                    + "dragged=\(shortItemID(draggedStripItemID))"
            )
        }
    }

    private func clearStripDropTarget() {
        guard dropTargetStripItemID != nil || dropTargetPlacement != nil else { return }
        logDrag("hover leave target=\(shortItemID(dropTargetStripItemID))")
        dropTargetStripItemID = nil
        dropTargetPlacement = nil
    }

    private func clearStripDragState(animated: Bool) {
        let clearState = {
            stripDragRecoveryGeneration += 1
            dropTargetStripItemID = nil
            dropTargetPlacement = nil
            draggedStripItemID = nil
        }

        if animated {
            withAnimation(.easeOut(duration: 0.12)) {
                clearState()
            }
        } else {
            clearState()
        }

        stripItemFrames = [:]
        stopClipAutoScroll()
    }

    private func scheduleStripDragStateRecovery() {
        guard let draggedStripItemID else { return }
        stripDragRecoveryGeneration += 1
        // Folder tabs depend on the clip drag staying alive after the pointer
        // leaves the strip; only cancel once the mouse is actually released.
        pollForStripDragRelease(
            expectedDraggedID: draggedStripItemID,
            generation: stripDragRecoveryGeneration
        )
    }

    private func pollForStripDragRelease(expectedDraggedID: UUID, generation: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard generation == stripDragRecoveryGeneration else { return }

            switch dragRecoveryAction(
                currentDraggedID: draggedStripItemID,
                expectedDraggedID: expectedDraggedID,
                currentTargetID: dropTargetStripItemID,
                pressedMouseButtons: NSEvent.pressedMouseButtons
            ) {
            case .clearDragState:
                logDrag("mouse release outside strip cleared drag state")
                clearStripDragState(animated: true)
            case .keepWaiting:
                pollForStripDragRelease(expectedDraggedID: expectedDraggedID, generation: generation)
            case .stopWaiting:
                return
            }
        }
    }

    private func shouldShowDropIndicator(for targetID: UUID) -> Bool {
        dropTargetStripItemID == targetID && draggedStripItemID != targetID
    }

    private func dropIndicatorAlignment(for targetID: UUID) -> Alignment {
        guard dropTargetStripItemID == targetID else { return .leading }
        return dropTargetPlacement == .after ? .trailing : .leading
    }

    private func dropIndicatorOffset(for targetID: UUID) -> CGFloat {
        guard dropTargetStripItemID == targetID else { return -8 }
        return dropTargetPlacement == .after ? 8 : -8
    }

    private func updateClipAutoScrollState() {
        guard draggedStripItemID != nil,
              let targetID = dropTargetStripItemID,
              targetID != draggedStripItemID,
              let frame = stripItemFrames[targetID],
              clipStripViewportWidth > 0 else {
            stopClipAutoScroll()
            return
        }

        let state = clipAutoScrollState(frame: frame, viewportWidth: clipStripViewportWidth)
        guard state.direction != 0 else {
            stopClipAutoScroll()
            return
        }
        startClipAutoScroll(direction: state.direction, proximity: state.proximity)
    }

    private func startClipAutoScroll(direction: Int, proximity: CGFloat) {
        clipAutoScrollDirection = direction
        clipAutoScrollProximity = proximity

        guard clipAutoScrollTimer == nil else { return }

        clipAutoScrollLastTick = CFAbsoluteTimeGetCurrent()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { _ in
            DispatchQueue.main.async {
                performClipAutoScrollStep()
            }
        }
        timer.tolerance = 1.0 / 240.0
        clipAutoScrollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func performClipAutoScrollStep() {
        guard draggedStripItemID != nil,
              dropTargetStripItemID != nil,
              clipAutoScrollDirection != 0,
              clipAutoScrollProximity > 0,
              let scrollView = clipStripScrollView,
              let documentView = scrollView.documentView else {
            stopClipAutoScroll()
            return
        }

        let now = CFAbsoluteTimeGetCurrent()
        let deltaTime: CFAbsoluteTime
        if let last = clipAutoScrollLastTick {
            deltaTime = min(max(now - last, 1.0 / 240.0), 1.0 / 24.0)
        } else {
            deltaTime = 1.0 / 60.0
        }
        clipAutoScrollLastTick = now

        let speed = clipAutoScrollSpeed(proximity: clipAutoScrollProximity)
        let deltaX = CGFloat(deltaTime) * speed * CGFloat(clipAutoScrollDirection)
        guard abs(deltaX) >= 0.05 else {
            stopClipAutoScroll()
            return
        }

        let contentView = scrollView.contentView
        let currentX = contentView.bounds.origin.x
        let maxX = max(0, documentView.bounds.width - contentView.bounds.width)
        let nextX = min(max(currentX + deltaX, 0), maxX)
        if abs(nextX - currentX) < 0.05 {
            stopClipAutoScroll()
            return
        }

        contentView.setBoundsOrigin(CGPoint(x: nextX, y: contentView.bounds.origin.y))
        scrollView.reflectScrolledClipView(contentView)
    }

    private func stopClipAutoScroll() {
        clipAutoScrollTimer?.invalidate()
        clipAutoScrollTimer = nil
        clipAutoScrollDirection = 0
        clipAutoScrollProximity = 0
        clipAutoScrollLastTick = nil
    }

    private func snapClipStripToLatest(using proxy: ScrollViewProxy) {
        var transaction = Transaction()
        transaction.animation = nil

        withTransaction(transaction) {
            if store.settings.newestTrayClipsOnRight {
                proxy.scrollTo(Self.clipStripTrailingAnchorID, anchor: .trailing)
            } else {
                proxy.scrollTo(Self.clipStripLeadingAnchorID, anchor: .leading)
            }
        }

        // Keep the AppKit fallback in place for the drag auto-scroll path.
        if let scrollView = clipStripScrollView {
            let contentView = scrollView.contentView
            let maxX = max(0, (scrollView.documentView?.bounds.width ?? 0) - contentView.bounds.width)
            contentView.setBoundsOrigin(CGPoint(
                x: store.settings.newestTrayClipsOnRight ? maxX : 0,
                y: contentView.bounds.origin.y
            ))
            scrollView.reflectScrolledClipView(contentView)
        }
    }

    private var displayedStripItems: [ClipStripItem] {
        store.settings.newestTrayClipsOnRight ? Array(store.stripItems.reversed()) : store.stripItems
    }

    private func shortItemID(_ id: UUID?) -> String {
        guard let id else { return "nil" }
        return String(id.uuidString.prefix(8))
    }

    private func logDrag(_ message: String) {
        guard dragDebugLoggingEnabled else { return }
        dragLogger.debug("\(message, privacy: .public)")
    }
}

private struct ClipStripScrollViewAccessor: NSViewRepresentable {
    let onResolve: (NSScrollView?) -> Void

    func makeNSView(context: Context) -> AccessorView {
        let view = AccessorView()
        view.onResolve = onResolve
        return view
    }

    func updateNSView(_ nsView: AccessorView, context: Context) {
        nsView.onResolve = onResolve
        nsView.resolveScrollView()
    }

    final class AccessorView: NSView {
        var onResolve: (NSScrollView?) -> Void = { _ in }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            resolveScrollView()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            resolveScrollView()
        }

        func resolveScrollView() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                onResolve(self.enclosingScrollView)
            }
        }
    }
}

private struct PulseOpacity: ViewModifier {
    @State private var pulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(pulsing ? 0.7 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
    }
}
