import Foundation

/// User-facing on-device AI actions that take a clip's text and produce a new text result
/// (delivered to the clipboard). Declaration order is the menu order.
enum AITextAction: String, CaseIterable, Identifiable {
    case summarize
    case fixGrammar
    case makeFormal
    case makeFriendly
    case bulletize
    case shorten

    var id: String { rawValue }

    /// Menu label (localized — user-facing).
    var label: String {
        switch self {
        case .summarize:
            return L10n.string("ai.action.summarize", default: "Summarize")
        case .fixGrammar:
            return L10n.string("ai.action.fixGrammar", default: "Fix Spelling & Grammar")
        case .makeFormal:
            return L10n.string("ai.action.makeFormal", default: "Make Formal")
        case .makeFriendly:
            return L10n.string("ai.action.makeFriendly", default: "Make Friendly")
        case .bulletize:
            return L10n.string("ai.action.bulletize", default: "Turn into Bullets")
        case .shorten:
            return L10n.string("ai.action.shorten", default: "Make Shorter")
        }
    }

    /// SF Symbol for the menu row.
    var icon: String {
        switch self {
        case .summarize: return "text.line.first.and.arrowtriangle.forward"
        case .fixGrammar: return "checkmark.gobackward"
        case .makeFormal: return "briefcase"
        case .makeFriendly: return "face.smiling"
        case .bulletize: return "list.bullet"
        case .shorten: return "arrow.down.right.and.arrow.up.left"
        }
    }

    /// System instructions handed to the model. English-only on purpose: this is model input, not
    /// display copy, and the model is told to keep the original language. The "ONLY the text" rule
    /// keeps the output paste-ready (no preamble, no quotes).
    var instruction: String {
        let base = "You are a precise writing assistant inside a clipboard app. Reply with ONLY the resulting text: no preamble, no quotation marks around it, no explanation. Always answer in the same language as the input."
        switch self {
        case .summarize:
            return base + " Summarize the user's text into its key points, as briefly as you can while staying faithful to the meaning."
        case .fixGrammar:
            return base + " Correct spelling, grammar, and punctuation only. Preserve the original meaning, tone, line breaks, and formatting. Do not restyle."
        case .makeFormal:
            return base + " Rewrite the text in a clear, professional, formal tone while keeping the meaning."
        case .makeFriendly:
            return base + " Rewrite the text in a warm, friendly, conversational tone while keeping the meaning."
        case .bulletize:
            return base + " Rewrite the text as a tight bulleted list. Start each bullet with '- ' and keep one idea per bullet."
        case .shorten:
            return base + " Make the text noticeably shorter and tighter without losing the core meaning."
        }
    }

    /// Noun used in the success toast, e.g. "Summary copied to your clipboard."
    var resultNoun: String {
        switch self {
        case .summarize:
            return L10n.string("ai.result.summary", default: "Summary")
        case .fixGrammar:
            return L10n.string("ai.result.corrected", default: "Corrected text")
        case .makeFormal:
            return L10n.string("ai.result.formal", default: "Formal rewrite")
        case .makeFriendly:
            return L10n.string("ai.result.friendly", default: "Friendly rewrite")
        case .bulletize:
            return L10n.string("ai.result.bullets", default: "Bulleted version")
        case .shorten:
            return L10n.string("ai.result.shorter", default: "Shorter version")
        }
    }
}
