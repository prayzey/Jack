import Foundation

/// Availability of Apple's on-device Foundation model, expressed in a form that is safe to
/// store and display on ANY macOS version.
///
/// IMPORTANT: This type must never reference a `FoundationModels` symbol. Those types only exist
/// on macOS 26+, so `OnDeviceAIService` maps the framework's availability into this OS-agnostic
/// enum before anything else in the app touches it. That lets Settings, view models, and feature
/// code reason about availability without being gated behind `if #available(macOS 26, *)`.
enum OnDeviceAIStatus: String, Codable, Equatable, Sendable {
    /// Apple Intelligence is on and the on-device model is ready to use.
    case available
    /// The running OS is older than macOS 26, so the framework does not exist.
    case unsupportedOS
    /// The Mac hardware does not support Apple Intelligence (e.g. Intel Macs).
    case deviceNotEligible
    /// Apple Intelligence is supported but the user has not enabled it.
    case appleIntelligenceOff
    /// Apple Intelligence is enabled but the model is still downloading or warming up.
    case modelNotReady
    /// Unavailable for a reason we do not have a specific message for.
    case unknown

    /// Whether AI features can actually run right now.
    var isUsable: Bool { self == .available }

    /// Whether the user can do something to fix this state (vs. a hard hardware/OS limit).
    var isResolvableByUser: Bool {
        switch self {
        case .appleIntelligenceOff, .modelNotReady: return true
        case .available, .unsupportedOS, .deviceNotEligible, .unknown: return false
        }
    }

    /// Short headline for the disclaimer / status row.
    var title: String {
        switch self {
        case .available:
            return L10n.string("ai.status.available.title", default: "On-device AI is ready")
        case .unsupportedOS:
            return L10n.string("ai.status.unsupportedOS.title", default: "Requires macOS 26")
        case .deviceNotEligible:
            return L10n.string("ai.status.deviceNotEligible.title", default: "Not supported on this Mac")
        case .appleIntelligenceOff:
            return L10n.string("ai.status.appleIntelligenceOff.title", default: "Turn on Apple Intelligence")
        case .modelNotReady:
            return L10n.string("ai.status.modelNotReady.title", default: "Preparing the on-device model")
        case .unknown:
            return L10n.string("ai.status.unknown.title", default: "On-device AI is unavailable")
        }
    }

    /// Friendly explanation shown to the user. Written for non-technical people, no jargon.
    var message: String {
        switch self {
        case .available:
            return L10n.string(
                "ai.status.available.message",
                default: "Apple's on-device model is ready. These features run privately on your Mac, for free, and work offline."
            )
        case .unsupportedOS:
            return L10n.string(
                "ai.status.unsupportedOS.message",
                default: "On-device AI features need macOS 26 or later. You're on an earlier version, so these features stay off. Everything else in Jack works as usual."
            )
        case .deviceNotEligible:
            return L10n.string(
                "ai.status.deviceNotEligible.message",
                default: "On-device AI needs an Apple silicon Mac that supports Apple Intelligence. This Mac can't run these features, so they're hidden. Everything else in Jack works as usual."
            )
        case .appleIntelligenceOff:
            return L10n.string(
                "ai.status.appleIntelligenceOff.message",
                default: "These features use Apple Intelligence, which is currently turned off. Turn it on in System Settings, under Apple Intelligence & Siri, to start using them."
            )
        case .modelNotReady:
            return L10n.string(
                "ai.status.modelNotReady.message",
                default: "Apple Intelligence is still getting the on-device model ready, and it may still be downloading. Try again in a little while."
            )
        case .unknown:
            return L10n.string(
                "ai.status.unknown.message",
                default: "On-device AI isn't available right now. Everything else in Jack works as usual."
            )
        }
    }
}
