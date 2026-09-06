import SwiftUI

/// Chat tab inside the Jack popover. Shows a scrollable message list and an
/// input field anchored at the bottom. Talks to a `JackChatStore` instance
/// passed in by the controller.
///
/// All chat state lives in the store — this view is purely presentational.
struct JackChatView: View {
    @ObservedObject var store: JackChatStore

    @State private var draft: String = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            messagesArea
            statusFooter
            inputBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Messages

    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if store.messages.isEmpty {
                        emptyState
                    }
                    ForEach(store.messages) { message in
                        bubble(for: message)
                            .id(message.id)
                    }
                    // Anchor for auto-scroll-to-bottom.
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)
            }
            .scrollIndicators(.hidden)
            .onChange(of: store.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: store.status) { _, _ in
                // Loading / thinking state changes can also extend the
                // visible content height. Keep the view pinned at the
                // bottom so the user sees the freshest state.
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.string("ui.chat.with.jack", default: "Chat with Jack"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))
            Text(
                store.isModelCached
                    ? "Ask anything. Replies come from the local AI on your Mac. No internet needed."
                    : "First message will download the local AI model (~2.5 GB). After that, every reply is offline and free."
            )
            .font(.system(size: 11.5))
            .foregroundStyle(Color.white.opacity(0.55))
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }

    private func bubble(for message: JackChatMessage) -> some View {
        let isUser = message.role == .user
        return HStack(alignment: .top, spacing: 0) {
            if isUser { Spacer(minLength: 32) }
            Text(message.text)
                .font(.system(size: 12.5))
                .foregroundStyle(isUser ? Color.white.opacity(0.96) : Color.white.opacity(0.92))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isUser
                              ? Color(red: 0.30, green: 0.42, blue: 0.92).opacity(0.55)
                              : Color.white.opacity(0.08))
                )
                .textSelection(.enabled)
            if !isUser { Spacer(minLength: 32) }
        }
    }

    // MARK: - Status / loading footer

    @ViewBuilder
    private var statusFooter: some View {
        switch store.status {
        case .idle:
            EmptyView()
        case .thinking:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(L10n.string("ui.jack.is.thinking", default: "Jack is thinking…"))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        case .loadingModel:
            // Quick disk→memory load (~1–2s). Quiet spinner only — no
            // "first-time setup" copy, no progress bar, because nothing's
            // being downloaded.
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(L10n.string("ui.waking.jack.up", default: "Waking Jack up…"))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        case .downloadingModel(let progress):
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L10n.string("ui.first.time.setup.fetching.the.local.ai.model", default: "First-time setup. Fetching the local AI model"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.78))
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                ProgressView(value: progress)
                    .tint(Color(red: 0.40, green: 0.55, blue: 0.95))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        case .error(let message):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.orange.opacity(0.85))
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                    Button(L10n.string("ui.try.again", default: "Try again")) {
                        Task { await store.retryLastTurn() }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(red: 0.55, green: 0.75, blue: 1.0))
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Message Jack…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.white.opacity(0.95))
                .lineLimit(1...4)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                )
                .focused($inputFocused)
                .onSubmit { submit() }

            Button {
                submit()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(canSend ? Color(red: 0.45, green: 0.60, blue: 0.98) : Color.white.opacity(0.25))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .keyboardShortcut(.return, modifiers: [.command])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.20))
        .onAppear { inputFocused = true }
    }

    private var canSend: Bool {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        switch store.status {
        case .idle, .error: return true
        case .thinking, .downloadingModel, .loadingModel: return false
        }
    }

    private func submit() {
        guard canSend else { return }
        let text = draft
        draft = ""
        Task { await store.send(text) }
    }
}
