import AppKit
import SwiftUI

func radialPageCount(total: Int, pageSize: Int, maxPages: Int) -> Int {
    guard pageSize > 0 else { return 1 }
    guard maxPages > 0 else { return 1 }
    let computed = Int(ceil(Double(max(0, total)) / Double(pageSize)))
    return max(1, min(maxPages, computed))
}

func clampedRadialPageIndex(index: Int, total: Int, pageSize: Int, maxPages: Int) -> Int {
    let maxIndex = radialPageCount(total: total, pageSize: pageSize, maxPages: maxPages) - 1
    return min(max(0, index), maxIndex)
}

func radialPageSlice<T>(_ items: [T], pageIndex: Int, pageSize: Int, maxPages: Int) -> ArraySlice<T> {
    guard pageSize > 0, !items.isEmpty else { return [] }
    let cappedItems = Array(items.prefix(pageSize * max(1, maxPages)))
    let safePage = clampedRadialPageIndex(
        index: pageIndex,
        total: cappedItems.count,
        pageSize: pageSize,
        maxPages: maxPages
    )
    let start = safePage * pageSize
    let end = min(start + pageSize, cappedItems.count)
    return cappedItems[start..<end]
}

/// Radial menu mode — quick-access ring of recent clips at cursor position.
struct RadialMenuView: View {
    @EnvironmentObject private var store: ClipboardStore
    @Environment(\.openWindow) private var openWindow
    @FocusState private var searchFocused: Bool
    @FocusState private var containerFocused: Bool
    @State private var isSearchOpen = false
    @State private var diameter: CGFloat = 400
    @State private var showResizeHint = false
    @State private var pageIndex = 0
    @State private var horizontalPageCarry: CGFloat = 0

    private let folderBarHeight: CGFloat = 36
    private let maxItems = 8
    private let maxPages = 6

    private var searchExpanded: Bool {
        isSearchOpen || !store.searchText.isEmpty
    }

    private var ringRadius: CGFloat {
        diameter * 0.35
    }

    private var nodeSize: CGSize {
        let scale = diameter / 400
        return CGSize(width: 90 * scale, height: 70 * scale)
    }

    private var goldAccent: Color {
        Color(red: 0.83, green: 0.66, blue: 0.26)
    }

    private var visibleClips: [ClipItemModel] {
        Array(
            radialPageSlice(
                store.filteredClips,
                pageIndex: pageIndex,
                pageSize: maxItems,
                maxPages: maxPages
            )
        )
    }

    private var totalPages: Int {
        radialPageCount(total: store.filteredClips.count, pageSize: maxItems, maxPages: maxPages)
    }

    private var hasMultiplePages: Bool {
        totalPages > 1
    }

    private var pageSwipeThreshold: CGFloat {
        let sensitivity = min(max(store.settings.radialPageSwipeSensitivity, 0.4), 1.6)
        return 34 / CGFloat(sensitivity)
    }

    var body: some View {
        rootContent
    }

    private var rootContent: some View {
        applyRootModifiers(
            ZStack {
                VStack(spacing: 0) {
                    radialCircle
                    radialFolderBar
                }

                if let previewItem {
                    ClipPreviewOverlay(item: previewItem)
                        .environmentObject(store)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .zIndex(1)
                }

            }
        )
    }

    private var radialCircle: some View {
        // Circle with ring of clips
        ZStack {
            // Theme-aware background (same engine as tray/drawer/grid)
            themedBackgroundCircle

            // Ring of clips
            ForEach(Array(visibleClips.enumerated()), id: \.element.clipID) { index, item in
                let count = visibleClips.count
                let angle = angleFor(index: index, total: count)

                RadialClipNode(item: item, nodeSize: nodeSize)
                    .environmentObject(store)
                    .offset(
                        x: cos(angle) * ringRadius,
                        y: sin(angle) * ringRadius
                    )
            }

            centerHub

            // First-use resize hint
            if showResizeHint {
                resizeHintBadge
                    .offset(y: 52)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }

            // License gate — sized to circle, clipped to match
            if store.appAccessState == .locked {
                LicenseGateView()
                    .frame(width: diameter, height: diameter)
                    .clipShape(Circle())
            }
        }
        .frame(width: diameter, height: diameter)
        .background(
            RadialScrollResizeOverlay(
                onPageScroll: { deltaX in
                    handleHorizontalPageScroll(deltaX)
                }
            )
            .frame(width: diameter, height: diameter)
            .clipShape(Circle())
        )
        .overlay(alignment: .top) {
            if searchExpanded {
                radialSearchBar
                    .padding(.top, 10)
                    .padding(.horizontal, 12)
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
            }
        }
    }

    private var radialFolderBar: some View {
        // Folder pills bar — full width, no background pill. Trailing inner
        // padding gives the last pill breathing room so overflow doesn't read
        // as an abrupt edge. We intentionally avoid `.mask` here because a
        // gradient mask on a ScrollView disables the hardware-accelerated
        // scroll path and makes horizontal scrolling visibly laggy.
        ScrollView(.horizontal, showsIndicators: false) {
            FolderTabsView()
                .environmentObject(store)
                .padding(.leading, 14)
                .padding(.trailing, 28)
        }
        .frame(width: diameter, height: folderBarHeight)
    }

    private func applyRootModifiers<Content: View>(_ content: Content) -> some View {
        content
        .frame(width: diameter, height: diameter + folderBarHeight)
        .onReceive(NotificationCenter.default.publisher(for: .requestSearchFocus)) { _ in
            if searchExpanded {
                searchFocused = true
            }
        }
        .focusable()
        .focused($containerFocused)
        .focusEffectDisabled()
        .onKeyPress(.escape) {
            if store.previewingClipID != nil {
                store.previewingClipID = nil
                return .handled
            }
            if searchExpanded {
                dismissSearch()
                return .handled
            }
            AppWindowManager.shared.toggleWindow(source: "radial-escape")
            return .handled
        }
        .onKeyPress(.leftArrow) {
            guard !searchFocused else { return .ignored }
            guard store.previewingClipID == nil else { return .ignored }
            stepPage(by: -1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard !searchFocused else { return .ignored }
            guard store.previewingClipID == nil else { return .ignored }
            stepPage(by: 1)
            return .handled
        }
        .onKeyPress(.space) {
            guard !searchExpanded else { return .ignored }
            store.openPreviewForSelection()
            return .handled
        }
        .onKeyPress(.delete) {
            guard !isTextInputFocused else { return .ignored }
            guard !store.selectedClipIDs.isEmpty else { return .ignored }
            store.deleteClips(store.selectedClipIDs)
            return .handled
        }
        .onKeyPress(.deleteForward) {
            guard !isTextInputFocused else { return .ignored }
            guard !store.selectedClipIDs.isEmpty else { return .ignored }
            store.deleteClips(store.selectedClipIDs)
            return .handled
        }
        .onDeleteCommand {
            guard !isTextInputFocused else { return }
            guard !store.selectedClipIDs.isEmpty else { return }
            store.deleteClips(store.selectedClipIDs)
        }
        .onReceive(NotificationCenter.default.publisher(for: .radialSizeDidChange)) { notification in
            if let newSize = notification.object as? CGFloat {
                diameter = newSize
                // Dismiss hint immediately once the user scrolls to resize
                if showResizeHint {
                    withAnimation(.easeOut(duration: 0.2)) { showResizeHint = false }
                    store.settings.hasSeenRadialResizeHint = true
                }
            }
        }
        .onAppear {
            containerFocused = true
            guard !store.settings.hasSeenRadialResizeHint else { return }
            // Show the hint after a short delay so it doesn't compete with the appear animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.easeOut(duration: 0.35)) { showResizeHint = true }
            }
            // Auto-dismiss after 4 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                guard showResizeHint else { return }
                withAnimation(.easeOut(duration: 0.4)) { showResizeHint = false }
                store.settings.hasSeenRadialResizeHint = true
            }
        }
        .onChange(of: searchFocused) { _, focused in
            if !focused { containerFocused = true }
        }
        .onChange(of: store.selectedClipIDs) { _, _ in
            if !searchFocused { containerFocused = true }
        }
        .onChange(of: store.selectedFolderID) { _, _ in
            pageIndex = 0
            horizontalPageCarry = 0
            if !searchFocused { containerFocused = true }
        }
        .onChange(of: store.searchText) { _, _ in
            pageIndex = 0
            horizontalPageCarry = 0
        }
        .onChange(of: store.filteredClips.count) { _, count in
            pageIndex = clampedRadialPageIndex(
                index: pageIndex,
                total: count,
                pageSize: maxItems,
                maxPages: maxPages
            )
            horizontalPageCarry = 0
        }
        .onChange(of: store.settings.radialSwipeDirection) { _, _ in
            horizontalPageCarry = 0
        }
        .onChange(of: store.settings.radialPageSwipeSensitivity) { _, _ in
            horizontalPageCarry = 0
        }
        .animation(.easeInOut(duration: 0.2), value: searchExpanded)
        .folderDeleteOverlay()
        .folderClearOverlay()
    }

    private var previewItem: ClipItemModel? {
        guard let previewID = store.previewingClipID else { return nil }
        return store.filteredClips.first(where: { $0.clipID == previewID })
    }

    /// Keep mode shortcuts from stealing focus while the preview editor is active.
    private var isTextInputFocused: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        return responder is NSTextView || responder is NSTextField
    }

    private var themedBackgroundCircle: some View {
        Rectangle()
            .fill(Color.clear)
            .modifier(AuricBackground(store: store, cornerRadius: diameter / 2))
            .clipShape(Circle())
        .overlay(
            Circle()
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var centerHub: some View {
        Button {
            NSApp.activate(ignoringOtherApps: true)
            AppWindowManager.shared.prepareForSettingsPresentation(source: "radial-center-settings")
            openWindow(id: SettingsNavigation.windowID)
        } label: {
            ZStack {
                Circle()
                    .fill(Color(NSColor(white: 0.10, alpha: 0.9)))
                    .frame(width: 74, height: 74)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [goldAccent, goldAccent.opacity(0.5)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
                    .shadow(color: goldAccent.opacity(0.2), radius: 8)

                VStack(spacing: 2) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(goldAccent)

                    Text(L10n.string("common.settings", default: "Settings"))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.76))
                }
            }
        }
        .buttonStyle(.plain)
        .help("Settings")
        .overlay {
            radialPageControls
        }
    }

    @ViewBuilder
    private var radialPageControls: some View {
        if hasMultiplePages {
            HStack(spacing: 10) {
                Button {
                    stepPage(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(pageIndex > 0 ? 0.82 : 0.35))
                .disabled(pageIndex == 0)

                radialPageDots

                Button {
                    stepPage(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(pageIndex < (totalPages - 1) ? 0.82 : 0.35))
                .disabled(pageIndex >= totalPages - 1)
            }
            .offset(y: 58)
        }
    }

    private var radialPageDots: some View {
        HStack(spacing: 5) {
            ForEach(0..<totalPages, id: \.self) { index in
                Circle()
                    .fill(index == pageIndex ? goldAccent : Color.white.opacity(0.22))
                    .frame(width: 5, height: 5)
            }
        }
    }

    private var resizeHintBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "scroll.fill")
                .font(.system(size: 9, weight: .semibold))
            Text(L10n.string("ui.scroll.to.resize", default: "Scroll to resize"))
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.7))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color(NSColor(white: 0.10, alpha: 0.88)))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                )
        )
        .allowsHitTesting(false)
    }

    private var radialSearchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))

            ClipSearchTextField(
                placeholder: "Search clips...",
                focus: $searchFocused,
                onEscape: { dismissSearch() }
            )

            if !store.searchText.isEmpty {
                Text("\(store.filteredClips.count)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
            }

            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.35))
                .onTapGesture { dismissSearch() }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(width: max(190, min(300, diameter * 0.72)))
        .background(
            Capsule()
                .fill(Color(NSColor(white: 0.08, alpha: 0.9)))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                )
        )
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard searchExpanded else { return }
            searchFocused = true
        }
    }

    private func stepPage(by delta: Int) {
        guard hasMultiplePages else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            pageIndex = clampedRadialPageIndex(
                index: pageIndex + delta,
                total: store.filteredClips.count,
                pageSize: maxItems,
                maxPages: maxPages
            )
        }
    }

    private func handleHorizontalPageScroll(_ deltaX: CGFloat) {
        guard hasMultiplePages else { return }
        let adjusted = deltaX * store.settings.radialSwipeDirection.multiplier
        horizontalPageCarry += adjusted

        let threshold = pageSwipeThreshold
        guard abs(horizontalPageCarry) >= threshold else { return }

        let step = horizontalPageCarry > 0 ? 1 : -1
        stepPage(by: step)
        // Keep leftover movement for natural continuation, but prevent runaway jumps.
        if step > 0 {
            horizontalPageCarry = max(0, horizontalPageCarry - threshold)
        } else {
            horizontalPageCarry = min(0, horizontalPageCarry + threshold)
        }
    }

    /// Calculate the angle for an item at the given index in a circle.
    /// Starts from the top (-pi/2) and goes clockwise.
    private func angleFor(index: Int, total: Int) -> CGFloat {
        guard total > 0 else { return 0 }
        let step = (2 * CGFloat.pi) / CGFloat(total)
        // Start at top (-pi/2) and go clockwise
        return -CGFloat.pi / 2 + step * CGFloat(index)
    }
}
