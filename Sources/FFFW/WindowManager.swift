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

            // Get running applications, filtering out background processes
            let runningApps = NSWorkspace.shared.runningApplications.filter { app in
                // Skip background processes and daemons that never have user windows
                app.activationPolicy == .regular || app.activationPolicy == .accessory
            }

            // Process apps in parallel for speed
            let queue = DispatchQueue(label: "window-enumeration", attributes: .concurrent)
            let group = DispatchGroup()
            let lock = NSLock()

            for app in runningApps {
                group.enter()
                queue.async {
                    defer { group.leave() }
                    let pid = app.processIdentifier
                    let appName = app.localizedName ?? "Unknown"

                    // Use AX API to get windows for this app
                    let axApp = AXUIElementCreateApplication(pid)
                    var windowsRef: CFTypeRef?

                    guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                          let axWindows = windowsRef as? [AXUIElement] else {
                        return
                    }

                    // Get app icon once per app (not per window)
                    let appIcon = app.icon

                    var appWindows: [WindowInfo] = []

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
                            id: 0, // Will be reassigned after sorting
                            title: title,
                            ownerName: appName,
                            processID: pid,
                            windowNumber: 0,
                            icon: appIcon
                        )

                        appWindows.append(windowInfo)
                    }

                    // Thread-safe append
                    lock.lock()
                    newWindows.append(contentsOf: appWindows)
                    lock.unlock()
                }
            }

            // Wait for all apps to be processed
            group.wait()

            // Reassign IDs after all windows collected
            for (index, window) in newWindows.enumerated() {
                newWindows[index] = WindowInfo(
                    id: index,
                    title: window.title,
                    ownerName: window.ownerName,
                    processID: window.processID,
                    windowNumber: index,
                    icon: window.icon
                )
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
