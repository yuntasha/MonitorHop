import AppKit
import ApplicationServices

/// Brings another app to the front from a background (menu bar) app.
///
/// `NSRunningApplication.activate` became "cooperative" in macOS 14 and may be ignored when
/// the caller is not the active app, which is always the case for a hotkey handler. The
/// Carbon Process Manager call still works (Hammerspoon relies on it) but is marked
/// unavailable in Swift, so it is resolved at runtime; if it ever disappears we fall back
/// to the Accessibility and AppKit paths.
enum AppActivator {
    private typealias GetProcessForPIDFunction = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
    private typealias SetFrontProcessWithOptionsFunction = @convention(c) (UnsafePointer<ProcessSerialNumber>, OptionBits) -> OSStatus

    private static let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
    private static let getProcessForPID: GetProcessForPIDFunction? = {
        dlsym(rtldDefault, "GetProcessForPID").map { unsafeBitCast($0, to: GetProcessForPIDFunction.self) }
    }()
    private static let setFrontProcessWithOptions: SetFrontProcessWithOptionsFunction? = {
        dlsym(rtldDefault, "SetFrontProcessWithOptions").map { unsafeBitCast($0, to: SetFrontProcessWithOptionsFunction.self) }
    }()
    /// kSetFrontProcessFrontWindowOnly: bring only the front window, like clicking it.
    private static let frontWindowOnly: OptionBits = 1

    static var hasProcessManager: Bool { getProcessForPID != nil && setFrontProcessWithOptions != nil }

    /// Makes `pid` the active app and brings (only) its main window forward.
    @discardableResult
    static func bringToFront(pid: pid_t) -> Bool {
        guard let getProcessForPID, let setFrontProcessWithOptions else { return false }
        var psn = ProcessSerialNumber()
        guard getProcessForPID(pid, &psn) == noErr else { return false }
        return setFrontProcessWithOptions(&psn, frontWindowOnly) == noErr
    }

    /// Public-API fallback: ask the app to become frontmost via Accessibility and AppKit.
    static func activateFallback(pid: pid_t) {
        if AccessibilityPermission.isTrusted {
            AX.set(AX.application(pid), kAXFrontmostAttribute, kCFBooleanTrue)
        }
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        if #available(macOS 14, *) {
            app.activate()
        } else {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }
}

enum Cursor {
    /// Moves the mouse cursor to a point in global Quartz coordinates.
    static func warp(to point: CGPoint) {
        CGWarpMouseCursorPosition(point)
        // Without this the cursor "sticks" for ~250 ms after a warp.
        CGAssociateMouseAndMouseCursorPosition(1)
    }
}
