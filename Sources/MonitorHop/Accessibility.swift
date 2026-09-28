import AppKit
import ApplicationServices

enum AccessibilityPermission {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt (first time only) and adds the app to the Accessibility list.
    @discardableResult
    static func request() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}

/// Thin, failure-tolerant wrappers around the AXUIElement C API.
enum AX {
    static let timeout: Float = 1.0

    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        value(element, attribute) as? Bool
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }

    static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let v = value(element, attribute), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(v as! AXValue, .cgPoint, &point) ? point : nil
    }

    static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let v = value(element, attribute), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(v as! AXValue, .cgSize, &size) ? size : nil
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let v = value(element, attribute), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        let child = v as! AXUIElement
        AXUIElementSetMessagingTimeout(child, timeout)
        return child
    }

    static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        guard let list = value(element, attribute) as? [AXUIElement] else { return [] }
        for child in list { AXUIElementSetMessagingTimeout(child, timeout) }
        return list
    }

    @discardableResult
    static func set(_ element: AXUIElement, _ attribute: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(element, attribute as CFString, value) == .success
    }

    @discardableResult
    static func setPoint(_ element: AXUIElement, _ attribute: String, _ point: CGPoint) -> Bool {
        var p = point
        guard let v = AXValueCreate(.cgPoint, &p) else { return false }
        return set(element, attribute, v)
    }

    @discardableResult
    static func setSize(_ element: AXUIElement, _ attribute: String, _ size: CGSize) -> Bool {
        var s = size
        guard let v = AXValueCreate(.cgSize, &s) else { return false }
        return set(element, attribute, v)
    }

    static func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success else { return false }
        return settable.boolValue
    }

    @discardableResult
    static func perform(_ element: AXUIElement, _ action: String) -> Bool {
        AXUIElementPerformAction(element, action as CFString) == .success
    }

    static func application(_ pid: pid_t) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)
        return app
    }
}

// `_AXUIElementGetWindow` maps an AX window to its CGWindowID. It is private but has been
// stable for over a decade (used by yabai, Rectangle, AltTab, Hammerspoon). Resolved with
// dlsym so a future removal only disables exact matching instead of breaking the app.
private typealias AXGetWindowFunction = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
private let axGetWindow: AXGetWindowFunction? = {
    guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else { return nil }
    return unsafeBitCast(symbol, to: AXGetWindowFunction.self)
}()

/// An on-screen window reachable through the Accessibility API.
struct AXWindow {
    let element: AXUIElement
    let pid: pid_t

    static var canResolveWindowIDs: Bool { axGetWindow != nil }

    static func windows(of pid: pid_t) -> [AXWindow] {
        AX.elements(AX.application(pid), kAXWindowsAttribute).map { AXWindow(element: $0, pid: pid) }
    }

    static func focusedWindow(of pid: pid_t) -> AXWindow? {
        AX.element(AX.application(pid), kAXFocusedWindowAttribute).map { AXWindow(element: $0, pid: pid) }
    }

    /// The focused window of the focused application, as reported by the system-wide element.
    static func systemFocusedWindow() -> AXWindow? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, AX.timeout)
        guard let app = AX.element(systemWide, kAXFocusedApplicationAttribute) else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(app, &pid) == .success, pid != getpid() else { return nil }
        return AX.element(app, kAXFocusedWindowAttribute).map { AXWindow(element: $0, pid: pid) }
    }

    var frame: CGRect? {
        guard let origin = AX.point(element, kAXPositionAttribute),
              let size = AX.size(element, kAXSizeAttribute) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    var windowID: CGWindowID? {
        guard let axGetWindow else { return nil }
        var id: CGWindowID = 0
        return axGetWindow(element, &id) == .success && id != 0 ? id : nil
    }

    var title: String? { AX.string(element, kAXTitleAttribute) }
    var isMinimized: Bool { AX.bool(element, kAXMinimizedAttribute) ?? false }
    var isFullScreen: Bool { AX.bool(element, "AXFullScreen") ?? false }
    var canMove: Bool { AX.isSettable(element, kAXPositionAttribute) }
    var canResize: Bool { AX.isSettable(element, kAXSizeAttribute) }

    func raise() { AX.perform(element, kAXRaiseAction) }
    func becomeMain() { AX.set(element, kAXMainAttribute, kCFBooleanTrue) }

    /// Moves/resizes the window and returns the frame it actually ended up with.
    /// Size → position → size: the first resize avoids the OS clamping the window while it
    /// crosses displays, the second fixes apps that adjust their size after moving.
    @discardableResult
    func setFrame(_ frame: CGRect) -> CGRect? {
        // Apps with "enhanced user interface" on (Chromium/Electron when VoiceOver-like
        // clients are active) animate frame changes and drop intermediate values.
        let app = AX.application(pid)
        let enhanced = AX.bool(app, "AXEnhancedUserInterface") ?? false
        if enhanced { AX.set(app, "AXEnhancedUserInterface", kCFBooleanFalse) }
        defer { if enhanced { AX.set(app, "AXEnhancedUserInterface", kCFBooleanTrue) } }

        let resizable = canResize
        if resizable { AX.setSize(element, kAXSizeAttribute, frame.size) }
        AX.setPoint(element, kAXPositionAttribute, frame.origin)
        if resizable { AX.setSize(element, kAXSizeAttribute, frame.size) }
        return self.frame
    }

    func setPosition(_ origin: CGPoint) {
        AX.setPoint(element, kAXPositionAttribute, origin)
    }
}
