import AppKit
import KortexAI
import KortexCloud
import SwiftUI

/// Kortex › Settings… (⌘,).
public struct SettingsView: View {
    public init() {}

    public var body: some View {
        TabView {
            AISettings().tabItem { Label("AI", systemImage: "sparkles") }
            AccountNumberSettings().tabItem { Label("Account Numbers", systemImage: "lock.shield") }
        }
        .frame(width: 560)
        .preferredColorScheme(.dark)
    }
}

/// The Vercel AI Gateway key (kept in the Keychain) and which model reads statements.
struct AISettings: View {
    @AppStorage("aiModel") private var modelID = AIModel.default.rawValue
    @State private var key = ""
    @State private var hasKey = AIKeyStore.hasKey
    @State private var status: String?
    @State private var testing = false

    var body: some View {
        Form {
            Section {
                if hasKey {
                    LabeledContent("Gateway key") {
                        HStack {
                            Label("Saved in your Keychain", systemImage: "checkmark.seal.fill").foregroundStyle(Color.kGrowth)
                            Button("Remove") { AIKeyStore.save(""); hasKey = false; status = nil }
                        }
                    }
                } else {
                    SecureField("Gateway key", text: $key, prompt: Text("vck_…"))
                    Button("Save key") {
                        hasKey = AIKeyStore.save(key) && AIKeyStore.hasKey
                        key = ""
                        status = hasKey ? nil : "Couldn't save the key to the Keychain."
                    }
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Vercel AI Gateway")
            } footer: {
                Text("Create a key at vercel.com › AI Gateway › API Keys. It's stored in this Mac's Keychain, not in the app.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Picker("Model", selection: $modelID) {
                    ForEach(AIModel.allCases) { Text($0.title).tag($0.rawValue) }
                }
                HStack {
                    Button(testing ? "Testing…" : "Test connection") { test() }.disabled(!hasKey || testing)
                    if let status { Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                }
            } header: {
                Text("Reading statements")
            } footer: {
                Text("Add account from statement sends the statement's pages to this model through the gateway. Kortex asks it for only the last 4 digits of account and card numbers.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }

    private func test() {
        testing = true
        status = nil
        let model = AIModel(rawValue: modelID) ?? .default
        Task {
            do {
                let reply = try await AIGateway().ping(model: model)
                status = "Connected · \(model.rawValue) replied “\(reply.trimmingCharacters(in: .whitespacesAndNewlines).prefix(20))”"
            } catch {
                status = error.localizedDescription
            }
            testing = false
        }
    }
}

/// App Check for full account numbers: the `financeKey` function only answers the Kortex app, and
/// without App Attest (a paid Apple Developer membership) this Mac proves itself with a debug token.
struct AccountNumberSettings: View {
    @State private var token = Cloud.appCheckDebugToken
    @State private var status: String?
    @State private var checking = false

    var body: some View {
        Form {
            Section {
                if let token {
                    LabeledContent("Debug token") {
                        HStack {
                            Text(token).font(.mono(11)).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(token, forType: .string)
                            }
                        }
                    }
                } else {
                    Text("Firebase isn't set up yet.").foregroundStyle(.secondary)
                }
                HStack {
                    Button(checking ? "Checking…" : "Check") { check() }.disabled(token == nil || checking)
                    if let status { Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                }
            } header: {
                Text("App Check")
            } footer: {
                Text("Full card and account numbers are encrypted with a key only the Kortex app can fetch. Add this Mac's token in the Firebase console › App Check › Apps › dev.kortex.mac › Manage debug tokens, then Check. Keep the token private: it lets anything holding it pass as Kortex.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }

    private func check() {
        checking = true
        status = nil
        Task {
            do {
                try await FinanceKeys.check()
                status = "This Mac can save and show full numbers."
            } catch {
                status = error.localizedDescription
            }
            checking = false
        }
    }
}
