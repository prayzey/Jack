import CoreAudio
import XCTest
@testable import Gilt

/// Pins the dictation mic pipeline rules: the soft limiter, the automatic
/// gain control, the Bluetooth-to-built-in mic choice, and the settings
/// migration that stops Jack from forcing the mic volume.
final class DictationAudioInputTests: XCTestCase {

    // MARK: - Soft limiter

    func testLimiterNeverPassesFullScale() {
        for x in stride(from: Float(-20), through: 20, by: 0.01) {
            XCTAssertLessThanOrEqual(abs(DictationInputLevelProcessor.softLimit(x)), 1, "x = \(x)")
        }
        XCTAssertEqual(DictationInputLevelProcessor.softLimit(.greatestFiniteMagnitude), 1)
        XCTAssertEqual(DictationInputLevelProcessor.softLimit(-.infinity), -1)
    }

    func testLimiterIsTransparentForSmallSignals() {
        for x in stride(from: Float(-0.8), through: 0.8, by: 0.001) {
            XCTAssertEqual(DictationInputLevelProcessor.softLimit(x), x)
        }
    }

    func testSoftwareBoostNoLongerHardClips() {
        var processor = DictationInputLevelProcessor(sampleRate: 16_000)
        processor.inputBoost = 2
        var samples: [Float] = [0.6, 0.9]
        samples.withUnsafeMutableBufferPointer { processor.process($0) }
        // 0.6 and 0.9 boosted to 1.2 and 1.8 used to both clip to 1.0.
        XCTAssertLessThan(samples[0], samples[1])
        XCTAssertLessThan(samples[1], 1)
    }

    // MARK: - Automatic gain control

    func testAGCBoostsQuietSpeechTowardTarget() {
        // -29 dBFS RMS: quiet, but well above the noise gate.
        let output = runSine(amplitude: 0.05, seconds: 4)
        let lastSecond = Array(output.suffix(16_000))
        XCTAssertEqual(rms(lastSecond), DictationInputLevelProcessor.targetRMS, accuracy: 0.01)
    }

    func testAGCDoesNotBoostSilence() {
        var processor = DictationInputLevelProcessor(sampleRate: 16_000)
        var buffer = [Float](repeating: 0, count: 320)
        for _ in 0..<200 {
            buffer.withUnsafeMutableBufferPointer { processor.process($0) }
        }
        XCTAssertEqual(processor.agcGain, 1)
        XCTAssertTrue(buffer.allSatisfy { $0 == 0 })
    }

    func testAGCDoesNotBoostSignalUnderTheGate() {
        // -57 dBFS RMS: background hiss level.
        let amplitude: Float = 0.002
        let output = runSine(amplitude: amplitude, seconds: 3)
        let input = sine(amplitude: amplitude, seconds: 3)
        XCTAssertEqual(rms(Array(output.suffix(16_000))), rms(Array(input.suffix(16_000))), accuracy: 1e-6)
    }

    func testAGCNeverPassesMaxBoost() {
        // -43 dBFS RMS: above the gate but far below target, so the AGC
        // would want ~14x. It must stop at +12 dB.
        let amplitude: Float = 0.01
        var processor = DictationInputLevelProcessor(sampleRate: 16_000)
        let input = sine(amplitude: amplitude, seconds: 5)
        var maxOutput: Float = 0
        for start in stride(from: 0, to: input.count, by: 320) {
            var chunk = Array(input[start..<min(start + 320, input.count)])
            chunk.withUnsafeMutableBufferPointer { processor.process($0) }
            XCTAssertLessThanOrEqual(processor.agcGain, DictationInputLevelProcessor.maxBoost)
            maxOutput = max(maxOutput, chunk.map(abs).max() ?? 0)
        }
        XCTAssertLessThanOrEqual(maxOutput, amplitude * DictationInputLevelProcessor.maxBoost * 1.0001)
        XCTAssertGreaterThan(processor.agcGain, DictationInputLevelProcessor.maxBoost * 0.95)
    }

    func testAGCNeverAttenuatesNormalSpeech() {
        // -13 dBFS RMS: louder than target, peaks still under the limiter knee.
        let output = runSine(amplitude: 0.3, seconds: 2)
        XCTAssertEqual(output, sine(amplitude: 0.3, seconds: 2))
    }

    // MARK: - Mic choice

    private let builtIn = AudioInputDevice(
        uid: "BuiltInMicrophoneDevice", name: "MacBook Pro Microphone", manufacturer: "Apple",
        transportType: kAudioDeviceTransportTypeBuiltIn, isSystemDefault: false
    )
    private let airPods = AudioInputDevice(
        uid: "AirPods-UID", name: "AirPods Pro", manufacturer: "Apple",
        transportType: kAudioDeviceTransportTypeBluetooth, isSystemDefault: true
    )
    private let usbMic = AudioInputDevice(
        uid: "USB-Mic-UID", name: "Shure MV7", manufacturer: "Shure",
        transportType: kAudioDeviceTransportTypeUSB, isSystemDefault: false
    )

    func testBluetoothDefaultUsesBuiltInMic() {
        for transport in [kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE] {
            XCTAssertEqual(
                AudioInputDeviceManager.dictationInputUID(
                    preferredUID: nil,
                    defaultTransport: transport,
                    availableDevices: [airPods, usbMic, builtIn],
                    preferBuiltInOverBluetooth: true
                ),
                builtIn.uid
            )
        }
    }

    func testPickedMicAlwaysWins() {
        XCTAssertEqual(
            AudioInputDeviceManager.dictationInputUID(
                preferredUID: airPods.uid,
                defaultTransport: kAudioDeviceTransportTypeBluetooth,
                availableDevices: [airPods, builtIn],
                preferBuiltInOverBluetooth: true
            ),
            airPods.uid
        )
    }

    func testSettingOffKeepsBluetoothDefault() {
        XCTAssertNil(AudioInputDeviceManager.dictationInputUID(
            preferredUID: nil,
            defaultTransport: kAudioDeviceTransportTypeBluetooth,
            availableDevices: [airPods, builtIn],
            preferBuiltInOverBluetooth: false
        ))
    }

    func testNoBuiltInMicKeepsDefault() {
        XCTAssertNil(AudioInputDeviceManager.dictationInputUID(
            preferredUID: nil,
            defaultTransport: kAudioDeviceTransportTypeBluetooth,
            availableDevices: [airPods, usbMic],
            preferBuiltInOverBluetooth: true
        ))
    }

    func testNonBluetoothDefaultSkipsDeviceEnumeration() {
        XCTAssertNil(AudioInputDeviceManager.dictationInputUID(
            preferredUID: nil,
            defaultTransport: kAudioDeviceTransportTypeUSB,
            availableDevices: { XCTFail("Must not enumerate devices"); return [] }(),
            preferBuiltInOverBluetooth: true
        ))
    }

    // MARK: - Settings migration

    func testOldSettingsGetHandsOffGainAndPreferBuiltIn() throws {
        // Every older build saved `inputGain: 1.0`, touched or not.
        let settings = try JSONDecoder().decode(
            DictationSettings.self,
            from: Data(#"{ "preferredMicDeviceUID": null, "inputGain": 1.0 }"#.utf8)
        )
        XCTAssertNil(settings.inputGain)
        XCTAssertTrue(settings.preferBuiltInMicOverBluetooth)

        let empty = try JSONDecoder().decode(DictationSettings.self, from: Data("{}".utf8))
        XCTAssertNil(empty.inputGain)
        XCTAssertTrue(empty.preferBuiltInMicOverBluetooth)
    }

    func testOldSettingsKeepAMovedGainSlider() throws {
        let settings = try JSONDecoder().decode(
            DictationSettings.self,
            from: Data(#"{ "inputGain": 1.6 }"#.utf8)
        )
        XCTAssertEqual(try XCTUnwrap(settings.inputGain), 1.6, accuracy: 0.001)
    }

    func testChosenGainAndBluetoothPreferenceSurviveRoundTrip() throws {
        var settings = DictationSettings()
        settings.inputGain = 1.0
        settings.preferBuiltInMicOverBluetooth = false
        let decoded = try JSONDecoder().decode(DictationSettings.self, from: JSONEncoder().encode(settings))
        // An explicit 100% must stay a choice, unlike the legacy key.
        XCTAssertEqual(decoded.inputGain, 1.0)
        XCTAssertFalse(decoded.preferBuiltInMicOverBluetooth)
        XCTAssertNil(try JSONDecoder().decode(
            DictationSettings.self,
            from: JSONEncoder().encode(DictationSettings())
        ).inputGain)
    }

    func testBluetoothCopyLocalizes() {
        for locale in ["de", "es"] {
            let title = L10n.string(
                "dictation.mic.preferBuiltIn.title",
                default: "Use the Mac\u{2019}s microphone instead of AirPods",
                locale: Locale(identifier: locale)
            )
            XCTAssertNotEqual(title, "Use the Mac\u{2019}s microphone instead of AirPods", locale)
            XCTAssertTrue(title.contains("AirPods"))
        }
    }

    // MARK: - Helpers

    private func sine(amplitude: Float, seconds: Double) -> [Float] {
        (0..<Int(seconds * 16_000)).map { amplitude * sin(2 * .pi * 440 * Float($0) / 16_000) }
    }

    /// Feeds a 440 Hz sine through a fresh processor in 20 ms buffers, the
    /// size dictation produces at 16 kHz.
    private func runSine(amplitude: Float, seconds: Double) -> [Float] {
        var processor = DictationInputLevelProcessor(sampleRate: 16_000)
        var samples = sine(amplitude: amplitude, seconds: seconds)
        for start in stride(from: 0, to: samples.count, by: 320) {
            samples.withUnsafeMutableBufferPointer { all in
                let end = min(start + 320, all.count)
                processor.process(UnsafeMutableBufferPointer(rebasing: all[start..<end]))
            }
        }
        return samples
    }

    private func rms(_ samples: [Float]) -> Float {
        (samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)).squareRoot()
    }
}
