import XCTest
@testable import Gilt

final class BrowserTabBridgeTests: XCTestCase {
    private func decode(_ json: String) -> BrowserTabMessage? {
        BrowserTabMessage.decode(Data(json.utf8))
    }

    private func encode(_ command: BrowserTabCommand) -> String? {
        command.data.map { String(decoding: $0, as: UTF8.self) }
    }

    // MARK: - Decoding

    func testDecodesHello() {
        XCTAssertEqual(decode(#"{"type":"hello","version":1,"browser":"Aside"}"#), .hello(browser: "Aside"))
    }

    func testHelloWithoutBrowserNameFallsBackToBrowser() {
        XCTAssertEqual(decode(#"{"type":"hello","version":1}"#), .hello(browser: "Browser"))
        XCTAssertEqual(decode(#"{"type":"hello","version":1,"browser":""}"#), .hello(browser: "Browser"))
    }

    func testDecodesTabsWithNullFavicon() throws {
        let json = #"""
        {"type":"tabs","tabs":[{"id":123,"title":"Lofi beats","url":"https://www.youtube.com/watch?v=1",
         "favIconUrl":null,"audible":true,"muted":false,"volume":0.8}]}
        """#
        guard case .tabs(let tabs)? = decode(json) else { return XCTFail("expected tabs") }
        let payload = try XCTUnwrap(tabs.first)
        XCTAssertEqual(tabs.count, 1)
        XCTAssertNil(payload.favIconUrl)

        let tab = BrowserTab(payload, connectionID: 4, browserName: "Aside")
        XCTAssertEqual(tab.id, "4:123")
        XCTAssertEqual(tab.tabID, 123)
        XCTAssertEqual(tab.browserName, "Aside")
        XCTAssertEqual(tab.title, "Lofi beats")
        XCTAssertEqual(tab.url, URL(string: "https://www.youtube.com/watch?v=1"))
        XCTAssertEqual(tab.host, "youtube.com")
        XCTAssertNil(tab.favIconURL)
        XCTAssertTrue(tab.isAudible)
        XCTAssertFalse(tab.isMuted)
        XCTAssertEqual(tab.volume, 0.8)
    }

    func testDecodesPing() {
        XCTAssertEqual(decode(#"{"type":"ping"}"#), .ping)
    }

    func testIgnoresUnknownTypes() {
        XCTAssertNil(decode(#"{"type":"mystery","tabs":[]}"#))
    }

    func testIgnoresMalformedJSON() {
        XCTAssertNil(decode("{not json"))
        XCTAssertNil(decode("[]"))
        XCTAssertNil(decode(#"{"browser":"Aside"}"#))
        XCTAssertNil(decode(#"{"type":"tabs"}"#))
        XCTAssertNil(decode(#"{"type":"tabs","tabs":[{"id":"not a number"}]}"#))
    }

    func testTabVolumeIsClamped() {
        let loud = BrowserTabMessage.Tab(id: 1, title: "", url: nil, favIconUrl: nil, audible: true, muted: false, volume: 1.7)
        XCTAssertEqual(BrowserTab(loud, connectionID: 1, browserName: "Chrome").volume, 1)
    }

    // MARK: - Encoding

    func testEncodesSetVolume() {
        XCTAssertEqual(encode(.setVolume(tabID: 123, volume: 0.5)), #"{"tabId":123,"type":"setVolume","volume":0.5}"#)
    }

    func testEncodesSetMuted() {
        XCTAssertEqual(encode(.setMuted(tabID: 123, muted: true)), #"{"muted":true,"tabId":123,"type":"setMuted"}"#)
    }

    func testEncodesRequestTabs() {
        XCTAssertEqual(encode(.requestTabs), #"{"type":"requestTabs"}"#)
    }

    func testNonFiniteVolumeIsNotEncoded() {
        XCTAssertNil(BrowserTabCommand.setVolume(tabID: 1, volume: .nan).data)
    }

    // MARK: - Host

    func testHostDerivation() {
        let cases: [(String?, String)] = [
            ("https://www.youtube.com/watch?v=1", "youtube.com"),
            ("https://WWW.Example.COM/", "example.com"),
            ("https://music.youtube.com/", "music.youtube.com"),
            ("https://wwwexample.com/", "wwwexample.com"),
            ("http://localhost:3000/player", "localhost"),
            ("about:blank", ""),
            ("file:///Users/me/song.mp3", ""),
            (nil, ""),
        ]
        for (string, host) in cases {
            XCTAssertEqual(BrowserTab.host(of: string.flatMap { URL(string: $0) }), host, "\(string ?? "nil")")
        }
    }

    // MARK: - Origin check

    func testOnlyExtensionOriginsCanConnect() {
        XCTAssertTrue(BrowserTabBridge.acceptsUpgrade(headers: [(name: "Origin", value: "chrome-extension://abcdef")]))
        XCTAssertTrue(BrowserTabBridge.acceptsUpgrade(headers: [(name: "origin", value: "chrome-extension://abcdef")]))
        XCTAssertFalse(BrowserTabBridge.acceptsUpgrade(headers: [(name: "Origin", value: "https://evil.example")]))
        XCTAssertFalse(BrowserTabBridge.acceptsUpgrade(headers: [(name: "Origin", value: "https://chrome-extension://x")]))
        XCTAssertFalse(BrowserTabBridge.acceptsUpgrade(headers: []))
    }
}
