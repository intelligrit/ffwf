import SwiftUI

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

            Spacer()

            // Footer
            HStack {
                Text("Changes take effect immediately")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 500, height: 250)
    }
}

extension Notification.Name {
    static let hotkeyChanged = Notification.Name("hotkeyChanged")
}
