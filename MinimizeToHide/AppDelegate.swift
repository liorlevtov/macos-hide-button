import Cocoa
import ServiceManagement

/// Main application delegate that manages the menu bar app lifecycle
class AppDelegate: NSObject, NSApplicationDelegate {
    
    // MARK: - Properties
    
    /// Status bar item for menu bar presence
    private var statusItem: NSStatusItem!
    
    /// Window observer for intercepting minimize events
    private var windowObserver: WindowObserver?
    
    /// Whether the minimize interception is currently enabled
    private var isEnabled: Bool = true {
        didSet {
            updateStatusItemIcon()
            if isEnabled {
                windowObserver?.startObserving()
            } else {
                windowObserver?.stopObserving()
            }
        }
    }
    
    /// Menu item for the enable/disable toggle
    private var toggleMenuItem: NSMenuItem!
    
    /// Menu item for launch at login toggle
    private var launchAtLoginMenuItem: NSMenuItem!
    
    // MARK: - Application Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        checkAccessibilityPermissions()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Clean up observers - this automatically reverts minimize behavior
        windowObserver?.stopObserving()
        windowObserver = nil
    }
    
    // MARK: - Status Bar Setup
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        updateStatusItemIcon()
        
        // Create the menu
        let menu = NSMenu()
        
        // Toggle enabled/disabled
        toggleMenuItem = NSMenuItem(
            title: "Enabled",
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        toggleMenuItem.target = self
        toggleMenuItem.state = .on
        menu.addItem(toggleMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Launch at login toggle
        launchAtLoginMenuItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLoginMenuItem.target = self
        launchAtLoginMenuItem.state = LoginItemManager.shared.isEnabled ? .on : .off
        menu.addItem(launchAtLoginMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Request accessibility permissions
        let accessibilityItem = NSMenuItem(
            title: "Grant Accessibility Access...",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(
            title: "Quit MinimizeToHide",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    private func updateStatusItemIcon() {
        if let button = statusItem.button {
            // Use SF Symbols for the menu bar icon
            let symbolName = isEnabled ? "minus.circle.fill" : "minus.circle"
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            
            if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "MinimizeToHide") {
                let configuredImage = image.withSymbolConfiguration(config)
                configuredImage?.isTemplate = true
                button.image = configuredImage
            }
            
            button.toolTip = isEnabled ? "MinimizeToHide: Active" : "MinimizeToHide: Disabled"
        }
    }
    
    // MARK: - Accessibility
    
    private func checkAccessibilityPermissions() {
        if AccessibilityHelper.checkAccessibilityPermissions() {
            initializeWindowObserver()
        } else {
            // Show alert prompting user to grant permissions
            showAccessibilityAlert()
            
            // Start polling for permission grant
            startAccessibilityPolling()
        }
    }
    
    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "MinimizeToHide needs Accessibility permission to intercept minimize actions. Please grant access in System Settings > Privacy & Security > Accessibility."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            AccessibilityHelper.openAccessibilitySettings()
        }
    }
    
    private var accessibilityTimer: Timer?
    
    private func startAccessibilityPolling() {
        // Poll every 2 seconds to check if permission was granted
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            if AccessibilityHelper.checkAccessibilityPermissions() {
                timer.invalidate()
                self?.accessibilityTimer = nil
                self?.initializeWindowObserver()
            }
        }
    }
    
    private func initializeWindowObserver() {
        windowObserver = WindowObserver()
        if isEnabled {
            windowObserver?.startObserving()
        }
    }
    
    // MARK: - Actions
    
    @objc private func toggleEnabled() {
        isEnabled.toggle()
        toggleMenuItem.title = isEnabled ? "Enabled" : "Disabled"
        toggleMenuItem.state = isEnabled ? .on : .off
    }
    
    @objc private func toggleLaunchAtLogin() {
        let newState = !LoginItemManager.shared.isEnabled
        LoginItemManager.shared.isEnabled = newState
        launchAtLoginMenuItem.state = newState ? .on : .off
    }
    
    @objc private func openAccessibilitySettings() {
        AccessibilityHelper.openAccessibilitySettings()
    }
    
    @objc private func quitApp() {
        // Clean up is handled in applicationWillTerminate
        NSApplication.shared.terminate(nil)
    }
}

