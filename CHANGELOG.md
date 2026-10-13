# Changelog

## 1.0.1

The default guest chat and `BusymateAI.channel` move from `channel=desktop` to `channel=desktop_sdk`, the hosted channel for third-party desktop apps (serebano/busymate-ai-src#1849). The chat now loads with the normal layout (no Console title-bar inset) and applies `locale` on the first frame. `desktop` is reserved for Busymate's own Console app. Identity bridge v2 (build 2.0.0) and microphone adapter 1.0.0 are unchanged. Replace any hard-coded `channel=desktop` in your own chat URL with `channel=desktop_sdk`.

## 1.0.0

First macOS distribution: identity bridge v2 (wire 2, build 2.0.0) ported to AppKit with the iOS wire unchanged and `platform: "macos"`; microphone adapter 1.0.0 using the macOS microphone TCC permission (`AVCaptureDevice`); `BusymateChatController` / `BusymateChatViewController` / `BusymateChatView` hosts with origin-pinned navigation, external links, media forwarding and web content process recovery. Default guest chat uses `channel=desktop`. Includes unit tests for bridge message handling, origin checks, microphone semantics and navigation policy, plus a sandboxed SwiftUI example app with a settings pane.
