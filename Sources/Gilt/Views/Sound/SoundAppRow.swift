import AppKit
import SwiftUI

/// What an app row can ask the mixer to do.
struct SoundAppActions {
    var setVolume: (Double) -> Void
    var toggleMute: () -> Void
    var toggleSolo: () -> Void
    var setOutput: (String?) -> Void
    var reset: () -> Void
    var playPause: (() -> Void)?
    var nextTrack: (() -> Void)?
}

/// One app in the sound panel: artwork or icon, what it's doing, a volume
/// slider with its live level, and its controls. ⌥-click the speaker to hear
/// only this app; right-click for everything else.
struct SoundAppRow: View {
    /// Rows in "Other apps" are this tall, so a scrolling list can show an
    /// exact number of them.
    static let compactHeight: CGFloat = 44

    let app: SoundApp
    var track: NowPlayingTrack?
    /// Live levels; nil for "Other apps", which aren't metered.
    var meters: SoundMeters?
    /// "Other apps": no subtitle, smaller icon.
    var compact = false
    var isSoloed = false
    let outputDevices: [AudioOutputDevice]
    let macOutputName: String
    let actions: SoundAppActions

    @State private var isHovering = false

    private var isDimmed: Bool { app.isMuted || app.effect == .silencedBySolo }
    private var routedDevice: AudioOutputDevice? {
        app.outputDeviceUID.flatMap { uid in outputDevices.first { $0.uid == uid } }
    }

    var body: some View {
        HStack(spacing: 10) {
            artwork
            VStack(alignment: .leading, spacing: compact ? 3 : 2) {
                HStack(spacing: 6) {
                    Text(app.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    if isSoloed { soloBadge }
                    Spacer(minLength: 4)
                    controls
                }
                .frame(height: 22)
                if !compact, let subtitle {
                    subtitleView(subtitle)
                        .padding(.bottom, 2)
                }
                HStack(spacing: 8) {
                    let label = String(format: L10n.string("ui.sound.volume.of", default: "%@ volume"), app.name)
                    if let meters {
                        SoundMeteredSlider(meters: meters, appID: app.id, value: app.volume, label: label, onChange: actions.setVolume)
                    } else {
                        SoundSlider(value: app.volume, label: label, onChange: actions.setVolume)
                    }
                    Text(app.isMuted ? L10n.string("ui.sound.muted", default: "Muted") : "\(Int((app.volume * 100).rounded()))%")
                        .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
                }
                .opacity(isDimmed ? 0.45 : 1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, compact ? 0 : 7)
        .frame(height: compact ? Self.compactHeight : nil)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(isHovering ? 0.055 : 0))
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(.snappy(duration: 0.16), value: isHovering)
        .contextMenu { contextMenu }
    }

    // MARK: - Artwork

    private var artwork: some View {
        let size: CGFloat = compact ? 24 : 32
        return ZStack(alignment: .bottomTrailing) {
            if let art = track?.artwork {
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                    )
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 15, height: 15)
                    .shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5)
                    .offset(x: 4, y: 4)
            } else {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
        .saturation(isDimmed ? 0.2 : 1)
        .opacity(isDimmed ? 0.7 : 1)
    }

    private var soloBadge: some View {
        Text(L10n.string("ui.sound.solo.badge", default: "Solo"))
            .font(.system(size: 9.5, weight: .bold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.accentColor.opacity(0.16)))
    }

    // MARK: - Subtitle

    /// What's most worth knowing about the app right now, most important first.
    private var subtitle: (text: String, mark: SubtitleMark)? {
        switch app.effect {
        case .silencedBySolo:
            return (L10n.string("ui.sound.effect.silenced.by.solo", default: "Silenced while another app is soloed"), .none)
        case .loweredForMic(let caller):
            return (String(format: L10n.string("ui.sound.effect.lowered.for.mic", default: "Lowered while %@ uses the mic"), caller), .call)
        case .loweredForDictation:
            return (L10n.string("ui.sound.effect.lowered.for.dictation", default: "Lowered while you dictate"), .dictation)
        case .muffledForDictation:
            return (L10n.string("ui.sound.effect.muffled.for.dictation", default: "Muffled while you dictate"), .dictation)
        case .soloed, .none:
            break
        }
        if app.isUsingMic {
            return (L10n.string("ui.sound.using.mic", default: "Using the mic"), .mic)
        }
        if let track {
            return (track.artist.isEmpty ? track.title : "\(track.title) · \(track.artist)", .none)
        }
        if let routedDevice {
            return (String(format: L10n.string("ui.sound.playing.on", default: "Playing on %@"), routedDevice.name), .none)
        }
        return nil
    }

    private enum SubtitleMark { case none, mic, call, dictation }

    private func subtitleView(_ subtitle: (text: String, mark: SubtitleMark)) -> some View {
        HStack(spacing: 5) {
            switch subtitle.mark {
            case .mic:
                // Same orange as macOS's own mic-in-use dot.
                Circle().fill(Color.orange).frame(width: 6, height: 6)
            case .call:
                Image(systemName: "phone.fill").font(.system(size: 8.5, weight: .semibold))
            case .dictation:
                Image(systemName: "waveform").font(.system(size: 9, weight: .semibold))
            case .none:
                EmptyView()
            }
            Text(subtitle.text)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(.secondary)
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 0) {
            if let playPause = actions.playPause, let track {
                Button(action: playPause) {
                    Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(SoundIconButtonStyle())
                .accessibilityLabel(track.isPlaying ? L10n.string("ui.sound.pause", default: "Pause") : L10n.string("ui.sound.play", default: "Play"))
            }
            if let nextTrack = actions.nextTrack, track != nil {
                Button(action: nextTrack) { Image(systemName: "forward.fill") }
                    .buttonStyle(SoundIconButtonStyle())
                    .accessibilityLabel(L10n.string("ui.sound.next.track", default: "Next track"))
            }
            if isHovering || routedDevice != nil {
                outputMenu
                    .transition(.opacity)
            }
            Button {
                // ⌥-click solos, like Logic and GarageBand.
                if NSEvent.modifierFlags.contains(.option) { actions.toggleSolo() } else { actions.toggleMute() }
            } label: {
                Image(systemName: app.isMuted || isDimmed ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(SoundIconButtonStyle(isActive: app.isMuted))
            .help(L10n.string("ui.sound.mute.help", default: "Mute. Option-click to hear only this app."))
            .accessibilityLabel(app.isMuted ? L10n.string("ui.sound.unmute", default: "Unmute") : L10n.string("ui.sound.mute", default: "Mute"))
        }
    }

    private var outputMenu: some View {
        Menu {
            SoundOutputMenu(
                devices: outputDevices,
                selectedUID: app.outputDeviceUID,
                macOutputName: macOutputName,
                onSelect: actions.setOutput
            )
        } label: {
            Image(systemName: routedDevice?.symbolName ?? "airplayaudio")
        }
        .menuStyle(.button)
        .buttonStyle(SoundIconButtonStyle(isActive: routedDevice != nil))
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L10n.string("ui.sound.play.on.help", default: "Choose the speaker for this app"))
        .accessibilityLabel(L10n.string("ui.sound.play.on", default: "Play on"))
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button(isSoloed
               ? L10n.string("ui.sound.stop.solo", default: "Stop Soloing")
               : L10n.string("ui.sound.hear.only", default: "Hear Only This App")) { actions.toggleSolo() }
        Button(app.isMuted ? L10n.string("ui.sound.unmute", default: "Unmute") : L10n.string("ui.sound.mute", default: "Mute")) {
            actions.toggleMute()
        }
        Menu(L10n.string("ui.sound.play.on", default: "Play on")) {
            SoundOutputMenu(
                devices: outputDevices,
                selectedUID: app.outputDeviceUID,
                macOutputName: macOutputName,
                onSelect: actions.setOutput
            )
        }
        Divider()
        Button(L10n.string("ui.sound.reset.app", default: "Reset to 100%")) { actions.reset() }
    }
}
