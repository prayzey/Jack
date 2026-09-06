import SwiftUI

/// Shared state for folder clear confirmation, observed by each view mode's root view.
@MainActor
final class FolderClearRequest: ObservableObject {
    static let shared = FolderClearRequest()

    struct Payload {
        let folderID: UUID
        let folderName: String
        let clipCount: Int
        let accentColor: Color
    }

    @Published var pending: Payload?

    func request(folder: ClipFolderModel, accentColor: Color) {
        let count = folder.clips.count
        guard count > 0 else { return }
        pending = Payload(
            folderID: folder.folderID,
            folderName: folder.displayName,
            clipCount: count,
            accentColor: accentColor
        )
    }

    func cancel() {
        pending = nil
    }
}

/// ViewModifier that overlays a folder clear confirmation centered in the parent view.
/// Apply alongside `.folderDeleteOverlay()` on each view mode's root view.
struct FolderClearOverlay: ViewModifier {
    @EnvironmentObject private var store: ClipboardStore
    @ObservedObject private var clearRequest = FolderClearRequest.shared

    func body(content: Content) -> some View {
        content
            .overlay {
                if let payload = clearRequest.pending {
                    ZStack {
                        Color.black.opacity(0.45)
                            .onTapGesture { clearRequest.cancel() }

                        clearCard(payload)
                            .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    }
                    // Clip the dim to the mode's rounded card so it never paints
                    // the window's transparent corners dark (the "dark outside
                    // the section" artifact).
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .animation(.spring(response: 0.22, dampingFraction: 0.82), value: clearRequest.pending != nil)
    }

    @ViewBuilder
    private func clearCard(_ payload: FolderClearRequest.Payload) -> some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Circle()
                    .fill(payload.accentColor)
                    .frame(width: 10, height: 10)
                Text(L10n.string("ui.clear.folder", default: "Clear Folder"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.06))

            VStack(spacing: 12) {
                Text("Remove all \(payload.clipCount) clip\(payload.clipCount == 1 ? "" : "s") from \"\(payload.folderName)\"?")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(L10n.string("ui.clips.that.belong.to.other.folders.w.79aed3", default: "Clips that belong to other folders will be unlinked. Clips only in this folder will be deleted."))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button {
                        clearRequest.cancel()
                    } label: {
                        Text(L10n.string("settings.alert.cancel", default: "Cancel"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)

                    Button {
                        store.clearFolder(id: payload.folderID)
                        clearRequest.cancel()
                    } label: {
                        Text(L10n.string("common.clear", default: "Clear"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(red: 0.85, green: 0.22, blue: 0.25))
                            )
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .frame(width: 280)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: NSColor(white: 0.12, alpha: 1)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
    }
}

extension View {
    func folderClearOverlay() -> some View {
        modifier(FolderClearOverlay())
    }
}
