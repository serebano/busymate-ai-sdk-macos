import AVFoundation
import WebKit

/// Optional add-on to the identity bridge (microphone wire 1, adapter 1.0.0). Install before the first load.
/// Keep this instance alive and route WKUIDelegate media requests to `allowMedia`.
///
/// macOS: the OS permission is the app's microphone TCC grant, asked through
/// `AVCaptureDevice.requestAccess(for: .audio)` ONLY when the chat sends a
/// request — that is, after the user tapped dictation or voice. Your app needs
/// `NSMicrophoneUsageDescription` in Info.plist and, when sandboxed or using the
/// hardened runtime, the `com.apple.security.device.audio-input` entitlement
/// (plus `com.apple.security.network.client` to load the chat).
@available(macOS 12.0, *)
public final class BusymateMicrophone: NSObject, WKScriptMessageHandlerWithReply {
    public static let handlerName = "BusymateMicrophone"
    public static let requestType = "busymate.microphone.v1.request"
    static let maxMessage = 4096

    /// The OS permission source. Internal so tests can stand in for TCC.
    struct Authorization {
        var status: () -> AVAuthorizationStatus
        var request: (@escaping (Bool) -> Void) -> Void
        static let system = Authorization(
            status: { AVCaptureDevice.authorizationStatus(for: .audio) },
            request: { AVCaptureDevice.requestAccess(for: .audio, completionHandler: $0) })
    }

    public let origins: Set<String>
    var authorization: Authorization = .system

    public init(webView: WKWebView, origins: Set<String>) {
        self.origins = Self.normalized(origins)
        super.init()
        let controller = webView.configuration.userContentController
        // One adapter per content controller: replace, never duplicate (a duplicate name raises).
        controller.removeScriptMessageHandler(forName: Self.handlerName, contentWorld: .page)
        controller.addScriptMessageHandler(self, contentWorld: .page, name: Self.handlerName)
    }

    /// Remove the adapter's handler, e.g. when the host disposes the chat or disables the microphone.
    public static func remove(from webView: WKWebView) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: handlerName, contentWorld: .page)
    }

    /// Exact https origins only: scheme + lower-case host + non-default port. Anything else is dropped.
    static func normalized(_ origins: Set<String>) -> Set<String> {
        Set(origins.compactMap { origin -> String? in
            guard let url = URL(string: origin), url.scheme == "https",
                  let host = url.host, !host.isEmpty, !origin.contains("*"), url.path.isEmpty,
                  url.query == nil, url.fragment == nil, url.user == nil, url.password == nil else { return nil }
            let port = url.port == nil || url.port == 443 ? "" : ":\(url.port!)"
            return "https://\(host.lowercased())\(port)"
        })
    }

    static func origin(protocol scheme: String, host: String, port: Int) -> String {
        let suffix = port == 0 || port == 443 ? "" : ":\(port)"
        return "\(scheme)://\(host.lowercased())\(suffix)"
    }

    private static func origin(_ value: WKSecurityOrigin) -> String {
        origin(protocol: value.protocol, host: value.host, port: value.port)
    }

    public func userContentController(_ controller: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void) {
        handle(body: message.body, origin: Self.origin(message.frameInfo.securityOrigin), reply: replyHandler)
    }

    /// The adapter minus WebKit: `origin` is the sending frame's security origin.
    func handle(body: Any, origin: String, reply: @escaping (Any?, String?) -> Void) {
        guard origins.contains(origin),
              let raw = body as? String, raw.utf8.count <= Self.maxMessage,
              let data = raw.data(using: .utf8),
              let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              request["type"] as? String == Self.requestType,
              let id = request["id"] as? String else {
            reply(nil, "Unsupported microphone request"); return
        }
        // An existing decision answers at once; only an undecided state shows the macOS prompt.
        // A denied or restricted state never re-prompts: the user changes it in System Settings.
        switch authorization.status() {
        case .authorized:
            reply(["id": id, "granted": true], nil)
        case .denied, .restricted:
            reply(["id": id, "granted": false], nil)
        default:
            authorization.request { granted in
                DispatchQueue.main.async { reply(["id": id, "granted": granted], nil) }
            }
        }
    }

    /// In your WKUIDelegate requestMediaCapturePermissionFor callback, pass
    /// the requesting origin and type. Camera or other origins fail closed.
    public func allowMedia(origin: WKSecurityOrigin, type: WKMediaCaptureType) -> WKPermissionDecision {
        allowMedia(origin: Self.origin(origin), type: type)
    }

    func allowMedia(origin: String, type: WKMediaCaptureType) -> WKPermissionDecision {
        origins.contains(origin) && type == .microphone &&
            authorization.status() == .authorized ? .grant : .deny
    }
}
