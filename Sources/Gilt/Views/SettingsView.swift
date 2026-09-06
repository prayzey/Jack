import SwiftUI
import UniformTypeIdentifiers

// MARK: - Settings Tab Enum

enum SettingsTab: String, CaseIterable {
    // Raw values are stable routing IDs. Keep them language-neutral so Settings
    // deep links and notifications do not break when labels are translated.
    case appearance = "appearance"
    case general = "general"
    case menuBar = "menuBar"
    case dictate = "dictate"
    case stats = "stats"
    case categories = "categories"
    case folders = "folders"
    case ai = "ai"
    case jack = "jack"
    case advanced = "advanced"
    case license = "license"

    // Accept legacy English labels so upgrades can still honor a pending
    // navigation request saved by older builds before raw values were stabilized.
    init?(navigationRawValue: String) {
        if let stableValue = Self(rawValue: navigationRawValue) {
            self = stableValue
            return
        }

        switch navigationRawValue {
        case "Appearance": self = .appearance
        case "General": self = .general
        case "Menu Bar", "MenuBar": self = .menuBar
        case "Dictate": self = .dictate
        case "Stats": self = .stats
        case "Categories": self = .categories
        case "Folders": self = .folders
        case "AI", "ai": self = .ai
        case "Jack": self = .jack
        case "Advanced": self = .advanced
        case "License": self = .license
        default: return nil
        }
    }

    var label: String { localizedLabel() }

    func localizedLabel(locale: Locale? = nil) -> String {
        switch self {
        case .appearance:
            return L10n.string("settings.tab.appearance", default: "Appearance", locale: locale)
        case .general:
            return L10n.string("settings.tab.general", default: "General", locale: locale)
        case .menuBar:
            return L10n.string("settings.tab.menuBar", default: "Menu Bar", locale: locale)
        case .dictate:
            return L10n.string("settings.tab.dictate", default: "Dictate", locale: locale)
        case .stats:
            return L10n.string("settings.tab.stats", default: "Stats", locale: locale)
        case .categories:
            return L10n.string("settings.tab.categories", default: "Categories", locale: locale)
        case .folders:
            return L10n.string("settings.tab.folders", default: "Folders", locale: locale)
        case .ai:
            return L10n.string("settings.tab.ai", default: "AI", locale: locale)
        case .jack:
            return L10n.string("settings.tab.jack", default: "Jack", locale: locale)
        case .advanced:
            return L10n.string("settings.tab.advanced", default: "Advanced", locale: locale)
        case .license:
            return L10n.string("settings.tab.license", default: "License", locale: locale)
        }
    }

    var icon: String {
        switch self {
        case .appearance: return "paintbrush"
        case .general: return "gearshape"
        case .menuBar: return "menubar.rectangle"
        case .dictate: return "mic.fill"
        case .stats: return "chart.line.uptrend.xyaxis"
        case .categories: return "tag"
        case .folders: return "folder"
        case .ai: return "sparkles"
        case .jack: return "figure.walk"
        case .advanced: return "slider.horizontal.3"
        case .license: return "key"
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject private var store: ClipboardStore
    @State private var selectedTab: SettingsTab = .appearance
    @Namespace private var sidebarNamespace
    @Namespace private var appearanceSubTabNamespace
    @Namespace private var folderSubTabNamespace
    @Namespace private var pulseCharacterModeNamespace
    @Namespace private var quickNotePlacementNamespace
    @Namespace private var quickNoteNavigationControlsNamespace
    @Namespace private var quickNoteTransparencyNamespace
    @Namespace private var quickNoteFontSizeNamespace
    @Namespace private var quickNotePaperTypeNamespace
    @Namespace private var quickNoteSectionNamespace
    @Namespace private var quickNoteFontFamilyNamespace
    @Namespace private var quickNoteFontWeightNamespace
    @State private var quickNoteSection: QuickNoteSection = .surface
    @State private var cachedAppIcon: NSImage? = SettingsView.loadAppIcon()

    private static func loadAppIcon() -> NSImage? {
        guard let url = AppResourceLocator.url(forResource: "AppIcon", withExtension: "png", subdirectory: "Resources") else { return nil }
        return NSImage(contentsOf: url)
    }
    @State private var isShowingEraseConfirmation = false
    @State private var opacitySliderValue: Double = 1.0
    @State private var opacitySaveTask: Task<Void, Never>?
    @State private var accessibilityGranted = false
    @State private var microphonePermissionStatus: MicrophonePermissionStatus = .unknown
    @State private var screenRecordingPermissionStatus: ScreenRecordingPermissionStatus = .unknown
    @State private var pendingFolderDeletionID: UUID?
    @State private var pendingFolderDeletionName = ""
    @State private var licenseKeyInput = ""
    @State private var skillScanResults: [ProviderScanResult] = []
    @State private var hasScannedForSkills = false
    @State private var isScanning = false
    @State private var appearanceSubTab: AppearanceSubTab = .clipboard
    @State private var folderSubTab: FolderSubTab = .folders

    private let appVersion = AppVersionInfo.current
    private let viewModeGridColumns = Array(
        repeating: GridItem(.flexible(minimum: 88), spacing: 14),
        count: 3
    )

    private enum FolderSubTab: String, CaseIterable {
        case folders = "folders"
        case bulkEdit = "bulkEdit"
        case aiSkills = "aiSkills"

        var label: String { localizedLabel() }

        func localizedLabel(locale: Locale? = nil) -> String {
            switch self {
            case .folders:
                return L10n.string("settings.folderSubTab.folders", default: "Folders", locale: locale)
            case .bulkEdit:
                return L10n.string("settings.folderSubTab.bulkEdit", default: "Bulk Edit", locale: locale)
            case .aiSkills:
                return L10n.string("settings.folderSubTab.aiSkills", default: "AI Skills", locale: locale)
            }
        }
    }

    private enum QuickNoteSection: String, CaseIterable, Identifiable {
        case surface
        case typography
        case wallpaper
        case behavior

        var id: String { rawValue }

        var label: String {
            switch self {
            case .surface: return "Surface"
            case .typography: return "Typography"
            case .wallpaper: return "Wallpaper"
            case .behavior: return "Behavior"
            }
        }
    }

    private enum AppearanceSubTab: String, CaseIterable {
        case clipboard = "clipboard"
        case quickNote = "quickNote"
        case workspace = "workspace"

        var label: String { localizedLabel() }

        func localizedLabel(locale: Locale? = nil) -> String {
            switch self {
            case .clipboard:
                return L10n.string("settings.appearanceSubTab.clipboard", default: "Clipboard", locale: locale)
            case .quickNote:
                return L10n.string("settings.appearanceSubTab.quickNote", default: "Quick Note", locale: locale)
            case .workspace:
                return L10n.string("settings.appearanceSubTab.workspace", default: "Workspace", locale: locale)
            }
        }
    }

    private var retentionBinding: Binding<HistoryRetention> {
        Binding(
            get: { store.settings.historyRetention },
            set: { store.setRetention($0) }
        )
    }

    private var globalShortcutBinding: Binding<GlobalShortcut> {
        Binding(
            get: { store.settings.globalShortcut },
            set: { store.setGlobalShortcut($0) }
        )
    }

    private var quickNoteShortcutBinding: Binding<GlobalShortcut> {
        Binding(
            get: { store.settings.quickNoteShortcut },
            set: { store.setQuickNoteShortcut($0) }
        )
    }

    private var commandPaletteShortcutBinding: Binding<GlobalShortcut> {
        Binding(
            get: { store.settings.commandPaletteShortcut },
            set: { store.setCommandPaletteShortcut($0) }
        )
    }

    private var appLanguageBinding: Binding<AppLanguage> {
        Binding(
            get: { store.settings.appLanguage },
            set: { store.setAppLanguage($0) }
        )
    }

    private var quickNoteAppearanceBinding: Binding<QuickNoteAppearance> {
        Binding(
            get: { store.settings.quickNoteAppearance },
            set: { store.settings.quickNoteAppearance = $0 }
        )
    }

    private var workspaceAppearanceBinding: Binding<WorkspaceAppearance> {
        Binding(
            get: { store.settings.workspaceAppearance },
            set: { store.settings.workspaceAppearance = $0 }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { store.settings.launchAtLogin },
            set: { newValue in
                guard store.settings.launchAtLogin != newValue else { return }
                store.settings.launchAtLogin = newValue
                Task { @MainActor in
                    store.setLaunchAtLogin(newValue)
                }
            }
        )
    }

    /// Identity for the tab content: changing tab or sub-tab resets the scroll position.
    private var currentScrollPageID: String {
        switch selectedTab {
        case .appearance: return "\(selectedTab.rawValue):\(appearanceSubTab.rawValue)"
        case .folders: return "\(selectedTab.rawValue):\(folderSubTab.rawValue)"
        default: return selectedTab.rawValue
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            sidebar
            
            // Divider line
                Rectangle()
                .fill(SettingsTheme.divider)
                .frame(width: 1)
            
            // Main content area
            VStack(spacing: 0) {
                // Header with greeting
                SettingsHeader()
                    .padding(.horizontal, 32)
                    .padding(.top, 28)
                    .padding(.bottom, 16)
                
                // Tab content
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                    switch selectedTab {
                    case .appearance:
                        appearanceTab
                    case .general:
                        generalTab
                    case .menuBar:
                        MenuBarSettingsTab()
                    case .dictate:
                        DictationSettingsView()
                    case .stats:
                        StatsSettingsView()
                    case .categories:
                        categoriesTab
                    case .folders:
                        foldersTab
                    case .ai:
                        AISettingsView()
                    case .jack:
                        JackSettingsView()
                    case .advanced:
                        advancedTab
                    case .license:
                        licenseTab
                    }
                }
                .id(currentScrollPageID)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 32)
            }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SettingsTheme.background)
        }
        .background(SettingsTheme.background.ignoresSafeArea(edges: .top))
        .background(
            SettingsWindowConfigurator()
        )
        .background(
            SettingsFontOverrideBridge(selection: store.settings.clipboardFont)
        )
        .preferredColorScheme(.light)
        .alert(SettingsCopy.eraseHistoryAlertTitle(), isPresented: $isShowingEraseConfirmation) {
            Button(SettingsCopy.eraseHistoryAlertConfirm(), role: .destructive) {
                store.eraseHistory()
            }
            Button(SettingsCopy.cancelButtonTitle(), role: .cancel) {}
        } message: {
            Text(SettingsCopy.eraseHistoryAlertMessage())
        }
        .alert(SettingsCopy.deleteFolderAlertTitle(), isPresented: Binding(
            get: { pendingFolderDeletionID != nil },
            set: { if !$0 { pendingFolderDeletionID = nil } }
        )) {
            Button(SettingsCopy.deleteFolderAlertConfirm(), role: .destructive) {
                if let pendingFolderDeletionID {
                    store.deleteFolder(id: pendingFolderDeletionID)
                }
                pendingFolderDeletionID = nil
            }
            Button(SettingsCopy.cancelButtonTitle(), role: .cancel) {
                pendingFolderDeletionID = nil
            }
        } message: {
            Text(SettingsCopy.deleteFolderAlertMessage(folderName: pendingFolderDeletionName))
        }
        .onExitCommand {
            NSApp.keyWindow?.performClose(nil)
        }
        .onAppear {
            if let rawValue = SettingsNavigation.consumeRequestedTabRawValue() {
                applyRequestedTab(rawValue)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: SettingsNavigation.requestTabNotification)) { notification in
            guard let rawValue = notification.object as? String else { return }
            applyRequestedTab(rawValue)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // App branding
            HStack(spacing: 10) {
                if let nsImage = cachedAppIcon {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(AppBrand.displayName.lowercased())
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(SettingsTheme.textPrimary)
                    Text(SettingsCopy.managerLabel())
                        .font(.system(size: 11))
                        .foregroundStyle(SettingsTheme.textTertiary)
                    Text(appVersion.sidebarLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(SettingsTheme.textTertiary.opacity(0.7))
                }
            }
            .padding(.horizontal, 18)
            // Hidden-title-bar Settings windows keep the traffic lights visible
            // above the sidebar, so the brand block needs extra clearance.
            .padding(.top, SettingsWindowPolicy.leadingTrafficLightClearanceTop)
            .padding(.bottom, 28)
            
            // Navigation items
            VStack(spacing: 4) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                    SettingsSidebarItem(
                        tab: tab,
                        isSelected: selectedTab == tab,
                        namespace: sidebarNamespace
                    ) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                            selectedTab = tab
                        }
                    }
                }
            }
                    .padding(.horizontal, 12)
            
            Spacer()
            
            // Done button at bottom
            Button {
                NSApp.keyWindow?.performClose(nil)
            } label: {
                Text(SettingsCopy.doneButtonTitle())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(SettingsTheme.gold)
                    )
                }
                .buttonStyle(.plain)
        .padding(.horizontal, 16)
            .padding(.bottom, 20)
            .keyboardShortcut(.defaultAction)
        }
        .frame(width: 200)
        .background(SettingsTheme.sidebarBackground)
    }

    // MARK: - Appearance Tab

    private var appearanceTab: some View {
        VStack(spacing: 16) {
            appearanceSubTabPicker

            switch appearanceSubTab {
            case .clipboard:
                clipboardAppearanceContent
            case .quickNote:
                quickNoteAppearanceContent
            case .workspace:
                workspaceAppearanceContent
            }
        }
    }

    private var appearanceSubTabPicker: some View {
        SettingsSegmentedPicker(
            options: AppearanceSubTab.allCases,
            selection: appearanceSubTab,
            namespace: appearanceSubTabNamespace,
            label: \.label
        ) { tab in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                appearanceSubTab = tab
            }
        }
        .padding(.horizontal, 4)
    }

    private var clipboardAppearanceContent: some View {
        SettingsSection {
            VStack(alignment: .leading, spacing: 0) {
                subsectionHeader(CommonCopy.viewMode())
                LazyVGrid(columns: viewModeGridColumns, alignment: .leading, spacing: 16) {
                    ForEach(ViewMode.allCases) { mode in
                        LightViewModeCard(
                            mode: mode,
                            isSelected: store.settings.viewMode == mode
                        ) {
                            store.settings.viewMode = mode
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)

                if store.settings.viewMode == .tray {
                    SettingsDivider()
                    SettingsToggleRow(
                        title: L10n.string("settings.appearance.tray.followNewest.title", default: "Keep Newest in View"),
                        subtitle: L10n.string(
                            "settings.appearance.tray.followNewest.subtitle",
                            default: "Return to the newest clips whenever the tray opens."
                        ),
                        icon: "arrow.forward.to.line",
                        isOn: $store.settings.scrollToLatestOnShow
                    )

                    SettingsDivider()
                    SettingsRow(
                        title: L10n.string("settings.appearance.tray.newestSide.title", default: "Newest Clip Side"),
                        subtitle: L10n.string(
                            "settings.appearance.tray.newestSide.subtitle",
                            default: "Choose where new clips enter the tray."
                        ),
                        icon: "rectangle.split.3x1"
                    ) {
                        Picker("", selection: $store.settings.newestTrayClipsOnRight) {
                            Text(DrawerSide.left.label).tag(false)
                            Text(DrawerSide.right.label).tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                    }
                }

                if store.settings.viewMode == .drawer {
                    SettingsDivider()
                    SettingsRow(title: L10n.string("settings.row.drawer.side", default: "Drawer Side"), subtitle: L10n.string("settings.row.which.side.of.the.screen.the.drawer.appears.on", default: "Which side of the screen the drawer appears on")) {
                        Picker("", selection: Binding(
                            get: { store.settings.drawerSide },
                            set: { newValue in
                                store.settings.drawerSide = newValue
                                AppWindowManager.shared.setDrawerSide(newValue, store: store)
                            }
                        )) {
                            ForEach(DrawerSide.allCases) { side in
                                Label(side.label, systemImage: side.icon)
                                    .tag(side)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                    }
                }

                if store.settings.viewMode == .panel {
                    SettingsDivider()
                    SettingsToggleRow(
                        title: L10n.string("settings.appearance.panel.followCursor.title", default: "Follow Cursor"),
                        subtitle: L10n.string(
                            "settings.appearance.panel.followCursor.subtitle",
                            default: "Open the panel centered on the pointer. Turn off to center on screen."
                        ),
                        isOn: $store.settings.panelFollowsCursor
                    )

                    SettingsDivider()
                    SettingsRow(
                        title: L10n.string("settings.appearance.panel.width.title", default: "Panel Width"),
                        subtitle: L10n.string(
                            "settings.appearance.panel.width.subtitle",
                            default: "Horizontal size of the floating panel (260-480)."
                        )
                    ) {
                        HStack(spacing: 8) {
                            Slider(
                                value: Binding(
                                    get: { store.settings.panelWidth },
                                    set: { newValue in
                                        store.settings.panelWidth = newValue
                                        AppWindowManager.shared.setPanelSize(animated: false)
                                    }
                                ),
                                in: 260...480,
                                step: 10
                            )
                            .frame(width: 160)

                            Text("\(Int(store.settings.panelWidth))")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(SettingsTheme.textSecondary)
                                .frame(width: 34, alignment: .trailing)
                        }
                    }

                    SettingsDivider()
                    SettingsRow(
                        title: L10n.string("settings.appearance.panel.height.title", default: "Panel Height"),
                        subtitle: L10n.string(
                            "settings.appearance.panel.height.subtitle",
                            default: "Vertical size of the floating panel."
                        )
                    ) {
                        HStack(spacing: 8) {
                            Slider(
                                value: Binding(
                                    get: { store.settings.panelHeight },
                                    set: { newValue in
                                        store.settings.panelHeight = newValue
                                        AppWindowManager.shared.setPanelSize(animated: false)
                                    }
                                ),
                                in: 320...760,
                                step: 10
                            )
                            .frame(width: 160)

                            Text("\(Int(store.settings.panelHeight))")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(SettingsTheme.textSecondary)
                                .frame(width: 34, alignment: .trailing)
                        }
                    }
                }

                SettingsDivider()

                subsectionHeader(L10n.string("settings.appearance.typography", default: "Typography"))
                SettingsRow(
                    title: L10n.string("settings.row.clipboard.font", default: "Clipboard Font"),
                    subtitle: L10n.string("settings.row.pick.the.font.used.by.the.main.clipboard.views", default: "Pick the font used by the main clipboard views."),
                    icon: "textformat"
                ) {
                    Picker("", selection: $store.settings.clipboardFont) {
                        ForEach(ClipboardFont.allCases, id: \.self) { font in
                            Text(font.label).tag(font)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 160)
                }

                SettingsDivider()

                subsectionHeader(L10n.string("settings.appearance.backgroundTheme", default: "Background Theme"))
                HStack(spacing: 0) {
                    ForEach(BackgroundTheme.allCases, id: \.self) { theme in
                        let isSelected = store.settings.backgroundTheme == theme
                        Button {
                            if theme == .custom && store.settings.customBackgroundGradient == nil {
                                store.settings.customBackgroundGradient = GradientSpec(
                                    color1: "#4A2080", color2: "#206080", angle: 135
                                )
                            }
                            store.settings.backgroundTheme = theme
                        } label: {
                            VStack(spacing: 8) {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: theme.previewGradient,
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(isSelected ? SettingsTheme.gold : Color.clear, lineWidth: 2.5)
                                    )
                                    .shadow(color: isSelected ? SettingsTheme.gold.opacity(0.4) : .clear, radius: 6)
                                Text(theme.label)
                                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                                    .foregroundStyle(isSelected ? SettingsTheme.textPrimary : SettingsTheme.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)

                if store.settings.backgroundTheme == .custom {
                    SettingsDivider()
                    GradientPickerView(spec: Binding(
                        get: {
                            store.settings.customBackgroundGradient ?? GradientSpec(
                                color1: "#4A2080", color2: "#206080", angle: 135
                            )
                        },
                        set: { newSpec in
                            store.settings.customBackgroundGradient = newSpec
                        }
                    ))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                }

                SettingsDivider()

                subsectionHeader(CommonCopy.wallpaper())
                HStack(spacing: 12) {
                    ForEach(BackgroundWallpaper.allCases, id: \.self) { wallpaper in
                        let isSelected = store.settings.backgroundWallpaper == wallpaper
                        let customFilename = store.settings.customWallpaperFilename
                        Button {
                            if wallpaper == .custom {
                                pickCustomWallpaper()
                            } else {
                                store.settings.backgroundWallpaper = wallpaper
                            }
                        } label: {
                            VStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(SettingsTheme.sidebarBackground)
                                    .frame(width: 60, height: 42)
                                    .overlay {
                                        if wallpaper == .custom {
                                            if let nsImage = wallpaper.loadImage(customFilename: customFilename) {
                                                Image(nsImage: nsImage)
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 60, height: 42)
                                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                            } else {
                                                Image(systemName: "plus")
                                                    .font(.system(size: 16, weight: .medium))
                                                    .foregroundStyle(SettingsTheme.textTertiary)
                                            }
                                        } else if let nsImage = wallpaper.loadImage(customFilename: customFilename) {
                                            Image(nsImage: nsImage)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 60, height: 42)
                                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                        } else {
                                            Image(systemName: "rectangle.slash")
                                                .font(.system(size: 14))
                                                .foregroundStyle(SettingsTheme.textTertiary)
                                        }
                                    }
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .strokeBorder(isSelected ? SettingsTheme.gold : SettingsTheme.border, lineWidth: isSelected ? 2.5 : 1)
                                    )
                                Text(wallpaper.label)
                                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                                    .foregroundStyle(isSelected ? SettingsTheme.textPrimary : SettingsTheme.textSecondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 18)
                .padding(.bottom, 18)

                if store.settings.backgroundWallpaper != .none {
                    SettingsDivider()

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(CommonCopy.position())
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(SettingsTheme.textPrimary)
                            Spacer()
                            if store.settings.wallpaperOffsetX != 0.5 || store.settings.wallpaperOffsetY != 0.5 {
                                Button(CommonCopy.reset()) {
                                    store.settings.wallpaperOffsetX = 0.5
                                    store.settings.wallpaperOffsetY = 0.5
                                }
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(SettingsTheme.gold)
                            }
                        }

                        WallpaperPositionPreview(wallpaperPreview: store.wallpaperPreview)
                            .frame(height: 140)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        Text(SettingsCopy.wallpaperDragHint())
                            .font(.system(size: 11))
                            .foregroundStyle(SettingsTheme.textTertiary)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .onChange(of: store.settings.backgroundWallpaper) { _, _ in
                        store.settings.wallpaperOffsetX = 0.5
                        store.settings.wallpaperOffsetY = 0.5
                    }
                }

                SettingsDivider()

                subsectionHeader(L10n.string("settings.appearance.transparency", default: "Transparency"))
                SettingsRow(title: L10n.string("settings.row.glass.effect", default: "Glass Effect"), subtitle: L10n.string("settings.row.adjust.the.background.opacity", default: "Adjust the background opacity"), icon: "drop.halffull") {
                    HStack(spacing: 8) {
                        Image(systemName: "circle.dotted")
                            .font(.system(size: 11))
                            .foregroundStyle(SettingsTheme.textTertiary)
                        Slider(value: $opacitySliderValue, in: 0...1)
                            .tint(SettingsTheme.gold)
                            .frame(width: 100)
                            .onChange(of: opacitySliderValue) { _, newValue in
                                Task { @MainActor in
                                    store.updateBackgroundOpacityLive(newValue)
                                }
                                opacitySaveTask?.cancel()
                                opacitySaveTask = Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(300))
                                    guard !Task.isCancelled else { return }
                                    store.liveBackgroundOpacity = nil
                                    store.settings.backgroundOpacity = newValue
                                }
                            }
                            .onAppear {
                                opacitySliderValue = store.settings.backgroundOpacity
                            }
                        Image(systemName: "circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(SettingsTheme.textTertiary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func subsectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .tracking(0.8)
            .foregroundStyle(SettingsTheme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 10)
    }

    private var quickNoteAppearanceContent: some View {
        VStack(spacing: 16) {
            SettingsSegmentedPicker(
                options: QuickNoteSection.allCases,
                selection: quickNoteSection,
                namespace: quickNoteSectionNamespace,
                label: \.label
            ) { section in
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    quickNoteSection = section
                }
            }
            .padding(.horizontal, 4)

            switch quickNoteSection {
            case .surface:
                quickNoteSurfaceSection
            case .typography:
                quickNoteTypographySection
            case .wallpaper:
                quickNoteWallpaperSection
            case .behavior:
                quickNoteBehaviorSection
            }
        }
    }

    private var quickNoteSurfaceSection: some View {
        SettingsSection(CommonCopy.surface()) {
            VStack(alignment: .leading, spacing: 16) {
                QuickNoteStylePickerView(selection: quickNoteAppearanceBinding.style)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)

            SettingsDivider()

            SettingsRow(
                title: L10n.string("settings.row.transparency.mode", default: "Transparency Mode"),
                subtitle: L10n.string("settings.row.decide.whether.the.note.surface.feels.so.540765", default: "Decide whether the note surface feels solid, frosted, or glassy"),
                icon: "cube.transparent"
            ) {
                SettingsSegmentedPicker(
                    options: QuickNoteTransparencyMode.allCases,
                    selection: quickNoteAppearanceBinding.transparencyMode.wrappedValue,
                    namespace: quickNoteTransparencyNamespace,
                    label: \.label
                ) { mode in
                    quickNoteAppearanceBinding.transparencyMode.wrappedValue = mode
                }
                .frame(width: 240)
            }

            SettingsDivider()

            SettingsRow(
                title: L10n.string("settings.row.card.opacity", default: "Card Opacity"),
                subtitle: L10n.string("settings.row.choose.how.solid.or.transparent.the.scra.4221a3", default: "Choose how solid or transparent the scratchpad surface feels"),
                icon: "circle.lefthalf.filled"
            ) {
                HStack(spacing: 8) {
                    Image(systemName: "square.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(SettingsTheme.textTertiary)
                    Slider(value: quickNoteAppearanceBinding.surfaceOpacity, in: 0.55...1)
                        .tint(SettingsTheme.gold)
                        .frame(width: 150)
                    Image(systemName: "square.dashed")
                        .font(.system(size: 10))
                        .foregroundStyle(SettingsTheme.textTertiary)
                }
            }

            // Surface this control only when it actually does something — there's
            // no wallpaper layer to peek through otherwise.
            if store.settings.quickNoteAppearance.backgroundWallpaper != .none {
                SettingsDivider()

                SettingsRow(
                    title: L10n.string("settings.row.card.over.wallpaper", default: "Card Over Wallpaper"),
                    subtitle: L10n.string("settings.row.how.much.the.card.tint.shows.through.whe.8d6ee0", default: "How much the card tint shows through when a wallpaper is set"),
                    icon: "photo.on.rectangle.angled"
                ) {
                    HStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.system(size: 10))
                            .foregroundStyle(SettingsTheme.textTertiary)
                        Slider(value: quickNoteAppearanceBinding.cardOpacityOverWallpaper, in: 0...1)
                            .tint(SettingsTheme.gold)
                            .frame(width: 150)
                        Image(systemName: "square.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(SettingsTheme.textTertiary)
                    }
                }

                SettingsDivider()

                SettingsToggleRow(
                    title: L10n.string("settings.row.auto.text.color", default: "Auto Text Color"),
                    subtitle: L10n.string("settings.row.pick.black.or.white.text.automatically.b.3af68c", default: "Pick black or white text automatically based on wallpaper brightness"),
                    icon: "wand.and.stars",
                    isOn: quickNoteAppearanceBinding.autoTextColorOnWallpaper
                )
            }

            SettingsDivider()

            SettingsRow(
                title: L10n.string("settings.row.text.color", default: "Text Color"),
                subtitle: store.settings.quickNoteAppearance.customTextColorHex == nil
                    ? "Override the style's default ink"
                    : "Custom. Tap the swatch to change or clear",
                icon: "paintpalette"
            ) {
                HStack(spacing: 10) {
                    ColorPicker(
                        "",
                        selection: Binding(
                            get: {
                                if let hex = store.settings.quickNoteAppearance.customTextColorHex {
                                    return Color(hex: hex)
                                }
                                return store.settings.quickNoteAppearance.style.textColor
                            },
                            set: { newValue in
                                var appearance = store.settings.quickNoteAppearance
                                appearance.customTextColorHex = newValue.hexString
                                store.settings.quickNoteAppearance = appearance
                            }
                        ),
                        supportsOpacity: false
                    )
                    .labelsHidden()
                    .frame(width: 36)

                    if store.settings.quickNoteAppearance.customTextColorHex != nil {
                        Button(CommonCopy.reset()) {
                            var appearance = store.settings.quickNoteAppearance
                            appearance.customTextColorHex = nil
                            store.settings.quickNoteAppearance = appearance
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            SettingsDivider()

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(SettingsTheme.gold.opacity(0.12))
                            .frame(width: 32, height: 32)
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(SettingsTheme.gold)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(SettingsCopy.paperTypeTitle())
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(SettingsTheme.textPrimary)
                        Text(SettingsCopy.paperTypeSubtitle())
                            .font(.system(size: 12))
                            .foregroundStyle(SettingsTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }

                SettingsSegmentedPicker(
                    options: QuickNotePaperType.allCases,
                    selection: quickNoteAppearanceBinding.paperType.wrappedValue,
                    namespace: quickNotePaperTypeNamespace,
                    label: \.label
                ) { type in
                    quickNoteAppearanceBinding.paperType.wrappedValue = type
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
    }

    private var quickNoteTypographySection: some View {
        VStack(spacing: 16) {
            QuickNoteTypographyPreviewCard(appearance: store.settings.quickNoteAppearance)

            SettingsSection(CommonCopy.font()) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(SettingsTheme.gold.opacity(0.12))
                                .frame(width: 32, height: 32)
                            Image(systemName: "textformat")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(SettingsTheme.gold)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(CommonCopy.family())
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(SettingsTheme.textPrimary)
                            Text(SettingsCopy.fontFamilySubtitle())
                                .font(.system(size: 12))
                                .foregroundStyle(SettingsTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)
                    }

                    QuickNoteFontFamilyGrid(
                        selection: quickNoteAppearanceBinding.fontFamily,
                        customFontLabel: customFontDisplayLabel,
                        onPickCustomFont: pickCustomQuickNoteFont
                    )
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)

                if store.settings.quickNoteAppearance.fontFamily == .custom,
                   store.settings.quickNoteAppearance.customFontPostScriptName != nil {
                    SettingsDivider()
                    SettingsRow(
                        title: customFontDisplayLabel,
                        subtitle: L10n.string("settings.row.stored.in.application.support.replace.or.740198", default: "Stored in Application Support. Replace or remove anytime"),
                        icon: "doc.richtext"
                    ) {
                        HStack(spacing: 8) {
                            Button(CommonCopy.replace()) {
                                pickCustomQuickNoteFont()
                            }
                            .buttonStyle(.bordered)
                            Button(role: .destructive) {
                                clearCustomQuickNoteFont()
                            } label: {
                                Text(CommonCopy.remove())
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                SettingsDivider()

                SettingsRow(
                    title: L10n.string("settings.row.weight", default: "Weight"),
                    subtitle: L10n.string("settings.row.from.feather.light.to.confidently.bold", default: "From feather-light to confidently bold"),
                    icon: "scalemass"
                ) {
                    SettingsSegmentedPicker(
                        options: QuickNoteFontWeight.allCases,
                        selection: quickNoteAppearanceBinding.fontWeight.wrappedValue,
                        namespace: quickNoteFontWeightNamespace,
                        label: \.label
                    ) { weight in
                        quickNoteAppearanceBinding.fontWeight.wrappedValue = weight
                    }
                    .frame(width: 320)
                }

                SettingsDivider()

                SettingsRow(
                    title: L10n.string("settings.row.size", default: "Size"),
                    subtitle: L10n.string("settings.row.base.point.size.for.your.note.text", default: "Base point size for your note text"),
                    icon: "textformat.size"
                ) {
                    SettingsSegmentedPicker(
                        options: QuickNoteFontSize.allCases,
                        selection: quickNoteAppearanceBinding.fontSize.wrappedValue,
                        namespace: quickNoteFontSizeNamespace,
                        label: \.label
                    ) { size in
                        quickNoteAppearanceBinding.fontSize.wrappedValue = size
                    }
                    .frame(width: 240)
                }
            }

            SettingsSection(CommonCopy.spacing()) {
                SettingsRow(
                    title: L10n.string("settings.row.line.height", default: "Line height"),
                    subtitle: L10n.string("settings.row.tightens.or.opens.up.the.vertical.rhythm.d21cbf", default: "Tightens or opens up the vertical rhythm between lines"),
                    icon: "arrow.up.and.down.text.horizontal"
                ) {
                    typographySlider(
                        value: quickNoteAppearanceBinding.lineHeightMultiplier,
                        range: 0.9...2.0,
                        unit: "x",
                        precision: 2
                    )
                }

                SettingsDivider()

                SettingsRow(
                    title: L10n.string("settings.row.letter.spacing", default: "Letter spacing"),
                    subtitle: L10n.string("settings.row.per.character.tracking.negative.tightens.6dd37b", default: "Per-character tracking. Negative tightens, positive opens up"),
                    icon: "arrow.left.and.right.text.vertical"
                ) {
                    typographySlider(
                        value: quickNoteAppearanceBinding.letterSpacing,
                        range: -1.0...4.0,
                        unit: "pt",
                        precision: 1
                    )
                }

                SettingsDivider()

                SettingsRow(
                    title: L10n.string("settings.row.paragraph.spacing", default: "Paragraph spacing"),
                    subtitle: L10n.string("settings.row.extra.gap.inserted.between.blank.line.se.88dfbf", default: "Extra gap inserted between blank-line separated paragraphs"),
                    icon: "text.alignleft"
                ) {
                    typographySlider(
                        value: quickNoteAppearanceBinding.paragraphSpacing,
                        range: 0...24,
                        unit: "pt",
                        precision: 0
                    )
                }
            }
        }
    }

    private var quickNoteWallpaperSection: some View {
        SettingsSection(CommonCopy.wallpaper()) {
            SurfaceWallpaperSettingsView(
                wallpaper: quickNoteAppearanceBinding.backgroundWallpaper,
                customFilename: quickNoteAppearanceBinding.customWallpaperFilename,
                offsetX: quickNoteAppearanceBinding.wallpaperOffsetX,
                offsetY: quickNoteAppearanceBinding.wallpaperOffsetY,
                previewState: store.quickNoteWallpaperPreview,
                previewAspectRatio: 1.18,
                previewTint: store.settings.quickNoteAppearance.style.secondaryTextColor
            ) {
                pickCustomWallpaper(slot: .quickNote) { filename in
                    var appearance = store.settings.quickNoteAppearance
                    appearance.customWallpaperFilename = filename
                    appearance.backgroundWallpaper = .custom
                    appearance.wallpaperOffsetX = 0.5
                    appearance.wallpaperOffsetY = 0.5
                    store.settings.quickNoteAppearance = appearance
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
        }
    }

    private var quickNoteBehaviorSection: some View {
        SettingsSection(CommonCopy.behavior()) {
            SettingsRow(title: L10n.string("settings.row.quick.note.opens", default: "Quick Note opens"), subtitle: L10n.string("settings.row.choose.whether.the.scratchpad.opens.cent.af8434", default: "Choose whether the scratchpad opens centered or near your pointer"), icon: "uiwindow.split.2x1") {
                SettingsSegmentedPicker(
                    options: QuickNoteOpenPosition.allCases,
                    selection: store.settings.quickNoteOpenPosition,
                    namespace: quickNotePlacementNamespace,
                    label: \.label
                ) { option in
                    store.settings.quickNoteOpenPosition = option
                }
                .frame(width: 220)
            }
            SettingsDivider()
            SettingsRow(
                title: L10n.string("settings.row.open.animation", default: "Open animation"),
                subtitle: L10n.string("settings.row.how.quick.note.appears.when.you.summon.it", default: "How Quick Note appears when you summon it"),
                icon: "sparkles"
            ) {
                Picker("", selection: $store.settings.quickNoteOpenAnimation) {
                    ForEach(QuickNoteAnimationStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 160)
            }
            SettingsDivider()
            SettingsRow(
                title: L10n.string("settings.row.close.animation", default: "Close animation"),
                subtitle: L10n.string("settings.row.how.quick.note.dismisses.when.you.close.it", default: "How Quick Note dismisses when you close it"),
                icon: "sparkle"
            ) {
                Picker("", selection: $store.settings.quickNoteCloseAnimation) {
                    ForEach(QuickNoteAnimationStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 160)
            }
            SettingsDivider()
            SettingsRow(
                title: L10n.string("settings.row.note.navigation.buttons", default: "Note navigation buttons"),
                subtitle: L10n.string("settings.row.top.left.arrows.to.move.between.notes.us.976c94", default: "Top-left arrows to move between notes. Use Minimal for borderless icons or Hidden to remove them"),
                icon: "arrow.left.arrow.right"
            ) {
                SettingsSegmentedPicker(
                    options: QuickNoteNavigationControlsStyle.allCases,
                    selection: store.settings.quickNoteNavigationControlsStyle,
                    namespace: quickNoteNavigationControlsNamespace,
                    label: \.label
                ) { option in
                    store.settings.quickNoteNavigationControlsStyle = option
                }
                .frame(width: 260)
            }
            SettingsDivider()
            SettingsToggleRow(
                title: L10n.string("settings.row.reverse.swipe.direction", default: "Reverse swipe direction"),
                subtitle: L10n.string("settings.row.turn.this.on.if.left.and.right.feel.back.3a0ecc", default: "Turn this on if left and right feel backwards on your trackpad"),
                icon: "arrow.left.and.right",
                isOn: $store.settings.reverseQuickNoteSwipeDirection
            )
            SettingsDivider()
            SettingsToggleRow(
                title: L10n.string("settings.row.auto.paste.copied.text", default: "Auto paste copied text"),
                subtitle: L10n.string("settings.row.while.quick.note.stays.open.copied.text..e1459a", default: "While Quick Note stays open, copied text and links from other apps are appended automatically"),
                icon: "text.append",
                isOn: $store.settings.quickNoteAutoPasteFromClipboard
            )
            SettingsDivider()
            SettingsToggleRow(
                title: L10n.string("settings.row.mirror.notes.into.clipboard", default: "Mirror notes into clipboard"),
                subtitle: L10n.string("settings.row.keep.a.linked.note.snapshot.in.clipboard.history", default: "Keep a linked note snapshot in clipboard history"),
                icon: "note.text.badge.plus",
                isOn: $store.settings.mirrorNotesIntoClipboardHistory
            )
            SettingsDivider()
            SettingsToggleRow(
                title: L10n.string("settings.row.dim.when.not.focused", default: "Dim when not focused"),
                subtitle: L10n.string("settings.row.fade.quick.note.while.you.work.in.anothe.803d1c", default: "Fade Quick Note while you work in another app. It snaps back when you return"),
                icon: "moon.zzz",
                isOn: $store.settings.quickNoteDimWhenUnfocused
            )
            if store.settings.quickNoteDimWhenUnfocused {
                SettingsDivider()
                SettingsRow(
                    title: L10n.string("settings.row.unfocused.opacity", default: "Unfocused Opacity"),
                    subtitle: L10n.string("settings.row.how.much.quick.note.fades.when.it.s.not.in.focus", default: "How much Quick Note fades when it's not in focus"),
                    icon: "slider.horizontal.below.rectangle"
                ) {
                    HStack(spacing: 8) {
                        Image(systemName: "circle.dashed")
                            .font(.system(size: 10))
                            .foregroundStyle(SettingsTheme.textTertiary)
                        Slider(value: $store.settings.quickNoteUnfocusedAlpha, in: 0.15...1)
                            .tint(SettingsTheme.gold)
                            .frame(width: 150)
                        Image(systemName: "circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(SettingsTheme.textTertiary)
                    }
                }
            }
        }
    }

    private var customFontDisplayLabel: String {
        let appearance = store.settings.quickNoteAppearance
        if let filename = appearance.customFontFilename, !filename.isEmpty {
            return (filename as NSString).deletingPathExtension.replacingOccurrences(of: "-", with: " ")
        }
        return "No custom font selected"
    }

    private func typographySlider(
        value: Binding<Double>,
        range: ClosedRange<Double>,
        unit: String,
        precision: Int
    ) -> some View {
        HStack(spacing: 10) {
            Slider(value: value, in: range)
                .tint(SettingsTheme.gold)
                .frame(width: 180)
            Text(formatSliderValue(value.wrappedValue, precision: precision) + unit)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(SettingsTheme.textSecondary)
                .frame(minWidth: 48, alignment: .trailing)
        }
    }

    private func formatSliderValue(_ value: Double, precision: Int) -> String {
        if precision == 0 { return "\(Int(value.rounded()))" }
        return String(format: "%.\(precision)f", value)
    }

    private func pickCustomQuickNoteFont() {
        let panel = NSOpenPanel()
        panel.title = "Choose Font File"
        // Allow the system font UTI plus the common file extensions so users can drop in
        // .ttf/.otf/.ttc files even when LaunchServices hasn't tagged them with a content type.
        var contentTypes: [UTType] = [.font]
        for ext in ["ttf", "otf", "ttc", "otc"] {
            if let type = UTType(filenameExtension: ext) {
                contentTypes.append(type)
            }
        }
        panel.allowedContentTypes = contentTypes
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModalInFront() == .OK, let url = panel.url else { return }

        guard let imported = QuickNoteFontRegistry.importFont(from: url) else {
            let alert = NSAlert()
            alert.messageText = "Could not import font"
            alert.informativeText = "The file does not appear to be a valid .ttf, .otf, or .ttc font."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModalInFront()
            return
        }

        var appearance = store.settings.quickNoteAppearance
        if let oldFilename = appearance.customFontFilename, oldFilename != imported.filename {
            QuickNoteFontRegistry.remove(filename: oldFilename)
        }
        appearance.customFontFilename = imported.filename
        appearance.customFontPostScriptName = imported.postScriptName
        appearance.fontFamily = .custom
        store.settings.quickNoteAppearance = appearance
    }

    private func clearCustomQuickNoteFont() {
        var appearance = store.settings.quickNoteAppearance
        QuickNoteFontRegistry.remove(filename: appearance.customFontFilename)
        appearance.customFontFilename = nil
        appearance.customFontPostScriptName = nil
        if appearance.fontFamily == .custom {
            appearance.fontFamily = .monospaced
        }
        store.settings.quickNoteAppearance = appearance
    }

    private var workspaceAppearanceContent: some View {
        VStack(spacing: 24) {
            SettingsSection(SettingsCopy.workspaceDesign()) {
                VStack(alignment: .leading, spacing: 16) {
                    WorkspaceThemePickerView(selection: workspaceAppearanceBinding.backgroundTheme)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)

                SettingsDivider()

                SettingsRow(
                    title: L10n.string("settings.row.background.opacity", default: "Background Opacity"),
                    subtitle: L10n.string("settings.row.tune.how.much.wallpaper.or.material.show.d5fa49", default: "Tune how much wallpaper or material shows through in Workspace"),
                    icon: "circle.lefthalf.filled"
                ) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(SettingsTheme.textTertiary)
                        Slider(value: workspaceAppearanceBinding.backgroundOpacity, in: 0.35...1)
                            .tint(SettingsTheme.gold)
                            .frame(width: 150)
                        Image(systemName: "square.dashed")
                            .font(.system(size: 10))
                            .foregroundStyle(SettingsTheme.textTertiary)
                    }
                }
            }

            SettingsSection(SettingsCopy.workspaceBackground()) {
                SurfaceWallpaperSettingsView(
                    wallpaper: workspaceAppearanceBinding.backgroundWallpaper,
                    customFilename: workspaceAppearanceBinding.customWallpaperFilename,
                    offsetX: workspaceAppearanceBinding.wallpaperOffsetX,
                    offsetY: workspaceAppearanceBinding.wallpaperOffsetY,
                    previewState: store.workspaceWallpaperPreview,
                    previewAspectRatio: 1.62,
                    previewTint: store.settings.workspaceAppearance.backgroundTheme.vignetteColor
                ) {
                    pickCustomWallpaper(slot: .workspace) { filename in
                        var appearance = store.settings.workspaceAppearance
                        appearance.customWallpaperFilename = filename
                        appearance.backgroundWallpaper = .custom
                        appearance.wallpaperOffsetX = 0.5
                        appearance.wallpaperOffsetY = 0.5
                        store.settings.workspaceAppearance = appearance
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
            }

            SettingsSection(SettingsCopy.workspaceBehavior()) {
                SettingsToggleRow(
                    title: L10n.string("settings.row.restore.workspace.tabs", default: "Restore workspace tabs"),
                    subtitle: L10n.string("settings.row.reopen.your.note.and.clipboard.tabs.next.time", default: "Reopen your note and clipboard tabs next time"),
                    icon: "rectangle.stack",
                    isOn: $store.settings.restoreWorkspaceTabs
                )
            }

            SettingsSection(
                L10n.string("settings.kanban.assist.section", default: "Kanban writing actions")
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(
                        L10n.string(
                            "settings.kanban.assist.intro",
                            default: "Built-in actions always appear when you edit or right-click a task. Add your own prompts below. Each becomes a menu option and chip on the board."
                        )
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsTheme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.top, 14)

                    KanbanCustomAssistPresetsSettingsView()
                }
            }
        }
    }

    private func clipTypeThemeEditor(for type: ClipType) -> some View {
        let theme = store.settings.clipTypeTheme(for: type)
        let headerStyle = theme.headerStyle
        let isGradient = headerStyle.isGradient
        let gradientPresets = store.settings.savedColorPresets.filter(\.isGradient)
        let solidPresets = store.settings.savedColorPresets.filter { !$0.isGradient }

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(ClipTypePresentation.label(for: type))
                    .font(.system(size: 12, weight: .semibold))

                RoundedRectangle(cornerRadius: 5)
                    .fill(headerPreviewStyle(for: theme))
                    .frame(width: 42, height: 14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.6)
                    )

                Spacer()

                if store.settings.clipTypeThemes[type.rawValue] != nil {
                    Button(CommonCopy.reset()) {
                        store.settings.resetClipTypeTheme(for: type)
                    }
                    .font(.system(size: 10, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }

            ColorPicker(
                "Accent",
                selection: Binding(
                    get: { theme.resolvedAccentColor.color },
                    set: { newColor in
                        var updated = theme
                        updated.accentRaw = newColor.hexString
                        store.settings.setClipTypeTheme(updated, for: type)
                    }
                )
            )

            ColorPicker(
                "Label",
                selection: Binding(
                    get: {
                        theme.resolvedLabelColor?.color
                            ?? ClipTypePresentation.headerLabelColors(for: type).primary
                    },
                    set: { newColor in
                        var updated = theme
                        updated.labelRaw = newColor.hexString
                        store.settings.setClipTypeTheme(updated, for: type)
                    }
                )
            )

            HStack(spacing: 6) {
                colorStylePill("Solid", selected: !isGradient) {
                    var updated = theme
                    updated.headerRaw = FolderColorValue.solid(theme.resolvedAccentColor).rawString
                    store.settings.setClipTypeTheme(updated, for: type)
                }
                colorStylePill("Gradient", selected: isGradient) {
                    var updated = theme
                    let base = theme.resolvedAccentColor.color.hexString
                    let gradient = GradientSpec(color1: base, color2: "#222222", angle: 90)
                    updated.headerRaw = FolderColorValue.gradient(gradient).rawString
                    store.settings.setClipTypeTheme(updated, for: type)
                }
            }

            if isGradient, case .gradient(let spec) = headerStyle {
                GradientPickerView(spec: Binding(
                    get: { spec },
                    set: { newSpec in
                        var updated = theme
                        updated.headerRaw = FolderColorValue.gradient(newSpec).rawString
                        store.settings.setClipTypeTheme(updated, for: type)
                    }
                ))

                if !gradientPresets.isEmpty {
                    PresetLibraryView(
                        presets: gradientPresets,
                        onApply: { preset in
                            var updated = theme
                            updated.headerRaw = FolderColorValue(rawString: preset.rawValue).rawString
                            store.settings.setClipTypeTheme(updated, for: type)
                        },
                        onDelete: { store.deleteColorPreset($0) }
                    )
                }

                Button(SettingsCopy.saveGradientPreset()) {
                    store.saveColorPreset(ColorPreset(name: "\(type.rawValue.capitalized) Header", rawValue: spec.serialized))
                }
                .font(.system(size: 10, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            } else {
                ColorPicker(
                    "Header",
                    selection: Binding(
                        get: {
                            switch headerStyle {
                            case .solid(let color): return color.color
                            case .gradient: return theme.resolvedAccentColor.color
                            }
                        },
                        set: { newColor in
                            var updated = theme
                            updated.headerRaw = FolderColorValue.solid(.hex(newColor.hexString)).rawString
                            store.settings.setClipTypeTheme(updated, for: type)
                        }
                    )
                )

                if !solidPresets.isEmpty {
                    PresetLibraryView(
                        presets: solidPresets,
                        onApply: { preset in
                            var updated = theme
                            updated.headerRaw = FolderColorValue.solid(ResolvedColor(rawString: preset.rawValue)).rawString
                            store.settings.setClipTypeTheme(updated, for: type)
                        },
                        onDelete: { store.deleteColorPreset($0) }
                    )
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func headerPreviewStyle(for theme: ClipTypeTheme) -> AnyShapeStyle {
        switch theme.headerStyle {
        case .gradient(let spec):
            return AnyShapeStyle(spec.linearGradient)
        case .solid(let color):
            return AnyShapeStyle(color.color)
        }
    }

    private func colorStylePill(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(selected ? .white : .white.opacity(0.7))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(selected ? 0.16 : 0.05)))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(selected ? 0.25 : 0.12), lineWidth: 0.6)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - General Tab

    private var generalTab: some View {
            VStack(spacing: 24) {
                SettingsSection(SettingsCopy.appSection()) {
                    SettingsRow(
                        title: L10n.string("settings.row.current.version", default: "Current Version"),
                        subtitle: L10n.string("settings.row.the.version.currently.installed.on.this.mac", default: "The version currently installed on this Mac"),
                        icon: "number"
                    ) {
                        Text(appVersion.settingsLabel)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(SettingsTheme.textPrimary)
                            .textSelection(.enabled)
                    }
                    SettingsDivider()
                    SettingsRow(
                        title: SettingsCopy.appLanguageTitle(),
                        subtitle: SettingsCopy.appLanguageSubtitle(),
                        icon: "globe"
                    ) {
                        Picker("", selection: appLanguageBinding) {
                            ForEach(AppLanguage.allCases, id: \.self) { language in
                                Text(language.label).tag(language)
                            }
                        }
                        .accessibilityLabel(SettingsCopy.appLanguageTitle())
                        .frame(width: 190)
                    }

                }

                SettingsSection(SettingsCopy.startupMenu()) {
                SettingsToggleRow(
                    title: L10n.string("settings.row.open.at.login", default: "Open at login"),
                    subtitle: String(
                        format: L10n.string(
                            "settings.row.open.at.login.sub",
                            default: "Start %@ automatically when you log in"
                        ),
                        AppBrand.displayName
                    ),
                    icon: "power",
                    isOn: launchAtLoginBinding
                )
                    if let error = store.launchAtLoginError {
                        SettingsDivider()
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.orange)
                            Text(error)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.7))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    SettingsDivider()
                    // Menu bar visibility + custom text live in their own
                    // dedicated tab now (SettingsTab.menuBar). Keeping the
                    // "Hide dock icon" toggle here because it's about the dock,
                    // not the menu bar.
                SettingsToggleRow(
                    title: L10n.string("settings.row.hide.dock.icon", default: "Hide dock icon"),
                    subtitle: String(
                        format: L10n.string(
                            "settings.row.hide.dock.icon.sub",
                            default: "Remove %@ from the dock"
                        ),
                        AppBrand.displayName
                    ),
                    icon: "dock.rectangle",
                    isOn: Binding(
                        get: { store.settings.hideFromDock },
                        // Hiding the dock icon would otherwise strand the app with
                        // no visible entry point, so force the menu bar item on.
                        set: { hide in
                            store.settings.hideFromDock = hide
                            if hide { store.settings.showInMenuBar = true }
                        }
                    )
                )
                }

                SettingsSection(CommonCopy.shortcut()) {
                SettingsRow(
                    title: L10n.string("settings.row.global.shortcut", default: "Global Shortcut"),
                    subtitle: String(
                        format: L10n.string(
                            "settings.row.global.shortcut.sub",
                            default: "Press to show/hide %@ from anywhere"
                        ),
                        AppBrand.displayName
                    ),
                    icon: "command"
                ) {
                        VStack(alignment: .trailing, spacing: 4) {
                            ShortcutRecorderField(shortcut: globalShortcutBinding) { captured in
                                store.setGlobalShortcut(captured)
                            }
                        .frame(width: 140, height: 28)

                            if let error = store.globalShortcutError {
                                Text(error)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    SettingsDivider()
                    SettingsRow(
                        title: L10n.string("settings.row.clipboard.motion", default: "Clipboard motion"),
                        subtitle: L10n.string(
                            "settings.row.clipboard.motion.sub",
                            default: "Choose a smooth glide or instant open and close"
                        ),
                        icon: "speedometer"
                    ) {
                        VStack(spacing: 3) {
                            Slider(value: $store.settings.trayAnimationSpeed, in: 0...1)
                                .frame(width: 170)
                                .accessibilityLabel(
                                    L10n.string("settings.row.clipboard.motion", default: "Clipboard motion")
                                )

                            HStack {
                                Text(L10n.string("settings.motion.smooth", default: "Smooth"))
                                Spacer()
                                Text(L10n.string("settings.motion.instant", default: "Instant"))
                            }
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(SettingsTheme.textSecondary)
                        }
                        .frame(width: 170)
                    }
                    SettingsDivider()
                    SettingsRow(title: L10n.string("settings.row.quick.note.shortcut", default: "Quick Note Shortcut"), subtitle: L10n.string("settings.row.open.the.floating.scratchpad.from.anywhere", default: "Open the floating scratchpad from anywhere"), icon: "square.and.pencil") {
                        ShortcutRecorderField(shortcut: quickNoteShortcutBinding) { captured in
                            store.setQuickNoteShortcut(captured)
                        }
                        .frame(width: 140, height: 28)
                    }
                    SettingsDivider()
                    SettingsRow(title: L10n.string("settings.row.command.palette.shortcut", default: "Command Palette Shortcut"), subtitle: L10n.string("settings.row.search.clips.notes.meetings.and.run.commands", default: "Search clips, notes, meetings, and run commands"), icon: "magnifyingglass") {
                        ShortcutRecorderField(shortcut: commandPaletteShortcutBinding) { captured in
                            store.setCommandPaletteShortcut(captured)
                        }
                        .frame(width: 140, height: 28)
                    }
                }

                SettingsSection(SettingsCopy.trackpadRevealSectionTitle()) {
                    SettingsToggleRow(
                        title: SettingsCopy.trackpadRevealBottomEdgeTitle(),
                        subtitle: SettingsCopy.trackpadRevealBottomEdgeSubtitle(),
                        icon: "hand.draw",
                        isOn: $store.settings.trackpadRevealBottomEdgeSwipeEnabled
                    )
                    SettingsDivider()
                    SettingsToggleRow(
                        title: SettingsCopy.trackpadRevealBottomCenterTitle(),
                        subtitle: SettingsCopy.trackpadRevealBottomCenterSubtitle(),
                        icon: "arrow.up",
                        isOn: $store.settings.trackpadRevealBottomCenterSwipeEnabled
                    )
                    SettingsDivider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text(SettingsCopy.trackpadRevealPrimaryNote())
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(SettingsTheme.textPrimary)
                        Text(SettingsCopy.trackpadRevealThreeFingerNote())
                            .font(.system(size: 11))
                            .foregroundStyle(SettingsTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }

                SettingsSection(SettingsCopy.pasteBehavior()) {
                SettingsToggleRow(
                    title: L10n.string("settings.row.paste.to.active.app", default: "Paste to active app"),
                    subtitle: L10n.string("settings.row.paste.directly.into.the.frontmost.application", default: "Paste directly into the frontmost application"),
                    icon: "doc.on.clipboard",
                    isOn: $store.settings.pasteToActiveApp
                )
                    SettingsDivider()
                SettingsToggleRow(
                    title: L10n.string("settings.row.always.plain.text", default: "Always plain text"),
                    subtitle: L10n.string("settings.row.strip.formatting.from.copied.text", default: "Strip formatting from copied text"),
                    icon: "textformat",
                    isOn: $store.settings.alwaysPlainText
                )
                    SettingsDivider()
                SettingsToggleRow(
                    title: L10n.string("settings.row.single.click.to.paste", default: "Single click to paste"),
                    subtitle: L10n.string("settings.row.paste.clips.with.a.single.click.instead.of.double", default: "Paste clips with a single click instead of double"),
                    icon: "cursorarrow.click",
                    isOn: $store.settings.singleClickToPaste
                )
                }

                SettingsSection(SettingsCopy.history()) {
                SettingsRow(title: L10n.string("settings.row.keep.history", default: "Keep History"), subtitle: L10n.string("settings.row.how.long.to.keep.clipboard.history", default: "How long to keep clipboard history"), icon: "clock") {
                        Picker("", selection: retentionBinding) {
                            ForEach(HistoryRetention.allCases, id: \.self) { retention in
                                Text(retention.label).tag(retention)
                            }
                        }
                        .frame(width: 160)
                    }
                    SettingsDivider()
                SettingsRow(title: L10n.string("settings.row.erase.history", default: "Erase History"), subtitle: L10n.string("settings.row.remove.all.saved.clips.immediately", default: "Remove all saved clips immediately"), icon: "trash") {
                    Button {
                            isShowingEraseConfirmation = true
                    } label: {
                        Text(CommonCopy.erase())
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.red.opacity(0.85))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

                SettingsSection(SettingsCopy.notesVault()) {
                    SettingsRow(
                        title: L10n.string("settings.row.obsidian.vault", default: "Obsidian Vault"),
                        subtitle: L10n.string("settings.row.pick.a.folder.to.save.quick.notes.into.t.cf986c", default: "Pick a folder to save Quick Notes into, then choose each note's folder from the destination button inside a note."),
                        icon: "books.vertical"
                    ) {
                        Button {
                            chooseVaultFolderFromSettings()
                        } label: {
                            Text(store.hasNotesVault ? "Change…" : "Choose…")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(SettingsTheme.gold.opacity(0.85))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    if store.hasNotesVault, let path = store.settings.notesVaultDisplayPath {
                        SettingsDivider()
                        vaultFolderRow(path: path)
                    }
                }
        }
    }

    // MARK: - Smart Categories Tab

    private var categoriesTab: some View {
            VStack(spacing: 24) {
                SettingsSection(SettingsCopy.autoDetect()) {
                SettingsToggleRow(title: L10n.string("settings.row.code.snippets", default: "Code Snippets"), subtitle: L10n.string("settings.row.detect.code.blocks.and.scripts", default: "Detect code blocks and scripts"), icon: "chevron.left.forwardslash.chevron.right", isOn: Binding(
                            get: { store.settings.smartCategories.codeEnabled },
                            set: { store.settings.smartCategories.codeEnabled = $0; store.removeDisabledSmartFolders() }
                        ))
                    SettingsDivider()
                SettingsToggleRow(title: L10n.string("settings.row.images", default: "Images"), subtitle: L10n.string("settings.row.detect.copied.images.and.screenshots", default: "Detect copied images and screenshots"), icon: "photo", isOn: Binding(
                            get: { store.settings.smartCategories.imagesEnabled },
                            set: { store.settings.smartCategories.imagesEnabled = $0; store.removeDisabledSmartFolders() }
                        ))
                    SettingsDivider()
                SettingsToggleRow(title: L10n.string("settings.row.links", default: "Links"), subtitle: L10n.string("settings.row.detect.urls.and.web.links", default: "Detect URLs and web links"), icon: "link", isOn: Binding(
                            get: { store.settings.smartCategories.linksEnabled },
                            set: { store.settings.smartCategories.linksEnabled = $0; store.removeDisabledSmartFolders() }
                        ))
                    SettingsDivider()
                SettingsToggleRow(title: L10n.string("settings.row.contacts", default: "Contacts"), subtitle: L10n.string("settings.row.detect.phone.numbers.and.emails", default: "Detect phone numbers and emails"), icon: "person.crop.circle", isOn: Binding(
                            get: { store.settings.smartCategories.contactsEnabled },
                            set: { store.settings.smartCategories.contactsEnabled = $0; store.removeDisabledSmartFolders() }
                        ))
                    SettingsDivider()
                SettingsToggleRow(title: L10n.string("settings.row.colors", default: "Colors"), subtitle: L10n.string("settings.row.detect.hex.and.rgb.color.codes", default: "Detect hex and rgb color codes"), icon: "paintpalette", isOn: Binding(
                            get: { store.settings.smartCategories.colorsEnabled },
                            set: { store.settings.smartCategories.colorsEnabled = $0; store.removeDisabledSmartFolders() }
                        ))
                    SettingsDivider()
                SettingsToggleRow(title: L10n.string("settings.row.addresses", default: "Addresses"), subtitle: L10n.string("settings.row.detect.physical.locations", default: "Detect physical locations"), icon: "mappin.and.ellipse", isOn: Binding(
                            get: { store.settings.smartCategories.addressesEnabled },
                            set: { store.settings.smartCategories.addressesEnabled = $0; store.removeDisabledSmartFolders() }
                        ))

                    Text(SettingsCopy.smartFoldersHint())
                        .font(.system(size: 11))
                    .foregroundStyle(SettingsTheme.textTertiary)
                    .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                }

                SettingsSection(SettingsCopy.sensitiveContent()) {
                SettingsToggleRow(title: L10n.string("settings.row.detect.sensitive.content", default: "Detect Sensitive Content"), subtitle: L10n.string("settings.row.identify.passwords.api.keys.and.tokens", default: "Identify passwords, API keys, and tokens"), icon: "lock.shield", isOn: Binding(
                            get: { store.settings.smartCategories.sensitiveEnabled },
                            set: { store.settings.smartCategories.sensitiveEnabled = $0; store.removeDisabledSmartFolders() }
                        ))

                    if store.settings.smartCategories.sensitiveEnabled {
                        SettingsDivider()
                    SettingsToggleRow(title: L10n.string("settings.row.auto.expire", default: "Auto-expire"), subtitle: L10n.string("settings.row.automatically.delete.sensitive.clips", default: "Automatically delete sensitive clips"), icon: "timer", isOn: $store.settings.smartCategories.autoExpireSensitive)

                        if store.settings.smartCategories.autoExpireSensitive {
                            SettingsDivider()
                            SettingsRow(title: L10n.string("settings.row.expire.after", default: "Expire After")) {
                                Picker("", selection: $store.settings.smartCategories.sensitiveExpiry) {
                                    ForEach(SensitiveExpiry.allCases, id: \.self) { expiry in
                                        Text(expiry.label).tag(expiry)
                                    }
                                }
                                .frame(width: 140)
                            }
                        }
                    }
                }
        }
    }

    // MARK: - Folders Tab

    private var settingsEditableFolders: [ClipFolderModel] {
        store.folders.filter(\.isBulkEditable)
    }

    private var settingsSmartFolderIDs: Set<UUID> {
        Set(store.folders.filter(\.isSmartFolder).map(\.folderID))
    }

    private var settingsUserFolderIDs: Set<UUID> {
        Set(store.folders.filter { !$0.isSystem && !$0.isSmartFolder }.map(\.folderID))
    }

    private func reconcileSettingsBulkSelection() {
        let liveIDs = Set(settingsEditableFolders.map(\.folderID))
        bulkSelectedIDs.formIntersection(liveIDs)
    }

    private var settingsBulkSelectedFolders: [ClipFolderModel] {
        settingsEditableFolders.filter { bulkSelectedIDs.contains($0.folderID) }
    }

    private var settingsBulkTextColorMode: FolderTextColorMode? {
        guard let firstMode = settingsBulkSelectedFolders.first?.textColorMode else { return nil }
        guard settingsBulkSelectedFolders.allSatisfy({ $0.textColorMode == firstMode }) else { return nil }
        return firstMode
    }

    private var settingsBulkTextModeHelperText: String {
        settingsBulkTextColorMode?.helperText ?? "Choose how folder text should be colored."
    }

    private var settingsBulkCustomTextColor: ResolvedColor {
        settingsBulkSelectedFolders.first?.resolvedCustomTextColor
            ?? settingsBulkSelectedFolders.first?.resolvedColor
            ?? ResolvedColor(rawString: FolderColorToken.white.rawValue)
    }

    private var foldersTab: some View {
        VStack(spacing: 16) {
            // Sub-tab picker
            folderSubTabPicker

            // Content based on selected sub-tab
            switch folderSubTab {
            case .folders:
                foldersSubContent
            case .bulkEdit:
                bulkEditSubContent
            case .aiSkills:
                aiSkillsSection
            }
        }
    }

    private var folderSubTabPicker: some View {
        SettingsSegmentedPicker(
            options: FolderSubTab.allCases,
            selection: folderSubTab,
            namespace: folderSubTabNamespace,
            label: \.label
        ) { tab in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                folderSubTab = tab
                // Leaving bulk edit should clear its temporary multi-select state
                // so the next visit starts from a clean slate instead of stale picks.
                if tab != .bulkEdit {
                    bulkSelectedIDs.removeAll()
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private var foldersSubContent: some View {
        VStack(spacing: 24) {
            // Smart Categories Section
            SettingsSection(SettingsCopy.smartCategories()) {
                VStack(spacing: 0) {
                    ForEach(Array(SmartCategory.allCases.enumerated()), id: \.element) { index, category in
                        smartCategorySettingsRow(category)
                        if index < SmartCategory.allCases.count - 1 {
                            SettingsDivider()
                        }
                    }
                }
            }

            // User Folders Section
            SettingsSection(SettingsCopy.yourFolders()) {
                VStack(spacing: 0) {
                    let folders = store.folders.filter { !$0.isSystem && !$0.isSmartFolder }
                    ForEach(Array(folders.enumerated()), id: \.element.folderID) { index, folder in
                        userFolderSettingsRow(folder)
                        if index < folders.count - 1 {
                            SettingsDivider()
                        }
                    }

                    if folders.isEmpty {
                        HStack {
                            Text(SettingsCopy.noCustomFolders())
                                .font(.system(size: 13))
                                .foregroundStyle(SettingsTheme.textTertiary)
                            Spacer()
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                    }

                    SettingsDivider()

                    // Add folder button
                    Button {
                        store.createFolder()
                    } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(SettingsTheme.gold.opacity(0.12))
                                    .frame(width: 32, height: 32)
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(SettingsTheme.gold)
                            }

                            Text(SettingsCopy.createNewFolder())
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(SettingsTheme.textPrimary)

                            Spacer()
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            // Hidden folders (custom + linked skill folders hidden via right-click)
            if !store.hiddenTabFolders.isEmpty {
                SettingsSection(SettingsCopy.hiddenFromTabBar()) {
                    VStack(spacing: 0) {
                        let hidden = store.hiddenTabFolders
                        ForEach(Array(hidden.enumerated()), id: \.element.folderID) { index, folder in
                            hiddenFolderSettingsRow(folder)
                            if index < hidden.count - 1 {
                                SettingsDivider()
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func hiddenFolderSettingsRow(_ folder: ClipFolderModel) -> some View {
        let accentColor = folder.resolvedColor.color
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.15))
                    .frame(width: 32, height: 32)

                FolderIconView(
                    folder: folder,
                    accentColor: accentColor,
                    textColor: SettingsTheme.textPrimary,
                    fontSize: 14,
                    circleSize: 0
                )
            }

            Text(folder.displayName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(SettingsTheme.textPrimary)

            Spacer()

            Button {
                store.showFolderInTabs(id: folder.folderID)
            } label: {
                Text(CommonCopy.show())
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SettingsTheme.gold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(SettingsTheme.gold.opacity(0.1))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    // MARK: - AI Skills Section

    private var aiSkillsSection: some View {
        SettingsSection(SettingsCopy.aiSkills()) {
            VStack(spacing: 0) {
                // Header + scan button
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(SettingsTheme.gold.opacity(0.12))
                            .frame(width: 36, height: 36)
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(SettingsTheme.gold)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(SettingsCopy.skillFoldersTitle())
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(SettingsTheme.textPrimary)
                        Text(SettingsCopy.skillFoldersSubtitle())
                            .font(.system(size: 12))
                            .foregroundStyle(SettingsTheme.textSecondary)
                    }

                    Spacer()

                    Button {
                        isScanning = true
                        let results = SkillScanner.scanAll()
                        skillScanResults = results
                        store.rescanLinkedSkills(scanResults: results)
                        hasScannedForSkills = true
                        isScanning = false
                    } label: {
                        HStack(spacing: 6) {
                            if isScanning {
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(width: 12, height: 12)
                            } else {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            Text(store.settings.linkedSkillProviders.isEmpty ? "Scan" : "Re-scan")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(SettingsTheme.gold)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isScanning)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)

                // Scan results — toggle-based
                if hasScannedForSkills {
                    SettingsDivider()

                    if skillScanResults.isEmpty {
                        HStack {
                            Image(systemName: "info.circle")
                                .font(.system(size: 13))
                                .foregroundStyle(SettingsTheme.textTertiary)
                            Text(SettingsCopy.noAIToolsFound())
                                .font(.system(size: 13))
                                .foregroundStyle(SettingsTheme.textTertiary)
                            Spacer()
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                    } else {
                        ForEach(Array(skillScanResults.enumerated()), id: \.element.id) { index, result in
                            skillToggleRow(result)
                            if index < skillScanResults.count - 1 {
                                SettingsDivider()
                            }
                        }
                    }
                }

                // Show already-linked providers (even without scanning) — with toggles
                if !hasScannedForSkills && !store.settings.linkedSkillProviders.isEmpty {
                    SettingsDivider()
                    ForEach(store.settings.linkedSkillProviders, id: \.self) { providerID in
                        if let provider = AIProvider.provider(for: providerID) {
                            linkedProviderToggleRow(provider)
                        }
                    }
                }

                // Custom linked folders
                if !store.settings.customSkillPaths.isEmpty {
                    SettingsDivider()
                    ForEach(store.settings.customSkillPaths, id: \.self) { path in
                        customFolderRow(path: path)
                    }
                }

                // Add custom folder button
                SettingsDivider()
                Button {
                    openFolderPicker()
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(SettingsTheme.gold.opacity(0.12))
                                .frame(width: 32, height: 32)
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(SettingsTheme.gold)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(SettingsCopy.addCustomFolderTitle())
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(SettingsTheme.textPrimary)
                            Text(SettingsCopy.addCustomFolderSubtitle())
                                .font(.system(size: 11))
                                .foregroundStyle(SettingsTheme.textTertiary)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Folder Settings Helpers
    
    @State private var expandedFolderID: UUID?
    @State private var bulkSelectedIDs: Set<UUID> = []
    

    @ViewBuilder
    private func smartCategorySettingsRow(_ category: SmartCategory) -> some View {
        let enabled = store.settings.smartCategories.isEnabled(category)
        let smartFolder = store.folders.first(where: { $0.smartCategoryRaw == category.rawValue })
        let accentColor = smartFolder?.resolvedColor.color ?? category.folderColor.color

        SmartCategoryRowContent(
            category: category,
            enabled: enabled,
            smartFolder: smartFolder,
            accentColor: accentColor,
            isExpanded: enabled && expandedFolderID == category.folderID,
            onToggle: { newValue in
                if newValue {
                    store.enableSmartCategory(category)
                } else {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        expandedFolderID = nil
                    }
                    store.hideSmartCategory(category)
                }
            },
            onChevronTap: {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    if expandedFolderID == category.folderID {
                        expandedFolderID = nil
                    } else {
                        expandedFolderID = category.folderID
                    }
                }
            },
            folderCustomizationPanel: { folder in
                folderCustomizationPanel(folder: folder, accentColor: accentColor)
            }
        )
    }
    
    @ViewBuilder
    private func userFolderSettingsRow(_ folder: ClipFolderModel) -> some View {
        let accentColor = folder.resolvedColor.color
        let isVisible = store.settings.isCustomFolderVisible(folder.folderID)
        let folders = store.folders.filter { !$0.isSystem && !$0.isSmartFolder }
        let index = folders.firstIndex(where: { $0.folderID == folder.folderID })
        let isFirst = index == folders.startIndex
        let isLast = folders.count <= 1 || index == folders.index(before: folders.endIndex)

        UserFolderRowContent(
            folder: folder,
            accentColor: accentColor,
            isVisible: isVisible,
            isExpanded: isVisible && expandedFolderID == folder.folderID,
            isFirst: isFirst,
            isLast: isLast,
            onToggle: { newValue in
                if !newValue {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        if expandedFolderID == folder.folderID {
                            expandedFolderID = nil
                        }
                    }
                }
                store.setUserFolderVisibility(id: folder.folderID, isVisible: newValue)
            },
            onMoveUp: { store.moveFolderLeft(id: folder.folderID) },
            onMoveDown: { store.moveFolderRight(id: folder.folderID) },
            onChevronTap: {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    if expandedFolderID == folder.folderID {
                        expandedFolderID = nil
                    } else {
                        expandedFolderID = folder.folderID
                    }
                }
            },
            folderCustomizationPanel: {
                folderCustomizationPanel(folder: folder, accentColor: accentColor)
            }
        )
    }
    
    @State private var renamingFolderID: UUID?
    @State private var renameText = ""
    @FocusState private var renameFieldFocused: Bool
    
    private func folderCustomizationPanel(folder: ClipFolderModel, accentColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsDivider()
            
            // Rename row
            HStack(spacing: 12) {
                Text(CommonCopy.name())
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SettingsTheme.textSecondary)
                    .frame(width: 50, alignment: .leading)
                
                if renamingFolderID == folder.folderID {
                    TextField("Folder name", text: $renameText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .frame(maxWidth: 180)
                        .focused($renameFieldFocused)
                        .onSubmit {
                            store.renameFolder(id: folder.folderID, name: renameText)
                            renamingFolderID = nil
                            renameText = ""
                        }
                        .onExitCommand {
                            renamingFolderID = nil
                            renameText = ""
                        }
                } else {
                    Text(folder.displayName)
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsTheme.textPrimary)
                    
                    Spacer()
                    
                    Button {
                        renamingFolderID = folder.folderID
                        renameText = folder.displayName
                        DispatchQueue.main.async {
                            renameFieldFocused = true
                        }
                    } label: {
                        Text(CommonCopy.rename())
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(SettingsTheme.gold)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            
            // Style row
            HStack(spacing: 12) {
                Text(CommonCopy.style())
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SettingsTheme.textSecondary)
                    .frame(width: 50, alignment: .leading)
                
                HStack(spacing: 6) {
                    ForEach(FolderColorMode.allCases, id: \.self) { mode in
                        lightStylePill(mode.label, selected: folder.colorMode == mode) {
                            store.setFolderColorMode(id: folder.folderID, mode: mode)
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            
            // Accent color row
            HStack(spacing: 12) {
                Text(CommonCopy.color())
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SettingsTheme.textSecondary)
                    .frame(width: 50, alignment: .leading)
                
                lightColorSwatchRow(selected: folder.color) { token in
                    store.setFolderAccentColor(id: folder.folderID, color: token)
                }
            }
            .padding(.horizontal, 18)
            
            // Icon row
            HStack(alignment: .top, spacing: 12) {
                Text(CommonCopy.icon())
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SettingsTheme.textSecondary)
                    .frame(width: 50, alignment: .leading)
                
                FolderIconPickerView(
                    folder: folder,
                    accentColor: accentColor,
                    onSelectIcon: { icon in
                        store.setFolderIcon(id: folder.folderID, icon: icon)
                    },
                    useLightTheme: true
                )
            }
            .padding(.horizontal, 18)

            HStack {
                Spacer()

                Button {
                    requestFolderDeletion(folder)
                } label: {
                    Label(CommonCopy.deleteFolder(), systemImage: "trash")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.red.opacity(0.85))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
        }
    }
    
    private func lightStylePill(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? SettingsTheme.textPrimary : SettingsTheme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(selected ? SettingsTheme.gold.opacity(0.15) : SettingsTheme.sidebarBackground)
                )
                .overlay(
                    Capsule().strokeBorder(selected ? SettingsTheme.gold.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
    
    private func lightColorSwatchRow(selected: FolderColorToken, action: @escaping (FolderColorToken) -> Void) -> some View {
        HStack(spacing: 6) {
            ForEach(FolderColorToken.allCases, id: \.self) { token in
                Button {
                    action(token)
                } label: {
                    Circle()
                        .fill(token.color)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle()
                                .strokeBorder(selected == token ? SettingsTheme.textPrimary : Color.clear, lineWidth: 2)
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white, lineWidth: selected == token ? 1.5 : 0)
                                .padding(1.5)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Bulk Edit Settings Section

    private var bulkEditSubContent: some View {
        VStack(spacing: 16) {
            // Quick select + controls
            SettingsSection(SettingsCopy.bulkApplyTo()) {
                VStack(alignment: .leading, spacing: 12) {
                    // Quick select chips
                    HStack(spacing: 6) {
                        bulkSettingsChip("All", active: !settingsEditableFolders.isEmpty && bulkSelectedIDs == Set(settingsEditableFolders.map(\.folderID))) {
                            let allIDs = Set(settingsEditableFolders.map(\.folderID))
                            if allIDs.isEmpty { return }
                            bulkSelectedIDs = bulkSelectedIDs == allIDs ? [] : allIDs
                        }
                        bulkSettingsChip("Smart", active: !settingsSmartFolderIDs.isEmpty && bulkSelectedIDs.isSuperset(of: settingsSmartFolderIDs)) {
                            if bulkSelectedIDs.isSuperset(of: settingsSmartFolderIDs) {
                                bulkSelectedIDs.subtract(settingsSmartFolderIDs)
                            } else {
                                bulkSelectedIDs.formUnion(settingsSmartFolderIDs)
                            }
                        }
                        bulkSettingsChip("Custom", active: !settingsUserFolderIDs.isEmpty && bulkSelectedIDs.isSuperset(of: settingsUserFolderIDs)) {
                            if bulkSelectedIDs.isSuperset(of: settingsUserFolderIDs) {
                                bulkSelectedIDs.subtract(settingsUserFolderIDs)
                            } else {
                                bulkSelectedIDs.formUnion(settingsUserFolderIDs)
                            }
                        }

                        Spacer()

                        if !bulkSelectedIDs.isEmpty {
                            Text(SettingsCopy.bulkSelectedCount(bulkSelectedIDs.count))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(SettingsTheme.gold)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)

                    // Folder list with checkboxes
                    SettingsDivider()
                    VStack(spacing: 0) {
                        ForEach(Array(settingsEditableFolders.enumerated()), id: \.element.folderID) { index, folder in
                            bulkFolderSelectRow(folder)
                            if index < settingsEditableFolders.count - 1 {
                                SettingsDivider()
                            }
                        }
                    }
                }
            }

            // Controls (always visible, disabled when nothing selected)
            SettingsSection(SettingsCopy.bulkChanges()) {
                VStack(alignment: .leading, spacing: 14) {
                    if bulkSelectedIDs.isEmpty {
                        HStack {
                            Image(systemName: "hand.tap")
                                .font(.system(size: 13))
                                .foregroundStyle(SettingsTheme.textTertiary)
                            Text(SettingsCopy.bulkSelectHint())
                                .font(.system(size: 13))
                                .foregroundStyle(SettingsTheme.textTertiary)
                            Spacer()
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                    } else {
                        HStack(spacing: 12) {
                            Text(CommonCopy.style())
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(SettingsTheme.textSecondary)
                                .frame(width: 50, alignment: .leading)

                            HStack(spacing: 6) {
                                ForEach(FolderColorMode.allCases, id: \.self) { mode in
                                    lightStylePill(mode.label, selected: false) {
                                        store.bulkSetFolderColorMode(ids: bulkSelectedIDs, mode: mode)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 12)

                        HStack(spacing: 12) {
                            Text(CommonCopy.accent())
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(SettingsTheme.textSecondary)
                                .frame(width: 50, alignment: .leading)

                            HStack(spacing: 6) {
                                ForEach(FolderColorToken.allCases, id: \.self) { token in
                                    Button {
                                        store.bulkSetFolderAccentColor(ids: bulkSelectedIDs, color: .token(token))
                                    } label: {
                                        Circle()
                                            .fill(token.color)
                                            .frame(width: 20, height: 20)
                                            .overlay(
                                                Circle()
                                                    .strokeBorder(SettingsTheme.border, lineWidth: 0.5)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.horizontal, 18)

                        HStack(spacing: 12) {
                            Text(CommonCopy.textMode())
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(SettingsTheme.textSecondary)
                                .frame(width: 50, alignment: .leading)

                            HStack(spacing: 6) {
                                ForEach([FolderTextColorMode.auto, .white, .accent, .custom], id: \.self) { mode in
                                    lightStylePill(mode.label, selected: settingsBulkTextColorMode == mode) {
                                        store.bulkSetFolderTextColorMode(ids: bulkSelectedIDs, mode: mode)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 18)

                        Text(settingsBulkTextModeHelperText)
                            .font(.system(size: 11))
                            .foregroundStyle(SettingsTheme.textTertiary)
                            .padding(.horizontal, 18)

                        if settingsBulkTextColorMode == .custom {
                            HStack(spacing: 12) {
                                Text(CommonCopy.textColor())
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(SettingsTheme.textSecondary)
                                    .frame(width: 50, alignment: .leading)

                                ColorPickerSwatch(
                                    selected: settingsBulkCustomTextColor,
                                    onSelectToken: { token in
                                        store.bulkSetFolderCustomTextColor(ids: bulkSelectedIDs, color: .token(token))
                                    },
                                    onSelectHex: { hex in
                                        store.bulkSetFolderCustomTextColor(ids: bulkSelectedIDs, color: .hex(hex))
                                    }
                                )
                            }
                            .padding(.horizontal, 18)
                        }
                    }
                }
            }
        }
        .onChange(of: store.folders.map(\.folderID)) { _, _ in
            reconcileSettingsBulkSelection()
        }
    }

    private func bulkFolderSelectRow(_ folder: ClipFolderModel) -> some View {
        let isSelected = bulkSelectedIDs.contains(folder.folderID)
        let accentColor = folder.resolvedColor.color
        return Button {
            if isSelected {
                bulkSelectedIDs.remove(folder.folderID)
            } else {
                bulkSelectedIDs.insert(folder.folderID)
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isSelected ? SettingsTheme.gold : SettingsTheme.textTertiary)

                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.15))
                        .frame(width: 28, height: 28)
                    FolderIconView(
                        folder: folder,
                        accentColor: accentColor,
                        textColor: SettingsTheme.textPrimary,
                        fontSize: 12,
                        circleSize: 0
                    )
                }

                Text(folder.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SettingsTheme.textPrimary.opacity(isSelected ? 1 : 0.7))

                Spacer()

                // Show current style as hint
                Text(folder.colorMode.label)
                    .font(.system(size: 10))
                    .foregroundStyle(SettingsTheme.textTertiary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? SettingsTheme.gold.opacity(0.04) : Color.clear)
    }

    private func bulkSettingsChip(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? SettingsTheme.textPrimary : SettingsTheme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(active ? SettingsTheme.gold.opacity(0.15) : SettingsTheme.sidebarBackground)
                )
                .overlay(
                    Capsule().strokeBorder(active ? SettingsTheme.gold.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }


    // MARK: - Advanced Tab

    private var advancedTab: some View {
            VStack(spacing: 24) {
                SettingsSection(SettingsCopy.storage()) {
                    StorageLocationCard(store: store)
                }

                SettingsSection(CommonCopy.permissions()) {
                    accessibilityPermissionRow

                    SettingsDivider()

                    microphonePermissionRow

                    SettingsDivider()

                    screenRecordingPermissionRow

                    if !accessibilityGranted {
                        SettingsDivider()
                        VStack(alignment: .leading, spacing: 6) {
                            Text(SettingsCopy.currentExecutable(AccessibilityService.executablePath))
                                .font(.system(size: 10))
                            .foregroundStyle(SettingsTheme.textTertiary)
                                .textSelection(.enabled)
                            Text(SettingsCopy.bundleID(AccessibilityService.bundleIdentifierText))
                                .font(.system(size: 10))
                            .foregroundStyle(SettingsTheme.textTertiary)
                                .textSelection(.enabled)
                        }
                    .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                    }
                }
                .onAppear {
                    accessibilityGranted = AccessibilityService.isTrusted()
                    refreshMicrophonePermissionStatus()
                    refreshScreenRecordingPermissionStatus()
                }

                SettingsSection(SettingsCopy.imageTextSearch()) {
                    SettingsToggleRow(
                        title: L10n.string("settings.row.search.text.inside.images", default: "Search text inside images"),
                        subtitle: L10n.string("settings.row.applies.to.clipboard.images.and.quick.note.drops", default: "Applies to clipboard images and Quick Note drops"),
                        icon: "text.viewfinder",
                        isOn: $store.settings.enableImageTextRecognition
                    )

                    if store.settings.enableImageTextRecognition {
                        SettingsDivider()
                        SettingsRow(title: L10n.string("settings.row.clipboard.recognition.quality", default: "Clipboard Recognition Quality")) {
                            Picker("", selection: $store.settings.ocrRecognitionLevelRaw) {
                                Text(CommonCopy.fast()).tag("fast")
                                Text(CommonCopy.accurate()).tag("accurate")
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 160)
                        }
                        SettingsDivider()
                        SettingsRow(title: L10n.string("settings.row.minimum.text.size", default: "Minimum Text Size"), subtitle: "\(Int(store.settings.ocrMinimumTextHeight * 100))%") {
                            Slider(
                                value: Binding(
                                    get: { Double(store.settings.ocrMinimumTextHeight) },
                                    set: { store.settings.ocrMinimumTextHeight = Float(min(max($0, 0.0), 0.2)) }
                                ),
                                in: 0.0...0.2
                            )
                            .tint(SettingsTheme.gold)
                            .frame(width: 160)
                        }
                    }
                }

            Spacer()
        }
    }

    private var accessibilityPermissionRow: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(accessibilityGranted ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: accessibilityGranted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(accessibilityGranted ? .green : .red)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(CommonCopy.accessibility())
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SettingsTheme.textPrimary)
                Text(accessibilityGranted
                     ? "Granted - paste to active app is working"
                     : "Not granted - paste to active app will not work")
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsTheme.textSecondary)
            }

            Spacer()

            if !accessibilityGranted {
                Button {
                    store.requestAccessibilityPermission()
                    store.openAccessibilitySettings()
                } label: {
                    Text(SettingsCopy.grantAccess())
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(SettingsTheme.gold)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Button {
                accessibilityGranted = AccessibilityService.isTrusted()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SettingsTheme.gold)
                    .padding(8)
                    .background(
                        Circle()
                            .fill(SettingsTheme.gold.opacity(0.1))
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var microphonePermissionRow: some View {
        HStack(spacing: 14) {
            let isGranted = microphonePermissionStatus.isGranted
            let isDenied = microphonePermissionStatus == .denied || microphonePermissionStatus == .restricted

            ZStack {
                Circle()
                    .fill(isGranted ? Color.green.opacity(0.15) : Color.orange.opacity(0.14))
                    .frame(width: 36, height: 36)
                Image(systemName: isGranted ? "mic.fill" : "mic.slash.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isGranted ? .green : .orange)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string(
                    "settings.advanced.microphone.title",
                    default: "Microphone"
                ))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SettingsTheme.textPrimary)
                Text(microphonePermissionSubtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsTheme.textSecondary)
            }

            Spacer()

            if !isGranted {
                Button {
                    if isDenied {
                        store.openMicrophoneSettings()
                    } else {
                        Task {
                            _ = await store.requestMicrophonePermission()
                            refreshMicrophonePermissionStatus()
                        }
                    }
                } label: {
                    Text(isDenied
                         ? L10n.string("settings.advanced.microphone.openSettings", default: "Open Settings")
                         : L10n.string("settings.advanced.microphone.request", default: "Request Access"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(SettingsTheme.gold)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Button {
                refreshMicrophonePermissionStatus()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SettingsTheme.gold)
                    .padding(8)
                    .background(
                        Circle()
                            .fill(SettingsTheme.gold.opacity(0.1))
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var microphonePermissionSubtitle: String {
        switch microphonePermissionStatus {
        case .authorized:
            return L10n.string(
                "settings.advanced.microphone.status.granted",
                default: "Granted - local meeting recording can use your microphone"
            )
        case .denied:
            return L10n.string(
                "settings.advanced.microphone.status.denied",
                default: "Blocked in macOS - open System Settings to turn it back on"
            )
        case .restricted:
            return L10n.string(
                "settings.advanced.microphone.status.restricted",
                default: "Restricted by macOS - microphone recording is unavailable"
            )
        case .notDetermined:
            return L10n.string(
                "settings.advanced.microphone.status.notDetermined",
                default: "Not requested yet - click Request Access to show the macOS prompt"
            )
        case .unknown:
            return L10n.string(
                "settings.advanced.microphone.status.checking",
                default: "Checking macOS microphone permission"
            )
        }
    }

    private func refreshMicrophonePermissionStatus() {
        microphonePermissionStatus = store.microphonePermissionStatus()
    }

    private var screenRecordingPermissionRow: some View {
        HStack(spacing: 14) {
            let isGranted = screenRecordingPermissionStatus.isGranted

            ZStack {
                Circle()
                    .fill(isGranted ? Color.green.opacity(0.15) : Color.orange.opacity(0.14))
                    .frame(width: 36, height: 36)
                Image(systemName: isGranted ? "rectangle.on.rectangle.angled.fill" : "rectangle.on.rectangle.slash.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isGranted ? .green : .orange)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string(
                    "settings.advanced.screenRecording.title",
                    default: "Screen & System Audio Recording"
                ))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SettingsTheme.textPrimary)
                Text(screenRecordingPermissionSubtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsTheme.textSecondary)
            }

            Spacer()

            if !isGranted {
                Button {
                    // Trigger the macOS prompt the first time, and always open
                    // System Settings — granted access requires a relaunch, so
                    // landing the user on the right pane is the unblocking step.
                    store.requestScreenRecordingPermission()
                    store.openScreenRecordingSettings()
                } label: {
                    Text(L10n.string(
                        "settings.advanced.screenRecording.openSettings",
                        default: "Open Settings"
                    ))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(SettingsTheme.gold)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Button {
                refreshScreenRecordingPermissionStatus()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SettingsTheme.gold)
                    .padding(8)
                    .background(
                        Circle()
                            .fill(SettingsTheme.gold.opacity(0.1))
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var screenRecordingPermissionSubtitle: String {
        switch screenRecordingPermissionStatus {
        case .authorized:
            return L10n.string(
                "settings.advanced.screenRecording.status.granted",
                default: "Granted - meetings can capture system audio from other apps"
            )
        case .denied, .notDetermined:
            return L10n.string(
                "settings.advanced.screenRecording.status.denied",
                default: "Not granted - System Audio capture for meetings won't work until you enable it"
            )
        case .unknown:
            return L10n.string(
                "settings.advanced.screenRecording.status.checking",
                default: "Checking macOS Screen Recording permission"
            )
        }
    }

    private func refreshScreenRecordingPermissionStatus() {
        screenRecordingPermissionStatus = store.screenRecordingPermissionStatus()
    }


    // MARK: - Skill Provider Rows (Toggle-based)

    private func skillToggleRow(_ result: ProviderScanResult) -> some View {
        let isLinked = store.isProviderLinked(result.provider.id)
        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(providerColor(result.provider).opacity(isLinked ? 0.15 : 0.08))
                    .frame(width: 32, height: 32)
                Image(systemName: result.provider.iconSymbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(providerColor(result.provider).opacity(isLinked ? 1 : 0.5))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(result.provider.displayName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SettingsTheme.textPrimary.opacity(isLinked ? 1 : 0.6))
                Text(SettingsCopy.skillsCount(result.skills.count))
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsTheme.textSecondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { isLinked },
                set: { newValue in
                    if newValue {
                        store.importSkillProvider(result)
                    } else {
                        store.unlinkSkillProvider(result.provider.id)
                    }
                }
            ))
            .toggleStyle(GoldToggleStyle())
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func linkedProviderToggleRow(_ provider: AIProvider) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(providerColor(provider).opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: provider.iconSymbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(providerColor(provider))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(provider.displayName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SettingsTheme.textPrimary)
                Text(CommonCopy.linked())
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsTheme.textSecondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { true },
                set: { newValue in
                    if !newValue {
                        store.unlinkSkillProvider(provider.id)
                    }
                }
            ))
            .toggleStyle(GoldToggleStyle())
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func customFolderRow(path: String) -> some View {
        let url = URL(fileURLWithPath: path)
        let folderName = url.lastPathComponent
        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(SettingsTheme.gold.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: "folder.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SettingsTheme.gold)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(folderName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SettingsTheme.textPrimary)
                Text(path)
                    .font(.system(size: 11))
                    .foregroundStyle(SettingsTheme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button {
                store.unlinkCustomSkillFolder(path)
            } label: {
                Text(CommonCopy.remove())
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.red.opacity(0.1))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func openFolderPicker() {
        let panel = NSOpenPanel()
        panel.title = "Choose a skills folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        guard panel.runModalInFront() == .OK, let url = panel.url else { return }
        store.importCustomSkillFolder(url)
    }

    /// Choose the Obsidian vault root from Settings. Stores a security-scoped
    /// bookmark via the store; Phase 0 never writes into the chosen folder.
    private func chooseVaultFolderFromSettings() {
        if let url = NoteVaultBookmarkService.pickVaultFolder() {
            store.setNotesVault(url: url)
        }
    }

    private func vaultFolderRow(path: String) -> some View {
        let url = URL(fileURLWithPath: path)
        let folderName = url.lastPathComponent
        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(SettingsTheme.gold.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SettingsTheme.gold)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(folderName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SettingsTheme.textPrimary)
                Text(path)
                    .font(.system(size: 11))
                    .foregroundStyle(SettingsTheme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button {
                store.clearNotesVault()
            } label: {
                Text(CommonCopy.clear())
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.red.opacity(0.1))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func providerColor(_ provider: AIProvider) -> Color {
        (FolderColorToken(rawValue: provider.color) ?? .slate).color
    }

    // MARK: - License Tab

    private var licenseTab: some View {
        VStack(spacing: 24) {
            // Status section
            SettingsSection(CommonCopy.status()) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(licenseStatusColor.opacity(0.15))
                                .frame(width: 36, height: 36)
                            Image(systemName: licenseStatusIcon)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(licenseStatusColor)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(licenseStatusTitle)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(SettingsTheme.textPrimary)
                            Text(licenseStatusSubtitle)
                                .font(.system(size: 12))
                                .foregroundStyle(SettingsTheme.textSecondary)
                        }

                        Spacer()

                        if store.licenseState.isLicensed {
                            Text(CommonCopy.activeBadge())
                                .font(.system(size: 10, weight: .bold))
                                .tracking(0.8)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule().fill(Color.green)
                                )
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }
            }

            // Activate section (only when unlicensed)
            if !store.licenseState.isLicensed {
                SettingsSection(CommonCopy.activate()) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(SettingsCopy.licenseEnterKey())
                            .font(.system(size: 13))
                            .foregroundStyle(SettingsTheme.textSecondary)
                            .padding(.horizontal, 18)
                            .padding(.top, 14)

                        HStack(spacing: 10) {
                            TextField("GILT-XXXX-XXXX-XXXX", text: $licenseKeyInput)
                                .font(.system(size: 13, design: .monospaced))
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(SettingsTheme.sidebarBackground)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(SettingsTheme.border, lineWidth: 0.5)
                                )

                            Button {
                                Task {
                                    await store.activateLicenseKey(licenseKeyInput)
                                    if store.licenseState.isLicensed {
                                        licenseKeyInput = ""
                                    }
                                }
                            } label: {
                                Group {
                                    if store.isLicenseBusy {
                                        ProgressView()
                                            .controlSize(.small)
                                            .frame(width: 14, height: 14)
                                    } else {
                                        Text(CommonCopy.activate())
                                    }
                                }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(licenseKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                              ? SettingsTheme.gold.opacity(0.4)
                                              : SettingsTheme.gold)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(licenseKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isLicenseBusy)
                        }
                        .padding(.horizontal, 18)

                        if let error = store.licenseErrorMessage {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 11))
                                Text(error)
                                    .font(.system(size: 12))
                            }
                            .foregroundStyle(.red)
                            .padding(.horizontal, 18)
                        }

                        SettingsDivider()

                        HStack {
                            Text(SettingsCopy.licenseNoLicense())
                                .font(.system(size: 12))
                                .foregroundStyle(SettingsTheme.textSecondary)

                            Button {
                                if let url = URL(string: PolarConstants.checkoutURL) {
                                    NSWorkspace.shared.open(url)
                                }
                            } label: {
                                Text(SettingsCopy.licenseBuyForTen())
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(SettingsTheme.gold)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 14)
                    }
                }
            }

            // Manage section (only when licensed)
            if store.licenseState.isLicensed {
                SettingsSection(CommonCopy.manage()) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(SettingsCopy.licenseThisMac())
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(SettingsTheme.textPrimary)
                                Text(LicenseVault.machineLabel)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(SettingsTheme.textTertiary)
                            }

                            Spacer()

                            Button {
                                Task {
                                    await store.refreshLicenseStatus()
                                }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(SettingsTheme.gold)
                                    .padding(8)
                                    .background(
                                        Circle()
                                            .fill(SettingsTheme.gold.opacity(0.1))
                                    )
                            }
                            .buttonStyle(.plain)
                            .disabled(store.isLicenseBusy)
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 14)

                        SettingsDivider()

                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(SettingsCopy.licenseSwitchingMacs())
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(SettingsTheme.textPrimary)
                                Text(SettingsCopy.licenseSwitchingMacsBody())
                                    .font(.system(size: 12))
                                    .foregroundStyle(SettingsTheme.textSecondary)
                            }

                            Spacer()

                            Button {
                                Task { await store.deactivateCurrentDevice() }
                            } label: {
                                Text(SettingsCopy.removeLicense())
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.red)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.red.opacity(0.1))
                                    )
                            }
                            .buttonStyle(.plain)
                            .disabled(store.isLicenseBusy)
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 14)
                    }
                }
            }

            OpenSourceCreditsSection()

            Spacer()
        }
    }

    // MARK: - License Status Helpers

    private var licenseStatusColor: Color {
        switch store.appAccessState {
        case .fullAccess: return .green
        case .trialActive: return SettingsTheme.gold
        case .locked: return .red
        }
    }

    private var licenseStatusIcon: String {
        switch store.appAccessState {
        case .fullAccess: return "checkmark.seal.fill"
        case .trialActive: return "clock.fill"
        case .locked: return "lock.fill"
        }
    }

    private var licenseStatusTitle: String {
        switch store.appAccessState {
        case .fullAccess:
            return L10n.string("settings.license.status.licensed", default: "Licensed")
        case .trialActive:
            return L10n.string("settings.license.status.trial", default: "Free Trial")
        case .locked:
            return L10n.string("settings.license.status.expired", default: "Trial Expired")
        }
    }

    private var licenseStatusSubtitle: String {
        switch store.appAccessState {
        case .fullAccess:
            return String(
                format: L10n.string(
                    "settings.license.status.fullAccess",
                    default: "%@ is fully activated on this Mac"
                ),
                AppBrand.displayName
            )
        case .trialActive(let remaining):
            let hours = Int(remaining) / 3600
            let minutes = (Int(remaining) % 3600) / 60
            if hours > 0 {
                return String(
                    format: L10n.string(
                        "settings.license.status.trialHours",
                        default: "%dh %dm remaining in your trial"
                    ),
                    hours,
                    minutes
                )
            } else {
                return String(
                    format: L10n.string(
                        "settings.license.status.trialMinutes",
                        default: "%dm remaining in your trial"
                    ),
                    minutes
                )
            }
        case .locked:
            return String(
                format: L10n.string(
                    "settings.license.status.enterKey",
                    default: "Enter a license key to continue using %@."
                ),
                AppBrand.displayName
            )
        }
    }

    private func applyRequestedTab(_ rawValue: String) {
        guard let requestedTab = SettingsTab(navigationRawValue: rawValue) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedTab = requestedTab
        }
    }

    private func requestFolderDeletion(_ folder: ClipFolderModel) {
        pendingFolderDeletionID = folder.folderID
        pendingFolderDeletionName = folder.displayName
    }

    /// Opens an NSOpenPanel for the user to pick a wallpaper image for a specific
    /// surface, then hands the stored filename back to the caller.
    private func pickCustomWallpaper(
        slot: WallpaperSlot = .clipboard,
        onImported: ((String) -> Void)? = nil
    ) {
        let panel = NSOpenPanel()
        panel.title = "Choose Wallpaper Image"
        panel.allowedContentTypes = [.image]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModalInFront() == .OK, let url = panel.url else { return }

        if let filename = BackgroundWallpaper.importCustomImage(from: url, slot: slot) {
            if let onImported {
                onImported(filename)
                return
            }

            store.settings.customWallpaperFilename = filename
            store.settings.backgroundWallpaper = .custom
            store.settings.wallpaperOffsetX = 0.5
            store.settings.wallpaperOffsetY = 0.5
        }
    }
}


// MARK: - Smart Category Row Content

private struct SmartCategoryRowContent<Panel: View>: View {
    let category: SmartCategory
    let enabled: Bool
    let smartFolder: ClipFolderModel?
    let accentColor: Color
    let isExpanded: Bool
    let onToggle: (Bool) -> Void
    let onChevronTap: () -> Void
    @ViewBuilder let folderCustomizationPanel: (ClipFolderModel) -> Panel
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(enabled ? 0.15 : 0.08))
                        .frame(width: 32, height: 32)
                    
                    if let smartFolder {
                        FolderIconView(
                            folder: smartFolder,
                            accentColor: accentColor.opacity(enabled ? 1 : 0.4),
                            textColor: SettingsTheme.textPrimary.opacity(enabled ? 0.9 : 0.4),
                            fontSize: 14,
                            circleSize: 0
                        )
                    } else {
                        Image(systemName: category.systemImage)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(accentColor.opacity(enabled ? 1 : 0.4))
                    }
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(smartFolder?.displayName ?? category.folderName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(SettingsTheme.textPrimary.opacity(enabled ? 1 : 0.5))
                    
                    Text(category.settingsDescription)
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsTheme.textSecondary)
                }
                
                Spacer()
                
                Toggle("", isOn: Binding(
                    get: { enabled },
                    set: { onToggle($0) }
                ))
                .toggleStyle(GoldToggleStyle())
                
                if enabled {
                    Button(action: onChevronTap) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(SettingsTheme.textTertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            
            if isExpanded, let folder = smartFolder {
                folderCustomizationPanel(folder)
            }
        }
    }
}

// MARK: - User Folder Row Content

private struct UserFolderRowContent<Panel: View>: View {
    let folder: ClipFolderModel
    let accentColor: Color
    let isVisible: Bool
    let isExpanded: Bool
    let isFirst: Bool
    let isLast: Bool
    let onToggle: (Bool) -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onChevronTap: () -> Void
    @ViewBuilder let folderCustomizationPanel: () -> Panel
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(isVisible ? 0.15 : 0.08))
                        .frame(width: 32, height: 32)
                    
                    FolderIconView(
                        folder: folder,
                        accentColor: accentColor.opacity(isVisible ? 1 : 0.4),
                        textColor: SettingsTheme.textPrimary.opacity(isVisible ? 1 : 0.45),
                        fontSize: 14,
                        circleSize: 0
                    )
                }
                
                Text(folder.displayName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SettingsTheme.textPrimary.opacity(isVisible ? 1 : 0.5))
                
                Spacer()

                Toggle("", isOn: Binding(
                    get: { isVisible },
                    set: { onToggle($0) }
                ))
                .toggleStyle(GoldToggleStyle())
                
                // Reorder buttons
                HStack(spacing: 2) {
                    Button(action: onMoveUp) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(SettingsTheme.textTertiary.opacity(isFirst ? 0.3 : 1))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .disabled(isFirst)
                    
                    Button(action: onMoveDown) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(SettingsTheme.textTertiary.opacity(isLast ? 0.3 : 1))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLast)
                }

                Button(action: onChevronTap) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SettingsTheme.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(isVisible ? 1 : 0)
                .allowsHitTesting(isVisible)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            
            if isExpanded {
                folderCustomizationPanel()
            }
        }
    }
}

// MARK: - Wallpaper Position Preview

private struct WallpaperPositionPreview: View {
    @EnvironmentObject private var store: ClipboardStore
    @ObservedObject var wallpaperPreview: WallpaperPreviewState
    @State private var previewMode: ViewMode = .tray
    @State private var dragStartOffsetX: Double?
    @State private var dragStartOffsetY: Double?
    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 8) {
            previewModePicker

            GeometryReader { geo in
                let wallpaper = store.settings.backgroundWallpaper
                let wallpaperOffsets = wallpaperPreview.resolved(using: store.settings)
                let oX = wallpaperOffsets.x
                let oY = wallpaperOffsets.y
                let maxW = geo.size.width
                let maxH = geo.size.height
                let aspect = max(previewMode.previewAspectRatio, 0.1)
                let widthByHeight = maxH * aspect
                let frameWidth = min(maxW, widthByHeight)
                let frameHeight = frameWidth / aspect
                let previewImage = wallpaper.loadImage(customFilename: store.settings.customWallpaperFilename)

                VStack {
                    ZStack {
                        if let nsImage = previewImage {
                            let imgSize = nsImage.size
                            let imageAspect = imgSize.width / imgSize.height
                            let containerAspect = frameWidth / frameHeight
                            let scale: CGFloat = imageAspect > containerAspect
                                ? frameHeight / imgSize.height
                                : frameWidth / imgSize.width
                            let scaledW = imgSize.width * scale
                            let scaledH = imgSize.height * scale
                            let overflowX = max(scaledW - frameWidth, 0)
                            let overflowY = max(scaledH - frameHeight, 0)
                            let pixelX = (0.5 - oX) * overflowX
                            let pixelY = (0.5 - oY) * overflowY

                            Image(nsImage: nsImage)
                                .resizable()
                                .frame(width: scaledW, height: scaledH)
                                .offset(x: pixelX, y: pixelY)
                        } else {
                            Color.black.opacity(0.3)
                        }

                        Color.black.opacity(isDragging ? 0.38 : 0.25)

                        // 2D handle
                        VStack(spacing: 3) {
                            Image(systemName: "arrow.up")
                            HStack(spacing: 7) {
                                Image(systemName: "arrow.left")
                                RoundedRectangle(cornerRadius: 2)
                                    .frame(width: 24, height: 4)
                                Image(systemName: "arrow.right")
                            }
                            Image(systemName: "arrow.down")
                        }
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.white.opacity(isDragging ? 0.92 : 0.72))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(
                            Capsule()
                                .fill(.black.opacity(isDragging ? 0.54 : 0.34))
                        )
                        .animation(.easeInOut(duration: 0.14), value: isDragging)
                    }
                    .frame(width: frameWidth, height: frameHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                if dragStartOffsetX == nil || dragStartOffsetY == nil {
                                    let startOffsets = wallpaperPreview.resolved(using: store.settings)
                                    dragStartOffsetX = startOffsets.x
                                    dragStartOffsetY = startOffsets.y
                                    isDragging = true
                                }
                                guard let startX = dragStartOffsetX, let startY = dragStartOffsetY else { return }

                                guard let imgSize = previewImage?.size, imgSize.width > 0, imgSize.height > 0 else { return }

                                let imageAspect = imgSize.width / imgSize.height
                                let containerAspect = frameWidth / frameHeight
                                let scale: CGFloat = imageAspect > containerAspect
                                    ? frameHeight / imgSize.height
                                    : frameWidth / imgSize.width
                                let overflowX = max(imgSize.width * scale - frameWidth, 0)
                                let overflowY = max(imgSize.height * scale - frameHeight, 0)

                                // If overflow is zero in this preview shape, fallback to gentle normalized movement
                                // so users can still adjust that axis for other view modes.
                                let fallbackX = Double(value.translation.width / max(frameWidth, 1)) * 0.4
                                let fallbackY = Double(value.translation.height / max(frameHeight, 1)) * 0.4
                                let deltaX = overflowX > 0 ? Double(value.translation.width / overflowX) : fallbackX
                                let deltaY = overflowY > 0 ? Double(value.translation.height / overflowY) : fallbackY

                                let newX = min(max(startX + deltaX, 0), 1)
                                let newY = min(max(startY + deltaY, 0), 1)
                                store.updateWallpaperOffsetLive(x: newX, y: newY)
                            }
                            .onEnded { _ in
                                store.commitWallpaperOffsetLive()
                                dragStartOffsetX = nil
                                dragStartOffsetY = nil
                                isDragging = false
                            }
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack(spacing: 8) {
                Text(CommonCopy.horizontal())
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 62, alignment: .leading)
                Slider(
                    value: Binding(
                        get: { wallpaperPreview.resolved(using: store.settings).x },
                        set: { newValue in
                            let currentY = wallpaperPreview.liveOffsets?.y
                                ?? dragStartOffsetY
                                ?? store.settings.wallpaperOffsetY
                            store.updateWallpaperOffsetLive(x: newValue, y: currentY)
                        }
                    ),
                    in: 0...1,
                    onEditingChanged: { editing in
                        if !editing {
                            store.commitWallpaperOffsetLive()
                        }
                    }
                )
                Text(CommonCopy.leftRight())
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .frame(width: 52, alignment: .trailing)
            }

            HStack(spacing: 8) {
                Text(CommonCopy.vertical())
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 62, alignment: .leading)
                Slider(
                    value: Binding(
                        get: { wallpaperPreview.resolved(using: store.settings).y },
                        set: { newValue in
                            let currentX = wallpaperPreview.liveOffsets?.x
                                ?? dragStartOffsetX
                                ?? store.settings.wallpaperOffsetX
                            store.updateWallpaperOffsetLive(x: currentX, y: newValue)
                        }
                    ),
                    in: 0...1,
                    onEditingChanged: { editing in
                        if !editing {
                            store.commitWallpaperOffsetLive()
                        }
                    }
                )
                Text(CommonCopy.upDown())
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .frame(width: 52, alignment: .trailing)
            }
        }
        .onAppear {
            previewMode = store.settings.viewMode
        }
        .onChange(of: store.settings.viewMode) { _, newValue in
            previewMode = newValue
        }
    }

    private var previewModePicker: some View {
        HStack(spacing: 6) {
            ForEach(ViewMode.allCases) { mode in
                let isSelected = previewMode == mode
                Button {
                    previewMode = mode
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 9.5, weight: .medium))
                        Text(mode.label)
                            .font(.system(size: 9.5, weight: isSelected ? .semibold : .regular))
                    }
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.72))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(isSelected ? Color.white.opacity(0.18) : Color.white.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Storage Location Card

private struct StorageLocationCard: View {
    let store: ClipboardStore
    @State private var copiedField: CopiedField?

    private enum CopiedField { case folder, database }

    private var folderDisplay: String { (store.storageFolderPath as NSString).abbreviatingWithTildeInPath }
    private var databaseDisplay: String { (store.storageDatabasePath as NSString).abbreviatingWithTildeInPath }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(SettingsTheme.gold.opacity(0.14))
                    Image(systemName: "externaldrive.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(SettingsTheme.gold)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(SettingsCopy.storageLivesHereTitle())
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SettingsTheme.textPrimary)
                    Text(SettingsCopy.storageLivesHereBody())
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Button {
                    store.browseStorageFolderInFinder()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right.square.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text(SettingsCopy.revealInFinder())
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [SettingsTheme.goldLight, SettingsTheme.gold],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .shadow(color: SettingsTheme.gold.opacity(0.35), radius: 6, y: 2)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)

            Divider().background(SettingsTheme.divider)

            VStack(spacing: 10) {
                pathRow(
                    label: "Folder",
                    icon: "folder.fill",
                    path: folderDisplay,
                    field: .folder,
                    action: { store.browseStorageFolderInFinder() }
                )
                pathRow(
                    label: "Database",
                    icon: "cylinder.split.1x2.fill",
                    path: databaseDisplay,
                    field: .database,
                    action: {
                        let url = URL(fileURLWithPath: store.storageDatabasePath)
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                )
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
    }

    @ViewBuilder
    private func pathRow(label: String, icon: String, path: String, field: CopiedField, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SettingsTheme.textSecondary)
                .frame(width: 16)

            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(SettingsTheme.textTertiary)
                .frame(width: 64, alignment: .leading)

            Text(path)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(SettingsTheme.textPrimary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                copy(path: field == .folder ? store.storageFolderPath : store.storageDatabasePath, field: field)
            } label: {
                Image(systemName: copiedField == field ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(copiedField == field ? .green : SettingsTheme.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(SettingsTheme.background)
                    )
            }
            .buttonStyle(.plain)
            .help("Copy path")

            Button(action: action) {
                Image(systemName: "arrow.up.forward.app.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SettingsTheme.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(SettingsTheme.background)
                    )
            }
            .buttonStyle(.plain)
            .help("Show in Finder")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(SettingsTheme.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(SettingsTheme.border.opacity(0.6), lineWidth: 0.5)
                )
        )
    }

    private func copy(path: String, field: CopiedField) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        withAnimation(.easeOut(duration: 0.15)) { copiedField = field }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            if copiedField == field {
                withAnimation(.easeOut(duration: 0.2)) { copiedField = nil }
            }
        }
    }
}

private extension ViewMode {
    var previewAspectRatio: CGFloat {
        switch self {
        case .tray:
            return 4.6
        case .drawer:
            return 0.42
        case .panel:
            return 320.0 / 520.0
        case .grid:
            return 580.0 / 500.0
        case .radial:
            return 1.0
        case .workspace:
            return 1240.0 / 760.0
        }
    }
}
