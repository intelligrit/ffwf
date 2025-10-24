import SwiftUI
import ServiceManagement

class LoginItemManager: ObservableObject {
    static let shared = LoginItemManager()

    @Published var isEnabled: Bool {
        didSet {
            setLoginItemEnabled(isEnabled)
        }
    }

    private init() {
        // Check current status
        self.isEnabled = SMAppService.mainApp.status == .enabled
    }

    private func setLoginItemEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status == .enabled {
                    // Already enabled
                    return
                }
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to \(enabled ? "enable" : "disable") login item: \(error)")
            // Revert the published value on failure
            DispatchQueue.main.async {
                self.isEnabled = SMAppService.mainApp.status == .enabled
            }
        }
    }
}

class HotkeySettings: ObservableObject {
    static let shared = HotkeySettings()

    @Published var hotkey: Hotkey {
        didSet {
            save()
            // Notify AppDelegate to re-register hotkey
            NotificationCenter.default.post(name: .hotkeyChanged, object: hotkey)
        }
    }

    private init() {
        // Load from UserDefaults
        if let data = UserDefaults.standard.data(forKey: "globalHotkey"),
           let decoded = try? JSONDecoder().decode(Hotkey.self, from: data) {
            self.hotkey = decoded
        } else {
            self.hotkey = .default
        }
    }

    private func save() {
        if let encoded = try? JSONEncoder().encode(hotkey) {
            UserDefaults.standard.set(encoded, forKey: "globalHotkey")
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings = HotkeySettings.shared
    @ObservedObject var loginManager = LoginItemManager.shared
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("FFWF Settings")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
            }
            .padding(.bottom, 10)

            Divider()

            // Hotkey setting
            VStack(alignment: .leading, spacing: 10) {
                Text("Global Hotkey")
                    .font(.system(size: 14, weight: .medium))

                HStack {
                    Text("Shortcut:")
                        .foregroundColor(.secondary)

                    HotkeyRecorder(hotkey: $settings.hotkey)

                    Spacer()

                    Button("Reset to Default") {
                        settings.hotkey = .default
                    }
                    .buttonStyle(.bordered)
                }

                Text("Click the shortcut field and press your desired key combination")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)

            // Launch at Login setting
            VStack(alignment: .leading, spacing: 10) {
                Text("Startup")
                    .font(.system(size: 14, weight: .medium))

                Toggle("Launch at Login", isOn: $loginManager.isEnabled)
                    .toggleStyle(.switch)

                Text("Automatically start FFWF when you log in")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)

            Spacer()

            // Footer
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Changes take effect immediately")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                        Text("FFWF v\(version)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 500, height: 350)
    }
}

extension Notification.Name {
    static let hotkeyChanged = Notification.Name("hotkeyChanged")
}
