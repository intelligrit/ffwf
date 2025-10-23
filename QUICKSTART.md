# FFWF Quick Start Guide

Get up and running with FFWF (Fast Fuzzy Window Finder) in under 2 minutes.

## Installation

### Step 1: Download and Build

```bash
# Clone the repository
git clone https://github.com/robertmeta/FFWF.git
cd FFWF

# Install to /Applications
make install
```

### Step 2: Grant Permissions

1. Launch FFWF from Spotlight (⌘Space, type "FFWF")
2. macOS will prompt for **Accessibility** permission
3. Click "Open System Settings"
4. Toggle on FFWF in Privacy & Security > Accessibility
5. Restart FFWF

**Note:** You may also need to grant Screen Recording permission depending on your macOS version.

### Step 3: Start Using It!

FFWF is now running in your menu bar (magnifying glass icon).

## Basic Usage

### Open the Window Finder

Press **Option+Shift+Space** (or click the menu bar icon)

### Search for Windows

Just start typing! Examples:

- `chme` → Finds Chrome windows
- `safari readme` → Finds README files in Safari
- `term` → Finds Terminal windows

### Navigate and Switch

- **↑/↓ Arrow keys** - Move selection up/down
- **Enter** - Switch to selected window
- **Escape** - Close without switching

## Customizing Your Hotkey

Don't like Option+Shift+Space? Change it:

1. **Right-click** the menu bar icon
2. Select **Settings...**
3. Click the hotkey field
4. Press your desired key combination (e.g., ⌘⇧F)
5. Close the settings window

Your new hotkey works immediately!

## Tips

- **Fuzzy matching** means you don't need to type exact names - just a few characters in order
- **Multiple words** let you narrow down results (e.g., "chrome github" finds GitHub tabs in Chrome)
- **App icons** help you quickly identify which window is which
- The search is **instant** - no lag, even with dozens of windows

## Quitting

Right-click the menu bar icon → Quit FFWF

## Uninstalling

```bash
cd FFWF
make uninstall
```

## Getting Help

- Full documentation: [README.md](README.md)
- Report bugs: [GitHub Issues](https://github.com/robertmeta/FFWF/issues)

## Keyboard Reference

| Key | Action |
|-----|--------|
| Option+Shift+Space | Open window finder (default) |
| Type to search | Filter windows |
| ↑ / ↓ | Navigate results |
| Enter | Switch to window |
| Escape | Close finder |
| Right-click icon | Open menu |
| ⌘, (in menu) | Open Settings |

---

**That's it!** You're now a window-switching ninja. Enjoy! 🚀
