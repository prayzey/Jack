import AppKit
import CryptoKit
import AVFoundation
import SwiftUI
import XCTest
@testable import Gilt

@MainActor
final class DictationReliabilityTests: XCTestCase {
    private final class ConfigurationTestEngine: AVAudioEngine {
        var reportsRunning = true
        override var isRunning: Bool { reportsRunning }
    }

    func testConfigurationNotificationsOnlyInterruptAnEngineThatIsStillStopped() async throws {
        let engine = ConfigurationTestEngine()
        var interruptions = 0
        let observer = DictationAudioCaptureService.observeConfigurationChanges(for: engine) {
            interruptions += 1
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        // Startup can queue a notification before the engine has finished starting.
        engine.reportsRunning = false
        NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: engine)
        engine.reportsRunning = true
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(interruptions, 0, "A stale startup notification must not stop a running microphone")

        // A real interruption leaves the engine stopped and must still be reported.
        engine.reportsRunning = false
        NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: engine)
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(interruptions, 1)
    }

    func testReleaseDuringPermissionRequestNeverStartsTheMicrophone() async throws {
        var grant: CheckedContinuation<Bool, Never>?
        let audio = DictationAudioCaptureService {
            await withCheckedContinuation { grant = $0 }
        }
        let task = Task { try await audio.start() }
        while grant == nil { await Task.yield() }
        audio.stop()
        grant?.resume(returning: true)
        do {
            try await task.value
            XCTFail("A released recording must not start after permission arrives")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertFalse(audio.isRecording)
    }

    func testCancelledStartupCannotOverwriteTheNextSession() async throws {
        var grants: [CheckedContinuation<Bool, Never>] = []
        let audio = DictationAudioCaptureService {
            await withCheckedContinuation { grants.append($0) }
        }
        let coordinator = DictationCoordinator(audio: audio)
        let suite = "DictationTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let store = DictationStore(defaults: defaults, rootURL: root)
        store.settings.duckOtherAudio = false
        store.settings.useScreenContext = false
        coordinator.attach(store: store)
        coordinator.startSession()
        coordinator.stopSession()
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertTrue(grants.isEmpty, "Immediate key release must not open a permission request later")
        coordinator.startSession()
        while grants.isEmpty { await Task.yield() }
        coordinator.cancelSession()
        coordinator.startSession()
        while grants.count < 2 { await Task.yield() }
        grants[0].resume(returning: false)
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(coordinator.phase, .listening)
        XCTAssertTrue(coordinator.isPreparing)
        try renderIfRequested(coordinator: coordinator, store: store, name: "starting")

        // The current request really fails: keep its message visible until dismissed.
        grants[1].resume(returning: false)
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(coordinator.phase, .failed(reason: DictationAudioError.permissionDenied.localizedDescription))
        try renderIfRequested(coordinator: coordinator, store: store, name: "microphone-error")
        coordinator.cancelSession()
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertFalse(audio.isRecording)
    }

    func testMeterDistinguishesSilenceFromAudio() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 320))
        buffer.frameLength = 320
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        samples.initialize(repeating: 0, count: 320)
        XCTAssertEqual(MeetingAudioCaptureService.averagePower(of: buffer), 0)
        samples.update(repeating: 0.04, count: 320)
        XCTAssertGreaterThan(MeetingAudioCaptureService.averagePower(of: buffer), 0.5)
        XCTAssertLessThanOrEqual(MeetingAudioCaptureService.averagePower(of: buffer), 1)
    }

    func testClipboardRestorationPreservesNewCopiesAndHandlesEmptyClipboard() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let service = DictationPasteService(pasteboard: board, postPaste: { true }, targetIsCurrent: { _ in true })
        board.setString("before", forType: .string)
        let pasted4102 = await service.paste(text: "dictation", target: testTarget)
        XCTAssertTrue(pasted4102)
        board.clearContents()
        board.setString("a newer copy", forType: .string)
        try await Task.sleep(for: .milliseconds(420))
        XCTAssertEqual(board.string(forType: .string), "a newer copy")

        board.clearContents()
        let pasted4402 = await service.paste(text: "temporary", target: testTarget)
        XCTAssertTrue(pasted4402)
        try await Task.sleep(for: .milliseconds(420))
        XCTAssertNil(board.string(forType: .string))

        board.setString("before", forType: .string)
        let pasted4618 = await service.paste(text: "dictation", target: testTarget)
        XCTAssertTrue(pasted4618)
        try await Task.sleep(for: .milliseconds(420))
        XCTAssertEqual(board.string(forType: .string), "before")
    }

    func testUnavailablePasteLeavesTheTranscriptForManualPasting() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("before", forType: .string)
        let service = DictationPasteService(pasteboard: board, postPaste: { false }, targetIsCurrent: { _ in true })
        let pasted = await service.paste(text: "keep these words", target: testTarget)
        XCTAssertFalse(pasted)
        try await Task.sleep(for: .milliseconds(420))
        XCTAssertEqual(board.string(forType: .string), "keep these words")
    }

    private var testTarget: DictationPasteTarget {
        DictationPasteTarget(pid: 1, element: AXUIElementCreateApplication(1), valueDigest: SHA256.hash(data: Data()), selection: nil)
    }

    private func renderIfRequested(coordinator: DictationCoordinator, store: DictationStore, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["JACK_DICTATION_SNAPSHOTS"] else { return }
        let host = NSHostingView(rootView: DictationOverlayView(coordinator: coordinator, store: store, onStop: coordinator.stopSession))
        host.frame = NSRect(origin: .zero, size: DictationCaptionLayout.sessionPanelSize)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            .write(to: folder.appendingPathComponent("\(name).png"))
    }
}
