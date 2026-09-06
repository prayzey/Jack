import Foundation

/// User-authored Kanban writing action shown in chips and the task context menu.
/// `title` is the button label; `instruction` is the system-style prompt block
/// sent to the on-device model (not localized — user content).
struct KanbanCustomAssistPreset: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var title: String
    var instruction: String

    init(
        id: UUID = UUID(),
        title: String,
        instruction: String
    ) {
        self.id = id
        self.title = title
        self.instruction = instruction
    }

    /// Trims fields and drops presets that would be empty in the UI or model prompt.
    func sanitized() -> KanbanCustomAssistPreset? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedInstruction.isEmpty else { return nil }
        let cappedInstruction = String(trimmedInstruction.prefix(Self.maxInstructionLength))
        return KanbanCustomAssistPreset(
            id: id,
            title: String(trimmedTitle.prefix(Self.maxTitleLength)),
            instruction: cappedInstruction
        )
    }

    static let maxTitleLength = 40
    static let maxInstructionLength = 2_000
}

/// Built-in quick actions plus user-defined presets from Settings.
enum KanbanAssistChoice: Identifiable, Equatable, Sendable {
    case builtIn(KanbanTextAssistAction)
    case custom(KanbanCustomAssistPreset)

    var id: String {
        switch self {
        case .builtIn(let action):
            return "builtin.\(action.rawValue)"
        case .custom(let preset):
            return "custom.\(preset.id.uuidString)"
        }
    }
}

enum KanbanAssistCatalog {
    static let maxCustomPresets = 24

    static func choices(customPresets: [KanbanCustomAssistPreset]) -> [KanbanAssistChoice] {
        let builtIns = KanbanTextAssistAction.allCases.map { KanbanAssistChoice.builtIn($0) }
        let customs = customPresets.compactMap { preset in
            preset.sanitized().map { KanbanAssistChoice.custom($0) }
        }
        return builtIns + customs
    }
}

extension KanbanAssistChoice {
    var menuTitle: String {
        switch self {
        case .builtIn(let action):
            return action.label
        case .custom(let preset):
            return preset.title
        }
    }

    var helpText: String? {
        switch self {
        case .builtIn(let action):
            return action.helpText
        case .custom(let preset):
            return preset.instruction
        }
    }
}

extension KanbanTextAssistAction {
    var label: String {
        switch self {
        case .fixSpelling:
            return L10n.string(
                "workspace.kanban.assist.fixSpelling",
                default: "Fix spelling"
            )
        case .polish:
            return L10n.string(
                "workspace.kanban.assist.polish",
                default: "Polish"
            )
        case .clarify:
            return L10n.string(
                "workspace.kanban.assist.clarify",
                default: "Clarify"
            )
        case .shorten:
            return L10n.string(
                "workspace.kanban.assist.shorten",
                default: "Shorten"
            )
        }
    }

    var helpText: String {
        switch self {
        case .fixSpelling:
            return L10n.string(
                "workspace.kanban.assist.fixSpelling.help",
                default: "Fix spelling and grammar without changing your meaning"
            )
        case .polish:
            return L10n.string(
                "workspace.kanban.assist.polish.help",
                default: "Make the task title clearer and more professional"
            )
        case .clarify:
            return L10n.string(
                "workspace.kanban.assist.clarify.help",
                default: "Turn a rough idea into a specific actionable task"
            )
        case .shorten:
            return L10n.string(
                "workspace.kanban.assist.shorten.help",
                default: "Shorten the title while keeping the same meaning"
            )
        }
    }
}
