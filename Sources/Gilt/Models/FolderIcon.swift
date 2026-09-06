import Foundation

enum FolderIcon: Equatable {
    case symbol(String)
    case glyph(String)

    private static let symbolPrefix = "sf:"

    init?(rawValue: String?) {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix(Self.symbolPrefix) {
            let name = String(trimmed.dropFirst(Self.symbolPrefix.count))
            guard !name.isEmpty else { return nil }
            self = .symbol(name)
        } else {
            self = .glyph(trimmed)
        }
    }

    var rawValue: String {
        switch self {
        case .symbol(let name):
            return Self.symbolPrefix + name
        case .glyph(let glyph):
            return glyph
        }
    }
}
