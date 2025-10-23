import SwiftUI
import Carbon

// Represents a keyboard shortcut
struct Hotkey: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32

    var displayString: String {
        var parts: [String] = []

        if modifiers & UInt32(controlKey) != 0 {
            parts.append("⌃")
        }
        if modifiers & UInt32(optionKey) != 0 {
            parts.append("⌥")
        }
        if modifiers & UInt32(shiftKey) != 0 {
            parts.append("⇧")
        }
        if modifiers & UInt32(cmdKey) != 0 {
            parts.append("⌘")
        }

        parts.append(keyCodeToString(keyCode))

        return parts.joined()
    }

    private func keyCodeToString(_ code: UInt32) -> String {
        switch Int(code) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_Escape: return "⎋"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default:
            // Try to get the actual character
            let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
            let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)

            if let layoutData = layoutData {
                let layout = unsafeBitCast(layoutData, to: CFData.self)
                var deadKeyState: UInt32 = 0
                var chars = [UniChar](repeating: 0, count: 4)
                var length = 0

                let keyboardLayout = unsafeBitCast(CFDataGetBytePtr(layout), to: UnsafePointer<UCKeyboardLayout>.self)

                UCKeyTranslate(
                    keyboardLayout,
                    UInt16(code),
                    UInt16(kUCKeyActionDisplay),
                    0,
                    UInt32(LMGetKbdType()),
                    UInt32(kUCKeyTranslateNoDeadKeysMask),
                    &deadKeyState,
                    chars.count,
                    &length,
                    &chars
                )

                if length > 0 {
                    return String(utf16CodeUnits: chars, count: length).uppercased()
                }
            }

            return "?"
        }
    }

    static let `default` = Hotkey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey | shiftKey))
}

// View for recording hotkey input
struct HotkeyRecorder: View {
    @Binding var hotkey: Hotkey
    @State private var isRecording = false
    @State private var eventMonitor: Any?

    var body: some View {
        Button(action: {
            if isRecording {
                stopRecording()
            } else {
                startRecording()
            }
        }) {
            HStack {
                Text(isRecording ? "Press keys..." : hotkey.displayString)
                    .frame(minWidth: 120, alignment: .center)
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isRecording ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 2)
                    )

                if isRecording {
                    Button("Cancel") {
                        stopRecording()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        isRecording = true

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            // Ignore modifier-only events unless it's a valid combination
            if event.type == .keyDown {
                let modifiers = event.modifierFlags.carbonModifiers
                let keyCode = UInt32(event.keyCode)

                // Require at least one modifier
                if modifiers != 0 {
                    hotkey = Hotkey(keyCode: keyCode, modifiers: modifiers)
                    stopRecording()
                    return nil // Consume the event
                }
            }

            return event
        }
    }

    private func stopRecording() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        isRecording = false
    }
}

// Helper extension to convert NSEvent modifiers to Carbon modifiers
extension NSEvent.ModifierFlags {
    var carbonModifiers: UInt32 {
        var carbon: UInt32 = 0

        if contains(.control) {
            carbon |= UInt32(controlKey)
        }
        if contains(.option) {
            carbon |= UInt32(optionKey)
        }
        if contains(.shift) {
            carbon |= UInt32(shiftKey)
        }
        if contains(.command) {
            carbon |= UInt32(cmdKey)
        }

        return carbon
    }
}
