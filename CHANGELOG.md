# Changelog

## 1.0.0

First macOS distribution: identity bridge v2 (wire 2, build 2.0.0) ported to AppKit with the iOS wire unchanged and `platform: "macos"`; microphone adapter 1.0.0 using the macOS microphone TCC permission (`AVCaptureDevice`); `BusymateChatController` / `BusymateChatViewController` / `BusymateChatView` hosts with origin-pinned navigation, external links, media forwarding and web content process recovery. Default guest chat uses `channel=desktop`. Includes unit tests for bridge message handling, origin checks, microphone semantics and navigation policy, plus a sandboxed SwiftUI example app with a settings pane.
