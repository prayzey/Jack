import Foundation
import OSLog

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Dictation polish via Apple's on-device Foundation model (macOS 26+,
/// Apple Intelligence). The model runs in an OS daemon, so it costs the app
/// essentially zero memory — which is exactly why it's the polish engine for
/// 8 GB Macs, where keeping the 2.4 GB Qwen resident next to the streaming
/// ASR helper would push the machine into swap.
///
/// Linking note: FoundationModels is newer than the macOS 14 deployment
/// target. The linker auto-weak-links it (LC_LOAD_WEAK_DYLIB), so the binary
/// still launches on older macOS as long as every use stays behind the
/// `#available` guards below. Do not reference FM types outside those guards.
///
/// Failure posture matches the Qwen path: any error (guardrail false
/// positive, context overflow, rate limit) returns nil and the caller ships
/// the raw transcript. Dictation must never block or lose words to a safety
/// refusal, so the session uses `permissiveContentTransformations` — Apple's
/// guardrail mode for transforming user-authored text.
@MainActor
enum AppleIntelligencePolisher {
    private static let logger = Logger(subsystem: AppBrand.logSubsystem, category: "AppleIntelligencePolish")

    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else { return false }
        if case .available = permissiveModel.availability { return true }
        return false
        #else
        return false
        #endif
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static var permissiveModel: SystemLanguageModel {
        SystemLanguageModel(guardrails: .permissiveContentTransformations)
    }
    #endif

    /// Run one polish completion. `prompt` is the full self-contained prompt
    /// (built by `DictationStyleEngine.makePrompt`); `onPartial` receives the
    /// cumulative response text as it streams. Returns nil when the model is
    /// unavailable or the request fails for any reason.
    static func polish(
        prompt: String,
        onPartial: (@MainActor (String) -> Void)? = nil
    ) async -> String? {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else { return nil }
        let model = permissiveModel
        guard case .available = model.availability else { return nil }
        let session = LanguageModelSession(model: model)
        do {
            var latest = ""
            // Snapshots are cumulative — assign, never append.
            let stream = session.streamResponse(to: prompt)
            for try await snapshot in stream {
                latest = snapshot.content
                onPartial?(latest)
            }
            return latest.isEmpty ? nil : latest
        } catch {
            logger.error("Apple Intelligence polish failed: \(error.localizedDescription)")
            return nil
        }
        #else
        return nil
        #endif
    }
}
