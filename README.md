# FFWF - Fast Fuzzy Window Finder

A blazing-fast macOS menu bar app for switching windows with fuzzy search. Built with Swift and SwiftUI for maximum performance.

![macOS](https://img.shields.io/badge/macOS-14.0+-blue.svg)
![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

## Features

- **Menu Bar App** - Always accessible, runs in the background
- **Configurable Global Hotkey** - Default: Option+Shift+Space (customizable in Settings)
- **Lightning-Fast Fuzzy Matching** - Search window titles and application names instantly
- **Multi-Term Search** - Space-separated terms for precise filtering
- **Smart Prioritization** - Exact and prefix matches ranked higher
- **Event-Driven Updates** - Window list updates automatically when apps launch/quit
- **Keyboard Navigation** - Arrow keys + Enter for quick switching
- **Visual Feedback** - App icons and highlighted selection
- **Accessibility Support** - Full VoiceOver support with screen reader announcements
- **Zero Overhead** - Background refresh only when popover is open

## Quick Start

See [QUICKSTART.md](QUICKSTART.md) for end-user installation and usage instructions.

## Requirements

- macOS 14.0 (Sonoma) or later
- Swift 5.9+ (for building from source)

## Installation

### Option 1: Install from Source (Recommended)

```bash
# Clone the repository
git clone https://github.com/robertmeta/FFWF.git
cd FFWF

# Build and install to /Applications
make install

# Launch from Spotlight or Applications folder
open /Applications/FFWF.app
```

### Option 2: Manual Build

```bash
# Build release version
make app

# Manually copy to Applications
cp -r FFWF.app /Applications/
```

### Uninstall

```bash
make uninstall
```

## Permissions

On first run, macOS will prompt for:

- **Accessibility** - Required to focus and raise windows (System Settings > Privacy & Security > Accessibility)
- **Screen Recording** - May be needed for window enumeration on some macOS versions

Grant these permissions when prompted, then restart the app.

## Usage

### Basic Workflow

1. **Launch** - FFWF appears as a magnifying glass icon in your menu bar
2. **Activate** - Click the icon or press your configured hotkey (default: Option+Shift+Space)
3. **Search** - Type to fuzzy filter windows by title or app name
4. **Navigate** - Use ↑/↓ arrow keys to select
5. **Switch** - Press Enter to activate the selected window
6. **Cancel** - Press Escape to hide without switching

### Customizing the Hotkey

1. Right-click the menu bar icon
2. Select "Settings..."
3. Click the hotkey field and press your desired key combination
4. Changes apply immediately

### Search Tips

- **Fuzzy matching**: Type any characters in order (e.g., "chme" matches "Chrome")
- **Multi-term search**: Use spaces to search multiple terms (e.g., "safari readme" matches "README.md - Safari")
- **Prefix boost**: Terms matching the start of words rank higher
- **Exact match**: Exact matches appear first

## Development

### Project Structure

```
FFWF/
├── Sources/FFWF/
│   ├── FFWFApp.swift          # Main app, menu bar, hotkey registration
│   ├── ContentView.swift      # Popover UI, search, keyboard navigation
│   ├── WindowManager.swift    # Window enumeration, NSWorkspace observers
│   ├── WindowInfo.swift       # Window data model
│   ├── FuzzyMatcher.swift     # Fuzzy search algorithm with scoring
│   ├── HotkeyRecorder.swift   # Hotkey capture component
│   └── SettingsView.swift     # Settings UI with persistence
├── Makefile                   # Build automation
├── Package.swift              # Swift package manifest
└── README.md
```

### Building

```bash
# Build debug version
make build

# Build release version
make build-release

# Build app bundle
make app

# Build and code sign
make app-signed

# Run in debug mode
make run
```

### Architecture

**FuzzyMatcher**
- Sublime Text-inspired fuzzy matching algorithm
- Scores matches based on: consecutive characters, word boundaries, camelCase, position
- Concurrent processing for large window lists (50+ windows)
- Returns `nil` for non-matches to enable efficient filtering

**WindowManager**
- Uses AX API (`AXUIElement`) to enumerate windows per application
- NSWorkspace observers for app launch/quit/activate events
- 0.5s background refresh while popover is visible
- Parallel processing with `DispatchQueue.concurrentPerform`
- Caches app icons for performance

**ContentView**
- Real-time fuzzy filtering on every keystroke
- `ScrollViewReader` for smooth auto-scrolling to selection
- `@FocusState` ensures search field stays focused
- Progressive loading: shows first 10 results, "Show more" button for remainder
- VoiceOver announcements for accessibility

**HotkeyRecorder**
- Interactive keyboard shortcut capture
- Requires at least one modifier key
- Supports all modifiers: ⌃ (Control), ⌥ (Option), ⇧ (Shift), ⌘ (Command)
- Pretty display format with symbols

**SettingsView**
- UserDefaults persistence for hotkey preference
- NotificationCenter for live hotkey updates
- Dynamic re-registration without app restart

### Performance Optimizations

1. **Pre-lowercased Strings** - Window titles/names lowercased once during enumeration
2. **Concurrent Enumeration** - Processes applications in parallel
3. **Early Returns** - Fuzzy matcher bails on non-matches immediately
4. **Icon Caching** - App icons fetched once per app, not per window
5. **Event-Driven Updates** - NSWorkspace observers instead of constant polling
6. **Efficient Diffing** - SwiftUI List uses stable IDs for minimal re-renders

## Makefile Targets

```bash
make help          # Show available targets
make build         # Build debug version
make build-release # Build release version
make run           # Run in debug mode
make app           # Build macOS app bundle
make app-signed    # Build and code sign app bundle
make install       # Install to /Applications
make uninstall     # Remove from /Applications
make clean         # Clean build artifacts
make xcode         # Generate Xcode project
```

## Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## Future Enhancements

- [ ] Browser tab enumeration (requires browser extensions)
- [ ] MRU (Most Recently Used) sorting option
- [ ] Window preview thumbnails on hover
- [ ] Custom app icon
- [ ] Blacklist/whitelist for specific apps
- [ ] Multiple hotkey profiles
- [ ] Export/import settings

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Credits

An Intelligrit Labs Product
https://intelligrit.com/labs/

Built with Swift and SwiftUI.
Fuzzy matching algorithm inspired by Sublime Text's Goto Anything feature.

© 2025 Intelligrit, LLC
