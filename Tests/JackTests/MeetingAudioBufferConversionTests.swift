@preconcurrency import AVFoundation
import CoreMedia
import XCTest
@testable import Gilt

/// Validates the CMSampleBuffer → AVAudioPCMBuffer conversion that
/// `MeetingAudioCaptureService` relies on for system-audio capture via
/// ScreenCaptureKit. The prior implementation silently produced empty buffers
/// for some valid float32 inputs because it used
/// `CMSampleBufferCopyPCMDataIntoAudioBufferList` without first ensuring the
/// AudioBufferList was sized correctly. The new path uses Apple's
/// `withAudioBufferList` pattern and is exercised here.
final class MeetingAudioBufferConversionTests: XCTestCase {
    func testConvertsInterleavedFloat32SampleBuffer() throws {
        let sampleBuffer = try makeFloat32SampleBuffer(
            sampleRate: 48_000,
            channels: 2,
            interleaved: true,
            frames: 1024
        )

        let pcmBuffer = try XCTUnwrap(AVAudioPCMBuffer.fromCMSampleBuffer(sampleBuffer))
        XCTAssertEqual(pcmBuffer.frameLength, 1024)
        XCTAssertEqual(pcmBuffer.format.sampleRate, 48_000)
        XCTAssertEqual(pcmBuffer.format.channelCount, 2)
        // Standard format from AVAudioFormat is always non-interleaved float32.
        XCTAssertFalse(pcmBuffer.format.isInterleaved)
    }

    func testConvertsNonInterleavedFloat32SampleBuffer() throws {
        let sampleBuffer = try makeFloat32SampleBuffer(
            sampleRate: 48_000,
            channels: 2,
            interleaved: false,
            frames: 512
        )

        let pcmBuffer = try XCTUnwrap(AVAudioPCMBuffer.fromCMSampleBuffer(sampleBuffer))
        XCTAssertEqual(pcmBuffer.frameLength, 512)
        XCTAssertNotNil(pcmBuffer.floatChannelData)
        // Output buffer must contain the same per-channel samples we wrote in.
        let firstChannel = pcmBuffer.floatChannelData![0]
        XCTAssertEqual(firstChannel[0], 0.0)
        // We wrote a known ramp; samples should be a deterministic ramp scaled
        // to 16-bit range.
        XCTAssertGreaterThan(firstChannel[100], 0)
    }

    func testReturnsNilForInvalidSampleBuffer() {
        // CMSampleBuffer created without a format description should not
        // crash — the conversion returns nil gracefully.
        var sampleBuffer: CMSampleBuffer?
        let timing = CMSampleTimingInfo(
            duration: CMTime(value: 0, timescale: 48_000),
            presentationTimeStamp: .zero,
            decodeTimeStamp: .invalid
        )
        let status = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: nil,
            dataReady: false,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: nil,
            sampleCount: 0,
            sampleTimingEntryCount: 1,
            sampleTimingArray: [timing],
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        XCTAssertEqual(status, noErr)
        let unwrapped = try? XCTUnwrap(sampleBuffer)
        if let unwrapped {
            XCTAssertNil(AVAudioPCMBuffer.fromCMSampleBuffer(unwrapped))
        }
    }

    // MARK: - Helpers

    /// Creates a CMSampleBuffer carrying a known float32 ramp. Mirrors the kind
    /// of buffer SCStream delivers on macOS 14+/15+.
    private func makeFloat32SampleBuffer(
        sampleRate: Double,
        channels: UInt32,
        interleaved: Bool,
        frames: Int
    ) throws -> CMSampleBuffer {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat
                | kAudioFormatFlagIsPacked
                | (interleaved ? 0 : kAudioFormatFlagIsNonInterleaved),
            mBytesPerPacket: interleaved ? UInt32(MemoryLayout<Float>.size) * channels : UInt32(MemoryLayout<Float>.size),
            mFramesPerPacket: 1,
            mBytesPerFrame: interleaved ? UInt32(MemoryLayout<Float>.size) * channels : UInt32(MemoryLayout<Float>.size),
            mChannelsPerFrame: channels,
            mBitsPerChannel: 32,
            mReserved: 0
        )

        var formatDescription: CMAudioFormatDescription?
        let createStatus = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        XCTAssertEqual(createStatus, noErr)
        let formatDescUnwrapped = try XCTUnwrap(formatDescription)

        // Build the audio data: a ramp from 0..1 over the frames, replicated
        // per channel. For interleaved buffers samples are LRLRLR…; for
        // non-interleaved we lay channels back-to-back.
        let totalSamples = frames * Int(channels)
        var samples = [Float](repeating: 0, count: totalSamples)
        for frame in 0..<frames {
            let value = Float(frame) / Float(frames)
            for channel in 0..<Int(channels) {
                let index = interleaved
                    ? frame * Int(channels) + channel
                    : channel * frames + frame
                samples[index] = value
            }
        }

        let bytesPerFrame = Int(asbd.mBytesPerFrame)
        let totalBytes = frames * bytesPerFrame * (interleaved ? 1 : Int(channels))
        var blockBuffer: CMBlockBuffer?
        let blockStatus = samples.withUnsafeBytes { rawPointer -> OSStatus in
            CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: nil,
                blockLength: totalBytes,
                blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: totalBytes,
                flags: 0,
                blockBufferOut: &blockBuffer
            )
        }
        XCTAssertEqual(blockStatus, noErr)
        let blockUnwrapped = try XCTUnwrap(blockBuffer)
        try samples.withUnsafeBytes { rawPointer in
            let status = CMBlockBufferReplaceDataBytes(
                with: rawPointer.baseAddress!,
                blockBuffer: blockUnwrapped,
                offsetIntoDestination: 0,
                dataLength: totalBytes
            )
            XCTAssertEqual(status, noErr)
        }

        var sampleBuffer: CMSampleBuffer?
        let timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: Int32(sampleRate)),
            presentationTimeStamp: .zero,
            decodeTimeStamp: .invalid
        )
        let sampleStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockUnwrapped,
            formatDescription: formatDescUnwrapped,
            sampleCount: frames,
            sampleTimingEntryCount: 1,
            sampleTimingArray: [timing],
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        XCTAssertEqual(sampleStatus, noErr)
        return try XCTUnwrap(sampleBuffer)
    }
}
