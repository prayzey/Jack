import SwiftUI

/// Side drawer mode — edge panel with vertical clip list.
struct SideDrawerView: View {
    @EnvironmentObject private var store: ClipboardStore
    @FocusState private var searchFocused: Bool
    @FocusState private var containerFocused: Bool
    @State private var isSearchOpen = false

    private var searchExpanded: Bool {
        isSearchOpen || !store.searchText.isEmpty
    }

    private var isDrawerOnLeft: Bool {
        store.settings.drawerSide == .left
    }

    var body: some View {
        HStack(spacing: 0) {
            if !isDrawerOnLeft {
                drawerResizeHandle
            }

            drawerContent

            if isDrawerOnLeft {
                drawerResizeHandle
            }
        }
        .overlay {
            if store.appAccessState == .locked {
                LicenseGateView()
            }
        }
        .modifier(AuricBackground(store: store, cornerRadius: 0))
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
            AppWindowManager.shared.toggleWindow(source: "drawer-escape")
            return .handled
        }
        .onKeyPress(.upArrow) {
            guard !searchFocused else { return .ignored }
            guard store.previewingClipID == nil else { return .ignored }
            DispatchQueue.main.async { store.navigateSelection(direction: -1) }
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard !searchFocused else { return .ignored }
            guard store.previewingClipID == nil else { return .ignored }
            DispatchQueue.main.async { store.navigateSelection(direction: 1) }
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
    }

    /// Keep global shortcuts from firing while search or preview editors own focus.
    private var isTextInputFocused: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        return responder is NSTextView || responder is NSTextField
    }

    private var drawerResizeHandle: some View {
        DrawerResizeHandle(side: store.settings.drawerSide)
            .frame(width: 8)
            .contentShape(Rectangle())
    }

    private var drawerContent: some View {
        VStack(spacing: 0) {
            drawerHeader
                .padding(.horizontal, 12)
                .padding(.top, 14)
                .padding(.bottom, 8)

            TrialNudgeBanner()
                .padding(.horizontal, 12)
            UpdateBanner()
                .padding(.horizontal, 12)

            // Search bar
            if searchExpanded {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))

                    ClipSearchTextField(
                        placeholder: "Search clips...",
                        focus: $searchFocused,
                        onEscape: { dismissSearch() }
                    )

                    if !store.searchText.isEmpty {
                        Text("\(store.filteredClips.count)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.white.opacity(0.1)))
                    }

                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.3))
                        .onTapGesture { dismissSearch() }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            FolderTabsView()
                .environmentObject(store)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)

            ZStack {
                // Clip list
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(Array(store.filteredClips.enumerated()), id: \.element.clipID) { index, item in
                            DrawerClipRow(
                                item: item,
                                isSelected: store.selectedClipIDs.contains(item.clipID)
                            )
                            .onAppear {
                                if index >= store.filteredClips.count - 5 {
                                    store.loadMoreClips()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var previewItem: ClipItemModel? {
        guard let previewID = store.previewingClipID else { return nil }
        return store.filteredClips.first(where: { $0.clipID == previewID })
    }

    private var drawerHeader: some View {
        HStack {
            Text(AppBrand.displayName)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))

            Spacer()

            // Search toggle
            Button {
                if searchExpanded {
                    dismissSearch()
                } else {
                    openSearch()
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)

            ModeSettingsLink(source: "drawer-settings")

            // Close button
            Button {
                AppWindowManager.shared.toggleWindow(source: "drawer-close")
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.white.opacity(0.06)))
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

}
