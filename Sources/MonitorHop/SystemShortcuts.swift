import Carbon
import MonitorHopCore

/// macOS keyboard shortcuts (System Settings › Keyboard › Keyboard Shortcuts).
///
/// `RegisterEventHotKey` does not fail when another app or the system uses the same
/// combination (every registrant is notified), so conflicts are detected here instead,
/// against the system's enabled "symbolic hot keys". Other apps' private hotkeys cannot be
/// detected by any public API.
enum SystemShortcuts {
    private static let modifierMask: Int = 0x1B00 // cmd | shift | option | control (Carbon)

    /// Enabled system shortcuts as (keyCode, Carbon modifiers).
    static func enabled() -> [(keyCode: UInt32, modifiers: UInt32)] {
        var unmanaged: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&unmanaged) == noErr, let array = unmanaged?.takeRetainedValue() as? [[String: Any]] else {
            return []
        }
        return array.compactMap { entry in
            guard (entry[kHISymbolicHotKeyEnabled as String] as? Bool) == true,
                  let code = entry[kHISymbolicHotKeyCode as String] as? Int,
                  let mods = entry[kHISymbolicHotKeyModifiers as String] as? Int,
                  code >= 0, code < 0xFFFF else { return nil }
            return (UInt32(code), UInt32(mods & modifierMask))
        }
    }

    static func isTaken(_ shortcut: Shortcut, in list: [(keyCode: UInt32, modifiers: UInt32)]? = nil) -> Bool {
        let flags = shortcut.modifiers.carbonFlags
        return (list ?? enabled()).contains { $0.keyCode == shortcut.keyCode && $0.modifiers == flags }
    }
}
