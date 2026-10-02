import Foundation

/// Why an app sounds different from its own slider right now.
enum SoundAppEffect: Equatable {
    case none
    case soloed
    case silencedBySolo
    /// Another app has the mic (a call, a dictation app), so this one is lowered.
    case loweredForMic(byAppName: String)
    case loweredForDictation
    case muffledForDictation
}

/// The automatic layers on top of each app's own level: solo, call mode,
/// and Jack's dictation ducking. Pure, so the precedence is testable.
struct SoundMixRules: Equatable {
    var soloAppID: String?
    /// Apps with the microphone open, keyed by bundle ID, valued by name.
    var micApps: [String: String] = [:]
    /// Volume for other apps while one uses the mic; nil when call mode is off.
    var callModeLevel: Float?
    /// Volume for every app while Jack dictates; nil when not dictating.
    var dictationLevel: Float?
    /// How every app is muffled while Jack dictates; nil when it isn't.
    var dictationMuffle: SoundMuffle?

    func effect(for appID: String) -> SoundAppEffect {
        if let soloAppID { return appID == soloAppID ? .soloed : .silencedBySolo }
        if dictationMuffle != nil { return .muffledForDictation }
        if dictationLevel != nil { return .loweredForDictation }
        if callModeLevel != nil, micApps[appID] == nil,
           let caller = micApps.sorted(by: { $0.key < $1.key }).first {
            return .loweredForMic(byAppName: caller.value)
        }
        return .none
    }

    /// What the tap should play the app at, given its own saved level.
    func gain(for appID: String, level: SoundAppLevel) -> Float {
        switch effect(for: appID) {
        case .soloed, .none, .muffledForDictation: return level.gain
        case .silencedBySolo: return 0
        case .loweredForMic: return level.gain * (callModeLevel ?? 1)
        case .loweredForDictation: return level.gain * (dictationLevel ?? 1)
        }
    }
}
