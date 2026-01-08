import Cocoa
import ApplicationServices

/// Helper class for managing accessibility permissions
class AccessibilityHelper {
    
    /// Check if the app has accessibility permissions
    /// - Returns: true if accessibility is enabled, false otherwise
    static func checkAccessibilityPermissions() -> Bool {
        // Check if we're trusted for accessibility
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
    
    /// Request accessibility permissions by prompting the user
    /// - Returns: true if already trusted, false if user needs to grant permission
    static func requestAccessibilityPermissions() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
    
    /// Open System Settings to the Accessibility pane
    static func openAccessibilitySettings() {
        // macOS 13+ uses the new System Settings URL scheme
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

