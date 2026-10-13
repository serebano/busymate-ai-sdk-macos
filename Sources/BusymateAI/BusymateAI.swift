import Foundation

/// SDK-level constants for the macOS distribution.
public enum BusymateAI {
    /// This platform distribution's version (distinct from identity wire 2 / build 2.0.0 and microphone adapter 1.0.0).
    public static let sdkVersion = "1.0.0"

    /// The hosted chat channel a macOS app pins. `desktop` is a channel the
    /// hosted product accepts at launch (sessions are recorded as `desktop`).
    /// `embed` is NOT usable here: the launch server requires an embed frame's
    /// parent page to be on the tenant's embed allow-list, so a top-level web
    /// view is refused ("We could not start this AI experience"). The hosted
    /// `desktop` layout is shared with Busymate's own Console app, and the
    /// `locale` parameter is applied after load rather than at first paint.
    public static let channel = "desktop"

    /// The public guest support assistant used by the example app.
    public static let guestAssistant = "busyproxy"

    /// `https://busymate.ai/support/<assistant>?channel=desktop&locale=<locale>`.
    public static func guestChatURL(assistant: String = guestAssistant, locale: String = "en") -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "busymate.ai"
        components.path = "/support/\(assistant)"
        components.queryItems = [URLQueryItem(name: "channel", value: channel), URLQueryItem(name: "locale", value: locale)]
        return components.url!
    }
}
