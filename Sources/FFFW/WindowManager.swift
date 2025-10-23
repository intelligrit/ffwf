import Cocoa
import ApplicationServices

class WindowManager: ObservableObject {
    @Published var windows: [WindowInfo] = []

    func refreshWindows() {
        var newWindows: [WindowInfo] = []
        var windowID = 0

        // Get all running applications
        let runningApps = NSWorkspace.shared.runningApplications

        for app in runningApps {
            // Skip background processes without UI
            guard app.activationPolicy == .regular else { continue }

            let pid = app.processIdentifier
            let appName = app.localizedName ?? "Unknown"

            // Use AX API to get windows for this app
            let axApp = AXUIElementCreateApplication(pid)
            var windowsRef: CFTypeRef?

            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                  let axWindows = windowsRef as? [AXUIElement] else {
                continue
            }

            for axWindow in axWindows {
                // Get window title
                var titleRef: CFTypeRef?
                let title: String
                if AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef) == .success,
                   let axTitle = titleRef as? String {
                    title = axTitle
                } else {
                    title = ""
                }

                // Skip windows without titles and app name
                guard !title.isEmpty || !appName.isEmpty else { continue }

                // Get window number if available (for matching during activation)
                var windowNumberRef: CFTypeRef?
                var windowNumber = 0
                if AXUIElementCopyAttributeValue(axWindow, kAXWindowAttribute as CFString, &windowNumberRef) == .success {
                    // Window number might not be directly available through AX
                    windowNumber = windowID
                } else {
                    windowNumber = windowID
                }

                let windowInfo = WindowInfo(
                    id: windowID,
                    title: title,
                    ownerName: appName,
                    processID: pid,
                    windowNumber: windowNumber
                )

                newWindows.append(windowInfo)
                windowID += 1
            }
        }

        windows = newWindows
    }

    func activateWindow(_ window: WindowInfo) {
        // Get the application by PID
        let app = NSRunningApplication(processIdentifier: window.processID)
        app?.activate()

        // Use AX API to focus the specific window
        let axApp = AXUIElementCreateApplication(window.processID)
        var windowsRef: CFTypeRef?

        if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let windows = windowsRef as? [AXUIElement] {

            // Try to find and focus the specific window
            for axWindow in windows {
                var titleRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef) == .success,
                   let title = titleRef as? String,
                   title == window.title {
                    AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, true as CFTypeRef)
                    AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                    return
                }
            }

            // If we didn't find exact match, just raise the first window
            if let firstWindow = windows.first {
                AXUIElementSetAttributeValue(firstWindow, kAXMainAttribute as CFString, true as CFTypeRef)
                AXUIElementPerformAction(firstWindow, kAXRaiseAction as CFString)
            }
        }
    }
}
