# Identity and authentication

Use the v2 `BusymateBridge`. macOS has no legacy v1 identity bridge. Install exactly one identity bridge on a web view before the first load (`BusymateChatController` does this for you).

Your authenticated backend mints a fresh single-use launch assertion for each SDK mint callback. Never cache or reuse a token/nonce pair. Never put a signing key, Busymate admin key or service-role credential in the app. Use your existing authenticated HTTPS backend API. The callback returns only `token` and `nonce`; preserve the nonce requested by v2 and bind assistant, audience and origin server-side (`request.assistant` and `request.origin` are set by the bridge, never by the page). A signed-out app returns `nil` or throws `MintError.notSignedIn`. Do not invent a public Busymate mint endpoint for your app: implement your tenant's authenticated backend endpoint using the official [identity guide](https://busymate.ai/docs/guides/mobile-in-app-support).

`account` is a synchronous closure reading your current account ID or nil. The bridge sends only SHA-256(`bundleId:accountId`) truncated to 128 bits; the raw ID is never sent. Call `BusymateBridge.accountChanged()` after login, logout or account switching. It emits a state event; hosted chat owns identity refresh and clearing. Configure `onClose` to dismiss your window or sheet and `onAction` only for a fixed app-owned set of actions, returning whether handled. Do not expose arbitrary native execution.

v2 verifies the **sending frame's** security origin: exactly `https://<assistant>.busymate.ai` plus the exact HTTPS origins you list. No wildcards. Other origins get `denied` and never reach your mint. Microphone origins are enforced independently by the adapter.

Keep navigation restricted to your trusted chat URLs. External URLs open in the default browser through `NSWorkspace` (an https `open`, a user-clicked link, or `window.open`). Identity failures keep chat anonymous (`not_signed_in`, `mint_failed`, `timeout`); never log a token, nonce, raw account ID or audio while troubleshooting.

The byte-frozen [v2 wire contract](../CONTRACT-v2.md) defines hello/state/mint/open/action, error envelopes, version negotiation and events. Its no-new-permissions statement applies to the identity bridge alone. The optional microphone integration adds the microphone permission.
