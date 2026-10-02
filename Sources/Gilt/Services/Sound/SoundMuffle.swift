import Foundation

/// Ways to muffle other apps while you dictate, so music sounds like it's
/// somewhere else instead of just quieter.
enum SoundMuffle: String, Codable, CaseIterable, Identifiable {
    /// Bass through a wall, like the party is in the next room.
    case nextDoor
    /// Deep and slowly wobbling.
    case underwater
    /// Thin, with a hallway echo, and quieter.
    case farAway
    /// Narrow and a little crunchy, like an old AM radio.
    case oldRadio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nextDoor: return L10n.string("sound.muffle.next.door", default: "Next door")
        case .underwater: return L10n.string("sound.muffle.underwater", default: "Underwater")
        case .farAway: return L10n.string("sound.muffle.far.away", default: "Far away")
        case .oldRadio: return L10n.string("sound.muffle.old.radio", default: "Old radio")
        }
    }

    var detail: String {
        switch self {
        case .nextDoor: return L10n.string("sound.muffle.next.door.detail", default: "Like the party is in the next room")
        case .underwater: return L10n.string("sound.muffle.underwater.detail", default: "Deep and slowly wobbling")
        case .farAway: return L10n.string("sound.muffle.far.away.detail", default: "Thin, with a hallway echo")
        case .oldRadio: return L10n.string("sound.muffle.old.radio.detail", default: "Tinny, like an old AM radio")
        }
    }

    var symbol: String {
        switch self {
        case .nextDoor: return "door.left.hand.closed"
        case .underwater: return "water.waves"
        case .farAway: return "figure.walk"
        case .oldRadio: return "radio"
        }
    }

    /// The sound of each style. Tuned by ear; frequencies in Hz.
    struct Recipe {
        var highpass: Float? = nil
        var lowpass: Float
        var lowpassStages = 1
        var echoSeconds: Float = 0
        var echoFeedback: Float = 0
        var echoLevel: Float = 0
        var wobbleHz: Float = 0
        var wobbleSeconds: Float = 0
        var drive: Float = 0
        var gain: Float
    }

    var recipe: Recipe {
        switch self {
        case .nextDoor:
            return Recipe(lowpass: 320, lowpassStages: 2, gain: 0.9)
        case .underwater:
            return Recipe(lowpass: 520, lowpassStages: 2, wobbleHz: 0.45, wobbleSeconds: 0.0025, gain: 0.8)
        case .farAway:
            return Recipe(highpass: 280, lowpass: 1600, echoSeconds: 0.14, echoFeedback: 0.38, echoLevel: 0.45, gain: 0.5)
        case .oldRadio:
            return Recipe(highpass: 550, lowpass: 3000, lowpassStages: 2, drive: 2.2, gain: 0.6)
        }
    }
}

/// One second-order filter section (RBJ Audio EQ Cookbook), run in
/// transposed direct form II.
struct Biquad {
    var b0: Float = 1, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0

    static func lowpass(_ frequency: Float, sampleRate: Float, q: Float = 0.707) -> Biquad {
        let (cosW, alpha) = terms(frequency, sampleRate, q)
        return normalized(b0: (1 - cosW) / 2, b1: 1 - cosW, b2: (1 - cosW) / 2, a0: 1 + alpha, a1: -2 * cosW, a2: 1 - alpha)
    }

    static func highpass(_ frequency: Float, sampleRate: Float, q: Float = 0.707) -> Biquad {
        let (cosW, alpha) = terms(frequency, sampleRate, q)
        return normalized(b0: (1 + cosW) / 2, b1: -(1 + cosW), b2: (1 + cosW) / 2, a0: 1 + alpha, a1: -2 * cosW, a2: 1 - alpha)
    }

    private static func terms(_ frequency: Float, _ sampleRate: Float, _ q: Float) -> (Float, Float) {
        let w0 = 2 * Float.pi * min(frequency, sampleRate * 0.45) / sampleRate
        return (cos(w0), sin(w0) / (2 * q))
    }

    private static func normalized(b0: Float, b1: Float, b2: Float, a0: Float, a1: Float, a2: Float) -> Biquad {
        Biquad(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }
}

/// Runs a `SoundMuffle` style on a stereo stream, one frame at a time, on the
/// real-time audio thread. Everything is allocated up front; `process` never
/// allocates, locks, or logs.
final class MuffleProcessor: @unchecked Sendable {
    /// High-pass, then up to two low-pass sections.
    private static let maxSections = 3
    private static let maxDelaySeconds: Float = 0.25

    private let sampleRate: Float
    private let styles = SoundMuffle.allCases
    /// Filter sections per style, `maxSections` each; unused ones pass through.
    private let sections: UnsafeMutablePointer<Biquad>
    /// Per channel, per section: z1, z2.
    private let filterState: UnsafeMutablePointer<Float>
    /// One delay line per channel, for the echo or the wobble.
    private let delay: UnsafeMutablePointer<Float>
    private let delayCapacity: Int
    private var writeIndex = 0
    private var phase: Float = 0
    private var activeStyle = -1

    init(sampleRate: Float) {
        self.sampleRate = sampleRate
        let sectionCount = SoundMuffle.allCases.count * Self.maxSections
        sections = .allocate(capacity: sectionCount)
        sections.initialize(repeating: Biquad(), count: sectionCount)
        for (styleIndex, style) in SoundMuffle.allCases.enumerated() {
            let recipe = style.recipe
            let base = styleIndex * Self.maxSections
            if let highpass = recipe.highpass {
                sections[base] = .highpass(highpass, sampleRate: sampleRate)
            }
            for stage in 0..<min(recipe.lowpassStages, Self.maxSections - 1) {
                sections[base + 1 + stage] = .lowpass(recipe.lowpass, sampleRate: sampleRate)
            }
        }
        filterState = .allocate(capacity: 2 * Self.maxSections * 2)
        filterState.initialize(repeating: 0, count: 2 * Self.maxSections * 2)
        delayCapacity = max(Int(sampleRate * Self.maxDelaySeconds), 1)
        delay = .allocate(capacity: delayCapacity * 2)
        delay.initialize(repeating: 0, count: delayCapacity * 2)
    }

    deinit {
        sections.deallocate()
        filterState.deallocate()
        delay.deallocate()
    }

    /// Muffles one stereo frame in place with the style at `styleIndex`
    /// (an index into `SoundMuffle.allCases`).
    func process(_ left: inout Float, _ right: inout Float, styleIndex: Int) {
        guard styles.indices.contains(styleIndex) else { return }
        if styleIndex != activeStyle {
            // Old filter and echo state belongs to another sound; start clean.
            filterState.update(repeating: 0, count: 2 * Self.maxSections * 2)
            delay.update(repeating: 0, count: delayCapacity * 2)
            activeStyle = styleIndex
        }
        let recipe = styles[styleIndex].recipe
        left = channel(left, 0, styleIndex: styleIndex, recipe: recipe)
        right = channel(right, 1, styleIndex: styleIndex, recipe: recipe)
        writeIndex = (writeIndex + 1) % delayCapacity
        if recipe.wobbleHz > 0 {
            phase += 2 * .pi * recipe.wobbleHz / sampleRate
            if phase > 2 * .pi { phase -= 2 * .pi }
        }
    }

    private func channel(_ input: Float, _ channel: Int, styleIndex: Int, recipe: SoundMuffle.Recipe) -> Float {
        var x = input
        let base = styleIndex * Self.maxSections
        for section in 0..<Self.maxSections {
            let coefficients = sections[base + section]
            let z = filterState + (channel * Self.maxSections + section) * 2
            let y = coefficients.b0 * x + z[0]
            z[0] = coefficients.b1 * x - coefficients.a1 * y + z[1]
            z[1] = coefficients.b2 * x - coefficients.a2 * y
            x = y
        }

        let line = delay + channel * delayCapacity
        if recipe.wobbleSeconds > 0 {
            // A slowly swinging delay bends the pitch back and forth.
            line[writeIndex] = x
            let samples = (recipe.wobbleSeconds * 1.5 + recipe.wobbleSeconds * sin(phase)) * sampleRate
            let position = Float(writeIndex) - samples
            let wrapped = position < 0 ? position + Float(delayCapacity) : position
            let index = Int(wrapped)
            let fraction = wrapped - Float(index)
            let next = (index + 1) % delayCapacity
            x = line[index] * (1 - fraction) + line[next] * fraction
        } else if recipe.echoSeconds > 0 {
            let readIndex = (writeIndex - Int(recipe.echoSeconds * sampleRate) + delayCapacity) % delayCapacity
            let echoed = line[readIndex]
            line[writeIndex] = x + echoed * recipe.echoFeedback
            x += echoed * recipe.echoLevel
        }

        if recipe.drive > 0 {
            x = tanh(x * recipe.drive) / tanh(recipe.drive)
        }
        return x * recipe.gain
    }
}
