import AppKit
import MonitorHopCore

/// A normal, on-screen window as reported by the window server.
struct WindowInfo: Equatable {
    let windowID: CGWindowID
    let pid: pid_t
    let ownerName: String
    /// Quartz / AX coordinates (top-left origin).
    let bounds: CGRect
}

enum WindowFinder {
    /// System UI processes that own layer-0 windows but are never focus targets.
    private static let ignoredBundleIDs: Set<String> = [
        "com.apple.dock",
        "com.apple.WindowManager",
        "com.apple.notificationcenterui",
        "com.apple.controlcenter",
        "com.apple.Spotlight",
        "com.apple.screencaptureui",
        "com.apple.systemuiserver",
    ]

    /// Visible normal windows of other apps on the current Space, front to back.
    /// Needs no permission (window titles are not used).
    static func visibleWindows() -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return [] }
        let ownPID = getpid()
        var allowedByPID: [pid_t: Bool] = [:]
        var result: [WindowInfo] = []

        // Stage Manager draws the side-strip thumbnails as small windows owned by the apps themselves,
        // each paired with a WindowManager window of exactly the same bounds. They are not on stage
        // and must never be focus targets.
        let stripBounds: [CGRect] = list.compactMap { entry in
            guard (entry[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let pid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.WindowManager",
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary
            else { return nil }
            return CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
        }

        for entry in list {
            guard (entry[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let pid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  pid != ownPID,
                  let id = (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  bounds.width >= 20, bounds.height >= 20
            else { continue }
            if let alpha = (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue, alpha < 0.01 { continue }
            if stripBounds.contains(where: { Geometry.approximatelyEqual($0, bounds, tolerance: 1) }) { continue }

            let allowed: Bool
            if let cached = allowedByPID[pid] {
                allowed = cached
            } else {
                allowed = isFocusableApp(pid)
                allowedByPID[pid] = allowed
            }
            guard allowed else { continue }

            result.append(WindowInfo(
                windowID: id,
                pid: pid,
                ownerName: entry[kCGWindowOwnerName as String] as? String ?? "?",
                bounds: bounds
            ))
        }
        return result
    }

    private static func isFocusableApp(_ pid: pid_t) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
        if let bundleID = app.bundleIdentifier, ignoredBundleIDs.contains(bundleID) { return false }
        return app.activationPolicy != .prohibited
    }
}
