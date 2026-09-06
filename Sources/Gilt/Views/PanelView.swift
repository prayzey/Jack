import AppKit
import SwiftUI

/// Panel mode — compact floating panel that appears near the cursor with a vertical list of clips.
/// Inspired by the Windows 11 clipboard manager, reinterpreted in Jack's dark two-zone style.
struct PanelView: View {
    @EnvironmentObject private var store: ClipboardStore
    @FocusState private var searchFocused: Bool
    @FocusState private var containerFocused: Bool
    @State private var isSearchOpen = false

    private var searchExpanded: Bool {
        isSearchOpen || !store.searchText.isEmpty
    }

    private var activeFolder: ClipFolderModel? {
        store.folders.first(where: { $0.folderID == store.selectedFolderID })
    }

    private var canClearActiveFolder: Bool {
        guard let folder = activeFolder else { return false }
        return folder.clips.isEmpty == false
    }

    var body: some View {
        panelContent
            .overlay {
                if store.appAccessState == .locked {
                    LicenseGateView()
                }
            }
            .modifier(AuricBackground(store: store, cornerRadius: 18))
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
                AppWindowManager.shared.toggleWindow(source: "panel-escape")
                return .handled
            }
            .onKeyPress(.upArrow) {
                guard !searchFocused, store.previewingClipID == nil else { return .ignored }
                DispatchQueue.main.async { store.navigateSelection(direction: -1) }
                return .handled
            }
            .onKeyPress(.downArrow) {
                guard !searchFocused, store.previewingClipID == nil else { return .ignored }
                DispatchQueue.main.async { store.navigateSelection(direction: 1) }
                return .handled
            }
            .onKeyPress(.return, phases: .down) { keyPress in
                guard let first = store.selectedClipIDs.first else { return .ignored }
                let forcePlain = keyPress.modifiers.contains(.option)
                store.loadSelectedOrSingleToClipboard(primaryID: first, autoPaste: true, forcePlainText: forcePlain)
                return .handled
            }
            .onKeyPress(.delete) {
                guard !isTextInputFocused, !store.selectedClipIDs.isEmpty else { return .ignored }
                DispatchQueue.main.async { store.deleteClips(store.selectedClipIDs) }
                return .handled
            }
            .onDeleteCommand {
                guard !isTextInputFocused, !store.selectedClipIDs.isEmpty else { return }
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
    }

    /// Keep global shortcuts from firing while search or preview editors own focus.
    private var isTextInputFocused: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        return responder is NSTextView || responder is NSTextField
    }

    private var panelContent: some View {
        VStack(spacing: 0) {
            topRail
                .padding(.horizontal, 12)
                .padding(.top, 8)

            TrialNudgeBanner()
                .padding(.horizontal, 12)
            UpdateBanner()
                .padding(.horizontal, 12)

            if searchExpanded {
                searchField
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            FolderTabsView()
                .environmentObject(store)
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 4)

            clipboardHeader
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 4)

            clipList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Top Rail

    private var topRail: some View {
        // Background drag region covers the full rail height; buttons sit on top with
        // their own hit targets so only the empty space between them drags the window.
        ZStack {
            WindowDragHandle()
                .contentShape(Rectangle())

            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: 28, height: 3)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 2)
                .allowsHitTesting(false)

            HStack(spacing: 6) {
                Text(AppBrand.displayName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .allowsHitTesting(false)

                Spacer(minLength: 6)

                Button {
                    if searchExpanded { dismissSearch() } else { openSearch() }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                ModeSettingsLink(source: "panel-settings")

                Button {
                    AppWindowManager.shared.toggleWindow(source: "panel-close")
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 30)
        .animation(.easeInOut(duration: 0.2), value: searchExpanded)
    }

    private var searchField: some View {
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
    }

    /// "Clipboard" title + "Clear all" affordance, matching the Windows panel's section header.
    private var clipboardHeader: some View {
        HStack(spacing: 8) {
            Text(L10n.string("systemFolder.clipboard.name", default: "Clipboard"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))

            Spacer(minLength: 0)

            Button {
                requestClearActiveFolder()
            } label: {
                Text(L10n.string("common.clearAll", default: "Clear all"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(canClearActiveFolder ? 0.78 : 0.3))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(Color.white.opacity(canClearActiveFolder ? 0.08 : 0.04))
                    )
                    .overlay(
                        Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canClearActiveFolder)
        }
    }

    // MARK: - Clip list

    private var clipList: some View {
        ZStack {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    ForEach(Array(store.filteredClips.enumerated()), id: \.element.clipID) { index, item in
                        PanelClipRow(
                            item: item,
                            isSelected: store.selectedClipIDs.contains(item.clipID)
                        )
                        .onAppear {
                            if index >= store.filteredClips.count - 5 {
                                store.loadMoreClips()
                            }
                        }
                    }

                    if store.filteredClips.isEmpty {
                        emptyState
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }

            if let previewItem {
                ClipPreviewOverlay(item: previewItem)
                    .environmentObject(store)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .zIndex(1)
            }
        }
    }

    private var previewItem: ClipItemModel? {
        guard let id = store.previewingClipID else { return nil }
        return store.filteredClips.first(where: { $0.clipID == id })
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.white.opacity(0.3))
            Text(L10n.string("common.nothingHereYet", default: "Nothing here yet"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
            Text(L10n.string("ui.copy.something.to.get.started", default: "Copy something to get started."))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Actions

    private func requestClearActiveFolder() {
        guard let folder = activeFolder, !folder.clips.isEmpty else { return }
        FolderClearRequest.shared.request(folder: folder, accentColor: folder.resolvedColor.color)
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
