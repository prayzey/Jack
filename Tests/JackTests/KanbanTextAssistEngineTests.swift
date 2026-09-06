import XCTest
@testable import Gilt

@MainActor
final class KanbanTextAssistEngineTests: XCTestCase {
    func testMakePromptIncludesDraftAndAction() {
        let prompt = KanbanTextAssistEngine.makePrompt(
            action: .clarify,
            draft: "fix login bug asap"
        )
        XCTAssertTrue(prompt.contains("fix login bug asap"))
        XCTAssertTrue(prompt.contains("ACTION — Clarify"))
        XCTAssertTrue(prompt.contains("Improved task title:"))
    }

    func testMakePromptSpellsOutEachBuiltInAction() {
        for action in KanbanTextAssistAction.allCases {
            let prompt = KanbanTextAssistEngine.makePrompt(action: action, draft: "sample")
            switch action {
            case .fixSpelling:
                XCTAssertTrue(prompt.contains("Fix spelling"))
            case .polish:
                XCTAssertTrue(prompt.contains("Polish"))
            case .clarify:
                XCTAssertTrue(prompt.contains("Clarify"))
            case .shorten:
                XCTAssertTrue(prompt.contains("Shorten"))
            }
        }
    }

    func testMakePromptEmbedsCustomInstruction() {
        let preset = KanbanCustomAssistPreset(
            title: "Make epic",
            instruction: "Rewrite as a concise epic title for engineering."
        )
        let prompt = KanbanTextAssistEngine.makePrompt(
            choice: .custom(preset),
            draft: "fix the thing"
        )
        XCTAssertTrue(prompt.contains("ACTION — Make epic:"))
        XCTAssertTrue(prompt.contains("concise epic title"))
    }

    func testCatalogOrdersBuiltInsBeforeCustom() {
        let custom = KanbanCustomAssistPreset(title: "VIP", instruction: "Add VIP prefix.")
        let choices = KanbanAssistCatalog.choices(customPresets: [custom])
        XCTAssertEqual(choices.count, KanbanTextAssistAction.allCases.count + 1)
        XCTAssertTrue(choices.first?.id.hasPrefix("builtin.") == true)
        XCTAssertEqual(choices.last?.id, "custom.\(custom.id.uuidString)")
    }

    func testSanitizedPresetDropsEmptyFields() {
        XCTAssertNil(
            KanbanCustomAssistPreset(title: "  ", instruction: "Do something").sanitized()
        )
        XCTAssertEqual(
            KanbanCustomAssistPreset(title: "  Ship it ", instruction: " Imperative. ").sanitized()?.title,
            "Ship it"
        )
    }

    func testCleanOutputStripsPrefixAndQuotes() {
        XCTAssertEqual(
            KanbanTextAssistEngine.cleanOutput("Improved task title: \"Ship beta\""),
            "Ship beta"
        )
    }

    func testCleanOutputKeepsFirstLineOnly() {
        XCTAssertEqual(
            KanbanTextAssistEngine.cleanOutput("First line\nSecond line"),
            "First line"
        )
    }

    func testEmptyDraftReturnsUnchangedWithoutCallingModel() async {
        let cache = FileManager.default.temporaryDirectory
            .appendingPathComponent("kanban-assist-test-\(UUID().uuidString)", isDirectory: true)
        let engine = KanbanTextAssistEngine(cacheDirectory: cache)
        let outcome = await engine.process(text: "   ", choice: .builtIn(.polish))
        XCTAssertEqual(outcome, .unchanged)
    }

    func testAppSettingsRoundTripsKanbanCustomPresets() throws {
        var settings = AppSettings()
        let preset = KanbanCustomAssistPreset(
            title: "Actionable",
            instruction: "Rewrite as a verb-led task under 12 words."
        )
        settings.kanbanCustomAssistPresets = [preset]
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.kanbanCustomAssistPresets, [preset])
    }
}
