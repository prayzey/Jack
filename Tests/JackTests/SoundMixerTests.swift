import CoreAudio
import XCTest
@testable import Gilt

final class SoundMixerTests: XCTestCase {
    func testMutedLevelSilencesAndFullLevelNeedsNoTap() {
        XCTAssertEqual(SoundAppLevel().gain, 1)
        XCTAssertEqual(SoundAppLevel(volume: 0.4).gain, 0.4)
        XCTAssertEqual(SoundAppLevel(volume: 0.4, isMuted: true).gain, 0)
    }

    @MainActor
    func testLevelsAndScenesPersistAndNearFullSnapsBackToUntouched() throws {
        let suite = "SoundMixerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let mixer = SoundMixer(defaults: defaults)
        mixer.setVolume(0.4, for: "com.spotify.client")
        mixer.toggleMute(for: "us.zoom.xos")
        mixer.setVolume(0.99, for: "com.google.Chrome")
        mixer.setOutput("AirPodsUID", for: "com.apple.Music")
        mixer.saveScene(named: " Focus ")

        let expected: [String: SoundAppLevel] = [
            "com.spotify.client": SoundAppLevel(volume: 0.4),
            "us.zoom.xos": SoundAppLevel(isMuted: true),
            "com.apple.Music": SoundAppLevel(outputDeviceUID: "AirPodsUID"),
        ]
        let reopened = SoundMixer(defaults: defaults)
        XCTAssertEqual(reopened.levels, expected)
        XCTAssertEqual(reopened.scenes.map(\.name), ["Focus"])
        XCTAssertEqual(reopened.currentSceneID, reopened.scenes.first?.id)

        reopened.resetApp("com.spotify.client")
        XCTAssertNil(reopened.currentSceneID)
        reopened.applyScene(try XCTUnwrap(reopened.scenes.first?.id))
        XCTAssertEqual(reopened.levels, expected)
    }

    // MARK: - Mix rules

    func testSoloSilencesEveryoneElseAndWinsOverCallMode() {
        let rules = SoundMixRules(soloAppID: "music", micApps: ["zoom": "Zoom"], callModeLevel: 0.25)
        XCTAssertEqual(rules.gain(for: "music", level: SoundAppLevel(volume: 0.8)), 0.8)
        XCTAssertEqual(rules.gain(for: "zoom", level: SoundAppLevel()), 0)
        XCTAssertEqual(rules.effect(for: "zoom"), .silencedBySolo)
    }

    func testCallModeLowersOnlyAppsNotUsingTheMic() {
        var rules = SoundMixRules(micApps: ["zoom": "Zoom"], callModeLevel: 0.25)
        XCTAssertEqual(rules.gain(for: "zoom", level: SoundAppLevel()), 1)
        XCTAssertEqual(rules.gain(for: "music", level: SoundAppLevel(volume: 0.8)), 0.2, accuracy: 0.0001)
        XCTAssertEqual(rules.effect(for: "music"), .loweredForMic(byAppName: "Zoom"))

        rules.callModeLevel = nil
        XCTAssertEqual(rules.gain(for: "music", level: SoundAppLevel()), 1)
        rules.callModeLevel = 0.25
        rules.micApps = [:]
        XCTAssertEqual(rules.effect(for: "music"), .none)
    }

    func testDictationLowersEveryApp() {
        let rules = SoundMixRules(micApps: ["zoom": "Zoom"], callModeLevel: 0.25, dictationLevel: 0.4)
        XCTAssertEqual(rules.gain(for: "zoom", level: SoundAppLevel()), 0.4, accuracy: 0.0001)
        XCTAssertEqual(rules.effect(for: "music"), .loweredForDictation)
    }

    // MARK: - Commands

    private let targets = [
        SoundTarget(id: "com.google.Chrome", name: "Google Chrome", kind: .app),
        SoundTarget(id: "com.apple.Music", name: "Music", kind: .app),
        SoundTarget(id: "us.zoom.xos", name: "zoom.us", kind: .app, aliases: ["zoom"]),
        SoundTarget(id: "1:7", name: "Lo-fi beats to study to", kind: .tab, aliases: ["youtube"]),
    ]

    func testParsesMuteSoloAndVolumeCommands() {
        XCTAssertEqual(SoundCommand.parse("mute chrome", targets: targets), .mute(targets[0]))
        XCTAssertEqual(SoundCommand.parse("Unmute Google Chrome", targets: targets), .unmute(targets[0]))
        XCTAssertEqual(SoundCommand.parse("solo music", targets: targets), .solo(targets[1]))
        XCTAssertEqual(SoundCommand.parse("set zoom to 30%", targets: targets), .setVolume(targets[2], 0.3))
        XCTAssertEqual(SoundCommand.parse("zoom 45", targets: targets), .setVolume(targets[2], 0.45))
        XCTAssertEqual(SoundCommand.parse("Zoom is too loud", targets: targets), .lower(targets[2]))
        XCTAssertEqual(SoundCommand.parse("turn the music up", targets: targets), .raise(targets[1]))
        XCTAssertEqual(SoundCommand.parse("mute youtube", targets: targets), .mute(targets[3]))
        XCTAssertEqual(SoundCommand.parse("What's playing?", targets: targets), .whatsPlaying)
    }

    func testIgnoresTextThatIsNotASoundCommand() {
        XCTAssertNil(SoundCommand.parse("remind me to call mom at 5", targets: targets))
        XCTAssertNil(SoundCommand.parse("mute", targets: targets))
        XCTAssertNil(SoundCommand.parse("tell me about chrome extensions", targets: targets))
    }

    // MARK: - Meters

    func testMetersRiseImmediatelyAndFallGently() {
        XCTAssertEqual(SoundMeters.smooth(previous: 0, peak: 0.25), 0.5)
        XCTAssertEqual(SoundMeters.smooth(previous: 0.5, peak: 0), 0.41, accuracy: 0.0001)
        XCTAssertEqual(SoundMeters.smooth(previous: 0.011, peak: 0), 0)
    }

    // MARK: - Render

    func testRenderPutsTheTapOnTheFirstStereoPairAndIgnoresTheMic() {
        // Inputs: a headset mic stream first, then the stereo tap (L=1, R=-1).
        // Output: a 4-channel interface; channels 3 and 4 get silence.
        let output = render(
            inputs: [buffer(channels: 1, frames: 4) { _, _ in 0.9 }, tapBuffer(frames: 4)],
            outputs: [buffer(channels: 4, frames: 4) { _, _ in 7 }],
            gain: 0.5
        )
        XCTAssertEqual(output.samples[0], Array(repeating: [0.5, -0.5, 0, 0], count: 4).flatMap { $0 })
        XCTAssertTrue(output.sawAudio)
        XCTAssertEqual(output.peak, 0.5)
    }

    func testRenderMixesToMonoAndSplitsNonInterleavedOutputs() {
        let mono = render(inputs: [tapBuffer(frames: 2)], outputs: [buffer(channels: 1, frames: 2) { _, _ in 7 }], gain: 1)
        XCTAssertEqual(mono.samples[0], [0, 0])

        let split = render(
            inputs: [tapBuffer(frames: 2)],
            outputs: [buffer(channels: 1, frames: 2) { _, _ in 7 }, buffer(channels: 1, frames: 2) { _, _ in 7 }],
            gain: 0.25
        )
        XCTAssertEqual(split.samples, [[0.25, 0.25], [-0.25, -0.25]])
    }

    func testListenOnlyWritesSilenceButMeasuresTheApp() {
        let probe = render(inputs: [tapBuffer(frames: 2)], outputs: [buffer(channels: 2, frames: 2) { _, _ in 7 }], gain: 0.5, listenOnly: true)
        XCTAssertEqual(probe.samples[0], [0, 0, 0, 0])
        XCTAssertTrue(probe.sawAudio)
        XCTAssertEqual(probe.peak, 1)

        let silent = render(inputs: [buffer(channels: 2, frames: 2) { _, _ in 0 }], outputs: [buffer(channels: 2, frames: 2) { _, _ in 7 }], gain: 0.5, listenOnly: true)
        XCTAssertFalse(silent.sawAudio)
    }

    func testGainRampsInsteadOfJumping() {
        // 4 frames at 48 kHz with a 30 ms ramp can move the gain by 4/1440.
        let output = render(inputs: [tapBuffer(frames: 4)], outputs: [buffer(channels: 2, frames: 4) { _, _ in 7 }], gain: 0, startGain: 1)
        let last = output.samples[0][6]
        XCTAssertEqual(last, 1 - 4.0 / 1440, accuracy: 0.0001)
    }

    // MARK: - Helpers

    private func tapBuffer(frames: Int) -> AudioBuffer {
        buffer(channels: 2, frames: frames) { _, channel in channel == 0 ? 1 : -1 }
    }

    private func buffer(channels: Int, frames: Int, fill: (Int, Int) -> Float) -> AudioBuffer {
        let data = UnsafeMutablePointer<Float>.allocate(capacity: channels * frames)
        for frame in 0..<frames {
            for channel in 0..<channels { data[frame * channels + channel] = fill(frame, channel) }
        }
        return AudioBuffer(
            mNumberChannels: UInt32(channels),
            mDataByteSize: UInt32(channels * frames * MemoryLayout<Float>.size),
            mData: UnsafeMutableRawPointer(data)
        )
    }

    private func render(
        inputs: [AudioBuffer],
        outputs: [AudioBuffer],
        gain: Float,
        startGain: Float? = nil,
        listenOnly: Bool = false
    ) -> (samples: [[Float]], sawAudio: Bool, peak: Float) {
        let inList = AudioBufferList.allocate(maximumBuffers: inputs.count)
        let outList = AudioBufferList.allocate(maximumBuffers: outputs.count)
        for (index, buffer) in inputs.enumerated() { inList[index] = buffer }
        for (index, buffer) in outputs.enumerated() { outList[index] = buffer }
        defer {
            (inputs + outputs).forEach { $0.mData?.deallocate() }
            inList.unsafeMutablePointer.deallocate()
            outList.unsafeMutablePointer.deallocate()
        }

        let state = RenderState(gain: gain, startGain: startGain ?? gain, isListenOnly: listenOnly)
        state.render(inList.unsafePointer, into: outList.unsafeMutablePointer)
        let samples = outputs.map { buffer in
            Array(UnsafeBufferPointer(
                start: buffer.mData!.assumingMemoryBound(to: Float.self),
                count: Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            ))
        }
        return (samples, state.sawAudio.pointee != 0, state.peak.pointee)
    }
}
