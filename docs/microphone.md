# Native microphone integration for macOS — adapter 1.0.0

The user taps the chat microphone or voice button; the chat sends a request to the app, the app asks macOS for microphone access, and the chat starts capture only after permission is granted. No separate native permission button is needed. macOS decides whether a prompt is shown: an existing grant answers at once, and a previous refusal must be changed by the user in System Settings › Privacy & Security › Microphone.

## Requirements

- macOS 12 or later (WebKit's media-capture delegate is macOS 12+).
- `NSMicrophoneUsageDescription` in your app's Info.plist, localized:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Use the microphone to speak to our support assistant.</string>
```

- **App Sandbox:** `com.apple.security.device.audio-input` and `com.apple.security.network.client`. Without the audio-input entitlement a sandboxed app never gets microphone input, even after the user allows it.
- **Hardened runtime (notarized apps outside the sandbox):** enable the Audio Input capability, which is the same `com.apple.security.device.audio-input` entitlement.
- Exact HTTPS origins that serve your assistant: scheme + host + optional port, with no trailing slash, path, credentials, wildcard, query or fragment. Host names are lowercased, and port 443 is the same as no port.

This is native code: integrating it requires **your app's own release**. Keep your identity bridge; the adapter works with it and does not change the identity wire.

## Installation

`BusymateChatController` installs and forwards everything. On your own `WKWebView`:

```swift
import AppKit
import WebKit
import BusymateAI

final class ChatController: NSViewController, WKUIDelegate {
    private var webView: WKWebView!
    private var microphone: BusymateMicrophone!

    override func loadView() {
        webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        webView.uiDelegate = self
        microphone = BusymateMicrophone(webView: webView, origins: ["https://YOUR_ASSISTANT.busymate.ai"])
        // Install your identity bridge before loading the chat too.
        webView.load(URLRequest(url: URL(string: "https://YOUR_ASSISTANT.busymate.ai")!))
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(microphone.allowMedia(origin: origin, type: type))
    }

    // When your host disposes of the chat:
    func disposeChat() { BusymateMicrophone.remove(from: webView) }
}
```

Keep your existing `WKUIDelegate` and forward only this callback. Keep one adapter per web view; creating another on the same content controller replaces the handler.

The request handler checks `AVCaptureDevice.authorizationStatus(for: .audio)`. `authorized` answers `granted: true` and `denied`/`restricted` answer `false` without a prompt. `notDetermined` calls `AVCaptureDevice.requestAccess(for: .audio)`, which shows the system prompt. WebKit's media callback is a second decision: the adapter grants **only microphone** capture, only from an allowed origin, and only after the OS grant. Camera and camera+microphone requests are denied. The adapter does not open System Settings and does not change audio devices.

## Event and reply contract

The handler is named `BusymateMicrophone` (content world `.page`) and receives a **JSON string** through `WKScriptMessageHandlerWithReply`:

```json
{"type":"busymate.microphone.v1.request","id":"mic-unique-id","source":"dictation"}
```

`source` is `dictation` or `voice`. Messages are accepted only from allowed frame origins and are limited to 4096 bytes. The reply is a dictionary resolved by the page's message Promise:

```json
{"id":"mic-unique-id","granted":true}
```

A malformed or untrusted request is rejected with an error and never prompts. Do not call the bridge from a page-load script or request OS permission when opening chat: the chat owns the user-tap trigger and request correlation.

The chat waits before `getUserMedia` or voice session creation. A native refusal, invalid reply or 60-second timeout shows the blocked notice. **Try again** asks the app again; concurrent requests share one pending ask. Each later activation rechecks permission, including a grant revoked in System Settings. Cancel dictation with another microphone tap, or leave voice mode; a late permission result cannot start capture after cancel or unmount. Cancelling chat does not dismiss the OS prompt or undo an OS grant.

## Download the adapter

`BusymateMicrophone.swift` (microphone adapter 1.0.0, wire 1) ships in this SDK and is attached to every GitHub release, with `SHA256SUMS`:

- Latest release: https://github.com/serebano/busymate-ai-sdk-macos/releases/latest/download/BusymateMicrophone.swift
- Pinned, SDK 1.0.2: https://github.com/serebano/busymate-ai-sdk-macos/releases/download/1.0.2/BusymateMicrophone.swift
- Checksums: https://github.com/serebano/busymate-ai-sdk-macos/releases/download/1.0.2/SHA256SUMS (`shasum -a 256 -c SHA256SUMS --ignore-missing`)

The SDK installs the adapter itself; the standalone file is for audit and vendoring.

This repository and its releases are the only source of the adapter. busymate.ai no longer publishes adapter copies; its legacy `https://busymate.ai/sdk/microphone/1.0.0/` files stay frozen for existing integrations.

## Troubleshooting

| Symptom | Check |
|---|---|
| No prompt on first tap | Permission may already be decided (see System Settings › Privacy & Security › Microphone). Otherwise confirm the adapter was installed before load and the exact chat origin is allowed. For development, `tccutil reset Microphone <bundle id>` resets the decision. |
| Allowed, but chat cannot record | Check the `audio-input` entitlement (sandbox or hardened runtime), the `WKUIDelegate` forwarding and the requesting origin. OS permission alone is not enough. |
| App crashes on first tap | `NSMicrophoneUsageDescription` is missing. |
| Retry shows no new prompt | Expected after a denial: grant access in System Settings, return and tap **Try again**. |
| Camera request denied | Expected: the adapter provides microphone access only. |

## Acceptance checklist for your app release

Verify on a real Mac, with your signed build (development, Developer ID or App Store), because TCC decisions are tied to the app's signature:

1. Fresh permission state: open chat without a prompt; tap **microphone**, see the macOS prompt, allow, and dictate. Repeat for **voice mode**.
2. Deny: see the blocked notice, with no capture and no prompt loop. Allow in System Settings, return and use **Try again**.
3. Already allowed: another activation starts without a prompt. Turn access off in System Settings and confirm the next activation is refused.
4. While permission is pending, cancel dictation or leave voice mode. Allow afterwards and confirm capture does not start.
5. Close and reopen the chat window, sleep and wake the Mac, and repeat an activation.
6. Confirm untrusted origins and camera requests are refused.

The SDK's unit tests cover request validation, origin checks, correlation and the grant/deny/retry/revoke decisions against a stubbed TCC state. They cannot verify the real macOS dialog. Record those results with your own app release.
