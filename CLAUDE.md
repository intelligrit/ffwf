# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

FFFW (Fast Fuzzy Find Windows) is a macOS menu bar app for switching windows with fuzzy search. Built with Swift and SwiftUI, it runs persistently in the system tray and can be activated via global hotkey (Cmd+Shift+Space) or clicking the menu bar icon. The primary goal is maximum performance - fuzzy matching and UI updates must be instantaneous.

## Build Commands

```bash
# Build debug version
swift build

# Build release version (optimized)
swift build -c release

# Run directly
swift run

# Run release build
.build/release/FFFW
```

## Architecture

### Core Components

1. **FuzzyMatcher** (FuzzyMatcher.swift)
   - Implements fast fuzzy string matching inspired by Sublime Text
   - Scores matches based on: consecutive characters, word boundaries, camelCase, match position
   - Returns `nil` for non-matches to enable efficient filtering
   - Uses `String.Index` for proper Unicode handling

2. **WindowManager** (WindowManager.swift)
   - Uses `CGWindowListCopyWindowInfo` to enumerate all on-screen windows
   - Filters out tiny windows (< 50x50) and desktop elements
   - Uses Accessibility API (`AXUIElement`) to focus and raise specific windows
   - Published `@ObservableObject` for reactive UI updates

3. **WindowInfo** (WindowInfo.swift)
   - Immutable struct representing a window with title, owner, PID, window number
   - `Identifiable` and `Hashable` for SwiftUI List performance
   - `ScoredWindow` wrapper adds fuzzy match score

4. **ContentView** (ContentView.swift)
   - Real-time fuzzy filtering on every keystroke
   - Keyboard navigation: ↑/↓ arrows, Enter to select, Escape to hide
   - `ScrollViewReader` for smooth auto-scrolling to selected item
   - `@FocusState` ensures search field stays focused
   - Resets search query and selection on each appearance

5. **FFFFWApp** (FFFFWApp.swift)
   - Menu bar application (NSStatusItem) with magnifying glass icon
   - NSPopover for search interface (600x400)
   - Global hotkey: Cmd+Shift+Space (registered via Carbon API)
   - Left-click icon or hotkey: toggle popover
   - Right-click icon: show quit menu
   - Runs as accessory (no Dock icon)
   - Hides popover after window activation instead of quitting

### Performance Considerations

- Fuzzy matching algorithm is O(n*m) worst case but optimized with early returns
- List uses `id` for efficient diffing - only changed items re-render
- Filtering happens synchronously on main thread (fast enough for typical window counts)
- If performance degrades with many windows, consider:
  - Debouncing search input (add 50ms delay)
  - Moving filtering to background thread with `Task`
  - Limiting displayed results to top 50

### macOS Permissions

The app requires:
- **Accessibility**: To focus and raise windows via AX API
- **Screen Recording**: May be required for `CGWindowListCopyWindowInfo` on some macOS versions

Permissions are declared in Info.plist with usage descriptions.

### Global Hotkey Implementation

- Uses Carbon Event Manager APIs (`RegisterEventHotKey`, `InstallEventHandler`)
- Default: Cmd+Shift+Space (can be modified in `registerGlobalHotkey()`)
- Registered on app launch, works system-wide
- Shows popover when triggered

## Usage

1. Launch app - icon appears in menu bar
2. Click icon or press Cmd+Shift+Space to show search
3. Type to fuzzy filter windows
4. ↑/↓ arrows to navigate, Enter to switch
5. Escape to hide without switching
6. Right-click menu bar icon to quit app

## Future Enhancements

- Browser tab enumeration (requires browser-specific extensions or AppleScript)
- Configurable hotkey
- MRU (Most Recently Used) sorting option
- Window preview on hover
