import SwiftUI

enum QuickNoteDropFeedback: Equatable {
    case recognizing
    case success
    case imageEmbedded
    case empty
    case failed
    case disabled

    var message: String {
        switch self {
        case .recognizing:
            return L10n.string("quickNote.dropFeedback.recognizing", default: "Extracting text from image...")
        case .success:
            return L10n.string("quickNote.dropFeedback.success", default: "Added text from dropped image")
        case .imageEmbedded:
            return L10n.string("quickNote.dropFeedback.imageEmbedded", default: "Added image to note")
        case .empty:
            return L10n.string("quickNote.dropFeedback.empty", default: "No readable text found in that image")
        case .failed:
            return L10n.string("quickNote.dropFeedback.failed", default: "Couldn't read that image")
        case .disabled:
            return L10n.string("quickNote.dropFeedback.disabled", default: "Image text search is turned off")
        }
    }

    var tint: Color {
        switch self {
        case .recognizing:
            return Color.white.opacity(0.86)
        case .success, .imageEmbedded:
            return Color(red: 0.72, green: 0.91, blue: 0.74)
        case .empty, .failed, .disabled:
            return Color(red: 0.96, green: 0.79, blue: 0.53)
        }
    }
}

struct QuickNoteDropFeedbackView: View {
    let feedback: QuickNoteDropFeedback

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 11, weight: .bold))
            Text(feedback.message)
                .font(.system(size: 11.5, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(feedback.tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.58))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                )
        )
    }

    private var iconName: String {
        switch feedback {
        case .recognizing:
            return "viewfinder"
        case .success:
            return "text.badge.checkmark"
        case .imageEmbedded:
            return "photo"
        case .empty:
            return "text.magnifyingglass"
        case .failed, .disabled:
            return "exclamationmark.triangle"
        }
    }
}
