import Foundation

// MARK: - Legacy (migration only — used to decode state.json during one-time migration)

struct ClipFolder: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var color: FolderColorToken
    var colorMode: FolderColorMode
    var fillColor: FolderColorToken
    var textColorMode: FolderTextColorMode
    var customTextColor: FolderColorToken?
    var isSystem: Bool

    init(
        id: UUID,
        name: String,
        color: FolderColorToken,
        colorMode: FolderColorMode = .dot,
        fillColor: FolderColorToken? = nil,
        textColorMode: FolderTextColorMode = .auto,
        customTextColor: FolderColorToken? = nil,
        isSystem: Bool
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.colorMode = colorMode
        self.fillColor = fillColor ?? color
        self.textColorMode = textColorMode
        self.customTextColor = customTextColor
        self.isSystem = isSystem
    }

    static let clipboardID = UUID(uuidString: "C44A3392-3BA4-4DBA-A61C-04A731A3C3F6")!

    static func defaults() -> [ClipFolder] {
        [
            ClipFolder(
                id: clipboardID,
                name: "Clipboard",
                color: .white,
                colorMode: .fill,
                fillColor: .slate,
                isSystem: true
            )
        ]
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, color, colorMode, fillColor, textColorMode, customTextColor, isSystem
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        color = try container.decode(FolderColorToken.self, forKey: .color)
        colorMode = try container.decodeIfPresent(FolderColorMode.self, forKey: .colorMode) ?? .dot
        fillColor = try container.decodeIfPresent(FolderColorToken.self, forKey: .fillColor) ?? color
        textColorMode = try container.decodeIfPresent(FolderTextColorMode.self, forKey: .textColorMode) ?? .auto
        customTextColor = try container.decodeIfPresent(FolderColorToken.self, forKey: .customTextColor)
        isSystem = try container.decode(Bool.self, forKey: .isSystem)
    }
}

// MARK: - Legacy (migration only)

struct ClipItem: Identifiable, Codable, Hashable {
    let id: UUID
    let type: ClipType
    var title: String
    var previewText: String
    var textValue: String?
    var urlValue: String?
    var imagePNGBase64: String?
    var sourceAppName: String
    var sourceBundleID: String?
    let createdAt: Date
    var folderIDs: [UUID]

    var imageData: Data? {
        guard let imagePNGBase64 else { return nil }
        return Data(base64Encoded: imagePNGBase64)
    }
}

// MARK: - Legacy (migration only)

struct PersistedState: Codable {
    var clips: [ClipItem]
    var folders: [ClipFolder]
    var settings: AppSettings
}
