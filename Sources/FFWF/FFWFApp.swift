import SwiftUI
import Carbon

@main
struct FFWFApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var settingsWindow: NSWindow?
    var aboutWindow: NSWindow?
    var eventMonitor: Any?
    var hotkeyRef: EventHotKeyRef?
    var hotkeyEventHandler: EventHandlerRef?
    var menu: NSMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Listen for hotkey changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotkeyDidChange),
            name: .hotkeyChanged,
            object: nil
        )
        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "magnifyingglass.circle", accessibilityDescription: "FFWF Window Finder")
            button.action = #selector(handleStatusItemClick)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])

            // Update tooltip with current hotkey
            updateTooltip()
        }

        // Create menu for right-click (but don't assign it yet)
        menu = NSMenu()
        menu?.addItem(NSMenuItem(title: "About FFWF", action: #selector(showAbout), keyEquivalent: ""))
        menu?.addItem(NSMenuItem.separator())
        menu?.addItem(NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ","))
        menu?.addItem(NSMenuItem.separator())
        menu?.addItem(NSMenuItem(title: "Quit FFWF", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        // Create popover
        popover = NSPopover()
        popover?.contentViewController = NSHostingController(rootView: ContentView(hideWindow: hidePopover))
        popover?.behavior = .transient

        // Register global hotkey (Cmd+Shift+Space)
        registerGlobalHotkey()

        // Don't show in Dock
        NSApp.setActivationPolicy(.accessory)

        // Check for required permissions
        checkAccessibilityPermission()

        // Start loading windows immediately at startup
        WindowManager.shared.refreshWindows()
    }

    func checkAccessibilityPermission() {
        // Check if we have accessibility permission
        let trusted = AXIsProcessTrusted()

        if !trusted {
            // Show alert after a short delay to ensure the app is fully loaded
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let alert = NSAlert()
                alert.messageText = "Accessibility Permission Required"
                alert.informativeText = """
                FFWF needs Accessibility permission to function properly.

                Without this permission, FFWF cannot:
                • Read the list of open windows
                • Switch between windows
                • Display window titles

                Please grant Accessibility permission in System Settings.
                """
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Open System Settings")
                alert.addButton(withTitle: "Quit")

                let response = alert.runModal()

                if response == .alertFirstButtonReturn {
                    // Open System Settings to Accessibility
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)

                    // Show follow-up instructions
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        let followUp = NSAlert()
                        followUp.messageText = "Enable FFWF in Accessibility"
                        followUp.informativeText = """
                        1. Click the lock icon and enter your password
                        2. Find "FFWF" in the list
                        3. Toggle the switch ON
                        4. Quit and relaunch FFWF

                        FFWF will continue running in the background, but won't work until you grant permission and restart.
                        """
                        followUp.alertStyle = .informational
                        followUp.addButton(withTitle: "OK")
                        followUp.runModal()
                    }
                } else {
                    // User chose to quit
                    NSApp.terminate(nil)
                }
            }
        }
    }

    @objc func handleStatusItemClick(_ sender: Any?) {
        // Check if this is a right click
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            // Show menu for right-click
            if let button = statusItem?.button, let menu = menu {
                statusItem?.menu = menu
                button.performClick(nil)
                statusItem?.menu = nil
            }
            return
        }

        // Left-click: toggle popover
        togglePopover()
    }

    func togglePopover() {
        if let popover = popover {
            if popover.isShown {
                hidePopover()
            } else {
                showPopover()
            }
        }
    }

    func showPopover() {
        if let button = statusItem?.button, let popover = popover {
            // Position below menu bar icon
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func hidePopover() {
        popover?.performClose(nil)
    }

    func registerGlobalHotkey() {
        // Unregister existing hotkey if any
        if let existingRef = hotkeyRef {
            UnregisterEventHotKey(existingRef)
            hotkeyRef = nil
        }

        // Remove existing event handler if any
        if let existingHandler = hotkeyEventHandler {
            RemoveEventHandler(existingHandler)
            hotkeyEventHandler = nil
        }

        // Get hotkey from settings
        let hotkey = HotkeySettings.shared.hotkey

        var hotKeyID = EventHotKeyID()
        hotKeyID.id = 1
        hotKeyID.signature = 0x46464657 // 'FFFW' as OSType

        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = OSType(kEventHotKeyPressed)

        var handler: EventHandlerRef?
        InstallEventHandler(GetApplicationEventTarget(), { (nextHandler, theEvent, userData) -> OSStatus in
            guard let userData = userData else { return noErr }
            let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                appDelegate.togglePopover()
            }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)

        hotkeyEventHandler = handler

        RegisterEventHotKey(hotkey.keyCode, hotkey.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotkeyRef)
    }

    @objc func hotkeyDidChange() {
        registerGlobalHotkey()
        updateTooltip()
    }

    func updateTooltip() {
        let hotkey = HotkeySettings.shared.hotkey
        let tooltip = "FFWF - Fast Fuzzy Window Finder (\(hotkey.displayString))"

        if let button = statusItem?.button {
            button.toolTip = tooltip
            button.setAccessibilityLabel("FFWF Window Finder")
            button.setAccessibilityHelp("Click to search and switch windows, or press \(hotkey.displayString)")
        }
    }

    @objc func showSettings() {
        // Create or show settings window
        if settingsWindow == nil {
            let settingsView = SettingsView()
            let hostingController = NSHostingController(rootView: settingsView)

            let window = NSWindow(contentViewController: hostingController)
            window.title = "FFWF Settings"
            window.styleMask = [.titled, .closable]
            window.center()
            window.setFrameAutosaveName("SettingsWindow")

            settingsWindow = window
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showAbout() {
        // Create or show about window
        if aboutWindow == nil {
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
            let aboutView = AboutView(version: version)
            let hostingController = NSHostingController(rootView: aboutView)

            let window = NSWindow(contentViewController: hostingController)
            window.title = "About FFWF"
            window.styleMask = [.titled, .closable]
            window.center()
            window.setFrameAutosaveName("AboutWindow")

            aboutWindow = window
        }

        aboutWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
