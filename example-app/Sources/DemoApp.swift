import BusymateAI
import SwiftUI

@main
struct BusymateSDKExampleApp: App {
    @StateObject private var session = DemoSession()
    var body: some Scene {
        WindowGroup("Busymate SDK Demo") {
            DemoRootView(session: session).frame(minWidth: 720, minHeight: 560)
        }
        // The standard macOS settings pane (⌘,) edits the same configuration.
        Settings {
            ScrollView { DemoSettingsForm(session: session).padding(20) }.frame(width: 560, height: 640)
        }
    }
}

struct DemoRootView: View {
    @ObservedObject var session: DemoSession
    var body: some View {
        TabView(selection: $session.selectedTab) {
            VStack(spacing: 0) {
                HStack {
                    Text(session.status).font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Button("Reload") { session.reload() }
                }.padding(8)
                Divider()
                if let chat = session.chat {
                    BusymateChatView(chat: chat)
                } else {
                    VStack(spacing: 12) {
                        Text("Chat closed").font(.headline)
                        Button("Open chat") { session.apply() }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .onAppear { session.startIfNeeded() }
            .tabItem { Text("Chat") }.tag(0)

            ScrollView { DemoSettingsForm(session: session).padding(20) }
                .tabItem { Text("Settings") }.tag(1)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("SDK callbacks and public bridge event names. Payloads, account IDs, tokens, nonces and audio are omitted.")
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Button("Clear") { session.events.removeAll() }
                }
                List(Array(session.events.enumerated()), id: \.offset) { _, event in
                    Text(event).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
            }.padding(12)
            .tabItem { Text("Events") }.tag(2)
        }
        .padding(.top, 4)
    }
}

struct DemoSettingsForm: View {
    @ObservedObject var session: DemoSession
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            section("Hosted chat") {
                input("Assistant slug", $session.configuration.assistant)
                input("Chat HTTPS URL", $session.configuration.chatURL)
                input("Locale (sets the URL's locale parameter; empty keeps it)", $session.configuration.locale)
                input("Exact HTTPS origins (comma separated)", $session.configuration.origins)
                note("Default: real guest chat on channel \(BusymateAI.channel). channel=embed is refused at top level (it needs a listed embed parent page). The hosted tenant controls appearance, voice availability and business behavior.")
            }
            section("Native microphone") {
                Toggle("Enable tap-triggered OS permission (adapter 1.0.0)", isOn: $session.configuration.microphoneEnabled)
                Text("macOS microphone access: \(session.microphoneStatus)").font(.caption)
                note("No prompt on page load. Apply installs or removes the adapter; macOS asks only after a dictation/voice tap. Disabled mode denies WebKit media requests.")
            }
            section("Identity — your real app session") {
                Picker("Mode", selection: $session.configuration.signedIn) {
                    Text("Guest").tag(false)
                    Text("Identified (mint callback)").tag(true)
                }.pickerStyle(.segmented)
                input("Signed-in account ID", $session.configuration.accountID)
                input("Authenticated HTTPS mint endpoint", $session.configuration.mintURL)
                VStack(alignment: .leading) {
                    Text("Existing backend session token (optional, memory only)").font(.caption).foregroundColor(.secondary)
                    SecureField("Bearer token", text: $session.configuration.backendSessionToken).textFieldStyle(.roundedBorder)
                }
                note("An account ID is not authentication. Your backend must authenticate the existing app session and mint a fresh assertion per callback. Redirects are refused. Never enter signing keys or admin credentials.")
                Button("Forward accountChanged()") { session.accountChanged() }
            }
            section("Actions and HTTPS opens") {
                Toggle("Handle close through onAction", isOn: $session.configuration.handleCloseAction)
                Toggle("Enable onClose fallback", isOn: $session.configuration.closeCallbackEnabled)
                Toggle("Use ASWebAuthenticationSession for auth opens", isOn: $session.configuration.authenticationOpen)
                input("Registered callback scheme", $session.configuration.callbackScheme)
            }
            section("Lifecycle") {
                Button("Invoke renderer recovery forwarding") { session.testRestoreForwarding() }
                note("Resume is emitted by the SDK when the app becomes active or the Mac wakes. Recovery calls the real SDK method; it does not simulate a crash.")
            }
            HStack {
                Button("Apply and open chat") { session.apply() }.keyboardShortcut(.defaultAction)
                Button("Reset to guest defaults") { session.reset() }
            }
            if let error = session.validationError { Text(error).foregroundColor(.red) }
        }
        .frame(maxWidth: 640, alignment: .leading)
    }
    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        GroupBox(label: Text(title).font(.headline)) {
            VStack(alignment: .leading, spacing: 8) { content() }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func input(_ label: String, _ value: Binding<String>) -> some View {
        VStack(alignment: .leading) {
            Text(label).font(.caption).foregroundColor(.secondary)
            TextField(label, text: value).textFieldStyle(.roundedBorder).disableAutocorrection(true)
        }
    }
    private func note(_ text: String) -> some View {
        Text(text).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}
