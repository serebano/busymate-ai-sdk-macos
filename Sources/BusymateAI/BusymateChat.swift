import AppKit
import SwiftUI
import WebKit

/// What the chat host reports to your app. URLs are given so you can decide
/// what to log; never log their query strings, tokens or nonces.
@available(macOS 12.0, *)
public enum BusymateChatEvent: Equatable {
    case loaded
    case loadFailed
    case navigationRefused(URL)
    case openedExternally(URL)
    case mediaDecision(granted: Bool)
    case contentProcessTerminated
}

@available(macOS 12.0, *)
public enum BusymateChatError: Error, Equatable {
    /// The chat URL is not https, carries credentials, or its origin is not in the bridge's allowed origins.
    case chatURLNotAllowed
}

/// A ready AppKit host for the hosted chat: one WKWebView with the v2 identity
/// bridge and (optionally) the microphone adapter installed before the first
/// load, top-level navigation pinned to the bridge's exact origins, outside
/// links handed to the system browser, WebKit's media decision forwarded to the
/// adapter, and web content process termination recovered.
///
/// Use it from AppKit with `BusymateChatViewController` (or add `webView` to
/// your own view), or from SwiftUI with `BusymateChatView`. Keep the controller
/// alive for as long as the chat is shown; call `dispose()` when your host is done.
@available(macOS 12.0, *)
@MainActor
public final class BusymateChatController: NSObject, WKUIDelegate, WKNavigationDelegate {
    public let webView: WKWebView
    public let chatURL: URL
    /// The exact origins the bridge answers, the adapter grants and top-level navigation may reach.
    public let allowedOrigins: [String]
    public private(set) var microphone: BusymateMicrophone?
    public var onEvent: ((BusymateChatEvent) -> Void)?
    private var loaded = false

    /// - Parameters:
    ///   - chatURL: your tenant's hosted chat URL, e.g.
    ///     `https://busymate.ai/support/<assistant>?channel=desktop_sdk&locale=en`. Its origin must be allowed by `bridge`.
    ///   - bridge: the v2 identity bridge configuration (assistant, origins, account, mint, callbacks).
    ///   - microphone: install the tap-triggered microphone adapter. When false, WebKit media requests are denied.
    ///   - configuration: an optional WKWebViewConfiguration of yours (data store, user scripts, …).
    public init(chatURL: URL, bridge: BusymateBridge.Config, microphone: Bool = true,
                configuration: WKWebViewConfiguration? = nil) throws {
        let allowed = BusymateBridge.allowedOrigins(bridge)
        guard let origin = Self.origin(of: chatURL), allowed.contains(origin) else {
            throw BusymateChatError.chatURLNotAllowed
        }
        self.chatURL = chatURL
        self.allowedOrigins = allowed
        self.webView = WKWebView(frame: .zero, configuration: configuration ?? WKWebViewConfiguration())
        super.init()
        webView.uiDelegate = self
        webView.navigationDelegate = self
        // Both handlers are registered BEFORE the first load.
        BusymateBridge.install(on: webView, config: bridge)
        if microphone {
            self.microphone = BusymateMicrophone(webView: webView, origins: Set(allowed))
        }
    }

    /// Load the chat once. Later calls are ignored; use `reload()` to reload.
    public func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        webView.load(URLRequest(url: chatURL))
    }

    public func reload() {
        loaded = true
        webView.load(URLRequest(url: chatURL))
    }

    /// End the chat document (and its media tracks) and drop the adapter. The
    /// frozen v2 bridge has no uninstall API; it is released with its web view.
    public func dispose() {
        webView.stopLoading()
        BusymateMicrophone.remove(from: webView)
        microphone = nil
        webView.loadHTMLString("", baseURL: nil)
        loaded = false
    }

    // MARK: policy (pure, testable)

    /// "https://host[:port]" for an https URL without credentials, else nil.
    public static func origin(of url: URL) -> String? {
        guard url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return nil }
        let port = url.port.map { $0 == 443 ? "" : ":\($0)" } ?? ""
        return BusymateBridge.normalizedOrigin("https://\(host)\(port)")
    }

    public enum NavigationDecision: Equatable { case allow, openExternally, cancel }

    /// Top-level navigation stays on the exact allowed origins. A user-activated
    /// link elsewhere opens in the system browser; anything else is refused.
    /// Subframes are not pinned here: the bridge and the adapter check each
    /// sending frame's own origin.
    public func decide(url: URL, mainFrame: Bool, userActivated: Bool) -> NavigationDecision {
        if url.absoluteString == "about:blank" || url.scheme == "about" { return .allow }
        if !mainFrame { return .allow }
        if let origin = Self.origin(of: url), allowedOrigins.contains(origin) { return .allow }
        if userActivated, url.scheme == "https" || url.scheme == "http" || url.scheme == "mailto" {
            return .openExternally
        }
        return .cancel
    }

    // MARK: WKNavigationDelegate

    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        let mainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        switch decide(url: url, mainFrame: mainFrame, userActivated: navigationAction.navigationType == .linkActivated) {
        case .allow:
            decisionHandler(.allow)
        case .openExternally:
            decisionHandler(.cancel)
            if BusymateBridge.openExternal(url) { onEvent?(.openedExternally(url)) }
        case .cancel:
            decisionHandler(.cancel)
            onEvent?(.navigationRefused(url))
        }
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView.url.flatMap(Self.origin(of:)) != nil { onEvent?(.loaded) }
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { onEvent?(.loadFailed) }
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        onEvent?(.contentProcessTerminated)
        BusymateBridge.contentProcessDidTerminate(webView)
    }

    // MARK: WKUIDelegate

    /// `window.open` / `target=_blank`: never a second web view with the bridge's reach.
    public func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, url.scheme == "https" || url.scheme == "http",
           BusymateBridge.openExternal(url) {
            onEvent?(.openedExternally(url))
        }
        return nil
    }

    public func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                        initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                        decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        let decision = microphone?.allowMedia(origin: origin, type: type) ?? .deny
        onEvent?(.mediaDecision(granted: decision == .grant))
        decisionHandler(decision)
    }
}

/// AppKit host: the controller's web view as this view controller's view; loads on first appearance.
@available(macOS 12.0, *)
@MainActor
public final class BusymateChatViewController: NSViewController {
    public let chat: BusymateChatController
    public init(chat: BusymateChatController) {
        self.chat = chat
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(chat:)") }
    public override func loadView() { view = chat.webView }
    public override func viewDidAppear() {
        super.viewDidAppear()
        chat.loadIfNeeded()
    }
}

/// SwiftUI host. Own the `BusymateChatController` outside the view (e.g. in an
/// ObservableObject) so SwiftUI updates never recreate the web view or its handlers.
@available(macOS 12.0, *)
public struct BusymateChatView: NSViewRepresentable {
    public let chat: BusymateChatController
    public init(chat: BusymateChatController) { self.chat = chat }

    public func makeNSView(context: Context) -> NSView {
        let container = NSView()
        let webView = chat.webView
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        chat.loadIfNeeded()
        return container
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        guard chat.webView.superview !== nsView else { return }
        // A new controller was passed: swap its web view in.
        nsView.subviews.forEach { $0.removeFromSuperview() }
        let webView = chat.webView
        webView.removeFromSuperview()
        webView.frame = nsView.bounds
        webView.autoresizingMask = [.width, .height]
        webView.translatesAutoresizingMaskIntoConstraints = true
        nsView.addSubview(webView)
        chat.loadIfNeeded()
    }
}
