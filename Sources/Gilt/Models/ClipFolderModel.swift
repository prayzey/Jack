import Foundation
import SwiftData

@Model
final class ClipFolderModel {
    var folderID: UUID
    var name: String
    var folderIconRaw: String?
    var colorRaw: String
    var colorModeRaw: String
    var fillColorRaw: String
    var textColorModeRaw: String
    var customTextColorRaw: String?
    var isSystem: Bool
    var isAutoCategorizationLocked: Bool
    var sortOrder: Int
    var smartCategoryRaw: String?
    var usesLocalizedSystemName: Bool?

    var clips: [ClipItemModel] = []
    var separators: [FolderSeparatorModel] = []

    init(
        folderID: UUID = UUID(),
        name: String,
        folderIconRaw: String? = nil,
        colorRaw: String = FolderColorToken.slate.rawValue,
        colorModeRaw: String = FolderColorMode.dotAndText.rawValue,
        fillColorRaw: String? = nil,
        textColorModeRaw: String = FolderTextColorMode.auto.rawValue,
        customTextColorRaw: String? = nil,
        isSystem: Bool = false,
        isAutoCategorizationLocked: Bool = false,
        sortOrder: Int = 0,
        smartCategoryRaw: String? = nil,
        usesLocalizedSystemName: Bool? = nil,
        clips: [ClipItemModel] = [],
        separators: [FolderSeparatorModel] = []
    ) {
        self.folderID = folderID
        self.name = name
        self.folderIconRaw = folderIconRaw
        self.colorRaw = colorRaw
        self.colorModeRaw = colorModeRaw
        self.fillColorRaw = fillColorRaw ?? colorRaw
        self.textColorModeRaw = textColorModeRaw
        self.customTextColorRaw = customTextColorRaw
        self.isSystem = isSystem
        self.isAutoCategorizationLocked = isAutoCategorizationLocked
        self.sortOrder = sortOrder
        self.smartCategoryRaw = smartCategoryRaw
        self.usesLocalizedSystemName = usesLocalizedSystemName
        self.clips = clips
        self.separators = separators
    }

    // MARK: - Computed Helpers

    var color: FolderColorToken {
        FolderColorToken(rawValue: colorRaw) ?? .slate
    }

    var colorMode: FolderColorMode {
        FolderColorMode(rawValue: colorModeRaw) ?? .dot
    }

    var fillColor: FolderColorToken {
        FolderColorToken(rawValue: fillColorRaw) ?? color
    }

    var textColorMode: FolderTextColorMode {
        FolderTextColorMode(rawValue: textColorModeRaw) ?? .auto
    }

    var customTextColor: FolderColorToken? {
        guard let raw = customTextColorRaw else { return nil }
        return FolderColorToken(rawValue: raw)
    }

    var smartCategory: SmartCategory? {
        guard let raw = smartCategoryRaw else { return nil }
        return SmartCategory(rawValue: raw)
    }

    var customFolderIcon: FolderIcon? {
        FolderIcon(rawValue: folderIconRaw)
    }

    var effectiveFolderIcon: FolderIcon? {
        if let customFolderIcon {
            return customFolderIcon
        }
        guard let smartCategory else { return nil }
        return .symbol(smartCategory.systemImage)
    }

    // MARK: - Resolved Color Helpers (support hex + gradient strings)

    var resolvedColor: ResolvedColor {
        ResolvedColor(rawString: colorRaw)
    }

    var resolvedFillColor: FolderColorValue {
        FolderColorValue(rawString: fillColorRaw)
    }

    var resolvedCustomTextColor: ResolvedColor? {
        guard let raw = customTextColorRaw else { return nil }
        return ResolvedColor(rawString: raw)
    }

    var isSmartFolder: Bool {
        smartCategory != nil
    }

    var isClipboardFolder: Bool {
        folderID == Self.clipboardID
    }

    var isBulkEditable: Bool {
        !isClipboardFolder
    }

    var supportsSeparators: Bool {
        !isClipboardFolder
    }

    // MARK: - Static

    static let clipboardID = UUID(uuidString: "C44A3392-3BA4-4DBA-A61C-04A731A3C3F6")!
}
