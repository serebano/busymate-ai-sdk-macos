import Foundation

/// SDK-level constants for the macOS distribution.
public enum BusymateAI {
    /// This platform distribution's version (distinct from identity wire 2 / build 2.0.0 and microphone adapter 1.0.0).
    public static let sdkVersion = "1.0.2"

    /// The hosted chat channel a macOS app pins: `desktop_sdk`, the hosted
    /// product's channel for third-party desktop apps built on the official
    /// desktop SDKs. The chat loads as the window's top-level page with no
    /// parent frame, uses the normal chat layout and applies `locale` on the
    /// first frame; sessions are labelled "Desktop app (SDK)" in the Console.
    /// Not `desktop` (Busymate's own Console app: title-bar inset, Console
    /// styling) and not `embed` (it needs an allow-listed parent page, so a
    /// top-level web view is refused with "We could not start this AI experience").
    public static let channel = "desktop_sdk"

    /// The public guest support assistant used by the example app.
    public static let guestAssistant = "busyproxy"

    /// `https://busymate.ai/support/<assistant>?channel=desktop_sdk&locale=<locale>`.
    public static func guestChatURL(assistant: String = guestAssistant, locale: String = "en") -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "busymate.ai"
        components.path = "/support/\(assistant)"
        components.queryItems = [URLQueryItem(name: "channel", value: channel), URLQueryItem(name: "locale", value: locale)]
        return components.url!
    }
}
