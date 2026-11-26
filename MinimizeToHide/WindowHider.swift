import Cocoa
import ApplicationServices

/// C-compatible callback for the per-app accessibility observers.
/// Fires when an app with parked windows focuses a different window.
private let focusChangedCallback: AXObserverCallback = { _, element, _, refcon in
    guard let refcon = refcon else { return }
    let hider = Unmanaged<WindowHider>.fromOpaque(refcon).takeUnretainedValue()
    hider.windowGainedFocus(element)
}

/// Hides single windows, which macOS has no API for (hiding is per-app).
///
/// A hidden window is parked just off the edge of its screen, with one point
/// left on screen so macOS keeps it where it was put. It comes back when:
/// - its app is switched to with ⌘Tab, the Dock, Spotlight and so on
///   (but not by clicking one of the app's other windows),
/// - the window itself is focused, e.g. from the app's Window menu or ⌘`,
/// - MinimizeToHide is disabled or quits.
final class WindowHider {

    private struct ParkedWindow {
        let window: AXUIElement
        let pid: pid_t
        let originalPosition: CGPoint
    }

    /// Parked windows, oldest first.
    private var parked: [ParkedWindow] = []
    private var focusObservers: [pid_t: AXObserver] = [:]
    private var workspaceTokens: [NSObjectProtocol] = []
    private var lastClick: (uptime: TimeInterval, point: CGPoint)?

    /// How long after a click an app activation counts as caused by that click.
    private let clickActivationWindow: TimeInterval = 1.0

    init() {
        let center = NSWorkspace.shared.notificationCenter

        workspaceTokens.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.appActivated(pid: app.processIdentifier)
        })

        workspaceTokens.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.forget(pid: app.processIdentifier)
        })
    }

    deinit {
        restoreAll()
        workspaceTokens.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }

    // MARK: - Public

    func isHidden(_ window: AXUIElement) -> Bool {
        return parked.contains { CFEqual($0.window, window) }
    }

    /// Record every left click, so an app activation caused by clicking one of
    /// its windows can be told apart from ⌘Tab.
    func noteClick(at point: CGPoint) {
        lastClick = (ProcessInfo.processInfo.systemUptime, point)
    }

    /// Moves `window` off-screen. Returns false if it couldn't be moved.
    func hide(_ window: AXUIElement, pid: pid_t) -> Bool {
        guard !isHidden(window),
              let position = pointAttribute(window, kAXPositionAttribute),
              let size = sizeAttribute(window, kAXSizeAttribute) else {
            return false
        }

        let frame = CGRect(origin: position, size: size)
        guard setPosition(window, parkingPosition(for: frame)) else {
            return false
        }

        parked.append(ParkedWindow(window: window, pid: pid, originalPosition: position))
        observeFocus(pid: pid)
        return true
    }

    /// Puts every parked window back where it was.
    func restoreAll() {
        for pid in Set(parked.map { $0.pid }) {
            restore(pid: pid, raise: false)
        }
    }

    // MARK: - Restoring

    private func appActivated(pid: pid_t) {
        guard parked.contains(where: { $0.pid == pid }),
              !wasActivatedByClickOnOwnWindow(pid: pid) else {
            return
        }
        restore(pid: pid, raise: true)
    }

    /// Called from the accessibility observer when an app focuses a window.
    fileprivate func windowGainedFocus(_ window: AXUIElement) {
        guard let index = parked.firstIndex(where: { CFEqual($0.window, window) }) else { return }
        let entry = parked.remove(at: index)
        setPosition(entry.window, entry.originalPosition)
        stopObservingFocusIfDone(pid: entry.pid)
    }

    private func restore(pid: pid_t, raise: Bool) {
        let windows = parked.filter { $0.pid == pid }
        parked.removeAll { $0.pid == pid }
        stopObservingFocusIfDone(pid: pid)

        for entry in windows {
            setPosition(entry.window, entry.originalPosition)
        }

        // Bring the most recently hidden window to the front
        if raise, let last = windows.last {
            AXUIElementPerformAction(last.window, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(last.window, kAXMainAttribute as CFString, kCFBooleanTrue)
        }
    }

    private func forget(pid: pid_t) {
        parked.removeAll { $0.pid == pid }
        stopObservingFocusIfDone(pid: pid)
    }

    /// True when the app was brought forward by a click on one of its own
    /// visible windows, rather than by ⌘Tab, the Dock, etc.
    private func wasActivatedByClickOnOwnWindow(pid: pid_t) -> Bool {
        guard let click = lastClick,
              ProcessInfo.processInfo.systemUptime - click.uptime < clickActivationWindow,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        // Window list is ordered front to back: the first visible window under
        // the click is the one that received it.
        for info in windows {
            guard let boundsDict = info[kCGWindowBounds as String],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as! CFDictionary),
                  bounds.contains(click.point),
                  ((info[kCGWindowAlpha as String] as? CGFloat) ?? 1) > 0 else {
                continue
            }
            return (info[kCGWindowOwnerPID as String] as? pid_t) == pid
        }
        return false
    }

    // MARK: - Focus observers

    private func observeFocus(pid: pid_t) {
        guard focusObservers[pid] == nil else { return }

        var observer: AXObserver?
        guard AXObserverCreate(pid, focusChangedCallback, &observer) == .success, let observer = observer else {
            return
        }

        let app = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(observer, app, kAXFocusedWindowChangedNotification as CFString, refcon)
        AXObserverAddNotification(observer, app, kAXMainWindowChangedNotification as CFString, refcon)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        focusObservers[pid] = observer
    }

    private func stopObservingFocusIfDone(pid: pid_t) {
        guard !parked.contains(where: { $0.pid == pid }),
              let observer = focusObservers.removeValue(forKey: pid) else {
            return
        }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }

    // MARK: - Geometry

    /// Where to put a window so all but one point of it is off-screen, without
    /// spilling onto a neighbouring display. Accessibility coordinates: origin
    /// at the top-left of the primary screen, y growing downward.
    private func parkingPosition(for frame: CGRect) -> CGPoint {
        let screens = screenFramesInAXCoordinates()
        guard !screens.isEmpty else {
            return CGPoint(x: frame.minX, y: 100_000)
        }

        let home = screens.max { overlapArea($0, frame) < overlapArea($1, frame) } ?? screens[0]
        let others = screens.filter { $0 != home }

        let candidates = [
            CGPoint(x: home.maxX - 1, y: home.maxY - 1),                // bottom-right
            CGPoint(x: home.minX - frame.width + 1, y: home.maxY - 1),  // bottom-left
        ]

        for origin in candidates {
            let parkedFrame = CGRect(origin: origin, size: frame.size)
            if !others.contains(where: { $0.intersects(parkedFrame) }) {
                return origin
            }
        }
        return candidates[0]
    }

    private func screenFramesInAXCoordinates() -> [CGRect] {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return [] }
        return NSScreen.screens.map { screen in
            let f = screen.frame
            return CGRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height)
        }
    }

    private func overlapArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let i = a.intersection(b)
        return i.isNull ? 0 : i.width * i.height
    }

    // MARK: - Accessibility helpers

    @discardableResult
    private func setPosition(_ window: AXUIElement, _ point: CGPoint) -> Bool {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return false }
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value) == .success
    }

    private func pointAttribute(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        var value: CFTypeRef?
        var point = CGPoint.zero
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value = value, CFGetTypeID(value) == AXValueGetTypeID(),
              AXValueGetValue(value as! AXValue, .cgPoint, &point) else {
            return nil
        }
        return point
    }

    private func sizeAttribute(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        var value: CFTypeRef?
        var size = CGSize.zero
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value = value, CFGetTypeID(value) == AXValueGetTypeID(),
              AXValueGetValue(value as! AXValue, .cgSize, &size) else {
            return nil
        }
        return size
    }
}
