# FFFW - Fast Fuzzy Find Windows

A blazing-fast macOS menu bar app for switching windows with fuzzy search.

## Features

- Lives in your menu bar - always accessible
- Global hotkey: **Option+Shift+Space**
- Lightning-fast fuzzy matching of window titles and application names
- Clean SwiftUI popover interface
- Keyboard-driven navigation (Arrow keys + Enter)
- Shows application icons for easy identification
- Automatically focuses and raises selected window
- Stays running in background - no need to relaunch

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 15.0 or later (for building)

## Building

```bash
swift build -c release
```

The binary will be in `.build/release/FFFW`

## Running

```bash
swift run
```

Or run the built binary directly:

```bash
.build/release/FFFW
```

## Permissions

On first run, macOS will prompt for:
- **Accessibility** permissions (required to focus windows)
- **Screen Recording** permissions (may be needed for window list access)

Grant these in System Settings > Privacy & Security

## Usage

1. Launch the app - a magnifying glass icon appears in your menu bar
2. Click the icon or press **Option+Shift+Space** to show the window finder
3. Start typing to fuzzy search window titles or app names
4. Use ↑/↓ arrow keys to navigate results
5. Press **Enter** to switch to the selected window
6. Press **Escape** to hide the finder without switching
7. Right-click the menu bar icon to quit the app

## Architecture

- **FuzzyMatcher**: Fast fuzzy string matching with scoring
- **WindowManager**: Uses CGWindowListCopyWindowInfo and AX APIs for window enumeration and activation
- **SwiftUI**: Reactive UI with real-time filtering
