import SwiftUI

/// The pill's only status light: 37 solid dots in a round 7 × 7 grid, after a
/// halogen timer. It sweeps while waiting, blooms from the center with your
/// voice, spins while Jack works, and draws a check when the text lands.
struct DictationDotGrid: View {
    enum Mode: Equatable {
        case off, waiting, speaking, working, done
    }

    let mode: Mode
    let level: Double
    let color: Color
    /// Opacity of an unlit dot. Every dot stays solid; brightness only changes its opacity.
    var dimOpacity: Double = 0.16

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var engine = DotGridEngine()

    var body: some View {
        TimelineView(.animation(paused: mode == .off)) { timeline in
            Canvas { context, size in
                let brightness = engine.advance(to: timeline.date, mode: mode, level: level, reduceMotion: reduceMotion)
                let pitch = size.width / 7
                let diameter = pitch * 0.7
                for (index, cell) in DotGridEngine.cells.enumerated() {
                    let rect = CGRect(
                        x: (CGFloat(cell.column) + 0.5) * pitch - diameter / 2,
                        y: (CGFloat(cell.row) + 0.5) * pitch - diameter / 2,
                        width: diameter,
                        height: diameter
                    )
                    let lit = brightness[index]
                    context.fill(Path(ellipseIn: rect), with: .color(color.opacity(dimOpacity + (1 - dimOpacity) * lit)))
                }
            }
        }
        .frame(width: DictationCaptionLayout.gridSize, height: DictationCaptionLayout.gridSize)
        .accessibilityHidden(true)
    }
}

/// Per-dot brightness for `DictationDotGrid`. Each frame eases every dot toward
/// its target, so switching modes crossfades instead of snapping.
final class DotGridEngine {
    struct Cell {
        let row: Int
        let column: Int
        /// Distance from the center: 0 in the middle, about 1 at the rim.
        let radius: Double
        /// Clockwise angle from the right, in radians.
        let angle: Double
    }

    /// A 7 × 7 grid with its corners cut so it reads as a circle.
    static let cells: [Cell] = (0..<7).flatMap { row in
        (0..<7).compactMap { column -> Cell? in
            let dy = Double(row - 3), dx = Double(column - 3)
            guard dx * dx + dy * dy <= 10.5 else { return nil }
            return Cell(row: row, column: column, radius: (dx * dx + dy * dy).squareRoot() / 3.2, angle: atan2(dy, dx))
        }
    }

    /// The dots that draw the check, in drawing order: a short tick down, then a long stroke up.
    static let checkPath: [Int] = [(4, 1), (5, 2), (4, 3), (3, 4), (2, 5)].compactMap { point in
        cells.firstIndex { $0.row == point.0 && $0.column == point.1 }
    }

    private(set) var brightness = [Double](repeating: 0, count: cells.count)
    private var lastDate: Date?
    private var mode: DictationDotGrid.Mode = .off
    private var modeStart = Date.distantPast

    func advance(to date: Date, mode: DictationDotGrid.Mode, level: Double, reduceMotion: Bool) -> [Double] {
        if mode != self.mode {
            self.mode = mode
            modeStart = date
        }
        let time = date.timeIntervalSinceReferenceDate
        let since = date.timeIntervalSince(modeStart)
        let loudness = min(1, level * 1.6)
        let targets = Self.cells.indices.map {
            Self.target(mode: mode, cell: $0, time: time, since: since, loudness: loudness, reduceMotion: reduceMotion)
        }
        // The first frame shows its state complete; after that dots ease toward their targets.
        guard let lastDate else {
            self.lastDate = date
            brightness = mode == .done ? Self.checkPath.indices.reduce(into: targets) { $0[Self.checkPath[$1]] = 1 } : targets
            return brightness
        }
        let elapsed = min(0.05, max(0, date.timeIntervalSince(lastDate)))
        self.lastDate = date
        let ease = reduceMotion || mode == .off ? 1 : 1 - exp(-elapsed * 20)
        for index in brightness.indices {
            brightness[index] += (targets[index] - brightness[index]) * ease
        }
        return brightness
    }

    /// How lit one dot should be, from 0 (dim) to 1 (full).
    static func target(
        mode: DictationDotGrid.Mode,
        cell index: Int,
        time: Double,
        since: Double,
        loudness: Double,
        reduceMotion: Bool
    ) -> Double {
        let cell = cells[index]
        switch mode {
        case .off:
            return 0
        case .waiting:
            if reduceMotion { return cell.radius > 0.8 ? 0.5 : 0 }
            return 0.6 * sweep(cell.angle, head: time * 1.7, tail: 1.5) * (0.35 + 0.65 * cell.radius)
        case .speaking:
            // Louder speech lights more rings from the center out; a faint flicker keeps it alive.
            let flicker = reduceMotion ? 0 : 0.14 * sin(time * 11 + Double(index) * 2.3)
            let bloom = clamp((loudness * 1.15 - cell.radius) * 2.8 + flicker)
            let idleSweep = reduceMotion ? 0 : 0.35 * (1 - loudness) * sweep(cell.angle, head: time * 1.7, tail: 1.5) * cell.radius
            return max(bloom, idleSweep)
        case .working:
            if reduceMotion { return cell.radius > 0.8 ? 0.6 : 0 }
            return sweep(cell.angle, head: time * 7.5, tail: 2) * (0.25 + 0.75 * cell.radius)
        case .done:
            guard let step = checkPath.firstIndex(of: index) else { return 0 }
            return reduceMotion ? 1 : clamp(since * 16 - Double(step) * 0.9)
        }
    }

    /// Brightness of a dot trailing a turning head: full at the head, fading over `tail` radians.
    private static func sweep(_ angle: Double, head: Double, tail: Double) -> Double {
        let turn = 2 * Double.pi
        var behind = (head - angle).truncatingRemainder(dividingBy: turn)
        if behind < 0 { behind += turn }
        return behind < tail ? pow(1 - behind / tail, 1.6) : 0
    }

    private static func clamp(_ value: Double) -> Double { min(1, max(0, value)) }
}
