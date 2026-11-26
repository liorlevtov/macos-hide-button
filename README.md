# MinimizeToHide

A macOS menu bar utility that intercepts the minimize button and hides the application instead.

## What it does

When you click the yellow minimize button, the window hides instead of minimizing to the Dock, and ⌘Tab brings it back, like minimize and Alt+Tab on Windows.

- **App's last open window** → the whole app hides (like pressing ⌘H).
- **App has other windows open** (for example several Chrome windows) → only the window you clicked hides; the others stay on screen.

A hidden window comes back when you switch to its app with ⌘Tab, the Dock or Spotlight, or pick it from the app's Window menu. Clicking one of the app's other windows doesn't bring it back. Disabling or quitting MinimizeToHide puts every hidden window back and restores normal minimize behavior.

## Features

- **System-wide** - Works across all applications
- **Seamless** - No minimize animation, instant hide
- **Menu bar app** - Runs silently with no Dock icon
- **Toggle on/off** - Enable or disable from the menu bar
- **Launch at login** - Optional automatic startup
- **Clean exit** - Quitting restores normal behavior

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode (for building)
- Accessibility permission

## Building

```bash
# Build and open output directory
make

# Or just build
make build

# Build and install to /Applications
make install

# Build and run
make run

# Clean build artifacts
make clean
```

The compiled app will be at: `build/Build/Products/Release/MinimizeToHide.app`

## Installation

1. Build the app: `make build`
2. Copy to Applications: `make install`
3. Launch MinimizeToHide
4. Grant Accessibility permission when prompted:
   - System Settings → Privacy & Security → Accessibility
   - Enable MinimizeToHide

## Usage

The app appears as a circle icon in the menu bar:

| Icon       | Status                                  |
| ---------- | --------------------------------------- |
| ● (filled) | Active - minimize clicks will hide apps |
| ○ (empty)  | Disabled - normal minimize behavior     |

**Menu options:**

- **Enabled/Disabled** - Toggle the feature
- **Launch at Login** - Start automatically
- **Grant Accessibility Access** - Opens System Settings
- **Quit** - Exit and restore normal minimize

## How it works

Uses macOS Accessibility APIs with a `CGEventTap` to:

1. Intercept all left mouse clicks before they reach windows
2. Check if the click is on a minimize button (`AXMinimizeButton`)
3. If it's the app's last visible window, consume the click and hide the application
4. Otherwise, consume the click and hide just that window by moving it off-screen (macOS can only hide whole apps); it's moved back when you switch to the app or focus the window

## License

MIT
