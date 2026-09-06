import XCTest
@testable import Gilt

@MainActor
final class SkillRescanTests: XCTestCase {
    func testLinkedSkillResultsOnlyReturnsLinkedProviders() {
        let codex = makeResult(providerID: "codex", name: "Codex Skills")
        let agents = makeResult(providerID: "agents", name: "Shared Skills")
        let claude = makeResult(providerID: "claude", name: "Claude Skills")

        let linked = ClipboardStore.linkedSkillResults(
            from: [codex, agents, claude],
            linkedProviderIDs: ["agents", "claude"]
        )

        XCTAssertEqual(linked.map(\.provider.id), ["agents", "claude"])
    }

    func testLinkedSkillResultsIgnoresMissingProviders() {
        let codex = makeResult(providerID: "codex", name: "Codex Skills")

        let linked = ClipboardStore.linkedSkillResults(
            from: [codex],
            linkedProviderIDs: ["agents", "codex", "claude"]
        )

        XCTAssertEqual(linked.map(\.provider.id), ["codex"])
    }

    private func makeResult(providerID: String, name: String) -> ProviderScanResult {
        ProviderScanResult(
            provider: AIProvider(
                id: providerID,
                displayName: name,
                color: FolderColorToken.gold.rawValue,
                iconSymbol: "brain.head.profile"
            ),
            skills: [],
            directoryPath: "/tmp/\(providerID)"
        )
    }
}
