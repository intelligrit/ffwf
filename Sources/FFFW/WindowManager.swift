import Cocoa
import ApplicationServices

class WindowManager: ObservableObject {
    static let shared = WindowManager()

    @Published var windows: [WindowInfo] = []
    private var isRefreshing = false
    private let refreshLock = NSLock()

    func refreshWindows() {
        // Prevent concurrent refreshes
        refreshLock.lock()
        guard !isRefreshing else {
            refreshLock.unlock()
            return
        }
        isRefreshing = true
        refreshLock.unlock()

        // Run window enumeration on background thread for speed
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var newWindows: [WindowInfo] = []
            var windowID = 0

            // Get ALL running applications (not just .regular ones)
            let runningApps = NSWorkspace.shared.runningApplications

            for app in runningApps {
                let pid = app.processIdentifier
                let appName = app.localizedName ?? "Unknown"

                // Use AX API to get windows for this app
                let axApp = AXUIElementCreateApplication(pid)
                var windowsRef: CFTypeRef?

                guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                      let axWindows = windowsRef as? [AXUIElement] else {
                    continue
                }

                // Get app icon once per app (not per window)
                let appIcon = app.icon

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

                    let windowInfo = WindowInfo(
                        id: windowID,
                        title: title,
                        ownerName: appName,
                        processID: pid,
                        windowNumber: windowID,
                        icon: appIcon
                    )

                    newWindows.append(windowInfo)
                    windowID += 1
                }
            }

            // Update on main thread
            DispatchQueue.main.async {
                self.windows = newWindows

                // Clear refresh lock
                self.refreshLock.lock()
                self.isRefreshing = false
                self.refreshLock.unlock()
            }
        }
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
