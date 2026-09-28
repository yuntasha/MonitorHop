// Small probe used by scripts/integration-test.py.
//   hoptool state                → {"frontmost": "...", "cursor": [x, y]}  (cursor in AX coordinates)
//   hoptool activate <bundle-id> → re-activates an app (used to restore focus after the test)
import AppKit

_ = NSApplication.shared
let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "" {
case "state":
    let p = NSEvent.mouseLocation
    let h = NSScreen.screens.first?.frame.height ?? 0
    let payload: [String: Any] = [
        "frontmost": NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "",
        "frontmostPID": Int(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0),
        "cursor": [Double(p.x), Double(h - p.y)],
    ]
    let data = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    print(String(data: data, encoding: .utf8)!)
case "front" where args.count > 5:
    // Front-most normal window whose center lies in the AX rect x y w h (same rules as MonitorHop).
    let r = CGRect(x: Double(args[2])!, y: Double(args[3])!, width: Double(args[4])!, height: Double(args[5])!)
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as! [[String: Any]]
    func bounds(_ e: [String: Any]) -> CGRect { CGRect(dictionaryRepresentation: e[kCGWindowBounds as String] as! CFDictionary)! }
    func bundle(_ e: [String: Any]) -> String? {
        NSRunningApplication(processIdentifier: (e[kCGWindowOwnerPID as String] as! NSNumber).int32Value)?.bundleIdentifier
    }
    let layer0 = list.filter { ($0[kCGWindowLayer as String] as? Int) == 0 }
    let strip = layer0.filter { bundle($0) == "com.apple.WindowManager" }.map(bounds)
    let ignored: Set<String> = ["com.apple.dock", "com.apple.WindowManager", "com.apple.notificationcenterui",
                                "com.apple.controlcenter", "com.apple.Spotlight", "com.apple.screencaptureui",
                                "com.apple.systemuiserver", "com.alencup.MonitorHop"]
    var found: [String: Any] = [:]
    for e in layer0 {
        let b = bounds(e)
        guard b.width >= 20, b.height >= 20, r.contains(CGPoint(x: b.midX, y: b.midY)),
              !strip.contains(where: { abs($0.minX - b.minX) <= 1 && abs($0.minY - b.minY) <= 1 && abs($0.width - b.width) <= 1 && abs($0.height - b.height) <= 1 }),
              !ignored.contains(bundle(e) ?? "") else { continue }
        found = ["pid": (e[kCGWindowOwnerPID as String] as! NSNumber).intValue, "id": (e[kCGWindowNumber as String] as! NSNumber).intValue,
                 "owner": e[kCGWindowOwnerName as String] as? String ?? "", "bundle": bundle(e) ?? ""]
        break
    }
    print(String(data: try! JSONSerialization.data(withJSONObject: found, options: [.sortedKeys]), encoding: .utf8)!)
case "activate" where args.count > 2:
    if let app = NSRunningApplication.runningApplications(withBundleIdentifier: args[2]).first {
        app.activate(options: [.activateIgnoringOtherApps])
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
    }
default:
    FileHandle.standardError.write(Data("usage: hoptool state | activate <bundle-id>\n".utf8))
    exit(2)
}
