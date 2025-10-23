import Cocoa
import ApplicationServices

class WindowManager: ObservableObject {
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

            // Enumerate tabs from Chrome
            windowID = self.enumerateChromeTabs(startingID: windowID, into: &newWindows)

            // Enumerate tabs from Terminal
            windowID = self.enumerateTerminalTabs(startingID: windowID, into: &newWindows)

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

    private func enumerateChromeTabs(startingID: Int, into windows: inout [WindowInfo]) -> Int {
        var windowID = startingID

        // Check if Chrome is running
        guard let chrome = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.google.Chrome" }) else {
            return windowID
        }

        let script = """
        tell application "Google Chrome"
            set output to ""
            repeat with w from 1 to count of windows
                repeat with t from 1 to count of tabs of window w
                    set output to output & (title of tab t of window w) & "|" & w & "|" & t & "\\n"
                end repeat
            end repeat
            return output
        end tell
        """

        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script),
              let result = appleScript.executeAndReturnError(&error).stringValue else {
            return windowID
        }

        // Parse line-by-line with pipe delimiter
        let lines = result.components(separatedBy: "\n")
        for line in lines {
            let parts = line.components(separatedBy: "|")
            guard parts.count == 3 else { continue }

            let title = parts[0]
            guard let winIndex = Int(parts[1]), let tabIndex = Int(parts[2]) else { continue }

            let windowInfo = WindowInfo(
                id: windowID,
                title: title,
                ownerName: "Chrome",
                processID: chrome.processIdentifier,
                windowNumber: windowID,
                icon: chrome.icon,
                isTab: true,
                tabIndex: tabIndex,
                windowIndex: winIndex
            )
            windows.append(windowInfo)
            windowID += 1
        }

        return windowID
    }

    private func enumerateTerminalTabs(startingID: Int, into windows: inout [WindowInfo]) -> Int {
        var windowID = startingID

        // Check if Terminal is running
        guard let terminal = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.Terminal" }) else {
            return windowID
        }

        let script = """
        tell application "Terminal"
            set output to ""
            repeat with w from 1 to count of windows
                tell window w
                    repeat with t from 1 to count of tabs
                        set tabName to custom title of tab t
                        if tabName is missing value or tabName is "" then
                            set tabName to "Terminal"
                        end if
                        set output to output & tabName & "|" & w & "|" & t & "\\n"
                    end repeat
                end tell
            end repeat
            return output
        end tell
        """

        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script),
              let result = appleScript.executeAndReturnError(&error).stringValue else {
            return windowID
        }

        // Parse line-by-line with pipe delimiter
        let lines = result.components(separatedBy: "\n")
        for line in lines {
            let parts = line.components(separatedBy: "|")
            guard parts.count == 3 else { continue }

            let title = parts[0]
            guard let winIndex = Int(parts[1]), let tabIndex = Int(parts[2]) else { continue }

            let windowInfo = WindowInfo(
                id: windowID,
                title: title,
                ownerName: "Terminal",
                processID: terminal.processIdentifier,
                windowNumber: windowID,
                icon: terminal.icon,
                isTab: true,
                tabIndex: tabIndex,
                windowIndex: winIndex
            )
            windows.append(windowInfo)
            windowID += 1
        }

        return windowID
    }

    func activateWindow(_ window: WindowInfo) {
        // Handle tabs specially
        if window.isTab, let winIndex = window.windowIndex, let tabIndex = window.tabIndex {
            activateTab(window: window, windowIndex: winIndex, tabIndex: tabIndex)
            return
        }

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

    private func activateTab(window: WindowInfo, windowIndex: Int, tabIndex: Int) {
        // Activate the application first
        let app = NSRunningApplication(processIdentifier: window.processID)
        app?.activate()

        // Use AppleScript to switch to the specific tab
        let script: String
        if window.ownerName == "Chrome" {
            script = """
            tell application "Google Chrome"
                set index of window \(windowIndex) to 1
                set active tab index of window \(windowIndex) to \(tabIndex)
            end tell
            """
        } else if window.ownerName == "Terminal" {
            script = """
            tell application "Terminal"
                set index of window \(windowIndex) to 1
                tell window \(windowIndex)
                    set selected tab to tab \(tabIndex)
                end tell
            end tell
            """
        } else {
            return
        }

        let appleScript = NSAppleScript(source: script)
        appleScript?.executeAndReturnError(nil)
    }
}
