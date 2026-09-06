import XCTest
@testable import Gilt

/// Pin down the prompt shape + response-cleanup behavior so a future change
/// to `JackChatPromptBuilder` can't silently regress the chat UX. The
/// builder is pure (no LLM calls), so these tests run instantly.
final class JackChatPromptBuilderTests: XCTestCase {

    // MARK: - Prompt shape

    func testPromptIncludesPersonaOverrideAndNewUserMessage() {
        let prompt = JackChatPromptBuilder.makePrompt(history: [], userMessage: "Hello")

        XCTAssertTrue(
            prompt.contains("You are Jack"),
            "Persona override must be in every prompt — the underlying model has a different baked-in system prompt we need to displace"
        )
        XCTAssertTrue(prompt.contains("User: Hello"))
        XCTAssertTrue(
            prompt.hasSuffix("Jack:"),
            "Prompt must end with 'Jack:' so the model continues by speaking as Jack"
        )
    }

    func testEmptyHistoryGetsPlaceholderLine() {
        let prompt = JackChatPromptBuilder.makePrompt(history: [], userMessage: "Hi")
        XCTAssertTrue(
            prompt.contains("(none yet"),
            "An empty history should be marked clearly so the model knows it's a fresh conversation"
        )
    }

    func testMultiTurnHistoryRendersInOrder() {
        let history: [JackChatMessage] = [
            JackChatMessage(role: .user, text: "What's 2+2?"),
            JackChatMessage(role: .jack, text: "Four."),
            JackChatMessage(role: .user, text: "And 3+3?"),
            JackChatMessage(role: .jack, text: "Six.")
        ]
        let prompt = JackChatPromptBuilder.makePrompt(history: history, userMessage: "And 4+4?")

        guard
            let firstUser = prompt.range(of: "User: What's 2+2?"),
            let firstJack = prompt.range(of: "Jack: Four."),
            let secondUser = prompt.range(of: "User: And 3+3?"),
            let newUser = prompt.range(of: "User: And 4+4?")
        else {
            return XCTFail("Expected each turn to be rendered as a 'Role: text' line")
        }

        XCTAssertLessThan(firstUser.lowerBound, firstJack.lowerBound)
        XCTAssertLessThan(firstJack.lowerBound, secondUser.lowerBound)
        XCTAssertLessThan(secondUser.lowerBound, newUser.lowerBound)
    }

    // MARK: - Budget trimming

    func testHistoryGetsTrimmedFromOldestWhenOverBudget() {
        // Build messages whose combined text exceeds the budget. Verify the
        // *oldest* messages drop first so the conversation tail stays intact.
        let chunk = String(repeating: "a", count: 1500)
        let messages: [JackChatMessage] = (0..<10).map { idx in
            JackChatMessage(role: idx.isMultiple(of: 2) ? .user : .jack, text: "\(idx)-" + chunk)
        }

        let trimmed = JackChatPromptBuilder.trimToBudget(messages, charLimit: 6000)

        XCTAssertLessThan(
            trimmed.reduce(0) { $0 + $1.text.count },
            6000 + chunk.count,
            "Trimmed history must fit roughly under the budget (one over-the-line message is OK because we drop whole messages)"
        )
        XCTAssertLessThan(trimmed.count, messages.count, "At least one message should have been dropped")

        // Tail preserved: the last message in `trimmed` should still be the
        // last message in `messages`.
        XCTAssertEqual(trimmed.last?.id, messages.last?.id)
    }

    func testHistoryUnchangedWhenUnderBudget() {
        let messages: [JackChatMessage] = [
            JackChatMessage(role: .user, text: "Hi"),
            JackChatMessage(role: .jack, text: "Hey there.")
        ]
        let trimmed = JackChatPromptBuilder.trimToBudget(messages, charLimit: 6000)
        XCTAssertEqual(trimmed, messages)
    }

    // MARK: - Response cleanup

    func testCleanResponseStripsTrailingFakeUserTurn() {
        // Qwen sometimes keeps generating fake "User:" / "Jack:" lines after
        // its real reply. We must cut them off — they break the chat UX.
        let raw = "Four.\nUser: And then?\nJack: Five."
        XCTAssertEqual(JackChatPromptBuilder.cleanResponse(raw), "Four.")
    }

    func testCleanResponseStripsFakeJackContinuation() {
        let raw = "Sure thing.\nJack: Anything else?"
        XCTAssertEqual(JackChatPromptBuilder.cleanResponse(raw), "Sure thing.")
    }

    func testCleanResponseStripsConversationHeaderHallucination() {
        let raw = "Hello! How can I help?\n--- Conversation so far ---\nUser: …"
        XCTAssertEqual(JackChatPromptBuilder.cleanResponse(raw), "Hello! How can I help?")
    }

    func testCleanResponseLeavesNormalAnswersAlone() {
        let raw = "  Sure, here's a list:\n- one\n- two\n- three  "
        XCTAssertEqual(
            JackChatPromptBuilder.cleanResponse(raw),
            "Sure, here's a list:\n- one\n- two\n- three"
        )
    }

    func testCleanResponseHandlesEmpty() {
        XCTAssertEqual(JackChatPromptBuilder.cleanResponse(""), "")
        XCTAssertEqual(JackChatPromptBuilder.cleanResponse("   \n  "), "")
    }
}
