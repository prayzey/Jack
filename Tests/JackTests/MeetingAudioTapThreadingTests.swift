@preconcurrency import AVFoundation
import XCTest
@testable import Gilt

final class MeetingAudioTapThreadingTests: XCTestCase {
    func testMicrophoneTapBlockCanRunOffMainThread() throws {
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8))
        buffer.frameLength = 8

        let semaphore = DispatchSemaphore(value: 0)
        let bridge = MeetingAudioBufferBridge { _ in
            semaphore.signal()
        }
        let tapBlock = MeetingAudioCaptureService.makeMicrophoneTapBlock(bridge: bridge)
        let invocation = AudioTapInvocation(tapBlock: tapBlock, buffer: buffer)

        DispatchQueue.global(qos: .userInitiated).async {
            invocation.invoke()
        }

        XCTAssertEqual(semaphore.wait(timeout: .now() + 1), .success)
    }
}

private final class AudioTapInvocation: @unchecked Sendable {
    private let tapBlock: AVAudioNodeTapBlock
    private let buffer: AVAudioPCMBuffer

    init(tapBlock: @escaping AVAudioNodeTapBlock, buffer: AVAudioPCMBuffer) {
        self.tapBlock = tapBlock
        self.buffer = buffer
    }

    func invoke() {
        tapBlock(buffer, AVAudioTime())
    }
}
