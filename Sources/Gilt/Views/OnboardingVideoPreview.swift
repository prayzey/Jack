import AVKit
import SwiftUI

/// Looping video preview for each ViewMode, shown in the onboarding Style step.
/// Each mode maps to a local .mp4 bundled in Resources.
struct OnboardingVideoPreview: View {
    let mode: ViewMode

    var body: some View {
        let zoom = Self.videoZoom(for: mode)
        GeometryReader { geo in
            LoopingVideoPlayer(resourceName: Self.videoResourceName(for: mode))
                .scaleEffect(zoom)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .clipped()
        .contentShape(Rectangle())
        .id(mode) // Force fresh player per mode
    }

    private static func videoResourceName(for mode: ViewMode) -> String {
        switch mode {
        case .tray: return "trayvid"
        case .drawer: return "sidebardos"
        case .panel: return "sidebardos"
        case .grid: return "Grid"
        case .radial: return "radiant"
        case .workspace: return "Grid"
        }
    }

    /// Grid and radial modes show small centered windows — zoom in so they fill the preview better.
    private static func videoZoom(for mode: ViewMode) -> CGFloat {
        switch mode {
        case .grid: return 1.4
        case .panel: return 1.2
        case .radial: return 1.6
        case .workspace: return 1.2
        default: return 1.0
        }
    }
}

/// NSViewRepresentable that plays a bundled video in a loop with no controls.
private struct LoopingVideoPlayer: NSViewRepresentable {
    let resourceName: String

    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.controlsStyle = .none
        playerView.videoGravity = .resizeAspectFill

        if let player = Self.makePlayer(named: resourceName) {
            playerView.player = player
            context.coordinator.observe(player: player)
            player.play()
        }

        return playerView
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        // Player is recreated via .id(mode) — no update needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private static func makePlayer(named name: String) -> AVPlayer? {
        guard let url = AppResourceLocator.url(forResource: name, withExtension: "mp4", subdirectory: "Resources") else {
            return nil
        }
        let player = AVPlayer(url: url)
        player.isMuted = true
        return player
    }

    final class Coordinator: NSObject {
        private var loopObserver: Any?

        func observe(player: AVPlayer) {
            loopObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { _ in
                player.seek(to: .zero)
                player.play()
            }
        }

        deinit {
            if let observer = loopObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}
