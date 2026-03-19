import Cocoa
import ApplicationServices

class WindowManager: ObservableObject {
    static let shared = WindowManager()
    private static let terminalBundleID = "com.apple.Terminal"
    private static let chromeBundleID = "com.google.Chrome"
    private static let slackBundleID = "com.tinyspeck.slackmacgap"
    private static let maxTabSearchDepth = 4

    @Published var windows: [WindowInfo] = []
    private var isRefreshing = false
    private let refreshLock = NSLock()
    private let terminalTabCacheLock = NSLock()
    private let chromeTabCacheLock = NSLock()
    private let slackItemCacheLock = NSLock()
    private var cachedTerminalTabs: [WindowInfo] = []
    private var cachedChromeTabs: [WindowInfo] = []
    private var cachedSlackItems: [WindowInfo] = []
    private var lastTerminalTabRefresh = Date.distantPast
    private var lastChromeTabRefresh = Date.distantPast
    private var lastSlackItemRefresh = Date.distantPast
    private let terminalTabRefreshInterval: TimeInterval = 1.5
    private let chromeTabRefreshInterval: TimeInterval = 1.5
    private let slackItemRefreshInterval: TimeInterval = 1.5

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
            let slackApp = runningApps.first { $0.bundleIdentifier == Self.slackBundleID }

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
                    let isSlack = app.bundleIdentifier == Self.slackBundleID

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
                        if isSlack, self.shouldHideSlackWindow(windowTitle: title) {
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
            newWindows.append(contentsOf: self.slackItems(for: slackApp))

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
        switch window.kind {
        case let .slackWorkspace(name):
            activateSlackWorkspace(named: name, processID: window.processID)
            return
        case let .slackChannel(workspace, name):
            activateSlackSidebarItem(workspace: workspace, itemName: name, itemKind: .slackChannel(workspace: workspace, name: name), processID: window.processID)
            return
        case let .slackDM(workspace, name):
            activateSlackSidebarItem(workspace: workspace, itemName: name, itemKind: .slackDM(workspace: workspace, name: name), processID: window.processID)
            return
        case .window, .terminalTab, .chromeTab:
            break
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

    private func slackItems(for slackApp: NSRunningApplication?) -> [WindowInfo] {
        guard let slackApp else {
            slackItemCacheLock.lock()
            cachedSlackItems = []
            lastSlackItemRefresh = Date.distantPast
            slackItemCacheLock.unlock()
            return []
        }

        let now = Date()
        slackItemCacheLock.lock()
        let shouldRefresh = cachedSlackItems.isEmpty || now.timeIntervalSince(lastSlackItemRefresh) >= slackItemRefreshInterval
        let cachedItems = cachedSlackItems
        slackItemCacheLock.unlock()

        guard shouldRefresh else {
            return cachedItems
        }

        let refreshedItems = fetchSlackItems(slackPID: slackApp.processIdentifier, icon: slackApp.icon)

        slackItemCacheLock.lock()
        cachedSlackItems = refreshedItems
        lastSlackItemRefresh = now
        let result = cachedSlackItems
        slackItemCacheLock.unlock()

        return result
    }

    private func fetchSlackItems(slackPID: pid_t, icon: NSImage?) -> [WindowInfo] {
        let axApp = AXUIElementCreateApplication(slackPID)
        guard let axWindows = copyAttribute(axApp, attribute: kAXWindowsAttribute) as? [AXUIElement],
              let window = axWindows.first else {
            return []
        }

        var slackItems: [WindowInfo] = []
        let selectedWorkspaceName = selectedSlackWorkspaceName(in: window) ?? slackWorkspaceNameFromWindow(window)

        for workspaceButton in slackWorkspaceButtons(in: window) {
            let workspaceName = slackWorkspaceName(for: workspaceButton)
            guard !workspaceName.isEmpty else { continue }

            let unreadCount = slackUnreadCount(for: workspaceButton, baseName: workspaceName)
            let subtitle = unreadCount > 0 ? "Slack workspace · \(workspaceName) · \(unreadCount) unread" : "Slack workspace · \(workspaceName)"
            let detailText = searchableSlackDetail(
                typeTokens: ["slack", "workspace", "team"],
                workspaceName: workspaceName,
                unreadCount: unreadCount,
                includeWorkspaceName: true
            )

            slackItems.append(
                WindowInfo(
                    id: 0,
                    title: workspaceName,
                    ownerName: "Slack",
                    processID: slackPID,
                    windowNumber: 0,
                    kind: .slackWorkspace(name: workspaceName),
                    subtitle: subtitle,
                    detailText: detailText,
                    icon: icon
                )
            )
        }

        if let workspaceName = selectedWorkspaceName {
            for sidebarItem in slackSidebarItems(in: window, workspaceName: workspaceName) {
                let subtitle: String
                let typeTokens: [String]

                switch sidebarItem.kind {
                case .slackDM:
                    subtitle = sidebarItem.unreadCount > 0 ? "Slack DM · \(workspaceName) · \(sidebarItem.unreadCount) unread" : "Slack DM · \(workspaceName)"
                    typeTokens = ["slack", "dm", "direct", "message"]
                case .slackChannel:
                    subtitle = sidebarItem.unreadCount > 0 ? "Slack channel · \(workspaceName) · \(sidebarItem.unreadCount) unread" : "Slack channel · \(workspaceName)"
                    typeTokens = ["slack", "chan", "channel"]
                case .window, .terminalTab, .chromeTab, .slackWorkspace:
                    continue
                }

                let detailText = searchableSlackDetail(
                    typeTokens: typeTokens,
                    workspaceName: workspaceName,
                    unreadCount: sidebarItem.unreadCount,
                    includeWorkspaceName: false
                )

                slackItems.append(
                    WindowInfo(
                        id: 0,
                        title: sidebarItem.name,
                        ownerName: "Slack",
                        processID: slackPID,
                        windowNumber: 0,
                        kind: sidebarItem.kind,
                        subtitle: subtitle,
                        detailText: detailText,
                        icon: icon
                    )
                )
            }
        }

        return slackItems
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

    private func activateSlackWorkspace(named workspaceName: String, processID: pid_t) {
        let app = NSRunningApplication(processIdentifier: processID)
        app?.activate()

        let axApp = AXUIElementCreateApplication(processID)
        guard let axWindows = copyAttribute(axApp, attribute: kAXWindowsAttribute) as? [AXUIElement],
              let window = axWindows.first,
              let button = slackWorkspaceButtons(in: window).first(where: { slackWorkspaceName(for: $0) == workspaceName }) else {
            return
        }

        AXUIElementPerformAction(button, kAXPressAction as CFString)
    }

    private func activateSlackSidebarItem(workspace: String, itemName: String, itemKind: WindowKind, processID: pid_t) {
        let app = NSRunningApplication(processIdentifier: processID)
        app?.activate()

        guard let window = primaryWindow(for: processID) else {
            return
        }

        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)

        if selectedSlackWorkspaceName(in: window) != workspace {
            activateSlackWorkspace(named: workspace, processID: processID)
            usleep(250_000)
        }

        guard let refreshedWindow = primaryWindow(for: processID),
              let row = matchingSlackSidebarRow(in: refreshedWindow, workspaceName: workspace, itemName: itemName, kind: itemKind) else {
            return
        }

        AXUIElementPerformAction(row, "AXScrollToVisible" as CFString)
        usleep(50_000)

        if let pressableDescendant = firstPressableDescendant(in: row) {
            AXUIElementPerformAction(pressableDescendant, kAXPressAction as CFString)
            return
        }

        if canPress(row) {
            AXUIElementPerformAction(row, kAXPressAction as CFString)
            return
        }

        if let pressableAncestor = nearestPressableAncestor(startingAt: row) {
            AXUIElementPerformAction(pressableAncestor, kAXPressAction as CFString)
            return
        }

        AXUIElementPerformAction(row, kAXPressAction as CFString)
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

    private func shouldHideSlackWindow(windowTitle: String) -> Bool {
        let normalized = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.contains(" - Slack")
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

    private func selectedSlackWorkspaceName(in window: AXUIElement) -> String? {
        let buttons = slackWorkspaceButtons(in: window)
        guard let selected = buttons.first(where: { boolAttribute($0, attribute: kAXSelectedAttribute) }) else {
            return nil
        }

        let name = slackWorkspaceName(for: selected)
        return name.isEmpty ? nil : name
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

    private func slackWorkspaceButtons(in window: AXUIElement) -> [AXUIElement] {
        guard let tabGroup = findElement(in: window, role: kAXTabGroupRole, descriptionContains: "Workspaces", depthRemaining: 14),
              let children = copyAttribute(tabGroup, attribute: kAXChildrenAttribute) as? [AXUIElement] else {
            return []
        }

        return children.filter {
            stringAttribute($0, attribute: kAXRoleAttribute) == kAXRadioButtonRole &&
            stringAttribute($0, attribute: kAXSubroleAttribute) == "AXTabButton"
        }
    }

    private func slackSidebarItems(in window: AXUIElement, workspaceName: String) -> [SlackSidebarItem] {
        guard let outline = findElement(in: window, role: kAXOutlineRole, descriptionContains: "Channels and direct messages", depthRemaining: 18),
              let rows = copyAttribute(outline, attribute: kAXChildrenAttribute) as? [AXUIElement] else {
            return []
        }

        var items: [SlackSidebarItem] = []
        var seen = Set<String>()
        var currentSection: String?

        for row in rows {
            guard stringAttribute(row, attribute: kAXRoleAttribute) == kAXRowRole else { continue }

            let label = slackSidebarRowLabel(row)
            guard !label.isEmpty else { continue }

            if isSlackSidebarSection(label) {
                currentSection = label
                let nestedItems = slackNestedSidebarItems(in: row, section: label, workspaceName: workspaceName)
                for item in nestedItems where seen.insert("\(item.kind)|\(item.name)").inserted {
                    items.append(item)
                }
                continue
            }

            let kind = slackSidebarKind(for: row, section: currentSection, workspaceName: workspaceName, label: label)
            let unreadCount = slackUnreadCount(for: row, baseName: label)
            let item = SlackSidebarItem(name: label, unreadCount: unreadCount, kind: kind)
            if seen.insert("\(item.kind)|\(item.name)").inserted {
                items.append(item)
            }
        }

        return items
    }

    private func matchingSlackSidebarRow(in window: AXUIElement, workspaceName: String, itemName: String, kind: WindowKind) -> AXUIElement? {
        guard let outline = findElement(in: window, role: kAXOutlineRole, descriptionContains: "Channels and direct messages", depthRemaining: 18),
              let rows = copyAttribute(outline, attribute: kAXChildrenAttribute) as? [AXUIElement] else {
            return nil
        }

        var currentSection: String?
        for row in rows {
            guard stringAttribute(row, attribute: kAXRoleAttribute) == kAXRowRole else { continue }
            let label = slackSidebarRowLabel(row)
            guard !label.isEmpty else { continue }

            if isSlackSidebarSection(label) {
                currentSection = label
                if let nestedMatch = matchingSlackNestedElement(in: row, section: label, itemName: itemName, kind: kind, workspaceName: workspaceName) {
                    return nestedMatch
                }
                continue
            }

            let rowKind = slackSidebarKind(for: row, section: currentSection, workspaceName: workspaceName, label: label)
            if rowKind == kind && label == itemName {
                return row
            }
        }

        return nil
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

    private func findElement(in element: AXUIElement, role: String, descriptionContains: String? = nil, depthRemaining: Int) -> AXUIElement? {
        guard depthRemaining >= 0 else { return nil }

        if stringAttribute(element, attribute: kAXRoleAttribute) == role {
            if let descriptionContains {
                if stringAttribute(element, attribute: kAXDescriptionAttribute).contains(descriptionContains) {
                    return element
                }
            } else {
                return element
            }
        }

        guard let children = copyAttribute(element, attribute: kAXChildrenAttribute) as? [AXUIElement] else {
            return nil
        }

        for child in children {
            if let match = findElement(in: child, role: role, descriptionContains: descriptionContains, depthRemaining: depthRemaining - 1) {
                return match
            }
        }

        return nil
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

    private func slackWorkspaceName(for element: AXUIElement) -> String {
        let title = normalizeSlackLabel(stringAttribute(element, attribute: kAXTitleAttribute))
        if !title.isEmpty {
            return title
        }

        let description = normalizeSlackLabel(stringAttribute(element, attribute: kAXDescriptionAttribute))
        if !description.isEmpty {
            return description
        }

        return normalizeSlackLabel(firstNonEmptyText(in: element))
    }

    private func slackWorkspaceNameFromWindow(_ window: AXUIElement) -> String? {
        if let tabPanel = findElement(in: window, role: kAXGroupRole, descriptionContains: nil, depthRemaining: 18),
           let panelName = slackSelectedWorkspacePanelName(in: tabPanel),
           !panelName.isEmpty {
            return panelName
        }

        let windowTitle = stringAttribute(window, attribute: kAXTitleAttribute)
        let parts = windowTitle.split(separator: "-").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if parts.count >= 2 {
            let workspace = parts[parts.count - 2]
            return workspace.isEmpty ? nil : workspace
        }

        return nil
    }

    private func slackSelectedWorkspacePanelName(in root: AXUIElement) -> String? {
        guard let panel = findElement(in: root, role: kAXGroupRole, descriptionContains: nil, depthRemaining: 18) else {
            return nil
        }

        if stringAttribute(panel, attribute: kAXSubroleAttribute) == "AXTabPanel" {
            let description = normalizeSlackLabel(stringAttribute(panel, attribute: kAXDescriptionAttribute))
            if !description.isEmpty, description.lowercased() != "home" {
                return description
            }
        }

        if let children = copyAttribute(root, attribute: kAXChildrenAttribute) as? [AXUIElement] {
            for child in children {
                if let match = slackSelectedWorkspacePanelName(in: child) {
                    return match
                }
            }
        }

        return nil
    }

    private func slackSidebarRowLabel(_ row: AXUIElement) -> String {
        let directLabel = normalizeSlackLabel(stringAttribute(row, attribute: kAXDescriptionAttribute))
        if !directLabel.isEmpty {
            return directLabel
        }

        let titleLabel = normalizeSlackLabel(stringAttribute(row, attribute: kAXTitleAttribute))
        if !titleLabel.isEmpty {
            return titleLabel
        }

        return normalizeSlackLabel(firstNonEmptyText(in: row))
    }

    private func normalizeSlackLabel(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+[0-9]+$", with: "", options: .regularExpression)
    }

    private func slackUnreadCount(for element: AXUIElement, baseName: String) -> Int {
        let texts = descendantTexts(in: element)
        for text in texts {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let count = Int(trimmed), count > 0 {
                return count
            }

            if trimmed.hasPrefix(baseName + " "),
               let count = Int(trimmed.replacingOccurrences(of: baseName + " ", with: "")),
               count > 0 {
                return count
            }
        }

        return 0
    }

    private func searchableSlackDetail(typeTokens: [String], workspaceName: String, unreadCount: Int, includeWorkspaceName: Bool) -> String {
        var tokens = typeTokens
        if includeWorkspaceName {
            tokens.append(workspaceName)
        }
        if unreadCount > 0 {
            tokens.append(contentsOf: ["slack-new", "new", "unread", "\(unreadCount)"])
        }
        return tokens.joined(separator: " ")
    }

    private func slackSidebarKind(for row: AXUIElement, section: String?, workspaceName: String, label: String) -> WindowKind {
        if section == "Direct Messages" || descendantTexts(in: row).contains(where: { $0.contains("Profile photo for") }) {
            return .slackDM(workspace: workspaceName, name: label)
        }

        return .slackChannel(workspace: workspaceName, name: label)
    }

    private func isSlackSidebarSection(_ label: String) -> Bool {
        let sectionLabels: Set<String> = [
            "Threads", "Huddles", "Recap", "Drafts & sent", "Directories", "Starred",
            "Channels", "Direct Messages", "Apps"
        ]
        return sectionLabels.contains(label)
    }

    private func slackNestedSidebarItems(in sectionRow: AXUIElement, section: String, workspaceName: String) -> [SlackSidebarItem] {
        slackDescendantRows(in: sectionRow).compactMap { row in
            let label = slackNestedLabel(from: slackSidebarRowLabel(row), section: section)
            guard !label.isEmpty else {
                return nil
            }

            let kind = slackSidebarKind(for: row, section: section, workspaceName: workspaceName, label: label)

            return SlackSidebarItem(
                name: label,
                unreadCount: slackUnreadCount(for: row, baseName: label),
                kind: kind
            )
        }
    }

    private func slackDescendantRows(in element: AXUIElement, depthRemaining: Int = 8) -> [AXUIElement] {
        guard depthRemaining >= 0 else { return [] }

        var rows: [AXUIElement] = []

        if depthRemaining < 8, stringAttribute(element, attribute: kAXRoleAttribute) == kAXRowRole {
            rows.append(element)
        }

        if let children = copyAttribute(element, attribute: kAXChildrenAttribute) as? [AXUIElement] {
            for child in children {
                rows.append(contentsOf: slackDescendantRows(in: child, depthRemaining: depthRemaining - 1))
            }
        }

        return rows
    }

    private func slackNestedLabel(from rawText: String, section: String) -> String {
        let normalized = rawText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+\\([^)]+\\)$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+[0-9]+$", with: "", options: .regularExpression)

        guard !normalized.isEmpty,
              normalized != section,
              !isSlackSidebarSection(normalized),
              !slackIgnoredLabels.contains(normalized),
              normalized.count > 1 else {
            return ""
        }

        return normalized
    }

    private var slackIgnoredLabels: Set<String> {
        [
            "Close", "More", "New message", "Create new", "Add workspaces", "loading",
            "Home", "DMs", "Activity", "Files", "Admin", "Canvas", "List", "Folder"
        ]
    }

    private func matchingSlackNestedElement(in sectionRow: AXUIElement, section: String, itemName: String, kind: WindowKind, workspaceName: String, depthRemaining: Int = 8) -> AXUIElement? {
        let rows = slackDescendantRows(in: sectionRow, depthRemaining: depthRemaining)
        return rows.first { row in
            let label = slackNestedLabel(from: slackSidebarRowLabel(row), section: section)
            guard !label.isEmpty else { return false }
            let rowKind = slackSidebarKind(for: row, section: section, workspaceName: workspaceName, label: label)
            return rowKind == kind && label == itemName
        }
    }

    private func firstNonEmptyText(in element: AXUIElement) -> String {
        descendantTexts(in: element).first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? ""
    }

    private func descendantTexts(in element: AXUIElement, depthRemaining: Int = 6) -> [String] {
        guard depthRemaining >= 0 else { return [] }

        var texts: [String] = []
        let title = stringAttribute(element, attribute: kAXTitleAttribute)
        let description = stringAttribute(element, attribute: kAXDescriptionAttribute)
        let value = stringAttribute(element, attribute: kAXValueAttribute)

        if !title.isEmpty { texts.append(title) }
        if !description.isEmpty { texts.append(description) }
        if !value.isEmpty { texts.append(value) }

        if let children = copyAttribute(element, attribute: kAXChildrenAttribute) as? [AXUIElement] {
            for child in children {
                texts.append(contentsOf: descendantTexts(in: child, depthRemaining: depthRemaining - 1))
            }
        }

        return texts
    }

    private func firstPressableElement(in element: AXUIElement, depthRemaining: Int = 6) -> AXUIElement? {
        guard depthRemaining >= 0 else { return nil }

        if canPress(element) {
            return element
        }

        guard let children = copyAttribute(element, attribute: kAXChildrenAttribute) as? [AXUIElement] else {
            return nil
        }

        for child in children {
            if let match = firstPressableElement(in: child, depthRemaining: depthRemaining - 1) {
                return match
            }
        }

        return nil
    }

    private func nearestPressableAncestor(startingAt element: AXUIElement, depthRemaining: Int = 8) -> AXUIElement? {
        guard depthRemaining >= 0 else { return nil }
        if canPress(element) {
            return element
        }

        guard let parentValue = copyAttribute(element, attribute: kAXParentAttribute) else {
            return nil
        }

        let parent = parentValue as! AXUIElement

        return nearestPressableAncestor(startingAt: parent, depthRemaining: depthRemaining - 1)
    }

    private func canPress(_ element: AXUIElement) -> Bool {
        var actionNames: CFArray?
        guard AXUIElementCopyActionNames(element, &actionNames) == .success,
              let names = actionNames as? [String] else {
            return false
        }

        return names.contains(kAXPressAction as String)
    }

    private func firstPressableDescendant(in element: AXUIElement, depthRemaining: Int = 6) -> AXUIElement? {
        guard depthRemaining >= 0,
              let children = copyAttribute(element, attribute: kAXChildrenAttribute) as? [AXUIElement] else {
            return nil
        }

        for child in children {
            if canPress(child) {
                return child
            }

            if let match = firstPressableDescendant(in: child, depthRemaining: depthRemaining - 1) {
                return match
            }
        }

        return nil
    }

    private func primaryWindow(for processID: pid_t) -> AXUIElement? {
        let axApp = AXUIElementCreateApplication(processID)
        guard let axWindows = copyAttribute(axApp, attribute: kAXWindowsAttribute) as? [AXUIElement] else {
            return nil
        }

        return axWindows.first
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

private struct SlackSidebarItem {
    let name: String
    let unreadCount: Int
    let kind: WindowKind
}
