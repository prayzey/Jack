import SwiftUI

struct PulseCharacterMessagePopoverView: View {
    @Environment(\.locale) private var locale
    let message: PulseCharacterAmbientMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: message.symbolName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(.white.opacity(0.10)))

                Text(message.title(locale: locale))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
            }

            Text(message.expandedText)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.94))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            if message.expandedText != message.text {
                Text(message.text)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.46))
                    .lineLimit(2)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.clear)
    }
}

private extension PulseCharacterAmbientMessage {
    var symbolName: String {
        switch source {
        case .reminder, .recurringReminder:
            return "bell.badge"
        case .custom:
            return "text.bubble"
        case .inspiration:
            return "sparkles"
        }
    }

    func title(locale: Locale) -> String {
        switch source {
        case .reminder, .recurringReminder:
            return L10n.string("pulse.characters.messagePopover.reminder.title", default: "Reminder", locale: locale)
        case .custom:
            return L10n.string("pulse.characters.messagePopover.custom.title", default: "Your Message", locale: locale)
        case .inspiration:
            return L10n.string("pulse.characters.messagePopover.inspiration.title", default: "Inspiration", locale: locale)
        }
    }
}
