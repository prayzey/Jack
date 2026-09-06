import SwiftUI

/// Shared state for folder deletion confirmation, observed by each view mode's root view.
@MainActor
final class FolderDeleteRequest: ObservableObject {
    static let shared = FolderDeleteRequest()

    struct Payload {
        let folderID: UUID
        let folderName: String
        let clipCount: Int
        let accentColor: Color
    }

    @Published var pending: Payload?

    func request(folder: ClipFolderModel, accentColor: Color) {
        pending = Payload(
            folderID: folder.folderID,
            folderName: folder.displayName,
            clipCount: folder.clips.count,
            accentColor: accentColor
        )
    }

    func cancel() {
        pending = nil
    }
}

/// ViewModifier that overlays a folder delete confirmation centered in the parent view.
/// Apply this to each view mode's root view (ContentView, SideDrawerView, FloatingGridView, RadialMenuView).
struct FolderDeleteOverlay: ViewModifier {
    @EnvironmentObject private var store: ClipboardStore
    @ObservedObject private var deleteRequest = FolderDeleteRequest.shared

    func body(content: Content) -> some View {
        content
            .overlay {
                if let payload = deleteRequest.pending {
                    ZStack {
                        // Dimmed backdrop — tap to cancel
                        Color.black.opacity(0.45)
                            .onTapGesture { deleteRequest.cancel() }

                        deleteCard(payload)
                            .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    }
                    // Clip the dim to the mode's rounded card so it never paints
                    // the window's transparent corners dark (the "dark outside
                    // the section" artifact).
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .animation(.spring(response: 0.22, dampingFraction: 0.82), value: deleteRequest.pending != nil)
    }

    @ViewBuilder
    private func deleteCard(_ payload: FolderDeleteRequest.Payload) -> some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Circle()
                    .fill(payload.accentColor)
                    .frame(width: 10, height: 10)
                Text(L10n.string("common.deleteFolder", default: "Delete Folder"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.06))

            VStack(spacing: 12) {
                Text("\"\(payload.folderName)\" will be permanently deleted.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if payload.clipCount > 0 {
                    Text("\(payload.clipCount) clip\(payload.clipCount == 1 ? "" : "s") in this folder will be unlinked, not deleted.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    Button {
                        deleteRequest.cancel()
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
                        store.deleteFolder(id: payload.folderID)
                        deleteRequest.cancel()
                    } label: {
                        Text(L10n.string("settings.alert.deleteFolder.confirm", default: "Delete"))
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
        .frame(width: 260)
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
    func folderDeleteOverlay() -> some View {
        modifier(FolderDeleteOverlay())
    }
}
