import SwiftUI

/// A visual divider card in the clip strip that marks the start of a named section.
/// Narrow vertical element with a label and a thin line.
struct SeparatorCardView: View {
    @EnvironmentObject private var store: ClipboardStore
    let separator: FolderSeparatorModel
    let cardHeight: CGFloat

    @State private var isEditing = false
    @State private var editText = ""
    @FocusState private var editFocused: Bool

    private let separatorWidth: CGFloat = 56
    private var canMoveLeft: Bool { store.canMoveSeparator(separator.separatorID, direction: .left) }
    private var canMoveRight: Bool { store.canMoveSeparator(separator.separatorID, direction: .right) }
    private var separatorAccentColor: Color { separator.resolvedColor.color }
    private var currentSeparatorColor: ResolvedColor { separator.resolvedColor }

    var body: some View {
        VStack(spacing: 0) {
            // Label area
            labelArea
                .frame(height: 36)
                .frame(maxWidth: .infinity)

            // Vertical line
            lineArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: separatorWidth, height: cardHeight)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(separatorAccentColor.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(separatorAccentColor.opacity(0.35), lineWidth: 0.8)
        )
        .contentShape(Rectangle())
        .contextMenu { separatorContextMenu }
        .onTapGesture(count: 2) {
            startEditing()
        }
    }

    // MARK: - Label

    @ViewBuilder
    private var labelArea: some View {
        if isEditing {
            TextField("Label", text: $editText)
                .textFieldStyle(.plain)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .focused($editFocused)
                .onSubmit { commitEdit() }
                .onExitCommand { cancelEdit() }
                .padding(.horizontal, 4)
                .padding(.top, 6)
        } else {
            Text(separator.label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.82))
                .padding(.horizontal, 4)
                .padding(.top, 6)
        }
    }

    // MARK: - Line

    private var lineArea: some View {
        VStack {
            Spacer(minLength: 4)
            // Thin glowing vertical line
            RoundedRectangle(cornerRadius: 1)
                .fill(
                    LinearGradient(
                        colors: [
                            separatorAccentColor.opacity(0.95),
                            separatorAccentColor.opacity(0.22),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 1.5)
            Spacer(minLength: 8)
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var separatorContextMenu: some View {
        Button {
            startEditing()
        } label: {
            Label(L10n.string("ui.edit.label", default: "Edit Label"), systemImage: "pencil")
        }

        Menu {
            if let folderColor = store.selectedFolder?.resolvedColor {
                Button {
                    store.setSeparatorColor(separator.separatorID, to: folderColor)
                } label: {
                    if currentSeparatorColor == folderColor {
                        Label(CommonCopy.matchFolder(), systemImage: "checkmark.circle.fill")
                    } else {
                        Label(CommonCopy.matchFolder(), systemImage: "folder")
                    }
                }
            }

            ForEach(FolderColorToken.allCases, id: \.self) { token in
                Button {
                    store.setSeparatorColor(separator.separatorID, to: .token(token))
                } label: {
                    if currentSeparatorColor == .token(token) {
                        Label(token.label, systemImage: "checkmark.circle.fill")
                    } else {
                        Label(token.label, systemImage: "paintpalette")
                    }
                }
            }
        } label: {
            Label(L10n.string("ui.set.color", default: "Set Color"), systemImage: "paintpalette")
        }

        Button {
            store.moveSeparator(separator.separatorID, direction: .left)
        } label: {
            Label(CommonCopy.moveLeft(), systemImage: "arrow.left")
        }
        .disabled(!canMoveLeft)

        Button {
            store.moveSeparator(separator.separatorID, direction: .right)
        } label: {
            Label(CommonCopy.moveRight(), systemImage: "arrow.right")
        }
        .disabled(!canMoveRight)

        Divider()

        Button(role: .destructive) {
            store.deleteSeparator(separator.separatorID)
        } label: {
            Label(L10n.string("ui.remove.separator", default: "Remove Separator"), systemImage: "trash")
        }
    }

    // MARK: - Editing

    private func startEditing() {
        editText = separator.label
        isEditing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            editFocused = true
        }
    }

    private func commitEdit() {
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            store.renameSeparator(separator.separatorID, to: trimmed)
        }
        isEditing = false
    }

    private func cancelEdit() {
        isEditing = false
    }
}
