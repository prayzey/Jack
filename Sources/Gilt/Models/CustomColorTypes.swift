import AppKit
import Foundation
import SwiftUI

extension NSImage {
    func pngData() -> Data? {
        guard let tiffData = tiffRepresentation,
              let imageRep = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return imageRep.representation(using: .png, properties: [:])
    }
}

// MARK: - Custom Color Types

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&rgb)
        if cleaned.count == 8 {
            self.init(
                red: Double((rgb >> 24) & 0xFF) / 255,
                green: Double((rgb >> 16) & 0xFF) / 255,
                blue: Double((rgb >> 8) & 0xFF) / 255,
                opacity: Double(rgb & 0xFF) / 255
            )
        } else {
            self.init(
                red: Double((rgb >> 16) & 0xFF) / 255,
                green: Double((rgb >> 8) & 0xFF) / 255,
                blue: Double(rgb & 0xFF) / 255
            )
        }
    }

    var hexString: String {
        guard let c = NSColor(self).usingColorSpace(.deviceRGB) else { return "#808080" }
        return String(
            format: "#%02X%02X%02X",
            Int((c.redComponent * 255).rounded()),
            Int((c.greenComponent * 255).rounded()),
            Int((c.blueComponent * 255).rounded())
        )
    }
}

enum ResolvedColor: Equatable {
    case token(FolderColorToken)
    case hex(String)

    init(rawString: String) {
        if rawString.hasPrefix("#") {
            self = .hex(rawString)
        } else if let token = FolderColorToken(rawValue: rawString) {
            self = .token(token)
        } else {
            self = .token(.slate)
        }
    }

    var rawString: String {
        switch self {
        case .token(let t): return t.rawValue
        case .hex(let h): return h
        }
    }

    var color: Color {
        switch self {
        case .token(let t): return t.color
        case .hex(let h): return Color(hex: h)
        }
    }
}

struct GradientSpec: Codable, Equatable {
    var color1: String
    var color2: String
    var angle: Double

    init(color1: String, color2: String, angle: Double = 180.0) {
        self.color1 = color1
        self.color2 = color2
        self.angle = angle
    }

    init?(rawString: String) {
        guard rawString.hasPrefix("grad:") else { return nil }
        let parts = String(rawString.dropFirst(5)).split(separator: ",")
        guard parts.count >= 2 else { return nil }
        self.color1 = String(parts[0])
        self.color2 = String(parts[1])
        self.angle = parts.count >= 3 ? Double(parts[2]) ?? 180.0 : 180.0
    }

    var serialized: String {
        "grad:\(color1),\(color2),\(angle)"
    }

    var linearGradient: LinearGradient {
        let startPt = unitPoint(for: angle + 180)
        let endPt = unitPoint(for: angle)
        return LinearGradient(
            colors: [Color(hex: color1), Color(hex: color2)],
            startPoint: startPt,
            endPoint: endPt
        )
    }

    /// Dark-tinted gradient colors for the settings window background.
    /// Takes the custom gradient's hues and produces very dark variants.
    var settingsGradientColors: [Color] {
        let c1 = NSColor(Color(hex: color1)).usingColorSpace(.deviceRGB) ?? NSColor.darkGray
        let c2 = NSColor(Color(hex: color2)).usingColorSpace(.deviceRGB) ?? NSColor.darkGray
        var h1: CGFloat = 0
        var s1: CGFloat = 0
        var b1: CGFloat = 0
        var a1: CGFloat = 0
        var h2: CGFloat = 0
        var s2: CGFloat = 0
        var b2: CGFloat = 0
        var a2: CGFloat = 0
        c1.getHue(&h1, saturation: &s1, brightness: &b1, alpha: &a1)
        c2.getHue(&h2, saturation: &s2, brightness: &b2, alpha: &a2)
        return [
            Color(hue: Double(h1), saturation: Double(s1) * 0.4, brightness: 0.08),
            Color(hue: Double((h1 + h2) / 2), saturation: Double((s1 + s2) / 2) * 0.3, brightness: 0.11),
            Color(hue: Double(h2), saturation: Double(s2) * 0.4, brightness: 0.14),
        ]
    }

    private func unitPoint(for degrees: Double) -> UnitPoint {
        let rad = degrees * .pi / 180
        return UnitPoint(x: 0.5 + 0.5 * sin(rad), y: 0.5 - 0.5 * cos(rad))
    }
}

enum FolderColorValue: Equatable {
    case solid(ResolvedColor)
    case gradient(GradientSpec)

    init(rawString: String) {
        if let grad = GradientSpec(rawString: rawString) {
            self = .gradient(grad)
        } else {
            self = .solid(ResolvedColor(rawString: rawString))
        }
    }

    var rawString: String {
        switch self {
        case .solid(let c): return c.rawString
        case .gradient(let g): return g.serialized
        }
    }

    var isGradient: Bool {
        if case .gradient = self { return true }
        return false
    }
}

struct ColorPreset: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var rawValue: String
    var createdAt: Date

    init(id: UUID = UUID(), name: String, rawValue: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.rawValue = rawValue
        self.createdAt = createdAt
    }

    var isGradient: Bool {
        rawValue.hasPrefix("grad:")
    }
}
