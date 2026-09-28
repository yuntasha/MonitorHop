import AppKit
import SwiftUI
import MonitorHopCore

/// Developer / automation helpers used by the integration test and for visual QA.
@MainActor
enum DevTools {
    /// Posts the key events of `action`'s bound shortcut, so the real hotkey path
    /// (window server → Carbon hotkey → action) runs. Only shortcuts MonitorHop has registered
    /// can be pressed, so this cannot be used to type arbitrary keys into other apps.
    static func pressShortcut(of action: ActionID) -> ActionOutcome {
        guard let shortcut = SettingsStore.shared.config.shortcut(for: action) else {
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
        return written
    }
}
