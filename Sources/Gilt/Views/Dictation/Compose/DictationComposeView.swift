import AppKit
import SwiftUI

/// The voice-compose surface: dictate into a Jack-owned editor, fold copied
/// links/clips into the middle via the reveal tray, then copy or paste the
/// result out. Lives in its own focusable window (see
/// `DictationComposeWindowManager`).
struct DictationComposeView: View {
    @ObservedObject var controller: DictationComposeController
    @ObservedObject var coordinator: DictationCoordinator
    let onClose: () -> Void
    let onPasteToApp: (String) -> Void

    /// Tray reveals while the cursor is over the handle/tray region, and stays
    /// open while pinned via the footer button.
    @State private var hoverReveal = false
    @State private var pinned = false

    private var showTray: Bool { hoverReveal || pinned }

    var body: some View {
        VStack(spacing: 0) {
            header
            ComposeTextEditorView(controller: controller)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            trayRegion
            footer
        }
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.and.mic")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            Text(L10n.string("menu.voiceCompose", default: "Voice Compose"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Reveal tray

    private var trayRegion: some View {
        VStack(spacing: 6) {
            if showTray {
                RecentClipsTray(controller: controller)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            handleBar
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        // Hover anywhere in the handle+tray region keeps it open, so moving the
        // cursor from the handle up into the chips doesn't collapse it.
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) { hoverReveal = hovering }
        }
        .animation(.easeOut(duration: 0.16), value: showTray)
    }

    private var handleBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 9, weight: .semibold))
            Text(showTray ? "Recent clips" : "Hover for recent clips")
                .font(.system(size: 10, weight: .medium))
            Image(systemName: showTray ? "chevron.down" : "chevron.up")
                .font(.system(size: 8, weight: .bold))
        }
        .foregroundStyle(.white.opacity(0.4))
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.white.opacity(0.05)))
        .contentShape(Capsule())
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            ComposeMicButton(coordinator: coordinator)
            Spacer()
            Text("\(controller.characterCount) chars")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.35))
            actionButton(icon: pinned ? "pin.fill" : "pin", help: "Keep recent clips open") {
                pinned.toggle()
            }
            actionButton(icon: "trash", help: "Clear", enabled: controller.hasText) {
                controller.clear()
            }
            actionButton(icon: "doc.on.doc", help: "Copy to clipboard", enabled: controller.hasText) {
                copyToClipboard()
            }
            actionButton(icon: "arrow.up.forward.app", help: "Paste into the last app", enabled: controller.hasText) {
                onPasteToApp(controller.currentText)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.18))
    }

    private func actionButton(
        icon: String,
        help: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(enabled ? 0.8 : 0.25))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.white.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }

    private func copyToClipboard() {
        let text = controller.currentText
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.08, blue: 0.10),
                    Color(red: 0.12, green: 0.12, blue: 0.15)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            Color.white.opacity(0.02)
        }
    }
}
