import Cocoa
import ApplicationServices

/// Global reference for the C callback to access
private var globalObserver: WindowObserver?

/// C-compatible callback for CGEventTap
private let eventCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
    
    // Handle tap disabled events - re-enable if system disabled it
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let observer = globalObserver, let tap = observer.getEventTap() {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passRetained(event)
    }
    
    // Only process left mouse down events
    guard type == .leftMouseDown else {
        return Unmanaged.passRetained(event)
    }
    
    let point = event.location
    
    // Check if click is on minimize button
    if let observer = globalObserver,
       let pid = observer.checkForMinimizeButton(at: point) {
        observer.hideApp(pid: pid)
        return nil  // Consume the event - prevents minimize
    }
    
    return Unmanaged.passRetained(event)
}

/// Observes and intercepts minimize button clicks across all applications,
/// hiding the application instead of minimizing the window
class WindowObserver {
    
    // MARK: - Properties
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isObserving = false
    
    // MARK: - Initialization
    
    init() {
        globalObserver = self
    }
    
    deinit {
        stopObserving()
        if globalObserver === self {
            globalObserver = nil
        }
    }
    
    // MARK: - Internal accessors for callback
    
    func getEventTap() -> CFMachPort? {
        return eventTap
    }
    
    // MARK: - Public Methods
    
    func startObserving() {
        guard !isObserving else { return }
        
        // Event mask for left mouse down
        let eventMask: CGEventMask = (1 << CGEventType.leftMouseDown.rawValue)
        
        // Create event tap
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: eventCallback,
            userInfo: nil
        ) else {
            return
        }
        
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            isObserving = true
        }
    }
    
    func stopObserving() {
        guard isObserving else { return }
        
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        
        eventTap = nil
        isObserving = false
    }
    
    // MARK: - Minimize Button Detection
    
    func checkForMinimizeButton(at point: CGPoint) -> pid_t? {
        let systemWide = AXUIElementCreateSystemWide()
        
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(
            systemWide,
            Float(point.x),
            Float(point.y),
            &element
        )
        
        guard result == .success, let clickedElement = element else {
            return nil
        }
        
        // Check subrole for minimize button
        var subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(clickedElement, kAXSubroleAttribute as CFString, &subrole)
        
        if let subroleStr = subrole as? String, subroleStr == "AXMinimizeButton" {
            var pid: pid_t = 0
            AXUIElementGetPid(clickedElement, &pid)
            return pid
        }
        
        // Check parent (button might have child elements)
        var parent: CFTypeRef?
        if AXUIElementCopyAttributeValue(clickedElement, kAXParentAttribute as CFString, &parent) == .success,
           let parentElement = parent {
            
            var parentSubrole: CFTypeRef?
            AXUIElementCopyAttributeValue(parentElement as! AXUIElement, kAXSubroleAttribute as CFString, &parentSubrole)
            
            if let parentSubroleStr = parentSubrole as? String, parentSubroleStr == "AXMinimizeButton" {
                var pid: pid_t = 0
                AXUIElementGetPid(parentElement as! AXUIElement, &pid)
                return pid
            }
        }
        
        return nil
    }
    
    func hideApp(pid: pid_t) {
        // Don't hide ourselves
        guard pid != ProcessInfo.processInfo.processIdentifier else { return }
        
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.hide()
        }
    }
}
