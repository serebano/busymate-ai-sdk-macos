# Busymate AI SDK for macOS — 1.0.1

Official independent macOS Swift package for Busymate AI hosted chat in a native Mac app: a `WKWebView` on AppKit with a SwiftUI wrapper, the frozen identity bridge v2 and the tap-triggered microphone adapter. Install once in your app; hosted chat receives web updates independently.

## Install with Swift Package Manager

In Xcode, File → Add Package Dependencies, use:

`https://github.com/serebano/busymate-ai-sdk-macos.git`

Choose **Exact Version 1.0.1** and add the `BusymateAI` product to your app target. Requires macOS 12+ and Swift tools 5.9+ (Swift 5 language mode). In a package manifest:

```swift
.package(url: "https://github.com/serebano/busymate-ai-sdk-macos.git", exact: "1.0.1")
// In your target's dependencies:
.product(name: "BusymateAI", package: "busymate-ai-sdk-macos")
```

## Integrate

`import BusymateAI`. The quickest path is `BusymateChatController`, which installs `BusymateBridge` (identity wire v2, immutable build 2.0.0) and `BusymateMicrophone` (wire 1, adapter 1.0.0) **before** the first load, pins top-level navigation to the exact allowed origins, sends other links to the default browser, forwards WebKit's media decision and recovers from web content process termination.

```swift
let chat = try BusymateChatController(
    chatURL: URL(string: "https://busymate.ai/support/acme?channel=desktop_sdk&locale=en")!,
    bridge: .init(assistant: "acme", origins: ["https://busymate.ai"],
                  account: { Auth.shared.userId },                     // nil = signed out
                  mint: { request in try await Backend.mintBusymate(nonce: request.nonce, aud: request.aud) },
                  onClose: { window.close() }))
// AppKit:  window.contentViewController = BusymateChatViewController(chat: chat)
// SwiftUI: BusymateChatView(chat: chat)   // own `chat` in an ObservableObject, not in the view
```

The [AppKit example](Examples/ChatWindowController.swift) compiles against the package in CI. You can also install the two bridges on your own `WKWebView`; see [configuration](docs/configuration.md).

Your app target needs:

- `NSMicrophoneUsageDescription` in Info.plist ([sample](Examples/Info.plist)); localize it.
- With the App Sandbox: `com.apple.security.network.client` and `com.apple.security.device.audio-input` ([sample](Examples/App.entitlements)). With the hardened runtime outside the sandbox: the Audio Input capability (`com.apple.security.device.audio-input`).

1. Read [identity and authentication](docs/identity.md).
2. Configure the [complete SDK reference](docs/configuration.md).
3. Follow [microphone and voice integration](docs/microphone.md).
4. Validate on a real Mac using the acceptance checklist; no OS prompt should occur merely on opening chat.

When the user taps microphone or voice, chat asks the native adapter; macOS microphone (TCC) permission is requested then. Only an OS grant plus an allowed-origin WebKit media grant permits recording. Denial offers Retry; revoked permission is rechecked; cancelled chat cannot start capture after a late reply.

## Chat URL and channel

The default guest chat is `https://busymate.ai/support/busyproxy?channel=desktop_sdk&locale=en` (`BusymateAI.guestChatURL()`). A Mac app pins **`desktop_sdk`**, the hosted product's channel for third-party desktop apps on the official desktop SDKs: the chat loads as the window's top-level page with no parent frame, uses the normal chat layout and applies `locale` on the first frame, and sessions are labelled "Desktop app (SDK)" in the Console. Do not use `desktop` — it is Busymate's own Console app and brings the Console's title-bar inset and styling — or `embed`, which requires an embed frame's parent page to be on the tenant's embed allow-list and is refused as a top-level web view. Your workspace owns hosted voice/history/knowledge/tools/handoff availability; native configuration does not fabricate backend capabilities or authenticate merely from an account ID. Integration guide: [busymate.ai/docs/guides/macos-sdk](https://busymate.ai/docs/guides/macos-sdk).

## Run the example app

Open `example-app/BusymateSDKExample.xcodeproj`, select the `BusymateSDKExample` scheme and **My Mac**, and run. It consumes this SDK as a local Swift package and has a settings pane (chat URL, locale, origins, guest or identified mint callback, microphone on/off, callbacks) and an events log. See the [example guide](example-app/README.md). Build with `bash example-app/scripts/build.sh`; test with `bash example-app/scripts/test-config.sh`.

## Versions and ownership

Platform distribution 1.0.1 is distinct from identity wire 2/build 2.0.0 and microphone wire 1/adapter 1.0.0. The macOS bridge is the AppKit port of the iOS file: the same envelope, operations, errors, events and origin rules, with `platform: "macos"` in `hello`. There is no legacy v1 identity bridge on macOS. The [release manifest](release-manifest.json) pins the source hashes. This repository is canonical for macOS SDK releases. Frozen web/shared contracts remain owned by the hosted product.

Run `bash scripts/check-macos.sh` on a Mac with Xcode. It verifies the manifest, builds the package, runs the SDK unit tests and typechecks the AppKit sample. It does not certify OS permission dialogs, App Store or notarized distribution, or your backend integration. See the [changelog](CHANGELOG.md) and the [v2 wire contract](CONTRACT-v2.md).
