import AVFoundation
import WebKit
import XCTest
@testable import BusymateAI

@MainActor
final class BusymateBridgeTests: XCTestCase {
    private var opened: [URL] = []
    private var webViews: [WKWebView] = []

    override func setUp() async throws {
        opened = []
        BusymateBridge.openExternal = { [weak self] url in self?.opened.append(url); return true }
    }

    private func bridge(
        account: @escaping () -> String? = { nil },
        mint: @escaping @MainActor (BusymateBridge.MintRequest) async throws -> BusymateBridge.MintToken? = { _ in nil },
        onAction: ((String, [String: Any]) -> Bool)? = nil,
        onClose: (() -> Void)? = nil
    ) -> BusymateBridge {
        let webView = WKWebView()
        webViews.append(webView)
        return BusymateBridge.install(on: webView, config: .init(
            assistant: "acme", origins: ["https://Support.Acme.com/", "https://*.acme.com", "http://plain.acme.com"],
            account: account, mint: mint, onAction: onAction, onClose: onClose))
    }

    /// Send one envelope and decode the reply envelope.
    private func send(_ bridge: BusymateBridge, _ envelope: Any, origin: String? = "https://acme.busymate.ai") async -> [String: Any]? {
        await withCheckedContinuation { continuation in
            bridge.receive(body: envelope, origin: origin, frame: nil) { value, _ in
                guard let text = value as? String, let data = text.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continuation.resume(returning: nil); return
                }
                continuation.resume(returning: object)
            }
        }
    }

    private func envelope(_ op: String, _ p: [String: Any] = [:], id: Any = "1") -> String {
        let data = try! JSONSerialization.data(withJSONObject: ["bm": 2, "id": id, "op": op, "p": p])
        return String(data: data, encoding: .utf8)!
    }

    // MARK: origins

    func testAllowedOriginsAreExactAssistantPlusNormalizedHttpsOnly() {
        let config = BusymateBridge.Config(assistant: "acme", origins: ["https://Support.Acme.com/", "https://support.acme.com:443",
            "https://*.acme.com", "http://plain.acme.com", "https://acme.com/path", "https://acme.com:8443"],
            account: { nil }, mint: { _ in nil })
        XCTAssertEqual(BusymateBridge.allowedOrigins(config),
                       ["https://acme.busymate.ai", "https://support.acme.com", "https://acme.com:8443"])
    }

    func testInvalidAssistantSlugAddsNoBusymateOrigin() {
        let config = BusymateBridge.Config(assistant: "Bad_Slug", origins: [], account: { nil }, mint: { _ in nil })
        XCTAssertEqual(BusymateBridge.allowedOrigins(config), [])
    }

    func testFrameOriginRefusesNonHttpsAndOpaqueFrames() {
        XCTAssertEqual(BusymateBridge.frameOrigin(protocol: "https", host: "acme.busymate.ai", port: 0), "https://acme.busymate.ai")
        XCTAssertEqual(BusymateBridge.frameOrigin(protocol: "https", host: "acme.busymate.ai", port: 443), "https://acme.busymate.ai")
        XCTAssertEqual(BusymateBridge.frameOrigin(protocol: "https", host: "acme.com", port: 8443), "https://acme.com:8443")
        XCTAssertNil(BusymateBridge.frameOrigin(protocol: "http", host: "acme.busymate.ai", port: 0))
        XCTAssertNil(BusymateBridge.frameOrigin(protocol: "", host: "", port: 0))
    }

    func testOtherOriginsAreDeniedAndNeverReachMint() async {
        var minted = 0
        let bridge = bridge(account: { "user" }, mint: { _ in minted += 1; return .init(token: "t", nonce: "n") })
        for origin in ["https://other.busymate.ai", "https://busymate.ai", "https://evil.acme.com", "https://plain.acme.com"] as [String?] + [nil] {
            let reply = await send(bridge, envelope("mint", ["nonce": "n"]), origin: origin)
            XCTAssertEqual(reply?["ok"] as? Bool, false)
            XCTAssertEqual(reply?["e"] as? String, "denied")
            XCTAssertEqual(reply?["bm"] as? Int, 2)
            XCTAssertEqual(reply?["id"] as? String, "1")
        }
        XCTAssertEqual(minted, 0)
    }

    // MARK: envelope

    func testMalformedWrongVersionOrOversizedEnvelopesGetNoReply() async {
        let bridge = bridge()
        let oversized = "{\"bm\":2,\"id\":\"1\",\"op\":\"hello\",\"p\":{\"x\":\"" + String(repeating: "a", count: 64 * 1024) + "\"}}"
        for body in ["not json", "{\"bm\":1,\"id\":\"1\",\"op\":\"hello\"}", "{\"bm\":2,\"op\":\"hello\"}", oversized] {
            let reply = await send(bridge, body)
            XCTAssertNil(reply, body.prefix(40).description)
        }
    }

    func testObjectBodiesAreAcceptedLikeStrings() async {
        let reply = await send(bridge(), ["bm": 2, "id": 7, "op": "state"] as [String: Any])
        XCTAssertEqual(reply?["ok"] as? Bool, true)
        XCTAssertEqual(reply?["id"] as? Int, 7)
    }

    func testUnknownOpIsUnsupported() async {
        let reply = await send(bridge(), envelope("format_disk"))
        XCTAssertEqual(reply?["ok"] as? Bool, false)
        XCTAssertEqual(reply?["e"] as? String, "unsupported")
    }

    func testHelloAnnouncesMacOSBridge() async throws {
        let reply = await send(bridge(), envelope("hello"), origin: "https://support.acme.com")
        let r = try XCTUnwrap(reply?["r"] as? [String: Any])
        XCTAssertEqual(reply?["ok"] as? Bool, true)
        XCTAssertEqual(r["bridge"] as? String, "busymate")
        XCTAssertEqual(r["v"] as? Int, 2)
        XCTAssertEqual(r["build"] as? String, "2.0.0")
        XCTAssertEqual(r["platform"] as? String, "macos")
        XCTAssertEqual(r["transport"] as? String, "reply")
        XCTAssertEqual(r["assistant"] as? String, "acme")
        XCTAssertEqual(r["origin"] as? String, "https://support.acme.com")
        XCTAssertEqual(r["origins"] as? [String], ["https://acme.busymate.ai", "https://support.acme.com"])
        XCTAssertEqual(r["caps"] as? [String], ["hello", "state", "mint", "open", "action", "ev:resume", "ev:state", "ev:restored", "ev:auth"])
        XCTAssertTrue((r["webview"] as? String)?.hasPrefix("macOS ") == true)
        XCTAssertNotNil(r["app"] as? [String: Any])
    }

    // MARK: state / mint

    func testStateHashesAccountAndNeverSendsRawId() async throws {
        let signedOut = await send(bridge(), envelope("state"))
        XCTAssertEqual((signedOut?["r"] as? [String: Any])?["signedIn"] as? Bool, false)
        XCTAssertTrue((signedOut?["r"] as? [String: Any])?["account"] is NSNull)

        let reply = await send(bridge(account: { "user-42" }), envelope("state"))
        let r = try XCTUnwrap(reply?["r"] as? [String: Any])
        XCTAssertEqual(r["signedIn"] as? Bool, true)
        let key = try XCTUnwrap(r["account"] as? String)
        XCTAssertEqual(key, BusymateBridge.accountKey(Bundle.main.bundleIdentifier ?? "", "user-42"))
        XCTAssertEqual(key.count, 32)
        XCTAssertFalse(key.contains("user-42"))
    }

    func testAccountKeyIsTruncatedSha256() {
        // First 128 bits of SHA-256("ai.busymate.app:user-42"), hex (python3 hashlib).
        XCTAssertEqual(BusymateBridge.accountKey("ai.busymate.app", "user-42"), "4b01cce0ed6c28628deeef543d62d082")
        XCTAssertNotEqual(BusymateBridge.accountKey("ai.app", "a"), BusymateBridge.accountKey("ai.other", "a"))
    }

    func testMintSignedOutNeverCallsBackend() async {
        var minted = 0
        let reply = await send(bridge(account: { nil }, mint: { _ in minted += 1; return nil }), envelope("mint", ["nonce": "n"]))
        XCTAssertEqual(reply?["e"] as? String, "not_signed_in")
        XCTAssertEqual(minted, 0)
    }

    func testMintPassesBridgeOwnedAssistantAndOriginAndReturnsToken() async throws {
        var seen: BusymateBridge.MintRequest?
        let bridge = bridge(account: { "user" }, mint: { request in
            seen = request
            return .init(token: "assertion", nonce: request.nonce)
        })
        let reply = await send(bridge, envelope("mint", ["nonce": "abc", "aud": "aud-1", "reason": "launch",
                                                          "assistant": "evil", "origin": "https://evil.example", "future": 1]))
        XCTAssertEqual(reply?["ok"] as? Bool, true)
        XCTAssertEqual((reply?["r"] as? [String: String]) ?? [:], ["token": "assertion", "nonce": "abc"])
        let request = try XCTUnwrap(seen)
        XCTAssertEqual(request.nonce, "abc")
        XCTAssertEqual(request.aud, "aud-1")
        XCTAssertEqual(request.reason, "launch")
        XCTAssertEqual(request.assistant, "acme")
        XCTAssertEqual(request.origin, "https://acme.busymate.ai")
        XCTAssertEqual(request.raw["assistant"] as? String, "acme")
        XCTAssertEqual(request.raw["origin"] as? String, "https://acme.busymate.ai")
        XCTAssertEqual(request.raw["future"] as? Int, 1)
    }

    func testMintNilOrNotSignedInOrFailure() async {
        let none = await send(bridge(account: { "u" }, mint: { _ in nil }), envelope("mint"))
        XCTAssertEqual(none?["e"] as? String, "not_signed_in")
        let out = await send(bridge(account: { "u" }, mint: { _ in throw BusymateBridge.MintError.notSignedIn }), envelope("mint"))
        XCTAssertEqual(out?["e"] as? String, "not_signed_in")
        let failed = await send(bridge(account: { "u" }, mint: { _ in throw URLError(.timedOut) }), envelope("mint"))
        XCTAssertEqual(failed?["e"] as? String, "mint_failed")
        XCTAssertEqual(failed?["ok"] as? Bool, false)
    }

    // MARK: open / action

    func testOpenAcceptsHttpsOnly() async {
        let bridge = bridge()
        for bad in ["http://acme.com", "javascript:alert(1)", "file:///etc/passwd", "https://", "not a url"] {
            let reply = await send(bridge, envelope("open", ["url": bad, "mode": "external"]))
            XCTAssertEqual(reply?["e"] as? String, "bad_request", bad)
        }
        let reply = await send(bridge, envelope("open", ["url": "https://acme.com/help", "mode": "external"]))
        XCTAssertEqual((reply?["r"] as? [String: Any])?["opened"] as? Bool, true)
        XCTAssertEqual(opened, [URL(string: "https://acme.com/help")!])
    }

    func testAuthModeWithoutCallbackSchemeOpensExternally() async {
        let reply = await send(bridge(), envelope("open", ["url": "https://login.acme.com", "mode": "auth"]))
        XCTAssertEqual(reply?["ok"] as? Bool, true)
        XCTAssertEqual(opened, [URL(string: "https://login.acme.com")!])
    }

    func testActionRoutesToOnActionThenCloseFallback() async {
        var actions: [String] = []
        var closed = 0
        let handled = bridge(onAction: { name, _ in actions.append(name); return name == "custom" }, onClose: { closed += 1 })
        let custom = await send(handled, envelope("action", ["name": "custom", "params": ["a": 1]]))
        XCTAssertEqual((custom?["r"] as? [String: Any])?["handled"] as? Bool, true)
        let ready = await send(handled, envelope("action", ["name": "ready"]))
        XCTAssertEqual((ready?["r"] as? [String: Any])?["handled"] as? Bool, false)
        let close = await send(handled, envelope("action", ["name": "close"]))
        XCTAssertEqual((close?["r"] as? [String: Any])?["handled"] as? Bool, true)
        XCTAssertEqual(actions, ["custom", "ready", "close"])
        XCTAssertEqual(closed, 1)

        let noClose = await send(bridge(), envelope("action", ["name": "close"]))
        XCTAssertEqual((noClose?["r"] as? [String: Any])?["handled"] as? Bool, false)
        let bad = await send(bridge(), envelope("action", ["name": String(repeating: "x", count: 65)]))
        XCTAssertEqual(bad?["e"] as? String, "bad_request")
    }
}
