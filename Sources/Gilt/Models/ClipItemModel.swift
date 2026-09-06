import Foundation
import SwiftData

@Model
final class ClipItemModel {
    var clipID: UUID
    var typeRaw: String
    var title: String
    var previewText: String
    var textValue: String?
    var urlValue: String?

    @Attribute(.externalStorage)
    var imageData: Data?
    var recognizedText: String?
    var ocrStatusRaw: String
    var ocrUpdatedAt: Date?
    var ocrErrorCode: String?

    var sourceAppName: String
    var sourceBundleID: String?
    var createdAt: Date

    // Persisted link metadata — no more re-fetching every launch
    var linkPageTitle: String?
    var linkFaviconURLString: String?

    // Rich link preview metadata
    var linkThumbnailURLString: String?  // "" = attempted but none found; nil = never attempted
    @Attribute(.externalStorage)
    var linkThumbnailData: Data?         // Locally cached thumbnail image
    var linkDescriptionText: String?     // og:description
    var linkPlatformRaw: String?         // LinkPlatform raw value
    var linkVideoDuration: String?       // Formatted "3:42" or "1:02:30"

    // Smart categorization properties (raw strings for SwiftData compat)
    var contentTagsRaw: String
    var isSensitive: Bool
    var detectedLanguageRaw: String?
    var sensitiveExpiresAt: Date?

    /// Comma-separated AI-generated topic keywords (lowercased), or nil if never enriched.
    /// Optional so adding it is a lightweight SwiftData migration for existing stores.
    /// Used to make clips findable by topic in search.
    var aiKeywordsRaw: String?

    /// SHA-256 content fingerprint for duplicate detection.
    /// Empty string means not yet computed (legacy clips); backfilled on launch.
    var contentHash: String

    /// Manual sort order for drag-to-reorder. Higher values appear first (newest).
    /// Defaults to 0; new clips get max + 1 so they land at the front.
    var sortOrder: Int
    /// Pinned clips stay grouped at the start of each folder view.
    var isPinned: Bool

    @Relationship(inverse: \ClipFolderModel.clips)
    var folders: [ClipFolderModel]

    init(
        clipID: UUID = UUID(),
        typeRaw: String,
        title: String,
        previewText: String,
        textValue: String? = nil,
        urlValue: String? = nil,
        imageData: Data? = nil,
        recognizedText: String? = nil,
        ocrStatusRaw: String = "none",
        ocrUpdatedAt: Date? = nil,
        ocrErrorCode: String? = nil,
        sourceAppName: String,
        sourceBundleID: String? = nil,
        createdAt: Date = Date(),
        linkPageTitle: String? = nil,
        linkFaviconURLString: String? = nil,
        contentTagsRaw: String = "",
        isSensitive: Bool = false,
        detectedLanguageRaw: String? = nil,
        sensitiveExpiresAt: Date? = nil,
        aiKeywordsRaw: String? = nil,
        contentHash: String = "",
        sortOrder: Int = 0,
        isPinned: Bool = false,
        folders: [ClipFolderModel] = []
    ) {
        self.clipID = clipID
        self.typeRaw = typeRaw
        self.title = title
        self.previewText = previewText
        self.textValue = textValue
        self.urlValue = urlValue
        self.imageData = imageData
        self.recognizedText = recognizedText
        self.ocrStatusRaw = ocrStatusRaw
        self.ocrUpdatedAt = ocrUpdatedAt
        self.ocrErrorCode = ocrErrorCode
        self.sourceAppName = sourceAppName
        self.sourceBundleID = sourceBundleID
        self.createdAt = createdAt
        self.linkPageTitle = linkPageTitle
        self.linkFaviconURLString = linkFaviconURLString
        self.contentTagsRaw = contentTagsRaw
        self.isSensitive = isSensitive
        self.detectedLanguageRaw = detectedLanguageRaw
        self.sensitiveExpiresAt = sensitiveExpiresAt
        self.aiKeywordsRaw = aiKeywordsRaw
        self.contentHash = contentHash
        self.sortOrder = sortOrder
        self.isPinned = isPinned
        self.folders = folders
    }

    // MARK: - Computed Helpers

    var clipType: ClipType {
        ClipType(rawValue: typeRaw) ?? .text
    }

    var linkFaviconURL: URL? {
        guard let urlString = linkFaviconURLString else { return nil }
        return URL(string: urlString)
    }

    var linkPlatform: LinkPlatform? {
        guard let raw = linkPlatformRaw else { return nil }
        return LinkPlatform(rawValue: raw)
    }

    var contentTags: Set<ContentTag> {
        get {
            guard !contentTagsRaw.isEmpty else { return [] }
            return Set(contentTagsRaw.components(separatedBy: ",").compactMap { ContentTag(rawValue: $0) })
        }
        set {
            contentTagsRaw = newValue.map(\.rawValue).sorted().joined(separator: ",")
        }
    }

    var detectedLanguage: DetectedLanguage? {
        get {
            guard let raw = detectedLanguageRaw else { return nil }
            return DetectedLanguage(rawValue: raw)
        }
        set {
            detectedLanguageRaw = newValue?.rawValue
        }
    }

    var aiKeywords: [String] {
        get {
            guard let raw = aiKeywordsRaw, !raw.isEmpty else { return [] }
            return raw.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        set {
            let cleaned = newValue.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
            aiKeywordsRaw = cleaned.isEmpty ? nil : cleaned.joined(separator: ",")
        }
    }
}
