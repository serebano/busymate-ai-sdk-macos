# Configuration reference

## `BusymateBridge.Config` (identity v2)

| Setting | Behavior |
|---|---|
| `assistant` | Required assistant slug; adds exactly `https://<assistant>.busymate.ai` to the allowed origins. Get your real assistant URL from Busymate; a marketing page is not a chat URL. |
| `origins` | Extra exact HTTPS origins, for example `https://busymate.ai` for a `/support/<assistant>` URL or your mapped support host. No wildcards, paths or `http:`; invalid entries are ignored. |
| `account` | Closure returning the current account ID or nil, read when state or mint is requested. |
| `mint` | Required authenticated-backend callback that returns a fresh token/nonce for every request, never a cached assertion. The bridge answers `timeout` after 15 s. |
| `onAction` | Optional fixed app-action handler; return true only when handled. Names in use: `close`, `ready` (informational). |
| `onClose` | Optional host dismissal callback; fallback for the `close` action. |
| `authCallbackScheme` | Optional custom URL scheme. With it, auth-mode opens use `ASWebAuthenticationSession`, anchored on the web view's window, and emit `auth` with the callback URL. Register the scheme in `CFBundleURLTypes`. Without it, auth opens go to the default browser. |

`BusymateBridge.install(on:config:)` registers before the first load (installing again on the same web view replaces the bridge). `allowedOrigins(config)` returns the normalized origins. `accountChanged()` emits the current state to installed bridges. `contentProcessDidTerminate(webView)` reloads the same web view and emits `restored` after the next `hello`. A `resume` event is emitted automatically when the app becomes active (`NSApplication.didBecomeActiveNotification`) or the Mac wakes (`NSWorkspace.didWakeNotification`); macOS has no foreground transition like iOS. Frozen build 2.0.0 has no public uninstall API; the bridge is released with its web view.

## `BusymateMicrophone` (adapter 1.0.0)

Takes `webView` and exact `origins`. Install it once before the load, not on each tap; `remove(from:)` removes its handler. Forward `WKUIDelegate.webView(_:requestMediaCapturePermissionFor:initiatedByFrame:type:decisionHandler:)` to `allowMedia(origin:type:)`. Chat triggers dictation/voice requests and controls a 60-second wait. There is no SDK setting for automatic OS prompts on page load, camera access, opening System Settings, timeout override, audio routing, provider credentials or token caching. Request type `busymate.microphone.v1.request`, source `dictation` or `voice`, correlated `id`; the reply has the same `id` and a boolean `granted`. See [microphone integration](microphone.md).

## `BusymateChatController` (AppKit host)

| Parameter | Behavior |
|---|---|
| `chatURL` | Your tenant's hosted chat URL. It must be HTTPS without credentials, and its origin must be in the bridge's allowed origins, or `init` throws `BusymateChatError.chatURLNotAllowed`. Keep the tenant's query parameters; pin `channel=desktop_sdk` (not `desktop`, which is Busymate's own Console app, nor `embed`). |
| `bridge` | The `BusymateBridge.Config` above. |
| `microphone` | `true` (default) installs the adapter with the same allowed origins. `false` denies every WebKit media request. |
| `configuration` | Optional `WKWebViewConfiguration` of yours (website data store, your own user scripts or handlers; do not register `BusymateBridge` or `BusymateMicrophone` yourself). |

Properties and methods: `webView`, `allowedOrigins`, `microphone`, `onEvent` (`loaded`, `loadFailed`, `navigationRefused`, `openedExternally`, `mediaDecision`, `contentProcessTerminated`), `loadIfNeeded()`, `reload()`, `dispose()` (stops loading, removes the microphone handler and blanks the document so its media tracks end), and `decide(url:mainFrame:userActivated:)`, the navigation policy. Top-level navigation stays on the allowed origins; a user-clicked https/http/mailto link elsewhere opens in the default browser; anything else is refused. Subframe navigations are not pinned, because the bridge and adapter check each sending frame's own origin.

`BusymateChatViewController(chat:)` uses the web view as its view and loads on first appearance. `BusymateChatView(chat:)` is the SwiftUI `NSViewRepresentable`. Own the controller outside the view (in an `ObservableObject`) so SwiftUI updates never recreate the web view or its handlers. If you pass a different controller, the view swaps its web view in.

If your app sets `WKAppBoundDomains`, list the chat origins there too. Hosted chat appearance, theme, locale, voice availability and tenant behavior come from the hosted chat and the Busymate Console, not from native SDK flags. Window chrome, layout and audio routing belong to your app.
