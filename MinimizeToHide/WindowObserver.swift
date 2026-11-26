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
        return Unmanaged.passUnretained(event)
    }
    
    // Only process left mouse down events
    guard type == .leftMouseDown else {
        return Unmanaged.passUnretained(event)
    }
    
    guard let observer = globalObserver else {
        return Unmanaged.passUnretained(event)
    }

    let point = event.location
    observer.windowHider.noteClick(at: point)

    // Clicked a minimize button: hide instead of minimizing
    if let action = observer.minimizeAction(forClickAt: point),
       observer.perform(action) {
        return nil  // Consume the event - prevents minimize
    }
    
    return Unmanaged.passUnretained(event)
}

/// What to do instead of minimizing.
enum MinimizeAction {
    /// Hide the whole app, like ⌘H. Used for the app's last visible window.
    case hideApp(pid: pid_t)
    /// Hide only this window, leaving the app's other windows on screen.
    /// `nextWindow` takes focus if the app is frontmost.
    case hideWindow(AXUIElement, pid: pid_t, nextWindow: AXUIElement)
}

/// Observes minimize button clicks across all applications and hides instead
/// of minimizing, so ⌘Tab brings the window back:
/// - the app's last visible window → the whole app is hidden (like ⌘H)
/// - the app has other windows open → only the clicked window is hidden
class WindowObserver {
    
    // MARK: - Properties

    let windowHider = WindowHider()
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isObserving = false
    private let systemWide = AXUIElementCreateSystemWide()
    
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

        // Don't leave windows stranded off-screen
        windowHider.restoreAll()
    }
    
    // MARK: - Minimize Button Detection

    /// Decides what a left click at `point` should do instead of minimizing.
    /// Returns nil to let the click through untouched.
    func minimizeAction(forClickAt point: CGPoint) -> MinimizeAction? {
        guard let button = minimizeButton(at: point) else { return nil }
        return minimizeAction(forMinimizeButton: button)
    }

    /// Same decision as `minimizeAction(forClickAt:)`, for a known minimize button.
    func minimizeAction(forMinimizeButton button: AXUIElement) -> MinimizeAction? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(button, &pid) == .success,
              pid != ProcessInfo.processInfo.processIdentifier else {
            return nil
        }

        let clickedWindow = window(containing: button)

        // Can't read the window list: fall back to a normal minimize rather
        // than risk hiding windows the user didn't pick.
        guard let others = otherVisibleWindows(pid: pid, besides: clickedWindow) else {
            return nil
        }

        guard let nextWindow = others.first else {
            return .hideApp(pid: pid)
        }

        guard let clickedWindow = clickedWindow else { return nil }
        return .hideWindow(clickedWindow, pid: pid, nextWindow: nextWindow)
    }

    /// Carries out `action`. Returns false if it couldn't, so the click should
    /// go through as a normal minimize.
    func perform(_ action: MinimizeAction) -> Bool {
        switch action {
        case .hideApp(let pid):
            hideApp(pid: pid)
            return true

        case .hideWindow(let window, let pid, let nextWindow):
            guard windowHider.hide(window, pid: pid) else { return false }

            // The hidden window still has focus; hand it to the next one so
            // typing doesn't go into a window you can't see.
            if NSRunningApplication(processIdentifier: pid)?.isActive == true {
                AXUIElementPerformAction(nextWindow, kAXRaiseAction as CFString)
                AXUIElementSetAttributeValue(nextWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
            }
            return true
        }
    }

    /// Returns the minimize button under `point`, if there is one.
    private func minimizeButton(at point: CGPoint) -> AXUIElement? {
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

        if isMinimizeButton(clickedElement) {
            return clickedElement
        }

        // Check parent (button might have child elements)
        if let parent = elementAttribute(clickedElement, kAXParentAttribute), isMinimizeButton(parent) {
            return parent
        }

        return nil
    }

    private func isMinimizeButton(_ element: AXUIElement) -> Bool {
        return stringAttribute(element, kAXSubroleAttribute) == (kAXMinimizeButtonSubrole as String)
    }

    /// The window a title bar button belongs to.
    private func window(containing button: AXUIElement) -> AXUIElement? {
        return elementAttribute(button, kAXWindowAttribute)
            ?? elementAttribute(button, kAXParentAttribute)
    }

    /// The app's normal windows that are on screen, other than `clickedWindow`,
    /// front to back. Skips minimized windows and windows we've hidden.
    /// Nil when the window list can't be read.
    private func otherVisibleWindows(pid: pid_t, besides clickedWindow: AXUIElement?) -> [AXUIElement]? {
        let app = AXUIElementCreateApplication(pid)

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else {
            return nil
        }

        return windows.filter { window in
            // Skip panels, popovers and other auxiliary windows
            guard stringAttribute(window, kAXSubroleAttribute) == (kAXStandardWindowSubrole as String) else {
                return false
            }

            var minimized: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimized)
            if (minimized as? Bool) == true {
                return false
            }

            if windowHider.isHidden(window) {
                return false
            }

            if let clickedWindow = clickedWindow, CFEqual(window, clickedWindow) {
                return false
            }

            return true
        }
    }

    // MARK: - Accessibility attribute helpers

    private func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func elementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value = value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    // MARK: - Hiding

    func hideApp(pid: pid_t) {
        // Don't hide ourselves
        guard pid != ProcessInfo.processInfo.processIdentifier else { return }

        if let app = NSRunningApplication(processIdentifier: pid) {
            app.hide()
        }
    }
}
