import Foundation
import ServiceManagement

/// Manages launch at login functionality using SMAppService (macOS 13+)
class LoginItemManager {
    
    static let shared = LoginItemManager()
    
    private init() {}
    
    /// Whether the app is currently set to launch at login
    var isEnabled: Bool {
        get {
            if #available(macOS 13.0, *) {
                return SMAppService.mainApp.status == .enabled
            } else {
                // Fallback for older macOS versions (not supported in this app)
                return false
            }
        }
        set {
            if #available(macOS 13.0, *) {
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    print("Failed to \(newValue ? "enable" : "disable") launch at login: \(error)")
                }
            }
        }
    }
}

