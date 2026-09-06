import Foundation
import OSLog
import FoundationModels

/// The single entry point to Apple's on-device Foundation model (macOS 26+, Apple Intelligence).
///
/// Design rules that the rest of the app depends on:
/// - This is the ONLY file that imports `FoundationModels`. Every other surface goes through here,
///   so the macOS-26-only symbols never leak into view code or the core clipboard logic.
/// - All public methods are callable on any macOS version. They guard with `#available` internally
///   and throw `OnDeviceAIError.unsupported` when the model can't run, so callers don't need their
///   own availability dance for the common text path.
/// - Structured (`Generable`) helpers are unavoidably `@available(macOS 26.0, *)` because the
///   `Generable` protocol itself is, so those callers wrap the call in `if #available`.
@MainActor
final class OnDeviceAIService: ObservableObject {
    static let shared = OnDeviceAIService()

    /// Cached availability, published so Settings and disclaimers update live. Refresh on demand
    /// (e.g. when a settings pane appears) because the user can toggle Apple Intelligence at any time.
    @Published private(set) var status: OnDeviceAIStatus = .unknown

    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "OnDeviceAI")

    private init() {
        refreshStatus()
    }

    var isUsable: Bool { status.isUsable }

    /// Re-query the framework for current availability. Cheap; safe to call when a view appears.
    func refreshStatus() {
        let resolved: OnDeviceAIStatus
        if #available(macOS 26.0, *) {
            resolved = Self.resolveStatus()
        } else {
            resolved = .unsupportedOS
        }
        if resolved != status {
            status = resolved
            logger.log("On-device AI status: \(resolved.rawValue, privacy: .public)")
        }
    }

    // MARK: - Plain text generation

    /// Generate a plain-text completion. `instructions` is the system prompt (role/voice/rules);
    /// `prompt` is the user turn. Throws `OnDeviceAIError` (never a raw framework error).
    func respond(
        instructions: String?,
        to prompt: String,
        temperature: Double? = nil
    ) async throws -> String {
        guard #available(macOS 26.0, *) else {
            throw OnDeviceAIError.unsupported(.unsupportedOS)
        }
        // Re-check live state: hardware-eligible but AI-off should fail clearly, not crash.
        let live = Self.resolveStatus()
        guard live.isUsable else { throw OnDeviceAIError.unsupported(live) }
        return try await Self.generateText(instructions: instructions, prompt: prompt, temperature: temperature)
    }

    // MARK: - FoundationModels-touching internals (macOS 26+ only)

    @available(macOS 26.0, *)
    private static func resolveStatus() -> OnDeviceAIStatus {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            return .appleIntelligenceOff
        case .unavailable(.modelNotReady):
            return .modelNotReady
        case .unavailable:
            return .unknown
        @unknown default:
            return .unknown
        }
    }

    @available(macOS 26.0, *)
    private static func makeSession(instructions: String?) -> LanguageModelSession {
        if let instructions, !instructions.isEmpty {
            return LanguageModelSession(instructions: instructions)
        }
        return LanguageModelSession()
    }

    @available(macOS 26.0, *)
    private static func options(_ temperature: Double?) -> GenerationOptions {
        if let temperature {
            return GenerationOptions(temperature: temperature)
        }
        return GenerationOptions()
    }

    @available(macOS 26.0, *)
    private static func generateText(
        instructions: String?,
        prompt: String,
        temperature: Double?
    ) async throws -> String {
        let session = makeSession(instructions: instructions)
        do {
            let response = try await session.respond(to: prompt, options: options(temperature))
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw OnDeviceAIError.emptyResult }
            return text
        } catch let error as LanguageModelSession.GenerationError {
            throw mapGenerationError(error)
        }
    }

    /// Generate a strongly-typed `Generable` value. macOS 26+ only because `Generable` is.
    @available(macOS 26.0, *)
    func respond<Content: Generable>(
        instructions: String?,
        to prompt: String,
        generating type: Content.Type,
        temperature: Double? = nil
    ) async throws -> Content {
        let live = Self.resolveStatus()
        guard live.isUsable else { throw OnDeviceAIError.unsupported(live) }
        let session = Self.makeSession(instructions: instructions)
        do {
            let response = try await session.respond(
                to: prompt,
                generating: type,
                options: Self.options(temperature)
            )
            return response.content
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.mapGenerationError(error)
        }
    }

    @available(macOS 26.0, *)
    private static func mapGenerationError(_ error: LanguageModelSession.GenerationError) -> OnDeviceAIError {
        switch error {
        case .exceededContextWindowSize:
            return .contextWindowExceeded
        default:
            return .generationFailed(error.localizedDescription)
        }
    }
}
