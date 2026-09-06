import AppKit
import SwiftUI

/// Floating grid mode — centered window with card grid layout.
// INVARIANT: Click-outside dismiss is managed by AppWindowManager via global mouse-down
// monitors, NOT by this view. When Settings preview is active, those monitors are
// suppressed so clicks in Settings don't dismiss the grid. Do not add onTapGesture
// dismiss logic here — it would bypass the Settings preview guard.
struct FloatingGridView: View {
    @EnvironmentObject private var store: ClipboardStore
    @FocusState private var searchFocused: Bool
    @FocusState private var containerFocused: Bool
    @State private var isSearchOpen = false
    @State private var usesDarkChrome = false
    @State private var draggedGridItemID: UUID?

    private let gridCardWidth: CGFloat = 170
    private let gridCardHeight: CGFloat = 160

    private var searchExpanded: Bool {
        isSearchOpen || !store.searchText.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            gridTopBar
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)

            TrialNudgeBanner()
                .padding(.horizontal, 14)
            UpdateBanner()
                .padding(.horizontal, 14)

            centerContent

            FolderTabsView()
                .environmentObject(store)
                .padding(.horizontal, 14)
                .frame(height: 42)
                .padding(.bottom, 10)
        }
        .frame(width: 580, height: 500)
        .overlay {
            if store.appAccessState == .locked {
                LicenseGateView()
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
        .modifier(AuricBackground(store: store, cornerRadius: 16))
        .folderDeleteOverlay()
        .folderClearOverlay()
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
            AppWindowManager.shared.toggleWindow(source: "grid-escape")
            return .handled
        }
        .onKeyPress(.space) {
            guard !searchExpanded else { return .ignored }
            store.openPreviewForSelection()
            return .handled
        }
        .onKeyPress(.return, phases: .down) { keyPress in
            guard !store.selectedClipIDs.isEmpty, let first = store.selectedClipIDs.first else { return .ignored }
            let forcePlain = keyPress.modifiers.contains(.option)
            store.loadSelectedOrSingleToClipboard(primaryID: first, autoPaste: true, forcePlainText: forcePlain)
            return .handled
        }
        .onKeyPress(.delete) {
            guard !isTextInputFocused else { return .ignored }
            guard !store.selectedClipIDs.isEmpty else { return .ignored }
            DispatchQueue.main.async { store.deleteClips(store.selectedClipIDs) }
            return .handled
        }
        .onKeyPress(.deleteForward) {
            guard !isTextInputFocused else { return .ignored }
            guard !store.selectedClipIDs.isEmpty else { return .ignored }
            DispatchQueue.main.async { store.deleteClips(store.selectedClipIDs) }
            return .handled
        }
        .onDeleteCommand {
            guard !isTextInputFocused else { return }
            guard !store.selectedClipIDs.isEmpty else { return }
            store.deleteClips(store.selectedClipIDs)
        }
        .onAppear {
            containerFocused = true
            refreshChromeContrast()
        }
        .onChange(of: searchFocused) { _, focused in
            if !focused { containerFocused = true }
        }
        .onChange(of: store.selectedClipIDs) { _, _ in
            if !searchFocused { containerFocused = true }
        }
        .onChange(of: store.selectedFolderID) { _, _ in
            if !searchFocused { containerFocused = true }
        }
        .onChange(of: store.settings.backgroundTheme) { _, _ in
            refreshChromeContrast()
        }
        .onChange(of: store.settings.backgroundWallpaper) { _, _ in
            refreshChromeContrast()
        }
        .onChange(of: store.settings.customWallpaperFilename) { _, _ in
            refreshChromeContrast()
        }
        .onChange(of: store.settings.customBackgroundGradient) { _, _ in
            refreshChromeContrast()
        }
        .onChange(of: store.settings.backgroundOpacity) { _, _ in
            refreshChromeContrast()
        }
        .onChange(of: store.liveBackgroundOpacity) { _, _ in
            refreshChromeContrast()
        }
        .onChange(of: draggedGridItemID) { oldValue, newValue in
            if oldValue == nil, newValue != nil {
                ClipDragLifecycle.begin()
            } else if oldValue != nil, newValue == nil {
                ClipDragLifecycle.end()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipDragDidEnd)) { _ in
            draggedGridItemID = nil
        }
    }

    private var previewItem: ClipItemModel? {
        guard let previewID = store.previewingClipID else { return nil }
        return store.filteredClips.first(where: { $0.clipID == previewID })
    }

    private var gridNoResults: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.white.opacity(0.3))
            Text(L10n.string("common.noMatches", default: "No matches"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
            Text(L10n.string("ui.try.a.different.search", default: "Try a different search."))
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // Extracted from `body` so the SwiftUI type-checker has a smaller expression
    // to solve (the full body otherwise trips the "unable to type-check in
    // reasonable time" limit).
    @ViewBuilder
    private var centerContent: some View {
        ZStack {
            if store.filteredClips.isEmpty {
                // No clips: show the discovery launchpad rather than a void.
                // While searching, show a quiet "no matches" instead.
                if store.searchText.isEmpty {
                    LaunchpadView()
                        .environmentObject(store)
                } else {
                    gridNoResults
                }
            } else {
                clipGrid
            }

            if let previewItem {
                ClipPreviewOverlay(item: previewItem)
                    .environmentObject(store)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .zIndex(1)
            }
        }
    }

    private var clipGrid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 10)],
                spacing: 10
            ) {
                ForEach(store.filteredClips, id: \.clipID) { item in
                    ClipCardView(
                        item: item,
                        cardWidth: gridCardWidth,
                        cardHeight: gridCardHeight,
                        onDragStarted: {
                            draggedGridItemID = item.clipID
                        }
                    )
                    .environmentObject(store)
                    .opacity(draggedGridItemID == item.clipID ? 0.45 : 1.0)
                    .scaleEffect(draggedGridItemID == item.clipID ? 0.97 : 1.0)
                    .animation(.easeOut(duration: 0.1), value: draggedGridItemID)
                    .onAppear {
                        // Load-more trigger: fires when one of the last 5 cards scrolls in.
                        if store.filteredClips.suffix(5).contains(where: { $0.clipID == item.clipID }) {
                            store.loadMoreClips()
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    /// Global mode shortcuts must not fire while typing into search or preview editors.
    private var isTextInputFocused: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        return responder is NSTextView || responder is NSTextField
    }

    private var gridTopBar: some View {
        HStack(spacing: 10) {
            // Search icon
            Button {
                if searchExpanded {
                    dismissSearch()
                } else {
                    openSearch()
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(chromePrimary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(chromeButtonBackground))
            }
            .buttonStyle(.plain)

            if searchExpanded {
                HStack(spacing: 6) {
                    ClipSearchTextField(
                        placeholder: "Search clips...",
                        textColor: chromeStrong,
                        focus: $searchFocused,
                        onEscape: { dismissSearch() }
                    )

                    if !store.searchText.isEmpty {
                        Text("\(store.filteredClips.count)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(chromeSecondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(chromePillBackground))
                    }

                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(chromeSecondary)
                        .onTapGesture { dismissSearch() }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(chromeSearchBackground))
                .frame(width: 200)
                .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .leading)))
            }

            Spacer()

            Text(L10n.string("ui.grid.view", default: "Grid View"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(chromeSecondary)

            Spacer()

            ModeSettingsLink(
                source: "grid-settings",
                iconSize: 11,
                frameSize: 24,
                foregroundColor: chromePrimary,
                backgroundColor: chromeButtonBackground
            )

            // Close button
            Button {
                AppWindowManager.shared.toggleWindow(source: "grid-close")
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(chromePrimary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(chromeButtonBackground))
            }
            .buttonStyle(.plain)
        }
        .animation(.easeInOut(duration: 0.2), value: searchExpanded)
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

    private var chromeStrong: Color {
        usesDarkChrome ? .black.opacity(0.9) : .white.opacity(0.95)
    }

    private var chromePrimary: Color {
        usesDarkChrome ? .black.opacity(0.76) : .white.opacity(0.78)
    }

    private var chromeSecondary: Color {
        usesDarkChrome ? .black.opacity(0.58) : .white.opacity(0.56)
    }

    private var chromeButtonBackground: Color {
        usesDarkChrome ? .white.opacity(0.24) : .white.opacity(0.08)
    }

    private var chromeSearchBackground: Color {
        usesDarkChrome ? .white.opacity(0.30) : .white.opacity(0.10)
    }

    private var chromePillBackground: Color {
        usesDarkChrome ? .black.opacity(0.12) : .white.opacity(0.12)
    }

    private func refreshChromeContrast() {
        let luminance = estimatedTopBarLuminance()
        withAnimation(.easeInOut(duration: 0.16)) {
            usesDarkChrome = luminance > 0.58
        }
    }

    /// Normalized wallpaper region behind the grid's top bar, the area whose
    /// brightness decides light-vs-dark chrome. Fixed, so it is not part of
    /// the luminance cache key.
    private static let topBarSampleRegion = CGRect(x: 0.30, y: 0.70, width: 0.40, height: 0.25)

    private func estimatedTopBarLuminance() -> Double {
        let theme = store.settings.backgroundTheme
        let solidOpacity = store.liveBackgroundOpacity ?? store.settings.backgroundOpacity
        let wallpaper = store.settings.backgroundWallpaper
        let hasWallpaper = wallpaper != .none
        let wallpaperLuminance = hasWallpaper
            ? wallpaper
                .loadImage(customFilename: store.settings.customWallpaperFilename)
                .flatMap { GridChromeLuminanceCache.luminance(of: $0, in: Self.topBarSampleRegion) }
            : nil

        let themeLuminance = averageThemeLuminance(for: theme)

        if theme == .scenic {
            return wallpaperLuminance ?? themeLuminance
        }

        if theme == .custom {
            if let imageValue = wallpaperLuminance {
                return max(0, min(1, imageValue * 0.35 + themeLuminance * 0.65))
            }
            return themeLuminance
        }

        if hasWallpaper, let imageValue = wallpaperLuminance {
            let mixed = imageValue * 0.45 + themeLuminance * 0.55
            return max(0, min(1, mixed * (1.0 - 0.12 * solidOpacity)))
        }

        return themeLuminance
    }

    private func averageThemeLuminance(for theme: BackgroundTheme) -> Double {
        if theme == .custom {
            let gradient = store.settings.customBackgroundGradient ?? GradientSpec(
                color1: "#4A2080",
                color2: "#206080",
                angle: 135
            )
            return (luminance(of: Color(hex: gradient.color1)) + luminance(of: Color(hex: gradient.color2))) / 2.0
        }
        let values = theme.gradientColors.map(luminance(of:))
        guard !values.isEmpty else { return 0.5 }
        return values.reduce(0, +) / Double(values.count)
    }

    private func luminance(of color: Color) -> Double {
        guard let rgb = NSColor(color).usingColorSpace(.deviceRGB) else { return 0.5 }
        return 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
    }

}

/// Memoized top-bar-region wallpaper luminance for the grid's chrome contrast.
///
/// `refreshChromeContrast()` is wired to `store.liveBackgroundOpacity`, which
/// changes on every frame of the Settings opacity-slider drag. Re-sampling the
/// wallpaper per frame (image decode + full TIFF re-encode + bitmap pixel loop
/// inside `WallpaperLuminance.averageLuminance(in:of:)`) made that drag heavy.
/// Opacity never changes the wallpaper's pixels, so the sample is cached and
/// only the cheap theme/opacity mixing in `estimatedTopBarLuminance()` runs
/// per frame.
///
/// Keyed by the `NSImage`'s object identity, WITH the image retained in the
/// entry. Both halves matter:
/// - A stable string key (wallpaper case + filename) would go stale, because
///   custom imports reuse a fixed per-slot filename ("clipboard.png") for new
///   pixels.
/// - Identity WITHOUT retention is unsafe: `BackgroundWallpaper.imageCache`
///   is an NSCache that clears on import and can evict under pressure, so a
///   replacement image could be allocated at the freed image's address and
///   silently hit the stale entry. Retaining the keyed image makes address
///   reuse impossible while the entry lives; a re-imported wallpaper arrives
///   as a distinct live instance and recomputes.
@MainActor
private enum GridChromeLuminanceCache {
    private static var storage: [ObjectIdentifier: (image: NSImage, value: Double)] = [:]
    /// Small cap, entries retain decoded wallpapers, and a session realistically
    /// touches one or two. Overflow just costs a one-off recompute.
    private static let capacity = 4

    static func luminance(of image: NSImage, in normalizedRegion: CGRect) -> Double? {
        let key = ObjectIdentifier(image)
        if let cached = storage[key] { return cached.value }
        guard let value = WallpaperLuminance.averageLuminance(in: normalizedRegion, of: image) else {
            return nil
        }
        if storage.count >= capacity { storage.removeAll(keepingCapacity: true) }
        storage[key] = (image, value)
        return value
    }
}
