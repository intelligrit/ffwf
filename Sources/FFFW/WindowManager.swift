import Cocoa
import ApplicationServices

class WindowManager: ObservableObject {
    @Published var windows: [WindowInfo] = []

    func refreshWindows() {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            windows = []
            return
        }

        var newWindows: [WindowInfo] = []
        var seenIDs = Set<Int>()

        for dict in windowList {
            guard let windowNumber = dict[kCGWindowNumber as String] as? Int,
                  let ownerPID = dict[kCGWindowOwnerPID as String] as? pid_t,
                  let bounds = dict[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = bounds["Width"], let height = bounds["Height"],
                  width > 50, height > 50 else {
                continue
            }

            // Skip duplicates
            guard !seenIDs.contains(windowNumber) else { continue }
            seenIDs.insert(windowNumber)

            let title = (dict[kCGWindowName as String] as? String) ?? ""
            let ownerName = (dict[kCGWindowOwnerName as String] as? String) ?? ""

            // Skip windows without useful names
            guard !title.isEmpty || !ownerName.isEmpty else { continue }

            let windowInfo = WindowInfo(
                id: windowNumber,
                title: title,
                ownerName: ownerName,
                processID: ownerPID,
                windowNumber: windowNumber
            )

            newWindows.append(windowInfo)
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
