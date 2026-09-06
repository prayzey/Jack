import Foundation

/// Builds prompts for the local summarizer + Q&A model. Pulled out of the
/// service file so we can unit-test the prompt shape without booting MLX.
struct MeetingPromptBuilder {
    var language: MeetingLanguage = .auto

    func summaryPrompt(for chunks: [MeetingTranscriptChunk], previousNotes: String?) -> String {
        let transcript = chunks
            .map { "[\($0.formattedTimestamp)] \($0.text)" }
            .joined(separator: "\n")

        var prompt = "You are a senior analyst summarizing a real recording. The transcript may be a business meeting, a sermon, a lecture, a coaching call, a podcast, or a casual conversation. Pick the right register and emphasize what a thoughtful listener would actually take away."
        prompt += "\nLanguage: \(language.bcpTag)"
        prompt += "\nOutput must be valid JSON with the following shape:"
        prompt += "\n{"
        prompt += "\n  \"headline\": string,"
        prompt += "\n  \"bullets\": string[],"
        prompt += "\n  \"decisions\": string[],"
        prompt += "\n  \"actionItems\": string[],"
        prompt += "\n  \"followUpQuestions\": string[]"
        prompt += "\n}"
        prompt += "\nRules:"
        prompt += "\n- Headline: one sentence that captures the actual topic of THIS conversation. Not a generic label like \"Discussion of leadership\" — name the specific point being made."
        prompt += "\n- Bullets: 4 to 7 substantive bullets. Each bullet is a complete thought (1-2 sentences) that explains what was said and why it matters. Capture themes, arguments, evidence, and turning points — not just keywords."
        prompt += "\n- For sermons and lectures: include the main teaching, supporting examples, scripture or sources referenced, and any practical application."
        prompt += "\n- For business meetings: include the problem framing, options considered, and rationale."
        prompt += "\n- Decisions: only fill if a real choice was made. Otherwise leave empty."
        prompt += "\n- Action items: only fill if someone committed to do something. Otherwise leave empty."
        prompt += "\n- Follow-up questions: 2-4 questions a listener would genuinely want answered next, specific to THIS content."
        prompt += "\n- Never fabricate names, dates, scripture references, or commitments not present in the transcript."
        prompt += "\n- If a section legitimately has no content, return an empty array — do not pad."

        if let previousNotes, !previousNotes.isEmpty {
            prompt += "\n\nPrevious rolling notes:\n\(previousNotes)"
        }
        prompt += "\n\nTranscript:\n\(transcript)"
        prompt += "\n\nReturn ONLY the JSON object. Do not add any prose before or after."
        return prompt
    }

    func answerPrompt(
        question: String,
        relevantChunks: [MeetingTranscriptChunk],
        rollingNotes: String,
        isFollowUp: Bool = false
    ) -> String {
        let snippets = relevantChunks
            .map { "[\($0.formattedTimestamp)] \($0.text)" }
            .joined(separator: "\n")

        var prompt = "You are answering a question about a recording the user just listened to. The content may be a meeting, sermon, lecture, or conversation. Answer the way a thoughtful person who actually listened would — synthesize themes, explain context, and quote sparingly."
        prompt += "\nLanguage: \(language.bcpTag)"
        prompt += "\n"
        prompt += "\nResponse rules:"
        if isFollowUp {
            prompt += "\n- This is a follow-up asking for MORE depth. Expand on the prior answer: explain the surrounding context, give 2-3 concrete examples or quotes from the transcript, and surface implications the speaker didn't make explicit."
            prompt += "\n- Aim for 5 to 8 sentences. Do not repeat earlier wording verbatim."
        } else {
            prompt += "\n- Aim for 3 to 6 sentences for substantive questions. Short factual questions can be shorter."
            prompt += "\n- For overview questions (\"what was discussed\", \"summarize\", \"catch me up\"), synthesize the arc of the conversation — main point, supporting ideas, and where it landed."
        }
        prompt += "\n- Lead with the direct answer. Then briefly cite specific timestamps in the form (MM:SS) to show where you got it."
        prompt += "\n- If the transcript does not contain enough to answer, say so plainly and suggest a related question the transcript COULD answer based on what's there."
        prompt += "\n- Never invent names, decisions, action items, or quotes. Don't say \"the speaker said X\" unless they actually said it."
        prompt += "\n- For greetings, respond briefly and invite a content question."

        prompt += "\n\nRolling notes:\n\(rollingNotes.isEmpty ? "(none yet)" : rollingNotes)"
        prompt += "\n\nRelevant transcript snippets:\n\(snippets.isEmpty ? "(none matched — answer from rolling notes if possible, otherwise say the transcript doesn't cover this yet)" : snippets)"
        prompt += "\n\nQuestion: \(question)"
        prompt += "\n\nAnswer now:"
        return prompt
    }

    /// Builds a prompt that asks the LLM to propose 4 contextual questions the
    /// user could click to learn more about a meeting in progress. Used by the
    /// "Ask" tab to replace generic hardcoded suggestions with topical ones
    /// that adapt as the transcript grows.
    func suggestedQuestionsPrompt(for chunks: [MeetingTranscriptChunk]) -> String {
        let transcript = chunks
            .map { "[\($0.formattedTimestamp)] \($0.text)" }
            .joined(separator: "\n")

        var prompt = "You are looking at the live transcript of a recording in progress. The user wants 4 short, specific questions they could click to dig deeper. The content may be a business meeting, a sermon, a lecture, a coaching call, or a conversation — match the register."
        prompt += "\nLanguage: \(language.bcpTag)"
        prompt += "\n"
        prompt += "\nRules:"
        prompt += "\n- Output a JSON array of exactly 4 strings. Nothing else."
        prompt += "\n- Each question must be 4 to 10 words. No filler."
        prompt += "\n- Questions must be specific to what has actually been said. Do not output generic templates like \"What are the next steps?\" unless that fits the content."
        prompt += "\n- Pull from real topics, names, terms, scripture, or claims that appeared in the transcript."
        prompt += "\n- At least one question should ask for a deeper explanation of a concept the speaker introduced."
        prompt += "\n- At least one question should ask about implications, examples, or applications."
        prompt += "\n- Do not number, prefix, or quote the questions inside the array."

        prompt += "\n\nTranscript so far:\n\(transcript)"
        prompt += "\n\nReturn ONLY the JSON array, e.g. [\"...\", \"...\", \"...\", \"...\"]"
        return prompt
    }

    /// Prompt that extends an in-progress story with one new paragraph drawn
    /// from the latest slice of transcript. The existing essay is locked
    /// context the model must not rewrite. Em-dashes are explicitly banned.
    func storyExtensionPrompt(
        existingStory: String,
        newChunks: [MeetingTranscriptChunk]
    ) -> String {
        let newTranscript = newChunks
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        var prompt = "You are a careful writer extending a meeting recap that is already in progress."
        prompt += " You write in the voice of a thoughtful colleague summarizing what happened, not a transcription engine."
        prompt += "\nLanguage: \(language.bcpTag)"
        prompt += "\n"
        prompt += "\nRULES"
        prompt += "\n1. Write in flowing prose. Full sentences. Connected paragraphs. No bullets, no fragments, no headers."
        prompt += "\n2. Do NOT use em-dashes or en-dashes anywhere. Use periods, commas, semicolons, or parentheses instead."
        prompt += "\n3. Do NOT include timestamps, speaker names, or stage directions like 'the meeting then turned to'."
        prompt += "\n4. Do NOT rewrite, edit, or refer back to any paragraph in <existing_essay>. Treat it as immutable. The user may have edited it. Respect their wording."
        prompt += "\n5. Append exactly one paragraph. Two only if the new transcript clearly covers two distinct topics."
        prompt += "\n6. Match the voice, tense, and rhythm of the existing essay. If it is matter-of-fact, stay matter-of-fact."
        prompt += "\n7. If the new transcript adds nothing substantive (small talk, silence, off-topic), return the literal string <NO_EXTENSION> and nothing else."
        prompt += "\n8. Output only the new paragraph. No preamble. No 'Here is the next paragraph.' Just the paragraph."

        prompt += "\n\n<existing_essay>"
        if existingStory.isEmpty {
            prompt += "\n(none yet, this is the opening paragraph of the essay)"
        } else {
            prompt += "\n\(existingStory)"
        }
        prompt += "\n</existing_essay>"

        prompt += "\n\n<new_transcript>"
        prompt += "\n\(newTranscript.isEmpty ? "(nothing new)" : newTranscript)"
        prompt += "\n</new_transcript>"

        prompt += "\n\nWrite the next paragraph now:"
        return prompt
    }

    /// Prompt that drafts the full essay from scratch when the user clicks
    /// "Regenerate". Same prose rules as the extension prompt.
    func storyRegeneratePrompt(
        transcript: [MeetingTranscriptChunk],
        meetingTitle: String
    ) -> String {
        let body = transcript
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        var prompt = "You are writing a recap of a meeting in essay form."
        prompt += " Write three to six paragraphs of flowing prose that tell the story of what was discussed,"
        prompt += " in the voice of a thoughtful colleague writing up notes after the call."
        prompt += "\nLanguage: \(language.bcpTag)"
        prompt += "\n"
        prompt += "\nRULES"
        prompt += "\n1. Full sentences, connected paragraphs. No bullets, no headers, no quoted dialogue."
        prompt += "\n2. Do NOT use em-dashes or en-dashes anywhere. Use periods, commas, semicolons, or parentheses instead."
        prompt += "\n3. Do NOT include timestamps."
        prompt += "\n4. Refer to participants naturally (\"Adam led with the data\") rather than as a transcript (\"Adam: the data shows…\")."
        prompt += "\n5. Cover the arc of the conversation: framing, options weighed, decisions, action items, open threads."
        prompt += "\n6. Never invent names, decisions, quotes, or commitments not present in the transcript."
        prompt += "\n7. Output only the essay. No title, no preamble, no closing remarks."

        prompt += "\n\nMeeting title: \(meetingTitle.isEmpty ? "(untitled)" : meetingTitle)"
        prompt += "\n\nTranscript:\n\(body)"
        prompt += "\n\nWrite the essay now:"
        return prompt
    }
}
