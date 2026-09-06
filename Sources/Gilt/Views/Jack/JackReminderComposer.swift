import SwiftUI

/// Inline composer at the bottom of the Reminders tab. Creates a reminder (with
/// an optional time) directly from the Jack popover, through the same
/// `addPulseReminder` funnel the rest of the app uses — so it also mirrors to
/// Apple Reminders when that sync is on.
///
/// Time selection is a horizontally scrollable row of presets (the macOS stand-in
/// for an iOS scroll wheel — `.wheel` picker style doesn't exist on macOS) plus a
/// "Custom…" chip that reveals a native stepper date/time field for fine-tuned
/// times.
struct JackReminderComposer: View {
    let onAdd: (PulseReminder) -> Void

    @State private var text: String = ""
    @State private var due: DueChoice = .anytime
    @State private var customDate: Date = Date().addingTimeInterval(3600)
    @FocusState private var fieldFocused: Bool

    /// Local picker model. `custom`'s date lives in `customDate`; everything else
    /// maps straight to a `JackReminderDue`.
    private enum DueChoice: String, CaseIterable, Hashable {
        case anytime, in10, in30, in1h, evening, tomorrow, custom
        var label: String {
            switch self {
            case .anytime: return "Anytime"
            case .in10: return "10 min"
            case .in30: return "30 min"
            case .in1h: return "1 hour"
            case .evening: return "Tonight"
            case .tomorrow: return "Tomorrow"
            case .custom: return "Custom…"
            }
        }
        /// Mapped due, or `nil` for `.custom` (which reads `customDate`).
        var mapped: JackReminderDue? {
            switch self {
            case .anytime: return .anytime
            case .in10: return .inTenMinutes
            case .in30: return .inThirtyMinutes
            case .in1h: return .inOneHour
            case .evening: return .thisEvening
            case .tomorrow: return .tomorrowMorning
            case .custom: return nil
            }
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            TextField("Remind me to…", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...3)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.white.opacity(0.95))
                .focused($fieldFocused)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
                .onSubmit(submit)

            timeChips

            if due == .custom {
                DatePicker("", selection: $customDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.stepperField)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            addButton
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
    }

    private var timeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(DueChoice.allCases, id: \.self) { choice in
                    chip(choice)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func chip(_ choice: DueChoice) -> some View {
        let selected = due == choice
        return Button { due = choice } label: {
            Text(choice.label)
                .font(.system(size: 11, weight: selected ? .semibold : .medium))
                .foregroundStyle(Color.white.opacity(selected ? 0.95 : 0.6))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(selected ? 0.16 : 0.06)))
                // Hit-target fix: make the whole chip clickable, not just the text.
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var addButton: some View {
        HStack(spacing: 8) {
            voiceMicButton
            Button(action: submit) {
                Text(L10n.string("ui.add.reminder", default: "Add reminder"))
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.white.opacity(addEnabled ? 0.16 : 0.06)))
                    .foregroundStyle(Color.white.opacity(addEnabled ? 0.95 : 0.4))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!addEnabled)
        }
    }

    /// Speak a reminder instead of typing — uses the voice-actions pipeline.
    private var voiceMicButton: some View {
        Button {
            DictationLauncher.shared.startVoiceActions()
        } label: {
            Image(systemName: "mic.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.85))
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.white.opacity(0.12)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Speak a reminder")
    }

    private var addEnabled: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        let mappedDue = due.mapped ?? .custom(customDate)
        guard let reminder = JackReminderDraft.makeReminder(text: text, due: mappedDue, now: Date()) else { return }
        onAdd(reminder)
        text = ""
        due = .anytime
        fieldFocused = false
    }
}
