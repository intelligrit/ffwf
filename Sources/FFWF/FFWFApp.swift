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
    var eventMonitor: Any?
    var hotkeyRef: EventHotKeyRef?
    var menu: NSMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "magnifyingglass.circle", accessibilityDescription: "FFWF Window Finder")
            button.action = #selector(handleStatusItemClick)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])

            // Accessibility
            button.toolTip = "FFWF - Fast Fuzzy Window Finder (Option+Shift+Space)"
            button.setAccessibilityLabel("FFWF Window Finder")
            button.setAccessibilityHelp("Click to search and switch windows, or press Option Shift Space")
        }

        // Create menu for right-click (but don't assign it yet)
        menu = NSMenu()
        menu?.addItem(NSMenuItem(title: "Quit FFWF", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        // Create popover
        popover = NSPopover()
        popover?.contentViewController = NSHostingController(rootView: ContentView(hideWindow: hidePopover))
        popover?.behavior = .transient

        // Register global hotkey (Cmd+Shift+Space)
        registerGlobalHotkey()

        // Don't show in Dock
        NSApp.setActivationPolicy(.accessory)

        // Start loading windows immediately at startup
        WindowManager.shared.refreshWindows()
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
        // Register Option+Shift+Space
        var hotKeyID = EventHotKeyID()
        hotKeyID.id = 1
        hotKeyID.signature = 0x46464657 // 'FFFW' as OSType

        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = OSType(kEventHotKeyPressed)

        InstallEventHandler(GetApplicationEventTarget(), { (nextHandler, theEvent, userData) -> OSStatus in
            guard let userData = userData else { return noErr }
            let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                appDelegate.togglePopover()
            }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), nil)

        RegisterEventHotKey(UInt32(kVK_Space), UInt32(optionKey | shiftKey), hotKeyID, GetApplicationEventTarget(), 0, &hotkeyRef)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
