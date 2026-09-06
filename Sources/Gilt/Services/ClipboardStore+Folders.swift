import AppKit
import Foundation

extension ClipboardStore {
    // MARK: - Folder CRUD

    /// Keep folder editing together so the main store file stays focused on clipboard ingest/search.

    var visibleFolders: [ClipFolderModel] {
        folders.filter { settings.isFolderVisibleInTabs($0) }
    }

    func setUserFolderVisibility(id: UUID, isVisible: Bool) {
        guard let folder = folders.first(where: { $0.folderID == id }),
              folder.isSystem == false,
              folder.isSmartFolder == false else { return }
        settings.setCustomFolderVisibility(isVisible, for: id)
    }

    /// Any tab can be hidden from the bar except the home Clipboard tab and
    /// smart folders (which are toggled via Smart Categories settings, where
    /// disabling actually deletes the folder rather than hiding it).
    func canHideFolderFromTabs(_ folder: ClipFolderModel) -> Bool {
        folder.folderID != ClipFolderModel.clipboardID && !folder.isSmartFolder
    }

    /// Hide a custom or linked skill folder from the tab bar without deleting it.
    /// The folder reappears once shown again from Settings.
    func hideFolderFromTabs(id: UUID) {
        guard let folder = folders.first(where: { $0.folderID == id }),
              canHideFolderFromTabs(folder) else { return }
        settings.setCustomFolderVisibility(false, for: id)
    }

    func showFolderInTabs(id: UUID) {
        settings.setCustomFolderVisibility(true, for: id)
    }

    /// Folders currently hidden from the tab bar, for the Settings unhide list.
    var hiddenTabFolders: [ClipFolderModel] {
        folders.filter { canHideFolderFromTabs($0) && !settings.isFolderVisibleInTabs($0) }
    }

    func reconcileFolderSelectionWithVisibility() {
        if !visibleFolders.contains(where: { $0.folderID == selectedFolderID }) {
            selectedFolderID = visibleFolders.first?.folderID ?? ClipFolderModel.clipboardID
        }
    }

    func createFolder() {
        let userFolders = folders.filter { $0.isSystem == false }.count + 1
        let name = "Folder \(userFolders)"
        let paletteIndex = folders.count % FolderColorToken.allCases.count
        let folder = ClipFolderModel(
            folderID: UUID(),
            name: name,
            colorRaw: FolderColorToken.allCases[paletteIndex].rawValue,
            colorModeRaw: FolderColorMode.text.rawValue,
            isSystem: false,
            sortOrder: folders.count
        )
        modelContext.insert(folder)
        save()
        refreshFolders()
        selectedFolderID = folder.folderID
        Analytics.folderCreated(totalCount: folders.filter { !$0.isSystem }.count)
    }

    func setFolderColorMode(id: UUID, mode: FolderColorMode) {
        guard let folder = folders.first(where: { $0.folderID == id }) else { return }
        folder.colorModeRaw = mode.rawValue
        save()
        refreshFolders()
    }

    func setFolderAccentColor(id: UUID, color: FolderColorToken) {
        guard let folder = folders.first(where: { $0.folderID == id }) else { return }
        let previousAccent = folder.colorRaw
        folder.colorRaw = color.rawValue
        if folder.fillColorRaw == previousAccent {
            folder.fillColorRaw = color.rawValue
        }
        save()
        refreshFolders()
    }

    func setFolderFillColor(id: UUID, color: FolderColorToken) {
        guard let folder = folders.first(where: { $0.folderID == id }) else { return }
        folder.fillColorRaw = color.rawValue
        save()
        refreshFolders()
    }

    func setFolderTextColorMode(id: UUID, mode: FolderTextColorMode) {
        guard let folder = folders.first(where: { $0.folderID == id }) else { return }
        folder.textColorModeRaw = mode.rawValue
        if mode != .custom {
            folder.customTextColorRaw = nil
        } else if folder.customTextColorRaw == nil {
            folder.customTextColorRaw = folder.colorRaw
        }
        save()
        refreshFolders()
    }

    func setFolderCustomTextColor(id: UUID, color: FolderColorToken) {
        guard let folder = folders.first(where: { $0.folderID == id }) else { return }
        folder.textColorModeRaw = FolderTextColorMode.custom.rawValue
        folder.customTextColorRaw = color.rawValue
        save()
        refreshFolders()
    }

    func setFolderIcon(id: UUID, icon: FolderIcon?) {
        guard let folder = folders.first(where: { $0.folderID == id }) else { return }
        folder.folderIconRaw = icon?.rawValue
        save()
        refreshFolders()
    }

    // MARK: - Resolved Color Setters

    func setFolderAccentColorResolved(id: UUID, color: ResolvedColor) {
        guard let folder = folders.first(where: { $0.folderID == id }) else { return }
        let previousAccent = folder.colorRaw
        folder.colorRaw = color.rawString
        if folder.fillColorRaw == previousAccent {
            folder.fillColorRaw = color.rawString
        }
        save()
        refreshFolders()
    }

    func setFolderFillColorResolved(id: UUID, value: FolderColorValue) {
        guard let folder = folders.first(where: { $0.folderID == id }) else { return }
        folder.fillColorRaw = value.rawString
        save()
        refreshFolders()
    }

    func setFolderCustomTextColorResolved(id: UUID, color: ResolvedColor) {
        guard let folder = folders.first(where: { $0.folderID == id }) else { return }
        folder.textColorModeRaw = FolderTextColorMode.custom.rawValue
        folder.customTextColorRaw = color.rawString
        save()
        refreshFolders()
    }

    // MARK: - Bulk Folder Editing

    func bulkSetFolderColorMode(ids: Set<UUID>, mode: FolderColorMode) {
        for id in ids {
            guard let folder = folders.first(where: { $0.folderID == id }) else { continue }
            folder.colorModeRaw = mode.rawValue
            // When switching to fill, always generate a fresh gradient from the accent color
            // so every folder gets a consistent, visible fill.
            if mode == .fill {
                let hex = folder.resolvedColor.color.hexString
                let darkened = darkenHex(hex, by: 0.35)
                folder.fillColorRaw = "grad:\(hex),\(darkened),135.0"
            }
        }
        save()
        refreshFolders()
    }

    /// Darken a hex color string by a factor (0..1) for gradient generation.
    private func darkenHex(_ hex: String, by factor: Double) -> String {
        let resolved = ResolvedColor.hex(hex)
        let nsColor = NSColor(resolved.color).usingColorSpace(.sRGB) ?? NSColor.gray
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        nsColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        r = max(0, r * (1 - factor))
        g = max(0, g * (1 - factor))
        b = max(0, b * (1 - factor))
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }

    func bulkSetFolderAccentColor(ids: Set<UUID>, color: ResolvedColor) {
        for id in ids {
            guard let folder = folders.first(where: { $0.folderID == id }) else { continue }
            folder.colorRaw = color.rawString
            // Always sync fill color in bulk — user expects all folders to match
            if folder.colorMode == .fill {
                let hex = color.color.hexString
                let darkened = darkenHex(hex, by: 0.35)
                folder.fillColorRaw = "grad:\(hex),\(darkened),135.0"
            } else {
                folder.fillColorRaw = color.rawString
            }
        }
        save()
        refreshFolders()
    }

    func bulkSetFolderTextColorMode(ids: Set<UUID>, mode: FolderTextColorMode) {
        for id in ids {
            guard let folder = folders.first(where: { $0.folderID == id }) else { continue }
            folder.textColorModeRaw = mode.rawValue
            if mode != .custom {
                folder.customTextColorRaw = nil
            } else if folder.customTextColorRaw == nil {
                folder.customTextColorRaw = folder.colorRaw
            }
        }
        save()
        refreshFolders()
    }

    func bulkSetFolderCustomTextColor(ids: Set<UUID>, color: ResolvedColor) {
        for id in ids {
            guard let folder = folders.first(where: { $0.folderID == id }) else { continue }
            folder.textColorModeRaw = FolderTextColorMode.custom.rawValue
            folder.customTextColorRaw = color.rawString
        }
        save()
        refreshFolders()
    }

    // MARK: - Color Presets

    func saveColorPreset(_ preset: ColorPreset) {
        settings.savedColorPresets.append(preset)
    }

    func deleteColorPreset(_ presetID: UUID) {
        settings.savedColorPresets.removeAll { $0.id == presetID }
    }

    func renameFolder(id: UUID, name: String) {
        guard let folder = folders.first(where: { $0.folderID == id }) else { return }
        guard folder.applyDisplayNameOverride(name) else { return }
        save()
        refreshFolders()
    }

    func setAutoCategorizationLock(for folderID: UUID, locked: Bool) {
        guard let folder = folders.first(where: { $0.folderID == folderID }) else { return }
        guard folder.isAutoCategorizationLocked != locked else { return }
        folder.isAutoCategorizationLocked = locked
        save()
        refreshFolders()
    }

    func moveFolderLeft(id: UUID) {
        guard let index = folders.firstIndex(where: { $0.folderID == id }), index > 0 else { return }
        let current = folders[index]
        let neighbor = folders[index - 1]
        let temp = current.sortOrder
        current.sortOrder = neighbor.sortOrder
        neighbor.sortOrder = temp
        save()
        refreshFolders()
    }

    func moveFolderRight(id: UUID) {
        guard let index = folders.firstIndex(where: { $0.folderID == id }), index < folders.count - 1 else { return }
        let current = folders[index]
        let neighbor = folders[index + 1]
        let temp = current.sortOrder
        current.sortOrder = neighbor.sortOrder
        neighbor.sortOrder = temp
        save()
        refreshFolders()
    }
}
