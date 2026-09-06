import Foundation
import SwiftData

/// A named visual divider within a folder that lets users create sections
/// (e.g., "Swift", "Python" sections inside a "Code" folder).
@Model
final class FolderSeparatorModel {
    var separatorID: UUID
    var label: String
    var colorRaw: String?
    /// Positions the separator among clips using the same sort-order space.
    /// Higher values appear first (left) in the strip, matching clip behavior.
    var sortOrder: Int

    @Relationship(inverse: \ClipFolderModel.separators)
    var folder: ClipFolderModel?

    init(
        separatorID: UUID = UUID(),
        label: String = "Section",
        colorRaw: String? = nil,
        sortOrder: Int = 0,
        folder: ClipFolderModel? = nil
    ) {
        self.separatorID = separatorID
        self.label = label
        self.colorRaw = colorRaw
        self.sortOrder = sortOrder
        self.folder = folder
    }

    var resolvedColor: ResolvedColor {
        ResolvedColor(rawString: colorRaw ?? FolderColorToken.slate.rawValue)
    }
}
