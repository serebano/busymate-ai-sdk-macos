import WebKit
import XCTest
@testable import BusymateAI

@MainActor
final class BusymateChatTests: XCTestCase {
    private func config(origins: [String] = ["https://busymate.ai"]) -> BusymateBridge.Config {
        .init(assistant: "busyproxy", origins: origins, account: { nil }, mint: { _ in nil })
    }

    func testDefaultGuestURLUsesDesktopChannelAndLocale() {
        XCTAssertEqual(BusymateAI.guestChatURL().absoluteString, "https://busymate.ai/support/busyproxy?channel=desktop_sdk&locale=en")
        XCTAssertEqual(BusymateAI.guestChatURL(locale: "ru").absoluteString, "https://busymate.ai/support/busyproxy?channel=desktop_sdk&locale=ru")
    }

    func testChatURLMustBeHttpsAndAllowed() throws {
        XCTAssertNoThrow(try BusymateChatController(chatURL: BusymateAI.guestChatURL(), bridge: config()))
        XCTAssertNoThrow(try BusymateChatController(chatURL: URL(string: "https://busyproxy.busymate.ai/")!, bridge: config(origins: [])))
        for raw in ["http://busymate.ai/support/busyproxy", "https://user:pw@busymate.ai/support/busyproxy",
                    "https://other.example/support"] {
            XCTAssertThrowsError(try BusymateChatController(chatURL: URL(string: raw)!, bridge: config())) { error in
                XCTAssertEqual(error as? BusymateChatError, .chatURLNotAllowed)
            }
        }
        // busymate.ai itself is not implied by the assistant: it must be listed.
        XCTAssertThrowsError(try BusymateChatController(chatURL: BusymateAI.guestChatURL(), bridge: config(origins: [])))
    }

    func testNavigationPolicyPinsTopLevelToAllowedOrigins() throws {
        let chat = try BusymateChatController(chatURL: BusymateAI.guestChatURL(), bridge: config())
        XCTAssertEqual(chat.allowedOrigins, ["https://busyproxy.busymate.ai", "https://busymate.ai"])
        func decide(_ raw: String, main: Bool = true, user: Bool = false) -> BusymateChatController.NavigationDecision {
            chat.decide(url: URL(string: raw)!, mainFrame: main, userActivated: user)
        }
        XCTAssertEqual(decide("https://busymate.ai/support/busyproxy?channel=desktop_sdk"), .allow)
        XCTAssertEqual(decide("https://BUSYMATE.ai:443/x"), .allow)
        XCTAssertEqual(decide("about:blank"), .allow)
        XCTAssertEqual(decide("https://evil.example/"), .cancel)
        XCTAssertEqual(decide("http://busymate.ai/"), .cancel)
        XCTAssertEqual(decide("https://other.busymate.ai/"), .cancel)
        XCTAssertEqual(decide("https://docs.example/help", user: true), .openExternally)
        XCTAssertEqual(decide("mailto:help@example.com", user: true), .openExternally)
        XCTAssertEqual(decide("file:///etc/passwd", user: true), .cancel)
        XCTAssertEqual(decide("https://challenges.example/frame", main: false), .allow)
    }

    func testMicrophoneToggleAndDisposeRemoveAdapter() throws {
        let on = try BusymateChatController(chatURL: BusymateAI.guestChatURL(), bridge: config())
        XCTAssertEqual(on.microphone?.origins, ["https://busyproxy.busymate.ai", "https://busymate.ai"])
        on.dispose()
        XCTAssertNil(on.microphone)
        let off = try BusymateChatController(chatURL: BusymateAI.guestChatURL(), bridge: config(), microphone: false)
        XCTAssertNil(off.microphone)
    }

    func testOriginOfURL() {
        XCTAssertEqual(BusymateChatController.origin(of: URL(string: "https://Acme.com:443/a?b")!), "https://acme.com")
        XCTAssertEqual(BusymateChatController.origin(of: URL(string: "https://acme.com:8443/")!), "https://acme.com:8443")
        XCTAssertNil(BusymateChatController.origin(of: URL(string: "http://acme.com")!))
        XCTAssertNil(BusymateChatController.origin(of: URL(string: "https://u:p@acme.com")!))
    }
}
