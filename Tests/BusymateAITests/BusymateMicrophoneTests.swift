import AVFoundation
import WebKit
import XCTest
@testable import BusymateAI

@MainActor
final class BusymateMicrophoneTests: XCTestCase {
    private var webView: WKWebView!
    private var status: AVAuthorizationStatus = .notDetermined
    private var prompts = 0
    private var promptAnswer = true

    override func setUp() async throws {
        webView = WKWebView()
        status = .notDetermined
        prompts = 0
        promptAnswer = true
    }

    private func adapter(_ origins: Set<String> = ["https://acme.busymate.ai"]) -> BusymateMicrophone {
        let mic = BusymateMicrophone(webView: webView, origins: origins)
        mic.authorization = .init(
            status: { [unowned self] in self.status },
            request: { [unowned self] done in
                self.prompts += 1
                self.status = self.promptAnswer ? .authorized : .denied
                done(self.promptAnswer)
            })
        return mic
    }

    private func ask(_ mic: BusymateMicrophone, _ body: Any, origin: String = "https://acme.busymate.ai") async -> (reply: [String: Any]?, error: String?) {
        await withCheckedContinuation { continuation in
            mic.handle(body: body, origin: origin) { value, error in
                continuation.resume(returning: (value as? [String: Any], error))
            }
        }
    }

    private let request = #"{"type":"busymate.microphone.v1.request","id":"mic-1","source":"dictation"}"#

    func testOriginsNormalizeAndRejectNonExact() {
        let mic = adapter(["https://ACME.busymate.ai", "https://support.acme.com:443", "https://acme.com:8443",
                           "https://*.acme.com", "http://acme.com", "https://acme.com/path", "https://acme.com?x=1",
                           "https://user:pw@acme.com"])
        XCTAssertEqual(mic.origins, ["https://acme.busymate.ai", "https://support.acme.com", "https://acme.com:8443"])
    }

    func testFirstTapPromptsOnceAndRepliesCorrelatedGrant() async {
        let mic = adapter()
        let result = await ask(mic, request)
        XCTAssertEqual(prompts, 1)
        XCTAssertEqual(result.reply?["id"] as? String, "mic-1")
        XCTAssertEqual(result.reply?["granted"] as? Bool, true)
        XCTAssertNil(result.error)
    }

    func testAlreadyGrantedAnswersWithoutPrompt() async {
        status = .authorized
        let result = await ask(adapter(), request)
        XCTAssertEqual(prompts, 0)
        XCTAssertEqual(result.reply?["granted"] as? Bool, true)
    }

    func testDeniedOrRestrictedAnswersFalseWithoutPromptLoop() async {
        for decided in [AVAuthorizationStatus.denied, .restricted] {
            status = decided
            let result = await ask(adapter(), request)
            XCTAssertEqual(result.reply?["granted"] as? Bool, false)
        }
        XCTAssertEqual(prompts, 0)
    }

    func testPromptRefusalRepliesFalseAndRetryRechecks() async {
        promptAnswer = false
        let mic = adapter()
        let first = await ask(mic, request)
        XCTAssertEqual(first.reply?["granted"] as? Bool, false)
        // The user grants in System Settings, then taps Try again: the next ask rechecks, no new prompt.
        status = .authorized
        let retry = await ask(mic, request)
        XCTAssertEqual(retry.reply?["granted"] as? Bool, true)
        XCTAssertEqual(prompts, 1)
        // Revoked later: rechecked again on the next activation.
        status = .denied
        let revoked = await ask(mic, request)
        XCTAssertEqual(revoked.reply?["granted"] as? Bool, false)
    }

    func testUntrustedOriginOrMalformedRequestIsRefusedWithoutPrompt() async {
        let mic = adapter()
        let bad: [(Any, String)] = [
            (request, "https://other.busymate.ai"),
            (request, "http://acme.busymate.ai"),
            (["type": "busymate.microphone.v1.request", "id": "x"], "https://acme.busymate.ai"),
            (#"{"type":"busymate.microphone.v2.request","id":"x"}"#, "https://acme.busymate.ai"),
            (#"{"type":"busymate.microphone.v1.request"}"#, "https://acme.busymate.ai"),
            ("{" + String(repeating: " ", count: 4096) + "}", "https://acme.busymate.ai"),
        ]
        for (body, origin) in bad {
            let result = await ask(mic, body, origin: origin)
            XCTAssertNil(result.reply)
            XCTAssertEqual(result.error, "Unsupported microphone request")
        }
        XCTAssertEqual(prompts, 0)
    }

    func testWebKitMediaGrantNeedsAllowedOriginMicrophoneOnlyAndOSGrant() {
        let mic = adapter()
        XCTAssertEqual(mic.allowMedia(origin: "https://acme.busymate.ai", type: .microphone), .deny, "no OS grant yet")
        status = .authorized
        XCTAssertEqual(mic.allowMedia(origin: "https://acme.busymate.ai", type: .microphone), .grant)
        XCTAssertEqual(mic.allowMedia(origin: "https://acme.busymate.ai", type: .camera), .deny)
        XCTAssertEqual(mic.allowMedia(origin: "https://acme.busymate.ai", type: .cameraAndMicrophone), .deny)
        XCTAssertEqual(mic.allowMedia(origin: "https://other.busymate.ai", type: .microphone), .deny)
    }

    func testFrameOriginFormatting() {
        XCTAssertEqual(BusymateMicrophone.origin(protocol: "https", host: "acme.busymate.ai", port: 0), "https://acme.busymate.ai")
        XCTAssertEqual(BusymateMicrophone.origin(protocol: "https", host: "acme.com", port: 443), "https://acme.com")
        XCTAssertEqual(BusymateMicrophone.origin(protocol: "https", host: "acme.com", port: 8443), "https://acme.com:8443")
    }

    func testReinstallReplacesHandlerInsteadOfRaising() {
        _ = adapter()
        _ = adapter()
        BusymateMicrophone.remove(from: webView)
        _ = adapter()
    }
}
