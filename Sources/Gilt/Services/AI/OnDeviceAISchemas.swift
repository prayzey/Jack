import Foundation
import FoundationModels

// Structured-output schemas for guided generation. Each type is macOS 26+ only because the
// `@Generable` / `@Guide` macros and the `Generable` protocol they synthesize are. Callers reach
// these only from inside `if #available(macOS 26.0, *)` blocks (see ClipboardStore+AI).
//
// Keep property names and @Guide descriptions in English: they are part of the prompt the model
// sees (model input), not user-facing display copy, so the localization guardrails don't apply.

/// A list of concrete tasks extracted from a clip's text.
@available(macOS 26.0, *)
@Generable(description: "Concrete action items found in a block of text")
struct AIActionItemList {
    @Guide(description: "Each distinct task, to-do, or commitment, phrased as a short imperative. Empty if the text contains none.")
    var items: [String]
}

/// Combined title + tags produced in a single call when a clip is captured (opt-in enrichment).
@available(macOS 26.0, *)
@Generable(description: "A short title and topic tags for a captured clip")
struct AIClipEnrichmentDraft {
    @Guide(description: "A short, descriptive title for the content: at most six words, no quotes, no trailing period")
    var title: String
    @Guide(description: "Up to five short, lowercase topic keywords describing what the content is about")
    var tags: [String]
}

/// AI-assisted tags + a friendly category for a clipboard item.
@available(macOS 26.0, *)
@Generable(description: "Topic tags and a category for a clipboard item")
struct AIClipTagging {
    @Guide(description: "Up to five short, lowercase topic keywords that describe what this content is about")
    var tags: [String]
    @Guide(description: "A short human-friendly category name for this content, one to three words, title case")
    var category: String
}

/// A reminder candidate detected in a clip.
@available(macOS 26.0, *)
@Generable(description: "A reminder detected in a block of text")
struct AIReminderDraft {
    @Guide(description: "True only if the text clearly contains a task, commitment, deadline, or something to remember")
    var isActionable: Bool
    @Guide(description: "A short reminder title in imperative form, for example 'Email Sam the signed invoice'")
    var title: String
    @Guide(description: "Any date or time mentioned for this reminder, copied as written. Empty string if none is mentioned.")
    var whenText: String
}

/// Structured interpretation of a natural-language search query, mapped into Jack's existing filters.
@available(macOS 26.0, *)
@Generable(description: "A clipboard search query broken into structured filters")
struct AISearchInterpretation {
    @Guide(description: "Content type to filter by. Exactly one of: text, link, image, audio, color. Empty string for any type.")
    var type: String
    @Guide(description: "Name of the source app to filter by if the query names one (for example Safari, Notes). Empty string otherwise.")
    var app: String
    @Guide(description: "The core keywords to match against item content, space separated, with filler words removed. May be empty.")
    var keywords: String
}

/// Structured meeting summary the model fills in. Mapped into the app's `MeetingSummary` afterward,
/// so this stays flat (plain strings) for reliable on-device generation.
@available(macOS 26.0, *)
@Generable(description: "A concise structured summary of a meeting transcript")
struct AIMeetingSummaryDraft {
    @Guide(description: "A one-line headline capturing the meeting's main outcome")
    var headline: String
    @Guide(description: "The most important points from the meeting, each a short sentence")
    var bullets: [String]
    @Guide(description: "Decisions that were made, each a short sentence. Empty if none.")
    var decisions: [String]
    @Guide(description: "Action items or tasks agreed on, each a short imperative sentence. Empty if none.")
    var actionItems: [String]
    @Guide(description: "Open questions or follow-ups raised, each a short sentence. Empty if none.")
    var followUps: [String]
}
