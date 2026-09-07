import Foundation

/// Bounds the caller's wait even when a model ignores task cancellation.
/// The operation retains ownership until it actually returns; callers use
/// onCompletion to release shared model state, never the timeout callback.
@MainActor
enum GenerationDeadline {
    enum Failure: Error { case timedOut }

    static func run(
        seconds: Double,
        onStop: @escaping @MainActor () -> Void = {},
        onCompletion: @escaping @MainActor () -> Void = {},
        operation: @escaping @MainActor () async throws -> String
    ) async throws -> String {
        if Task.isCancelled { onCompletion(); throw CancellationError() }
        let result = AsyncThrowingStream<String, Error>.makeStream()
        let state = State(continuation: result.continuation, onStop: onStop)
        Task { @MainActor in
            defer { onCompletion() }
            guard state.isActive else { return }
            do { state.complete(.success(try await operation())) }
            catch { state.complete(.failure(error)) }
        }
        let timer = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(max(0, seconds))) }
            catch { return }
            state.stop(Failure.timedOut)
        }
        defer { timer.cancel() }
        return try await withTaskCancellationHandler {
            for try await text in result.stream {
                try Task.checkCancellation()
                return text
            }
            throw CancellationError()
        } onCancel: {
            Task { @MainActor in state.stop(CancellationError()) }
        }
    }

    @MainActor
    private final class State {
        private let continuation: AsyncThrowingStream<String, Error>.Continuation
        private var onStop: (@MainActor () -> Void)?
        private(set) var isActive = true

        init(continuation: AsyncThrowingStream<String, Error>.Continuation, onStop: @escaping @MainActor () -> Void) {
            self.continuation = continuation
            self.onStop = onStop
        }

        func stop(_ error: Error) {
            guard isActive else { return }
            onStop?()
            complete(.failure(error))
        }

        func complete(_ result: Result<String, Error>) {
            guard isActive else { return }
            isActive = false
            // The cancelled timer can resume later. It must not keep a
            // finished model alive through this callback in the meantime.
            onStop = nil
            switch result {
            case .success(let text):
                continuation.yield(text)
                continuation.finish()
            case .failure(let error): continuation.finish(throwing: error)
            }
        }
    }
}
