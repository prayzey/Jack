import Foundation

/// Errors surfaced by `OnDeviceAIService`. Kept OS-agnostic (no FoundationModels symbols) so callers
/// on any macOS version can catch and present them.
enum OnDeviceAIError: LocalizedError, Equatable {
    /// The on-device model can't run in the current state (OS too old, device ineligible, AI off, etc.).
    case unsupported(OnDeviceAIStatus)
    /// The prompt plus context exceeded the model's context window. Caller should shorten input.
    case contextWindowExceeded
    /// The model produced nothing usable.
    case emptyResult
    /// A generation failure we couldn't classify; carries the framework's message for diagnostics.
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupported(let status):
            return status.message
        case .contextWindowExceeded:
            return L10n.string(
                "ai.error.contextWindowExceeded",
                default: "That was a bit too long for the on-device model. Try a shorter selection."
            )
        case .emptyResult:
            return L10n.string(
                "ai.error.emptyResult",
                default: "The on-device model didn't return anything this time. Please try again."
            )
        case .generationFailed:
            return L10n.string(
                "ai.error.generationFailed",
                default: "The on-device model couldn't finish that request. Please try again."
            )
        }
    }
}
