import SwiftUI

/// User-customizable visual overrides for each clipboard item type.
/// Accent controls selection/highlight color; header can be solid or gradient;
/// label controls the text color used in clip headers across all view modes.
struct ClipTypeTheme: Codable, Equatable {
    var accentRaw: String
    var headerRaw: String
    var labelRaw: String?
    var badgeRaw: String?

    init(accentRaw: String, headerRaw: String, labelRaw: String? = nil, badgeRaw: String? = nil) {
        self.accentRaw = accentRaw
        self.headerRaw = headerRaw
        self.labelRaw = labelRaw
        self.badgeRaw = badgeRaw
    }

    var resolvedAccentColor: ResolvedColor {
        ResolvedColor(rawString: accentRaw)
    }

    var headerStyle: FolderColorValue {
        FolderColorValue(rawString: headerRaw)
    }

    var resolvedLabelColor: ResolvedColor? {
        guard let labelRaw else { return nil }
        return ResolvedColor(rawString: labelRaw)
    }

    var resolvedBadgeColor: ResolvedColor? {
        guard let badgeRaw else { return nil }
        return ResolvedColor(rawString: badgeRaw)
    }

    // Codable is synthesized: keys match property names, optionals decode/encode
    // via decodeIfPresent/encodeIfPresent — byte-identical to the old hand-written
    // conformance, so persisted themes round-trip unchanged.
}
