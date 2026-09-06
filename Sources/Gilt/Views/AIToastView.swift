import SwiftUI

/// Small transient banner shown after an on-device AI action completes. Driven by
/// `ClipboardStore.aiToast`; tap to dismiss, otherwise it auto-dismisses.
struct AIToastView: View {
    let toast: AIToast
    var onDismiss: () -> Void

    private var icon: String {
        switch toast.kind {
        case .success: return "checkmark.circle.fill"
        case .failure: return "exclamationmark.triangle.fill"
        case .info: return "sparkles"
        }
    }

    private var tint: Color {
        switch toast.kind {
        case .success: return Color(red: 0.30, green: 0.78, blue: 0.55)
        case .failure: return Color(red: 0.95, green: 0.45, blue: 0.45)
        case .info: return Color(red: 0.40, green: 0.52, blue: 0.96)
        }
    }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
            Text(toast.message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color(white: 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(.white.opacity(0.10), lineWidth: 0.5)
                )
        )
        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
        .frame(maxWidth: 360)
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .onTapGesture { onDismiss() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(toast.message)
    }
}
