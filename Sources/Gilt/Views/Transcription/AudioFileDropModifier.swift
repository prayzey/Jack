import SwiftUI
import UniformTypeIdentifiers

/// Adds an audio-file drop target to any view. Dropped files are resolved to
/// `URL`s and handed to `AudioTranscriptionCoordinator`; filtering to actual
/// audio formats (and the friendly "not audio" feedback) happens there.
///
/// Matching is on `.fileURL`, not `.audio`, because Ogg-Opus voice notes don't
/// reliably advertise the `public.audio` UTI on macOS — but they always arrive
/// as file URLs.
struct AudioFileDropModifier: ViewModifier {
    let isEnabled: Bool
    let source: TranscriptionSource

    @State private var isTargeted = false

    private static let accent = Color(red: 0.96, green: 0.58, blue: 0.28)

    func body(content: Content) -> some View {
        content
            .onDrop(
                of: [.fileURL],
                isTargeted: isEnabled ? $isTargeted : .constant(false)
            ) { providers in
                guard isEnabled else { return false }
                let fileProviders = providers.filter {
                    $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
                }
                guard !fileProviders.isEmpty else { return false }
                AudioDropURLCollector.collect(from: fileProviders, source: source)
                return true
            }
            .overlay {
                if isTargeted {
                    dropHighlight
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.12), value: isTargeted)
    }

    private var dropHighlight: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Self.accent.opacity(0.10))
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    Self.accent.opacity(0.8),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                )
            VStack(spacing: 10) {
                Image(systemName: "waveform.badge.plus")
                    .font(.system(size: 30, weight: .medium))
                Text(L10n.string("ui.drop.to.transcribe", default: "Drop to transcribe"))
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
        }
        .padding(8)
    }
}

extension View {
    /// Accept audio-file drops on this view. See `AudioFileDropModifier`.
    func audioFileDropTarget(
        isEnabled: Bool = true,
        source: TranscriptionSource
    ) -> some View {
        modifier(AudioFileDropModifier(isEnabled: isEnabled, source: source))
    }
}

/// Resolves file URLs off dropped providers and forwards the whole batch to the
/// coordinator once every provider has reported. Mirrors the codebase's drop
/// idiom: decode to a Sendable value inside the provider's `@Sendable`
/// completion, then hop to the main actor to touch isolated state.
@MainActor
private enum AudioDropURLCollector {
    static func collect(from providers: [NSItemProvider], source: TranscriptionSource) {
        let coordinator = AudioTranscriptionCoordinator.shared
        let box = Box(remaining: providers.count)
        for provider in providers {
            provider.loadDataRepresentation(
                forTypeIdentifier: UTType.fileURL.identifier
            ) { data, _ in
                let url = data.flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                DispatchQueue.main.async {
                    box.add(url)
                    guard box.isDone, !box.urls.isEmpty else { return }
                    coordinator.transcribe(fileURLs: box.urls, source: source)
                }
            }
        }
    }

    /// Main-actor accumulator so the multi-file "2 of 3" batch stays intact even
    /// though providers resolve on background queues at different times.
    @MainActor
    private final class Box {
        private(set) var urls: [URL] = []
        private var remaining: Int

        init(remaining: Int) {
            self.remaining = remaining
        }

        func add(_ url: URL?) {
            if let url { urls.append(url) }
            remaining -= 1
        }

        var isDone: Bool { remaining <= 0 }
    }
}
