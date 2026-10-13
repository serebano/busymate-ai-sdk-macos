import AppKit
import WebKit
import BusymateAI

/// Minimal AppKit host: one window showing your tenant's hosted chat, with the
/// v2 identity bridge and the tap-triggered microphone adapter installed by
/// `BusymateChatController` before the first load.
@MainActor
final class ChatWindowController: NSWindowController, NSWindowDelegate {
    private let chat: BusymateChatController

    init(assistant: String, chatURL: URL, account: @escaping () -> String?,
         mint: @escaping @MainActor (BusymateBridge.MintRequest) async throws -> BusymateBridge.MintToken?) throws {
        var origins: [String] = []
        if let origin = BusymateChatController.origin(of: chatURL) { origins.append(origin) }
        var close: (() -> Void)?
        chat = try BusymateChatController(chatURL: chatURL, bridge: .init(
            assistant: assistant, origins: origins, account: account, mint: mint,
            onClose: { close?() }))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 640),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "Support"
        window.contentViewController = BusymateChatViewController(chat: chat)
        super.init(window: window)
        window.delegate = self
        close = { [weak self] in self?.close() }
        // Never log URLs with query strings, tokens, nonces or account ids.
        chat.onEvent = { event in
            if case .contentProcessTerminated = event { NSLog("Chat renderer restarted") }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use the dependency-injected initializer") }

    /// Invoke after your own login/logout/account switch succeeds.
    func accountChanged() { BusymateBridge.accountChanged() }

    func windowWillClose(_ notification: Notification) {
        // Ends the chat document and its media tracks; removes the microphone handler.
        chat.dispose()
    }
}
