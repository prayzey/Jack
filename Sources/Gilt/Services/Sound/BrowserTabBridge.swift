import Combine
import Foundation
import Network
import OSLog

/// A browser tab that is playing sound, or that the user muted or turned
/// down. Reported by the "Jack Tab Volume" extension in `BrowserExtension/`.
struct BrowserTab: Identifiable, Equatable {
    /// "<connection-id>:<tabId>". Tab IDs are only unique inside one browser,
    /// so the connection keeps two browsers' tab 7 apart.
    let id: String
    let tabID: Int
    let browserName: String
    let title: String
    let url: URL?
    /// "youtube.com" with a leading "www." removed; "" when the URL has none.
    let host: String
    let favIconURL: URL?
    var isAudible: Bool
    var isMuted: Bool
    var volume: Double
}

extension BrowserTab {
    init(_ tab: BrowserTabMessage.Tab, connectionID: Int, browserName: String) {
        let url = tab.url.flatMap { URL(string: $0) }
        self.init(
            id: "\(connectionID):\(tab.id)",
            tabID: tab.id,
            browserName: browserName,
            title: tab.title,
            url: url,
            host: Self.host(of: url),
            favIconURL: tab.favIconUrl.flatMap { URL(string: $0) },
            isAudible: tab.audible,
            isMuted: tab.muted,
            volume: min(max(tab.volume, 0), 1)
        )
    }

    static func host(of url: URL?) -> String {
        guard let host = url?.host()?.lowercased() else { return "" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// What the extension sends (see `BrowserExtension/background.js`).
enum BrowserTabMessage: Equatable {
    case hello(browser: String)
    case tabs([Tab])
    case ping

    struct Tab: Decodable, Equatable {
        let id: Int
        let title: String
        let url: String?
        let favIconUrl: String?
        let audible: Bool
        var muted: Bool
        var volume: Double
    }

    /// nil for malformed JSON and for unknown types, so a newer extension can
    /// add messages without breaking an older Jack.
    static func decode(_ data: Data) -> BrowserTabMessage? {
        struct Envelope: Decodable {
            let type: String
            let browser: String?
            let tabs: [Tab]?
        }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { return nil }
        switch envelope.type {
        case "hello":
            let name = envelope.browser ?? ""
            return .hello(browser: name.isEmpty ? "Browser" : name)
        case "tabs":
            return envelope.tabs.map { .tabs($0) }
        case "ping":
            return .ping
        default:
            return nil
        }
    }
}

/// What Jack sends to the extension.
enum BrowserTabCommand: Equatable {
    case setVolume(tabID: Int, volume: Double)
    case setMuted(tabID: Int, muted: Bool)
    case requestTabs

    /// nil only for a non-finite volume, which JSON can't represent.
    var data: Data? {
        struct Wire: Encodable {
            let type: String
            var tabId: Int?
            var volume: Double?
            var muted: Bool?
        }
        let wire = switch self {
        case let .setVolume(tabID, volume): Wire(type: "setVolume", tabId: tabID, volume: volume)
        case let .setMuted(tabID, muted): Wire(type: "setMuted", tabId: tabID, muted: muted)
        case .requestTabs: Wire(type: "requestTabs")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try? encoder.encode(wire)
    }
}

/// Lists browser tabs that are making sound and sets each one's volume and
/// mute state, through the "Jack Tab Volume" extension. The extension's
/// service worker connects to a WebSocket server Jack runs on loopback; there
/// is no native messaging host to install.
@MainActor
final class BrowserTabBridge: ObservableObject {
    static let shared = BrowserTabBridge()
    /// Hard-coded in `BrowserExtension/background.js`; change both together.
    nonisolated static let port: NWEndpoint.Port = 51723

    /// Every connected browser's tabs, sorted by browser name then title.
    @Published private(set) var tabs: [BrowserTab] = []
    /// Browsers with a live connection that said hello.
    @Published private(set) var connectedBrowsers: [String] = []

    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "BrowserTabBridge")
    private var listener: NWListener?
    private var peers: [Int: Peer] = [:]
    private var nextConnectionID = 1

    private struct Peer {
        let connection: NWConnection
        /// nil until the extension says hello.
        var browserName: String?
        var tabs: [BrowserTabMessage.Tab] = []
    }

    // MARK: - Lifecycle

    #if DEBUG
    /// Sample tabs for snapshot tests.
    func loadPreview(_ tabs: [BrowserTab]) {
        self.tabs = tabs
    }
    #endif

    func start() {
        guard listener == nil else { return }
        let webSocket = NWProtocolWebSocket.Options()
        webSocket.autoReplyPing = true
        webSocket.setClientRequestHandler(.main) { _, headers in
            .init(status: Self.acceptsUpgrade(headers: headers) ? .accept : .reject, subprotocol: nil)
        }
        let parameters = NWParameters.tcp
        parameters.defaultProtocolStack.applicationProtocols.insert(webSocket, at: 0)
        // Loopback only, so the port is never reachable from the network.
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: Self.port)

        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            logger.error("Couldn't create the browser tab listener: \(error.localizedDescription, privacy: .public)")
            return
        }
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            MainActor.assumeIsolated {
                guard let self, let listener, listener === self.listener else { return }
                self.listenerChanged(state)
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated { self?.accept(connection) }
        }
        self.listener = listener
        listener.start(queue: .main)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        let connections = peers.values.map(\.connection)
        peers = [:]
        connections.forEach { $0.cancel() }
        publish()
    }

    /// Any local web page can open a WebSocket to a loopback port, but it
    /// can't fake the Origin header, so only browser extensions get in.
    nonisolated static func acceptsUpgrade(headers: [(name: String, value: String)]) -> Bool {
        headers.contains { $0.name.lowercased() == "origin" && $0.value.hasPrefix("chrome-extension://") }
    }

    private func listenerChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            logger.info("Listening for browser tabs on 127.0.0.1:\(Self.port.rawValue)")
        case .failed(let error), .waiting(let error):
            // Usually the port is taken, for example by a second copy of Jack.
            // Stay idle: the rest of the sound panel works without browser tabs,
            // and a later start() tries again.
            logger.error("Browser tab bridge is idle: \(error.localizedDescription, privacy: .public)")
            listener?.cancel()
            listener = nil
        default:
            break
        }
    }

    // MARK: - Tab controls

    func setVolume(_ volume: Double, for tabID: BrowserTab.ID) {
        guard volume.isFinite, let (peerID, index, tab) = locate(tabID) else { return }
        // Snap near-full to exactly 100%, like SoundMixer, so the extension
        // stops listing a quiet tab the user dragged back up.
        let volume = volume > 0.98 ? 1 : max(0, volume)
        peers[peerID]?.tabs[index].volume = volume
        publish()
        send(.setVolume(tabID: tab, volume: volume), to: peerID)
    }

    func setMuted(_ muted: Bool, for tabID: BrowserTab.ID) {
        guard let (peerID, index, tab) = locate(tabID) else { return }
        peers[peerID]?.tabs[index].muted = muted
        publish()
        send(.setMuted(tabID: tab, muted: muted), to: peerID)
    }

    private func locate(_ id: BrowserTab.ID) -> (peer: Int, index: Int, tab: Int)? {
        let parts = id.split(separator: ":")
        guard parts.count == 2, let peerID = Int(parts[0]), let tab = Int(parts[1]),
              let index = peers[peerID]?.tabs.firstIndex(where: { $0.id == tab })
        else { return nil }
        return (peerID, index, tab)
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        let id = nextConnectionID
        nextConnectionID += 1
        peers[id] = Peer(connection: connection)
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                MainActor.assumeIsolated { self?.drop(id) }
            default:
                break
            }
        }
        receive(id, on: connection)
        connection.start(queue: .main)
    }

    private func receive(_ id: Int, on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, context, _, error in
            let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
            let opcode = (metadata as? NWProtocolWebSocket.Metadata)?.opcode
            MainActor.assumeIsolated {
                guard let self else {
                    connection.cancel()
                    return
                }
                // No WebSocket metadata means the stream ended. Stop here
                // rather than re-arming, or receive would spin on the closed
                // connection.
                guard error == nil, let opcode, opcode != .close else {
                    self.drop(id)
                    return
                }
                if opcode == .text, let data { self.handle(data, from: id) }
                self.receive(id, on: connection)
            }
        }
    }

    private func handle(_ data: Data, from id: Int) {
        guard var peer = peers[id], let message = BrowserTabMessage.decode(data) else { return }
        switch message {
        case .hello(let browser):
            peer.browserName = browser
            logger.info("\(browser, privacy: .public) connected")
        case .tabs(let tabs):
            peer.tabs = tabs
        case .ping:
            return
        }
        peers[id] = peer
        publish()
    }

    private func drop(_ id: Int) {
        guard let peer = peers.removeValue(forKey: id) else { return }
        peer.connection.cancel()
        publish()
    }

    private func send(_ command: BrowserTabCommand, to peerID: Int) {
        guard let connection = peers[peerID]?.connection, let data = command.data else { return }
        let context = NWConnection.ContentContext(
            identifier: "command",
            metadata: [NWProtocolWebSocket.Metadata(opcode: .text)]
        )
        connection.send(content: data, contentContext: context, isComplete: true, completion: .idempotent)
    }

    /// Rebuilds the published lists from every peer, assigning only on change
    /// so a ping-only or repeated tabs message doesn't redraw the panel.
    private func publish() {
        let all = peers.flatMap { id, peer in
            peer.tabs.map { BrowserTab($0, connectionID: id, browserName: peer.browserName ?? "Browser") }
        }
        let sorted = all.sorted {
            ($0.browserName.lowercased(), $0.title.lowercased(), $0.id)
                < ($1.browserName.lowercased(), $1.title.lowercased(), $1.id)
        }
        if tabs != sorted { tabs = sorted }
        let names = Set(peers.values.compactMap(\.browserName)).sorted()
        if connectedBrowsers != names { connectedBrowsers = names }
    }
}
