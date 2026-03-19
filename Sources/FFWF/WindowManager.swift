import Cocoa
import ApplicationServices

class WindowManager: ObservableObject {
    static let shared = WindowManager()
    private static let terminalBundleID = "com.apple.Terminal"
    private static let chromeBundleID = "com.google.Chrome"
    private static let maxTabSearchDepth = 4

    @Published var windows: [WindowInfo] = []
    private var isRefreshing = false
    private let refreshLock = NSLock()
    private let terminalTabCacheLock = NSLock()
    private let chromeTabCacheLock = NSLock()
    private var cachedTerminalTabs: [WindowInfo] = []
    private var cachedChromeTabs: [WindowInfo] = []
    private var lastTerminalTabRefresh = Date.distantPast
    private var lastChromeTabRefresh = Date.distantPast
    private let terminalTabRefreshInterval: TimeInterval = 1.5
    private let chromeTabRefreshInterval: TimeInterval = 1.5

    init() {
        setupWorkspaceObservers()
    }

    private func setupWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter

        // Refresh when apps launch
        center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshWindows()
        }

        // Refresh when apps terminate
        center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshWindows()
        }

        // Refresh when apps are activated (windows might become visible)
        center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshWindows()
        }
    }

    func refreshWindows() {
        // Prevent concurrent refreshes
        refreshLock.lock()
        guard !isRefreshing else {
            refreshLock.unlock()
            return
        }
        isRefreshing = true
        refreshLock.unlock()

        print("🔄 WindowManager: Starting window refresh...")

        // Run window enumeration on background thread for speed
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var newWindows: [WindowInfo] = []

            // Get running applications, filtering out background processes
            let runningApps = NSWorkspace.shared.runningApplications.filter { app in
                // Skip background processes and daemons that never have user windows
                app.activationPolicy == .regular || app.activationPolicy == .accessory
            }

            print("  Found \(runningApps.count) running apps to enumerate")
            let terminalApp = runningApps.first { $0.bundleIdentifier == Self.terminalBundleID }
            let chromeApp = runningApps.first { $0.bundleIdentifier == Self.chromeBundleID }

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
                    let isTerminal = app.bundleIdentifier == Self.terminalBundleID
                    let isChrome = app.bundleIdentifier == Self.chromeBundleID

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
                        if isTerminal, self.shouldHideTerminalWindow(axWindow: axWindow, windowTitle: title) {
                            continue
                        }
                        if isChrome, self.shouldHideChromeWindow(axWindow: axWindow, windowTitle: title) {
                            continue
                        }

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

            newWindows.append(contentsOf: self.terminalTabs(for: terminalApp))
            newWindows.append(contentsOf: self.chromeTabs(for: chromeApp))

            // Reassign IDs after all windows collected
            for (index, window) in newWindows.enumerated() {
                newWindows[index] = WindowInfo(
                    id: index,
                    title: window.title,
                    ownerName: window.ownerName,
                    processID: window.processID,
                    windowNumber: index,
                    kind: window.kind,
                    subtitle: window.subtitle,
                    detailText: window.detailText,
                    icon: window.icon
                )
            }

            print("  ✓ Found \(newWindows.count) total windows")

            // Update on main thread
            DispatchQueue.main.async {
                self.windows = newWindows
                print("  ✓ Published \(newWindows.count) windows to UI")

                // Clear refresh lock
                self.refreshLock.lock()
                self.isRefreshing = false
                self.refreshLock.unlock()
            }
        }
    }

    func activateWindow(_ window: WindowInfo) {
        if case let .terminalTab(windowTitle, tabTitle, tabIndex) = window.kind {
            activateTerminalTab(windowTitle: windowTitle, tabTitle: tabTitle, tabIndex: tabIndex, processID: window.processID)
            return
        }
        if case let .chromeTab(windowTitle, tabTitle, tabIndex) = window.kind {
            activateChromeTab(windowTitle: windowTitle, tabTitle: tabTitle, tabIndex: tabIndex, processID: window.processID)
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

    private func terminalTabs(for terminalApp: NSRunningApplication?) -> [WindowInfo] {
        guard let terminalApp else {
            terminalTabCacheLock.lock()
            cachedTerminalTabs = []
            lastTerminalTabRefresh = Date.distantPast
            terminalTabCacheLock.unlock()
            return []
        }

        let now = Date()
        terminalTabCacheLock.lock()
        let shouldRefresh = cachedTerminalTabs.isEmpty || now.timeIntervalSince(lastTerminalTabRefresh) >= terminalTabRefreshInterval
        let cachedTabs = cachedTerminalTabs
        terminalTabCacheLock.unlock()

        guard shouldRefresh else {
            return cachedTabs
        }

        let refreshedTabs = fetchTerminalTabs(terminalPID: terminalApp.processIdentifier, icon: terminalApp.icon)

        terminalTabCacheLock.lock()
        cachedTerminalTabs = refreshedTabs
        lastTerminalTabRefresh = now
        let result = cachedTerminalTabs
        terminalTabCacheLock.unlock()

        return result
    }

    private func fetchTerminalTabs(terminalPID: pid_t, icon: NSImage?) -> [WindowInfo] {
        let axApp = AXUIElementCreateApplication(terminalPID)
        guard let axWindows = copyAttribute(axApp, attribute: kAXWindowsAttribute) as? [AXUIElement] else {
            return []
        }

        var terminalTabs: [WindowInfo] = []

        for axWindow in axWindows {
            let windowTitle = stringAttribute(axWindow, attribute: kAXTitleAttribute).trimmingCharacters(in: .whitespacesAndNewlines)
            let tabButtons = terminalTabButtons(in: axWindow)

            for (index, tabButton) in tabButtons.enumerated() {
                let tabTitle = stringAttribute(tabButton, attribute: kAXTitleAttribute).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !tabTitle.isEmpty else { continue }

                let subtitle = "Terminal tab \(index + 1)"
                let detailText = windowTitle.isEmpty ? subtitle : windowTitle
                terminalTabs.append(
                    WindowInfo(
                        id: 0,
                        title: tabTitle,
                        ownerName: "Terminal",
                        processID: terminalPID,
                        windowNumber: 0,
                        kind: .terminalTab(windowTitle: windowTitle, tabTitle: tabTitle, tabIndex: index + 1),
                        subtitle: subtitle,
                        detailText: detailText,
                        icon: icon
                    )
                )
            }
        }

        return terminalTabs
    }

    private func chromeTabs(for chromeApp: NSRunningApplication?) -> [WindowInfo] {
        guard let chromeApp else {
            chromeTabCacheLock.lock()
            cachedChromeTabs = []
            lastChromeTabRefresh = Date.distantPast
            chromeTabCacheLock.unlock()
            return []
        }

        let now = Date()
        chromeTabCacheLock.lock()
        let shouldRefresh = cachedChromeTabs.isEmpty || now.timeIntervalSince(lastChromeTabRefresh) >= chromeTabRefreshInterval
        let cachedTabs = cachedChromeTabs
        chromeTabCacheLock.unlock()

        guard shouldRefresh else {
            return cachedTabs
        }

        let refreshedTabs = fetchChromeTabs(chromePID: chromeApp.processIdentifier, icon: chromeApp.icon)

        chromeTabCacheLock.lock()
        cachedChromeTabs = refreshedTabs
        lastChromeTabRefresh = now
        let result = cachedChromeTabs
        chromeTabCacheLock.unlock()

        return result
    }

    private func fetchChromeTabs(chromePID: pid_t, icon: NSImage?) -> [WindowInfo] {
        let axApp = AXUIElementCreateApplication(chromePID)
        guard let axWindows = copyAttribute(axApp, attribute: kAXWindowsAttribute) as? [AXUIElement] else {
            return []
        }

        var chromeTabs: [WindowInfo] = []

        for axWindow in axWindows {
            let windowTitle = stringAttribute(axWindow, attribute: kAXTitleAttribute).trimmingCharacters(in: .whitespacesAndNewlines)
            let tabButtons = chromeTabButtons(in: axWindow)

            for (index, tabButton) in tabButtons.enumerated() {
                let tabTitle = chromeTabTitle(for: tabButton)
                guard !tabTitle.isEmpty else { continue }

                let subtitle = "Chrome tab \(index + 1)"
                let detailText = windowTitle.isEmpty ? subtitle : windowTitle
                chromeTabs.append(
                    WindowInfo(
                        id: 0,
                        title: tabTitle,
                        ownerName: "Google Chrome",
                        processID: chromePID,
                        windowNumber: 0,
                        kind: .chromeTab(windowTitle: windowTitle, tabTitle: tabTitle, tabIndex: index + 1),
                        subtitle: subtitle,
                        detailText: detailText,
                        icon: icon
                    )
                )
            }
        }

        return chromeTabs
    }

    private func activateTerminalTab(windowTitle: String, tabTitle: String, tabIndex: Int, processID: pid_t) {
        let app = NSRunningApplication(processIdentifier: processID)
        app?.activate()

        let axApp = AXUIElementCreateApplication(processID)
        guard let axWindows = copyAttribute(axApp, attribute: kAXWindowsAttribute) as? [AXUIElement] else {
            return
        }

        let targetWindow = matchingTerminalWindow(in: axWindows, windowTitle: windowTitle, tabTitle: tabTitle, tabIndex: tabIndex)
        guard let targetWindow else {
            return
        }

        AXUIElementSetAttributeValue(targetWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(targetWindow, kAXRaiseAction as CFString)

        let tabButtons = terminalTabButtons(in: targetWindow)
        if let tabButton = matchingTerminalTabButton(in: tabButtons, tabTitle: tabTitle, tabIndex: tabIndex) {
            AXUIElementPerformAction(tabButton, kAXPressAction as CFString)
            return
        }
    }

    private func activateChromeTab(windowTitle: String, tabTitle: String, tabIndex: Int, processID: pid_t) {
        let app = NSRunningApplication(processIdentifier: processID)
        app?.activate()

        let axApp = AXUIElementCreateApplication(processID)
        guard let axWindows = copyAttribute(axApp, attribute: kAXWindowsAttribute) as? [AXUIElement] else {
            return
        }

        let targetWindow = matchingChromeWindow(in: axWindows, windowTitle: windowTitle, tabTitle: tabTitle, tabIndex: tabIndex)
        guard let targetWindow else {
            return
        }

        AXUIElementSetAttributeValue(targetWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(targetWindow, kAXRaiseAction as CFString)

        let tabButtons = chromeTabButtons(in: targetWindow)
        if let tabButton = matchingChromeTabButton(in: tabButtons, tabTitle: tabTitle, tabIndex: tabIndex) {
            AXUIElementPerformAction(tabButton, kAXPressAction as CFString)
        }
    }

    private func matchingTerminalWindow(in windows: [AXUIElement], windowTitle: String, tabTitle: String, tabIndex: Int) -> AXUIElement? {
        if !windowTitle.isEmpty,
           let titleMatched = windows.first(where: { stringAttribute($0, attribute: kAXTitleAttribute) == windowTitle && terminalTabButtons(in: $0).count >= tabIndex }) {
            return titleMatched
        }

        return windows.first { window in
            let tabButtons = terminalTabButtons(in: window)
            return matchingTerminalTabButton(in: tabButtons, tabTitle: tabTitle, tabIndex: tabIndex) != nil
        }
    }

    private func matchingTerminalTabButton(in tabButtons: [AXUIElement], tabTitle: String, tabIndex: Int) -> AXUIElement? {
        if tabIndex > 0, tabIndex <= tabButtons.count {
            let indexedButton = tabButtons[tabIndex - 1]
            if stringAttribute(indexedButton, attribute: kAXTitleAttribute) == tabTitle {
                return indexedButton
            }
        }

        return tabButtons.first { stringAttribute($0, attribute: kAXTitleAttribute) == tabTitle }
    }

    private func matchingChromeWindow(in windows: [AXUIElement], windowTitle: String, tabTitle: String, tabIndex: Int) -> AXUIElement? {
        if !windowTitle.isEmpty,
           let titleMatched = windows.first(where: { stringAttribute($0, attribute: kAXTitleAttribute) == windowTitle && chromeTabButtons(in: $0).count >= tabIndex }) {
            return titleMatched
        }

        return windows.first { window in
            let tabButtons = chromeTabButtons(in: window)
            return matchingChromeTabButton(in: tabButtons, tabTitle: tabTitle, tabIndex: tabIndex) != nil
        }
    }

    private func matchingChromeTabButton(in tabButtons: [AXUIElement], tabTitle: String, tabIndex: Int) -> AXUIElement? {
        if tabIndex > 0, tabIndex <= tabButtons.count {
            let indexedButton = tabButtons[tabIndex - 1]
            if chromeTabTitle(for: indexedButton) == tabTitle {
                return indexedButton
            }
        }

        return tabButtons.first { chromeTabTitle(for: $0) == tabTitle }
    }

    private func shouldHideTerminalWindow(axWindow: AXUIElement, windowTitle: String) -> Bool {
        guard let selectedTab = selectedTerminalTabButton(in: axWindow) else {
            return false
        }

        let selectedTabTitle = stringAttribute(selectedTab, attribute: kAXTitleAttribute).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedTabTitle.isEmpty else {
            return false
        }

        return windowTitle.trimmingCharacters(in: .whitespacesAndNewlines) == selectedTabTitle
    }

    private func shouldHideChromeWindow(axWindow: AXUIElement, windowTitle: String) -> Bool {
        guard let selectedTab = selectedChromeTabButton(in: axWindow) else {
            return false
        }

        let selectedTabTitle = chromeTabTitle(for: selectedTab)
        guard !selectedTabTitle.isEmpty else {
            return false
        }

        return windowTitle.trimmingCharacters(in: .whitespacesAndNewlines) == selectedTabTitle
    }

    private func selectedTerminalTabButton(in window: AXUIElement) -> AXUIElement? {
        let tabButtons = terminalTabButtons(in: window)
        return tabButtons.first(where: { boolAttribute($0, attribute: kAXSelectedAttribute) })
            ?? tabButtons.first(where: { boolAttribute($0, attribute: kAXValueAttribute) })
    }

    private func selectedChromeTabButton(in window: AXUIElement) -> AXUIElement? {
        let tabButtons = chromeTabButtons(in: window)
        return tabButtons.first(where: { boolAttribute($0, attribute: kAXSelectedAttribute) })
            ?? tabButtons.first(where: { boolAttribute($0, attribute: kAXValueAttribute) })
    }

    private func terminalTabButtons(in window: AXUIElement) -> [AXUIElement] {
        guard let tabGroup = findTerminalTabGroup(in: window, depthRemaining: Self.maxTabSearchDepth),
              let children = copyAttribute(tabGroup, attribute: kAXChildrenAttribute) as? [AXUIElement] else {
            return []
        }

        return children.filter {
            stringAttribute($0, attribute: kAXRoleAttribute) == kAXRadioButtonRole &&
            stringAttribute($0, attribute: kAXSubroleAttribute) == "AXTabButton"
        }
    }

    private func chromeTabButtons(in window: AXUIElement) -> [AXUIElement] {
        guard let tabGroup = findChromeTabGroup(in: window, depthRemaining: Self.maxTabSearchDepth),
              let tabListContainer = firstChromeTabListContainer(in: tabGroup),
              let tabButtons = findChromeTabButtons(in: tabListContainer, depthRemaining: Self.maxTabSearchDepth) else {
            return []
        }

        return tabButtons
    }

    private func findTerminalTabGroup(in element: AXUIElement, depthRemaining: Int) -> AXUIElement? {
        guard depthRemaining >= 0 else { return nil }

        if stringAttribute(element, attribute: kAXRoleAttribute) == kAXTabGroupRole {
            return element
        }

        guard let children = copyAttribute(element, attribute: kAXChildrenAttribute) as? [AXUIElement] else {
            return nil
        }

        for child in children {
            if let match = findTerminalTabGroup(in: child, depthRemaining: depthRemaining - 1) {
                return match
            }
        }

        return nil
    }

    private func findChromeTabGroup(in element: AXUIElement, depthRemaining: Int) -> AXUIElement? {
        findTerminalTabGroup(in: element, depthRemaining: depthRemaining)
    }

    private func firstChromeTabListContainer(in tabGroup: AXUIElement) -> AXUIElement? {
        guard let children = copyAttribute(tabGroup, attribute: kAXChildrenAttribute) as? [AXUIElement] else {
            return nil
        }

        return children.first { child in
            if let childChildren = copyAttribute(child, attribute: kAXChildrenAttribute) as? [AXUIElement] {
                return childChildren.contains {
                    stringAttribute($0, attribute: kAXRoleAttribute) == kAXRadioButtonRole &&
                    stringAttribute($0, attribute: kAXSubroleAttribute) == "AXTabButton"
                }
            }
            return false
        }
    }

    private func findChromeTabButtons(in element: AXUIElement, depthRemaining: Int) -> [AXUIElement]? {
        guard depthRemaining >= 0 else { return nil }

        if let children = copyAttribute(element, attribute: kAXChildrenAttribute) as? [AXUIElement] {
            let tabButtons = children.filter {
                stringAttribute($0, attribute: kAXRoleAttribute) == kAXRadioButtonRole &&
                stringAttribute($0, attribute: kAXSubroleAttribute) == "AXTabButton"
            }
            if !tabButtons.isEmpty {
                return tabButtons
            }

            for child in children {
                if let found = findChromeTabButtons(in: child, depthRemaining: depthRemaining - 1), !found.isEmpty {
                    return found
                }
            }
        }

        return nil
    }

    private func chromeTabTitle(for element: AXUIElement) -> String {
        let title = stringAttribute(element, attribute: kAXTitleAttribute).trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            return title
        }

        return stringAttribute(element, attribute: kAXDescriptionAttribute).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func copyAttribute(_ element: AXUIElement, attribute: String) -> AnyObject? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else {
            return nil
        }
        return value
    }

    private func stringAttribute(_ element: AXUIElement, attribute: String) -> String {
        (copyAttribute(element, attribute: attribute) as? String) ?? ""
    }

    private func boolAttribute(_ element: AXUIElement, attribute: String) -> Bool {
        (copyAttribute(element, attribute: attribute) as? Bool) ?? false
    }
}
