import AppKit
import SwiftUI
import MonitorHopCore

/// Developer / automation helpers used by the integration test and for visual QA.
@MainActor
enum DevTools {
    /// Developer tools must be enabled explicitly when the app is launched:
    /// `open --env MONITORHOP_DEVTOOLS=1 MonitorHop.app` (the integration test does this).
    static var isEnabled: Bool { ProcessInfo.processInfo.environment["MONITORHOP_DEVTOOLS"] == "1" }

    /// Posts the key events of `action`'s bound shortcut, so the real hotkey path
    /// (window server → Carbon hotkey → action) runs. Only valid shortcuts MonitorHop has
    /// registered can be pressed, and only with developer tools enabled.
    static func pressShortcut(of action: ActionID) -> ActionOutcome {
        guard isEnabled else {
            return .failed("개발용 기능이 꺼져 있습니다. MONITORHOP_DEVTOOLS=1 환경으로 앱을 실행하세요.")
        }
        guard let shortcut = SettingsStore.shared.config.shortcut(for: action), shortcut.validation == .valid else {
            return .failed("\(action.title)에 지정된 단축키가 없습니다.")
        }
        let hotkeys = HotkeyCenter.shared
        guard !hotkeys.isSuspended, hotkeys.failures[action] == nil, hotkeys.registeredCount > 0 else {
            return .failed("단축키가 등록되어 있지 않아 누를 수 없습니다.")
        }
        guard AccessibilityPermission.isTrusted else { return .failed("키 입력을 보내려면 접근성 권한이 필요합니다.") }
        var flags: CGEventFlags = []
        if shortcut.modifiers.contains(.control) { flags.insert(.maskControl) }
        if shortcut.modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if shortcut.modifiers.contains(.shift) { flags.insert(.maskShift) }
        if shortcut.modifiers.contains(.command) { flags.insert(.maskCommand) }
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(shortcut.keyCode), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(shortcut.keyCode), keyDown: false) else {
            return .failed("키 이벤트를 만들지 못했습니다.")
        }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return .done("\(shortcut.displayString(keyName: KeyNames.name(for:))) 입력을 보냈습니다.")
    }

    /// Sets the frame (AX coordinates) of the on-screen window with `windowID`. Used by the
    /// integration test to put windows back exactly where they were. Developer tools only.
    static func setFrame(windowID: CGWindowID, to frame: CGRect) -> ActionOutcome {
        guard isEnabled else { return .failed("개발용 기능이 꺼져 있습니다.") }
        guard let info = WindowFinder.visibleWindows().first(where: { $0.windowID == windowID }),
              let window = AXWindow.windows(of: info.pid).first(where: { $0.windowID == windowID }) else {
            return .failed("창 \(windowID)을(를) 찾지 못했습니다.")
        }
        let result = window.setFrame(frame)
        return .done("창 \(windowID): \(result.map { "\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))×\(Int($0.height))" } ?? "?")")
    }

    /// Renders each settings tab to `<directory>/settings-<tab>.png` exactly as the window server
    /// draws the real settings window (tab bar, background and all). Capturing our own window
    /// needs no Screen Recording permission.
    static func renderSettings(to directory: URL) -> [URL] {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var written: [URL] = []
        let tabs: [(SettingsTab, String)] = [(.shortcuts, "shortcuts"), (.monitors, "monitors"), (.general, "general")]
        for (tab, name) in tabs {
            let navigation = SettingsNavigation()
            navigation.tab = tab
            let hosting = NSHostingController(rootView: SettingsView(navigation: navigation, system: SystemStatusModel()))
            let window = NSWindow(contentViewController: hosting)
            window.title = "MonitorHop 설정"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            // Far off-screen: the window server still renders it, the user sees nothing.
            window.setFrameOrigin(NSPoint(x: -30000, y: -30000))
            window.orderFrontRegardless()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.2)) // let SwiftUI lay out and draw
            let url = directory.appendingPathComponent("settings-\(name).png")
            if let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber),
                                                   [.boundsIgnoreFraming, .bestResolution]),
               let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
               (try? data.write(to: url)) != nil {
                written.append(url)
            }
            window.orderOut(nil)
            window.close()
        }
        // HUD samples: switch number, error message, identify overlay.
        if let monitor = ScreenRegistry.shared.monitors.first {
            let samples: [(String, () -> Void)] = [
                ("hud-number", { HUD.shared.showNumber(2, detail: "Safari", on: monitor) }),
                ("hud-message", { HUD.shared.showMessage("3번 모니터가 없습니다. (연결된 모니터 2대)", on: monitor) }),
                ("hud-identify", { HUD.shared.identify([monitor], duration: 3) }),
            ]
            for (name, show) in samples {
                let before = Set(NSApp.windows.map(\.windowNumber))
                show()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
                let panel = NSApp.windows.first { $0 is NSPanel && $0.isVisible && !before.contains($0.windowNumber) }
                    ?? NSApp.windows.last { $0 is NSPanel && $0.isVisible }
                guard let panel,
                      let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(panel.windowNumber),
                                                          [.boundsIgnoreFraming, .bestResolution]),
                      let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { continue }
                let url = directory.appendingPathComponent("\(name).png")
                if (try? data.write(to: url)) != nil { written.append(url) }
                panel.orderOut(nil)
            }
        }
        return written
    }
}
