import AppKit
import CoreAudio
import SwiftUI
import XCTest
@testable import Gilt

/// Renders the sound panel with realistic content (a call, solo, routing,
/// browser tabs, scenes) in both appearances, so a change that breaks its
/// layout code fails here. Set `JACK_SNAPSHOT_DIR` to also save PNGs for a
/// visual check.
@MainActor
final class SoundPanelRenderTests: XCTestCase {
    func icon(_ path: String) -> NSImage { NSWorkspace.shared.icon(forFile: path) }

    func testPanelRendersInBothAppearances() throws {
        let speakers = AudioOutputDevice(id: 1, uid: "spk", name: "MacBook Pro Speakers", transport: kAudioDeviceTransportTypeBuiltIn)
        let airpods = AudioOutputDevice(id: 2, uid: "pods", name: "AirPods Pro", transport: kAudioDeviceTransportTypeBluetooth)
        let display = AudioOutputDevice(id: 3, uid: "disp", name: "Studio Display", transport: kAudioDeviceTransportTypeDisplayPort)
        let art = try XCTUnwrap(NSImage(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Sources/Gilt/Resources/terra-bloom.png").standardizedFileURL))

        func app(_ id: String, _ name: String, _ path: String, volume: Double = 1, muted: Bool = false, mic: Bool = false, effect: SoundAppEffect = .none, route: String? = nil, active: Bool = true) -> SoundApp {
            SoundApp(id: id, name: name, icon: icon(path), isActive: active, volume: volume, isMuted: muted, isUsingMic: mic, effect: effect, outputDeviceUID: route)
        }
        let quiet = [
            app("slack", "Slack", "/Applications/Slack.app", active: false),
            app("notion", "Notion", "/Applications/Notion.app", volume: 0.4, active: false),
            app("whatsapp", "WhatsApp", "/Applications/WhatsApp.app", active: false),
            app("mail", "Mail", "/System/Applications/Mail.app", muted: true, active: false),
            app("finder", "Finder", "/System/Library/CoreServices/Finder.app", active: false),
            app("claude", "Claude", "/Applications/Claude.app", active: false),
            app("chatgpt", "ChatGPT", "/Applications/ChatGPT.app", active: false),
        ]
        let scenes = [
            SoundScene(id: UUID(), name: "Focus", levels: [:]),
            SoundScene(id: UUID(), name: "Movie night", levels: ["x": SoundAppLevel(volume: 0.5)]),
            SoundScene(id: UUID(), name: "Calls", levels: ["y": SoundAppLevel(volume: 0.2)]),
        ]
        let tabs = [
            BrowserTab(id: "1:7", tabID: 7, browserName: "Aside", title: "lofi hip hop radio – beats to relax/study to", url: URL(string: "https://youtube.com"), host: "youtube.com", favIconURL: nil, isAudible: true, isMuted: false, volume: 0.7),
            BrowserTab(id: "1:9", tabID: 9, browserName: "Aside", title: "Daily standup – Google Meet", url: URL(string: "https://meet.google.com"), host: "meet.google.com", favIconURL: nil, isAudible: true, isMuted: true, volume: 1),
        ]

        let scenarios: [(String, [SoundApp], SoundMixRules)] = [
            ("call", [
                app("com.apple.Music", "Music", "/System/Applications/Music.app", volume: 0.8, effect: .loweredForMic(byAppName: "zoom.us")),
                app("us.zoom.xos", "zoom.us", "/Applications/zoom.us.app", mic: true),
                app("com.google.Chrome", "Google Chrome", "/Applications/Google Chrome.app", volume: 0.55, route: "pods"),
            ], SoundMixRules(micApps: ["us.zoom.xos": "zoom.us"], callModeLevel: 0.25)),
            ("solo", [
                app("com.apple.Music", "Music", "/System/Applications/Music.app", volume: 0.8),
                app("com.google.Chrome", "Google Chrome", "/Applications/Google Chrome.app", volume: 0.55, effect: .silencedBySolo),
            ], SoundMixRules(soloAppID: "com.apple.Music")),
        ]

        let mixer = SoundMixer(defaults: UserDefaults(suiteName: "snap-\(UUID())")!)
        let meters = SoundMeters()
        let nowPlaying = MediaNowPlaying.shared
        nowPlaying.loadPreview(["com.apple.Music": NowPlayingTrack(title: "Deserve Each Other", artist: "bludnymph", isPlaying: true, artwork: art)])
        let bridge = BrowserTabBridge.shared
        bridge.loadPreview(tabs)
        meters.update(appPeaks: ["com.apple.Music": 0.35, "us.zoom.xos": 0.12, "com.google.Chrome": 0.25], systemPeak: nil)

        for (name, active, rules) in scenarios {
            mixer.loadPreview(active: active, quiet: quiet, devices: [speakers, airpods, display], output: speakers, volume: 0.72, scenes: scenes, rules: rules)
            for scheme in [ColorScheme.dark, .light] {
                let view = SoundMenuView(mixer: mixer, meters: meters, nowPlaying: nowPlaying, tabs: bridge, callModeEnabled: .constant(true))
                    .frame(height: 760, alignment: .top)
                    .background(scheme == .dark ? Color(white: 0.17) : Color(white: 0.93))
                    .environment(\.colorScheme, scheme)
                try write(view, scheme: scheme, name: "panel-\(name)-\(scheme == .dark ? "dark" : "light")")
            }
        }
        // Other apps, expanded.
        let rows = VStack(spacing: 0) {
            ForEach(quiet, id: \.id) { (app: SoundApp) in
                SoundAppRow(app: app, compact: true, outputDevices: [speakers], macOutputName: "MacBook Pro Speakers",
                            actions: SoundAppActions(setVolume: { _ in }, toggleMute: {}, toggleSolo: {}, setOutput: { _ in }, reset: {}))
            }
        }
        .padding(10).frame(width: 340)
        try write(rows.background(Color(white: 0.17)).environment(\.colorScheme, .dark), scheme: .dark, name: "other-dark")
    }

    private func write(_ view: some View, scheme: ColorScheme, name: String) throws {
        NSApp?.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        XCTAssertGreaterThan(image.size.height, 200, name)
        guard let directory = ProcessInfo.processInfo.environment["JACK_SNAPSHOT_DIR"] else { return }
        let rep = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
    }
}
