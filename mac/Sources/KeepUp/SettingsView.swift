import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage(Pref.claudeKey) private var claudeKey = ""
    @AppStorage(Pref.supaUrl) private var supaUrl = ""
    @AppStorage(Pref.supaAnon) private var supaAnon = ""
    @AppStorage(Pref.syncKey) private var syncKey = ""
    @AppStorage(Pref.theme) private var theme = ThemePref.auto.rawValue
    @AppStorage(Pref.widgetOn) private var widgetOn = true

    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @ObservedObject private var store = Store.shared

    var body: some View {
        Form {
            Section("Look") {
                Picker("Theme", selection: $theme) {
                    ForEach(ThemePref.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Toggle("Show desktop widget", isOn: $widgetOn)
                Toggle("Open KeepUp at login", isOn: $openAtLogin)
                if let loginError {
                    Text(loginError).font(.caption).foregroundColor(.red)
                }
            }
            Section {
                SecureField("API key", text: $claudeKey, prompt: Text("sk-ant-…"))
            } header: {
                Text("Claude (chatbox)")
            }
            Section {
                TextField("Project URL", text: $supaUrl, prompt: Text("https://xxxx.supabase.co"))
                SecureField("Anon key", text: $supaAnon)
                SecureField("Sync key", text: $syncKey, prompt: Text("passphrase from schema.sql"))
                HStack {
                    Text(store.syncState.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    Spacer()
                    Button("Sync now") { store.markAllDirty() }
                }
            } header: {
                Text("Sync with phone (Supabase)")
            } footer: {
                Text("Stored only on this Mac. Setup steps are in the README.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .onChange(of: theme) { _ in ThemePref.apply() }
        .onChange(of: widgetOn) { _ in DesktopWidget.shared.refreshVisibility() }
        .onChange(of: openAtLogin) { on in
            do {
                if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                loginError = nil
            } catch {
                loginError = "Couldn't change login item: \(error.localizedDescription). Move KeepUp to Applications first."
            }
        }
    }
}
