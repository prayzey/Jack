import XCTest
@testable import Gilt

final class SoundMuffleTests: XCTestCase {
    private let sampleRate: Float = 48_000

    /// RMS of a sine at `frequency` after the style settles (second half).
    private func level(_ style: SoundMuffle, frequency: Float, amplitude: Float = 0.5) -> Float {
        let processor = MuffleProcessor(sampleRate: sampleRate)
        let index = SoundMuffle.allCases.firstIndex(of: style)!
        let frames = Int(sampleRate / 2)
        var sum: Float = 0
        for frame in 0..<frames {
            var left = amplitude * sin(2 * .pi * frequency * Float(frame) / sampleRate)
            var right = left
            processor.process(&left, &right, styleIndex: index)
            if frame >= frames / 2 { sum += left * left }
        }
        return sqrt(sum / Float(frames / 2))
    }

    func testNextDoorKeepsTheBassAndCutsTheRest() {
        let bass = level(.nextDoor, frequency: 80)
        let vocals = level(.nextDoor, frequency: 3_000)
        XCTAssertGreaterThan(bass, 0.2)
        // At least 40 dB quieter: through-the-wall, not just a bit dull.
        XCTAssertLessThan(vocals, bass / 100)
    }

    func testOldRadioCutsBothEndsAndStaysInRange() {
        let mid = level(.oldRadio, frequency: 1_200, amplitude: 1)
        XCTAssertGreaterThan(mid, level(.oldRadio, frequency: 60, amplitude: 1) * 4)
        XCTAssertGreaterThan(mid, level(.oldRadio, frequency: 12_000, amplitude: 1) * 4)
        XCTAssertLessThanOrEqual(mid, 1)
    }

    func testFarAwayEchoesAfterTheSound() {
        let processor = MuffleProcessor(sampleRate: sampleRate)
        let index = SoundMuffle.allCases.firstIndex(of: .farAway)!
        let echoAt = Int(SoundMuffle.farAway.recipe.echoSeconds * sampleRate)
        var output: [Float] = []
        for frame in 0..<(echoAt * 2) {
            // A short 1 kHz burst, then silence.
            var left: Float = frame < 480 ? sin(2 * .pi * 1_000 * Float(frame) / sampleRate) : 0
            var right = left
            processor.process(&left, &right, styleIndex: index)
            output.append(abs(left))
        }
        let quietGap = output[1_200..<(echoAt - 100)].max() ?? 0
        let echo = output[echoAt..<(echoAt + 600)].max() ?? 0
        XCTAssertGreaterThan(echo, 0.05)
        XCTAssertGreaterThan(echo, quietGap * 5)
    }

    func testMuffleRulesKeepEachAppsOwnLevel() {
        let rules = SoundMixRules(dictationMuffle: .underwater)
        XCTAssertEqual(rules.effect(for: "music"), .muffledForDictation)
        XCTAssertEqual(rules.gain(for: "music", level: SoundAppLevel(volume: 0.7)), 0.7)
    }

    func testMuffleChoiceStaysReadableByOlderBuilds() throws {
        var settings = DictationSettings()
        settings.backgroundChoice = .muffle
        settings.muffleStyle = .farAway
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any]
        // Older Jack builds only know these two modes.
        XCTAssertTrue(["lowerVolume", "pauseMedia"].contains(json?["backgroundAudioMode"] as? String))

        let decoded = try JSONDecoder().decode(DictationSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.backgroundChoice, .muffle)
        XCTAssertEqual(decoded.muffleStyle, .farAway)
    }
}
