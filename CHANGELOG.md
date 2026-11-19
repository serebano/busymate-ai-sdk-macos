# Changelog

## 1.0.4

The default hosted chat address is now `https://busymate.ai/chat/w/<assistant>` (default guest chat `https://busymate.ai/chat/w/busyproxy?channel=desktop_sdk&locale=en`), the single chat path across busymate.ai. Existing `/support/<assistant>` addresses keep working: Busymate redirects them permanently and the SDK only checks the origin, so a stored URL needs no migration. The identity wire v2 (build 2.0.0) and the microphone adapter 1.0.0 are unchanged (serebano/busymate-ai-src#6080). Distribution 1.0.3 is skipped on this platform so every Busymate SDK shares one 1.0.4 release.

## 1.0.2

Release packaging: the microphone adapter source (`BusymateMicrophone.swift` sha256 `419630cec81f2bb9ead8ffc0d0db1e4e1aa640a9b35cbc7e622a3325b2b7fdc4`; adapter 1.0.0, wire 1) is attached to every GitHub release and listed in `SHA256SUMS`; docs link the release ([Download the adapter](docs/microphone.md#download-the-adapter)). `release-manifest.json` lists `adapterAssets` and `scripts/verify-release.py` checks them. No adapter or bridge code change (refs serebano/busymate-ai-src#2156).

## 1.0.1

The default guest chat and `BusymateAI.channel` move from `channel=desktop` to `channel=desktop_sdk`, the hosted channel for third-party desktop apps (serebano/busymate-ai-src#1849). The chat now loads with the normal layout (no Console title-bar inset) and applies `locale` on the first frame. `desktop` is reserved for Busymate's own Console app. Identity bridge v2 (build 2.0.0) and microphone adapter 1.0.0 are unchanged. Replace any hard-coded `channel=desktop` in your own chat URL with `channel=desktop_sdk`.

## 1.0.0

First macOS distribution: identity bridge v2 (wire 2, build 2.0.0) ported to AppKit with the iOS wire unchanged and `platform: "macos"`; microphone adapter 1.0.0 using the macOS microphone TCC permission (`AVCaptureDevice`); `BusymateChatController` / `BusymateChatViewController` / `BusymateChatView` hosts with origin-pinned navigation, external links, media forwarding and web content process recovery. Default guest chat uses `channel=desktop`. Includes unit tests for bridge message handling, origin checks, microphone semantics and navigation policy, plus a sandboxed SwiftUI example app with a settings pane.
