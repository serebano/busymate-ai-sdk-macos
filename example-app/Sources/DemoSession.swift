import AVFoundation
import BusymateAI
import SwiftUI
import WebKit

/// Forwards public bridge event NAMES to the session without the content controller retaining it.
private final class DemoEventRelay: NSObject, WKScriptMessageHandler {
    weak var session: DemoSession?
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated { session?.bridgeEvent(message) }
    }
}

@MainActor
final class DemoSession: ObservableObject {
    @Published var configuration = DemoConfiguration()
    @Published var selectedTab = 0
    @Published var events: [String] = []
    @Published var status = "Ready — guest chat"
    @Published var validationError: String?
    @Published private(set) var chat: BusymateChatController?
    @Published private(set) var microphoneStatus = "unknown"
    private var applied = DemoConfiguration()
    private let relay = DemoEventRelay()
    private var activeObserver: NSObjectProtocol?

    init() {
        relay.session = self
        // Developer override: `open BusymateSDKExample.app --args -BusymateDemoChatURL <https url>`.
        if let url = UserDefaults.standard.string(forKey: "BusymateDemoChatURL") {
            configuration.chatURL = url
            configuration.locale = ""
        }
        refreshMicrophoneStatus()
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshMicrophoneStatus() }
        }
    }

    func startIfNeeded() { if chat == nil { apply() } }

    func log(_ message: String) {
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        events.insert("\(time) · \(message)", at: 0)
        if events.count > 100 { events.removeLast(events.count - 100) }
    }

    /// Reads the OS state only; it never prompts. The prompt comes from the SDK adapter on a chat tap.
    func refreshMicrophoneStatus() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: microphoneStatus = "granted"
        case .denied: microphoneStatus = "denied (change in System Settings › Privacy & Security › Microphone)"
        case .restricted: microphoneStatus = "restricted"
        case .notDetermined: microphoneStatus = "not determined (asked on first microphone tap)"
        @unknown default: microphoneStatus = "unknown"
        }
    }

    func apply() {
        do {
            let valid = try configuration.validated()
            applied = configuration
            validationError = nil
            chat?.dispose()
            let webConfiguration = WKWebViewConfiguration()
            let controller = webConfiguration.userContentController
            controller.add(relay, name: "DemoEvents")
            controller.addUserScript(WKUserScript(source: """
                window.addEventListener('busymate-bridge', function(event) {
                  try {
                    const value = typeof event.detail === 'string' ? JSON.parse(event.detail) : event.detail;
                    if (['resume','state','restored','auth'].includes(value.ev)) {
                      window.webkit.messageHandlers.DemoEvents.postMessage(value.ev);
                    }
                  } catch (_) {}
                });
                """, injectionTime: .atDocumentStart, forMainFrameOnly: false))
            let next = try BusymateChatController(
                chatURL: valid.chatURL,
                bridge: .init(
                    assistant: valid.assistant, origins: valid.origins,
                    account: { [weak self] in
                        guard let self, self.applied.signedIn else { return nil }
                        return self.applied.accountID
                    },
                    mint: { [weak self] request in
                        guard let self else { return nil }
                        return try await self.mint(request)
                    },
                    onAction: DemoCallbacks.action(enabled: applied.handleCloseAction,
                        close: { [weak self] in self?.log("SDK action: close handled by onAction"); self?.closeChat() },
                        ready: { [weak self] in self?.log("SDK action: ready") }),
                    onClose: DemoCallbacks.close(enabled: applied.closeCallbackEnabled) { [weak self] in
                        self?.log("SDK close fallback"); self?.closeChat()
                    },
                    authCallbackScheme: valid.callbackScheme),
                microphone: applied.microphoneEnabled,
                configuration: webConfiguration)
            next.onEvent = { [weak self] event in self?.chatEvent(event) }
            chat = next
            status = applied.signedIn ? "Identified mode — requires your authenticated backend" : "Guest chat"
            log("Installed identity v2 (build \(BusymateBridge.build)); native microphone \(applied.microphoneEnabled ? "enabled" : "disabled")")
            log("Loading \(DemoConfiguration.origin(valid.chatURL)) (channel \(BusymateAI.channel))")
            selectedTab = 0
        } catch {
            validationError = error.localizedDescription
            log("Configuration rejected")
        }
    }

    private func chatEvent(_ event: BusymateChatEvent) {
        switch event {
        case .loaded: log("Chat document loaded")
        case .loadFailed: status = "Chat unavailable — verify network and configured URL"; log("Navigation failed")
        case .navigationRefused(let url): log("Navigation refused: \(url.host ?? url.scheme ?? "?") is outside configured HTTPS origins")
        case .openedExternally(let url): log("Opened in default browser: \(url.host ?? url.scheme ?? "?")")
        case .mediaDecision(let granted):
            log("WebView media decision: \(granted ? "grant" : "deny")")
            refreshMicrophoneStatus()
        case .contentProcessTerminated: log("Actual web content process termination forwarded to SDK")
        }
    }

    fileprivate func bridgeEvent(_ message: WKScriptMessage) {
        guard let event = message.body as? String, ["resume", "state", "restored", "auth"].contains(event),
              let chat, message.frameInfo.securityOrigin.protocol == "https" else { return }
        let origin = message.frameInfo.securityOrigin
        let port = origin.port == 0 || origin.port == 443 ? "" : ":\(origin.port)"
        guard chat.allowedOrigins.contains("https://\(origin.host.lowercased())\(port)") else { return }
        log("SDK event: \(event) (payload omitted)")
    }

    private func closeChat() {
        chat?.dispose()
        chat = nil
        selectedTab = 1
        status = "Chat closed — Apply or Reload to reopen"
    }

    private func mint(_ request: BusymateBridge.MintRequest) async throws -> BusymateBridge.MintToken? {
        guard applied.signedIn else { log("Mint: signed out, no backend request"); return nil }
        guard let url = try applied.validated().backendURL else { throw DemoConfiguration.Invalid.backend }
        let payload = DemoMintPayload(nonce: request.nonce, audience: request.aud,
                                      reason: request.reason, assistant: request.assistant, origin: request.origin)
        log("Mint: authenticated backend requested")
        // Use existing app session cookies or an in-memory tenant backend session token.
        // Reject all redirects so authentication never travels to another endpoint.
        do {
            let (data, response) = try await URLSession.shared.data(
                for: payload.request(to: url, sessionToken: applied.backendSessionToken), delegate: NoMintRedirects())
            guard let http = response as? HTTPURLResponse else { throw DemoConfiguration.Invalid.backend }
            guard let identity = try payload.decode(data, status: http.statusCode) else {
                log("Mint: backend reports not signed in"); return nil
            }
            log("Mint: fresh correlated assertion received")
            return .init(token: identity.token, nonce: identity.nonce)
        } catch { log("Mint: backend request failed; guest fallback"); throw error }
    }

    func accountChanged() {
        do {
            _ = try configuration.validated()
            applied.signedIn = configuration.signedIn
            applied.accountID = configuration.accountID
            applied.mintURL = configuration.mintURL
            applied.backendSessionToken = configuration.backendSessionToken
            BusymateBridge.accountChanged()
            log("accountChanged() forwarded; no identity fabricated")
        } catch { validationError = error.localizedDescription }
    }

    func reset() { configuration = DemoConfiguration(); apply(); log("Demo settings reset to guest defaults") }
    func reload() { if chat == nil { apply() } else { chat?.reload(); log("Chat reloaded") } }
    func testRestoreForwarding() {
        guard let chat else { return }
        BusymateBridge.contentProcessDidTerminate(chat.webView)
        log("Renderer recovery forwarding invoked manually (no crash simulated)")
    }
}
