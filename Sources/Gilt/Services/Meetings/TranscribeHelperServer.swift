import Darwin
import Foundation
import OSLog

/// One long-lived `jack-transcribe-stream --serve` process that keeps the
/// Parakeet model loaded between dictations.
///
/// Loading the 731 MB model takes about 10 seconds, and the per-session
/// helper paid that on every dictation while buffered audio piled up behind
/// it. The server pays it once, then runs one session after another. Every
/// reply carries the session id it belongs to, so a late line from a
/// cancelled session is dropped instead of reaching the next one.
final class TranscribeHelperServer: @unchecked Sendable {
    enum Reply: Sendable {
        case partial(StreamingTranscriptUpdate)
        case final(String)
        case offline(String)
        case cancelled
        case failed
    }

    /// Wire opcodes; see Vendor/jack-transcribe-stream/main.c.
    enum Command: UInt32 {
        case begin = 1, audio, finish, cancel, run
    }

    private let helperPath: String
    private let modelPath: String
    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "TranscribeHelperServer")
    private let writes = DispatchQueue(label: "Jack.TranscribeHelperServer.writes", qos: .userInitiated)

    // Guarded by `lock`.
    private let lock = NSLock()
    private var process: Process?
    private var input: FileHandle?
    private var isReady = false
    private var readyWaiters: [UUID: CheckedContinuation<Void, Error>] = [:]
    private var handlers: [UInt32: @Sendable (Reply) -> Void] = [:]
    private var lastSessionID: UInt32 = 0
    private var isLeased = false

    init(helperPath: String, modelPath: String) {
        self.helperPath = helperPath
        self.modelPath = modelPath
    }

    deinit { shutDown() }

    var isRunning: Bool { lock.withLock { process?.isRunning == true } }

    /// Starts the helper if it is not running and waits until the model is loaded.
    func waitUntilReady(timeout: Duration = .seconds(45)) async throws {
        try startIfNeeded()
        if lock.withLock({ isReady }) { return }
        let waiter = UUID()
        let deadline = Task { [weak self] in
            try await Task.sleep(for: timeout)
            self?.failWaiter(waiter, with: MeetingTranscriptionError.transcriptionFailed)
        }
        defer { deadline.cancel() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.withLock {
                    if isReady {
                        continuation.resume()
                    } else {
                        readyWaiters[waiter] = continuation
                    }
                }
            }
        } onCancel: {
            failWaiter(waiter, with: CancellationError())
        }
    }

    /// Exclusive use for one dictation or one offline decode. Returns nil
    /// while another session holds the server; callers then use a one-off helper.
    func openSession(onReply: @escaping @Sendable (Reply) -> Void) -> UInt32? {
        lock.withLock {
            guard !isLeased else { return nil }
            isLeased = true
            lastSessionID &+= 1
            if lastSessionID == 0 { lastSessionID = 1 }
            handlers[lastSessionID] = onReply
            return lastSessionID
        }
    }

    func closeSession(_ id: UInt32) {
        lock.withLock {
            handlers[id] = nil
            isLeased = false
        }
    }

    func send(_ command: Command, session id: UInt32, payload: Data = Data()) {
        var frame = Data(capacity: 12 + payload.count)
        for value in [command.rawValue, id, UInt32(payload.count)] {
            withUnsafeBytes(of: value.littleEndian) { frame.append(contentsOf: $0) }
        }
        frame.append(payload)
        guard let handle = lock.withLock({ input }) else { return }
        // Ordered, off the caller's thread. A failed write means the helper
        // died; its reader sees EOF and fails the open session.
        writes.async { try? handle.write(contentsOf: frame) }
    }

    func send(_ command: Command, session id: UInt32, samples: [Float]) {
        send(command, session: id, payload: samples.withUnsafeBufferPointer { Data(buffer: $0) })
    }

    /// Ends the helper and frees the model, for the idle-unload setting.
    func shutDown() {
        let (running, handle) = lock.withLock { () -> (Process?, FileHandle?) in
            defer { process = nil; input = nil; isReady = false }
            return (process, input)
        }
        // Closing stdin ends the helper's read loop and it exits on its own.
        writes.async { try? handle?.close() }
        if let running, running.isRunning {
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if running.isRunning { running.terminate() }
            }
        }
    }

    // MARK: - Process

    private func startIfNeeded() throws {
        #if arch(x86_64)
        throw MeetingTranscriptionError.unsupportedArchitecture(engine: .parakeetUnifiedStream)
        #else
        try lock.withLock {
            if let process, process.isRunning { return }
            let process = Process()
            let stdinPipe = Pipe()
            let stdoutPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: helperPath)
            process.arguments = [modelPath, "--serve"]
            process.standardInput = stdinPipe
            process.standardOutput = stdoutPipe
            process.standardError = FileHandle.nullDevice
            // A write after the helper dies must throw EPIPE, not kill Jack with SIGPIPE.
            guard fcntl(stdinPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            try process.run()
            self.process = process
            self.input = stdinPipe.fileHandleForWriting
            self.isReady = false
            readReplies(from: stdoutPipe.fileHandleForReading, of: process)
        }
        #endif
    }

    private func readReplies(from handle: FileHandle, of process: Process) {
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                for try await line in handle.bytes.lines {
                    // ggml/Metal may print diagnostics to stdout; only JT> lines are protocol.
                    guard line.hasPrefix("JT>"),
                          let data = line.dropFirst(3).data(using: .utf8),
                          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    else { continue }
                    self?.handle(object, from: process)
                }
            } catch {}
            self?.helperExited(process)
        }
    }

    private func handle(_ object: [String: Any], from source: Process) {
        if object["ready"] as? Bool == true {
            let waiters = lock.withLock { () -> [CheckedContinuation<Void, Error>] in
                guard process === source else { return [] }
                isReady = true
                defer { readyWaiters.removeAll() }
                return Array(readyWaiters.values)
            }
            waiters.forEach { $0.resume() }
            return
        }
        guard let id = (object["sid"] as? NSNumber)?.uint32Value,
              let handler = lock.withLock({ handlers[id] }) else { return }
        if let text = object["final"] as? String {
            handler(.final(text))
        } else if let text = object["offline"] as? String {
            handler(.offline(text))
        } else if object["cancelled"] != nil {
            handler(.cancelled)
        } else if object["error"] != nil {
            logger.error("Helper session failed: \(object["error"] as? String ?? "", privacy: .public)")
            handler(.failed)
        } else {
            handler(.partial(StreamingTranscriptUpdate(
                committed: object["committed"] as? String ?? "",
                tentative: object["tentative"] as? String ?? ""
            )))
        }
    }

    private func helperExited(_ source: Process) {
        let (waiters, open) = lock.withLock { () -> ([CheckedContinuation<Void, Error>], [@Sendable (Reply) -> Void]) in
            guard process === source || process == nil else { return ([], []) }
            process = nil
            input = nil
            isReady = false
            defer { readyWaiters.removeAll() }
            return (Array(readyWaiters.values), Array(handlers.values))
        }
        if !open.isEmpty || !waiters.isEmpty {
            logger.error("Transcribe helper exited while in use")
        }
        waiters.forEach { $0.resume(throwing: MeetingTranscriptionError.transcriptionFailed) }
        open.forEach { $0(.failed) }
    }

    private func failWaiter(_ id: UUID, with error: Error) {
        lock.withLock { readyWaiters.removeValue(forKey: id) }?.resume(throwing: error)
    }
}
