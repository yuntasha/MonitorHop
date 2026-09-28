// Test fixture for scripts/integration-test.py.
// Opens titled windows at given AX (top-left origin) frames and continuously writes a JSON status
// file: whether the app is active, which window is key, and each window's AX frame.
// Usage: MonitorHopTestWindow <status.json> <title> <x> <y> <w> <h> [<title> <x> <y> <w> <h> ...]
import AppKit

final class Delegate: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []
    private let statusURL: URL
    private let specs: [String]

    init(statusURL: URL, specs: [String]) {
        self.statusURL = statusURL
        self.specs = specs
    }

    private var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    func applicationDidFinishLaunching(_ notification: Notification) {
        var i = 0
        while i + 4 < specs.count {
            let title = specs[i]
            let x = Double(specs[i + 1]) ?? 0, y = Double(specs[i + 2]) ?? 0
            let w = Double(specs[i + 3]) ?? 400, h = Double(specs[i + 4]) ?? 300
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                                  styleMask: [.titled, .closable, .resizable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.title = title
            window.isReleasedWhenClosed = false
            let label = NSTextField(labelWithString: "MonitorHop test window \(title)")
            label.font = .systemFont(ofSize: 22, weight: .semibold)
            label.alignment = .center
            window.contentView = label
            window.setFrame(NSRect(x: x, y: primaryHeight - y - h, width: w, height: h), display: true)
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
            i += 5
        }
        NSApp.activate(ignoringOtherApps: true)
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.writeStatus() }
        }
        writeStatus()
    }

    private func writeStatus() {
        var frames: [String: [Double]] = [:]
        var ids: [String: Int] = [:]
        for window in windows {
            let f = window.frame
            frames[window.title] = [Double(f.minX), Double(primaryHeight - f.maxY), Double(f.width), Double(f.height)]
            ids[window.title] = window.windowNumber
        }
        let payload: [String: Any] = [
            "active": NSApp.isActive,
            "key": NSApp.keyWindow?.title ?? "",
            "frames": frames,
            "ids": ids,
            "pid": Int(getpid()),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return }
        let tmp = statusURL.appendingPathExtension("tmp")
        try? data.write(to: tmp)
        _ = try? FileManager.default.replaceItemAt(statusURL, withItemAt: tmp)
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 6 else {
    FileHandle.standardError.write(Data("usage: MonitorHopTestWindow <status.json> <title> <x> <y> <w> <h> ...\n".utf8))
    exit(2)
}
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = Delegate(statusURL: URL(fileURLWithPath: arguments[0]), specs: Array(arguments.dropFirst()))
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
