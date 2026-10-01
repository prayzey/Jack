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
    func testLevelsPersistAndNearFullSnapsBackToUntouched() throws {
        let suite = "SoundMixerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let mixer = SoundMixer(defaults: defaults)
        mixer.setVolume(0.4, for: "com.spotify.client")
        mixer.toggleMute(for: "us.zoom.xos")
        mixer.setVolume(0.99, for: "com.google.Chrome")

        let saved = try JSONDecoder().decode(
            [String: SoundAppLevel].self,
            from: XCTUnwrap(defaults.data(forKey: "JackSoundAppLevels"))
        )
        XCTAssertEqual(saved, [
            "com.spotify.client": SoundAppLevel(volume: 0.4),
            "us.zoom.xos": SoundAppLevel(isMuted: true),
        ])
        // A fresh mixer (next launch) reads the same levels back.
        XCTAssertEqual(SoundMixer(defaults: defaults).levels, saved)
    }

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

    func testProbeWritesSilenceButNoticesAudio() {
        let probe = render(inputs: [tapBuffer(frames: 2)], outputs: [buffer(channels: 2, frames: 2) { _, _ in 7 }], gain: 0.5, probe: true)
        XCTAssertEqual(probe.samples[0], [0, 0, 0, 0])
        XCTAssertTrue(probe.sawAudio)

        let silent = render(inputs: [buffer(channels: 2, frames: 2) { _, _ in 0 }], outputs: [buffer(channels: 2, frames: 2) { _, _ in 7 }], gain: 0.5, probe: true)
        XCTAssertFalse(silent.sawAudio)
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

    private func render(inputs: [AudioBuffer], outputs: [AudioBuffer], gain: Float, probe: Bool = false) -> (samples: [[Float]], sawAudio: Bool) {
        let inList = AudioBufferList.allocate(maximumBuffers: inputs.count)
        let outList = AudioBufferList.allocate(maximumBuffers: outputs.count)
        for (index, buffer) in inputs.enumerated() { inList[index] = buffer }
        for (index, buffer) in outputs.enumerated() { outList[index] = buffer }
        defer {
            (inputs + outputs).forEach { $0.mData?.deallocate() }
            inList.unsafeMutablePointer.deallocate()
            outList.unsafeMutablePointer.deallocate()
        }

        let state = RenderState(gain: gain, isProbe: probe)
        state.render(inList.unsafePointer, into: outList.unsafeMutablePointer)
        let samples = outputs.map { buffer in
            Array(UnsafeBufferPointer(
                start: buffer.mData!.assumingMemoryBound(to: Float.self),
                count: Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            ))
        }
        return (samples, state.sawAudio.pointee != 0)
    }
}
