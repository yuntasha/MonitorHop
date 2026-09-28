/// Modifier keys of a shortcut, independent of AppKit/Carbon.
public struct ModifierSet: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let command = ModifierSet(rawValue: 1 << 0)
    public static let option  = ModifierSet(rawValue: 1 << 1)
    public static let control = ModifierSet(rawValue: 1 << 2)
    public static let shift   = ModifierSet(rawValue: 1 << 3)

    // Carbon modifier masks (Events.h): cmdKey, shiftKey, optionKey, controlKey.
    static let carbonCommand: UInt32 = 0x0100
    static let carbonShift: UInt32   = 0x0200
    static let carbonOption: UInt32  = 0x0800
    static let carbonControl: UInt32 = 0x1000

    // NSEvent.ModifierFlags raw values.
    static let cocoaShift: UInt   = 1 << 17
    static let cocoaControl: UInt = 1 << 18
    static let cocoaOption: UInt  = 1 << 19
    static let cocoaCommand: UInt = 1 << 20

    /// Flags for `RegisterEventHotKey`.
    public var carbonFlags: UInt32 {
        var f: UInt32 = 0
        if contains(.command) { f |= Self.carbonCommand }
        if contains(.shift) { f |= Self.carbonShift }
        if contains(.option) { f |= Self.carbonOption }
        if contains(.control) { f |= Self.carbonControl }
        return f
    }

    /// Builds the set from `NSEvent.ModifierFlags.rawValue` (other bits are ignored).
    public init(cocoaFlags raw: UInt) {
        var s: ModifierSet = []
        if raw & Self.cocoaCommand != 0 { s.insert(.command) }
        if raw & Self.cocoaShift != 0 { s.insert(.shift) }
        if raw & Self.cocoaOption != 0 { s.insert(.option) }
        if raw & Self.cocoaControl != 0 { s.insert(.control) }
        self = s
    }

    /// Converts back to `NSEvent.ModifierFlags.rawValue`.
    public var cocoaFlags: UInt {
        var f: UInt = 0
        if contains(.command) { f |= Self.cocoaCommand }
        if contains(.shift) { f |= Self.cocoaShift }
        if contains(.option) { f |= Self.cocoaOption }
        if contains(.control) { f |= Self.cocoaControl }
        return f
    }

    /// Symbols in Apple's canonical order: ⌃⌥⇧⌘.
    public var symbols: String {
        var s = ""
        if contains(.control) { s += "⌃" }
        if contains(.option) { s += "⌥" }
        if contains(.shift) { s += "⇧" }
        if contains(.command) { s += "⌘" }
        return s
    }
}

/// A global keyboard shortcut: a virtual key code plus modifiers.
public struct Shortcut: Codable, Hashable, Sendable {
    /// macOS virtual key code (kVK_*), layout independent.
    public var keyCode: UInt32
    public var modifiers: ModifierSet

    public init(keyCode: UInt32, modifiers: ModifierSet) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Display string such as "⌃⌥1". `keyName` lets the app supply layout-aware key names.
    public func displayString(keyName: (UInt32) -> String? = KeyCodes.fallbackName) -> String {
        modifiers.symbols + (keyName(keyCode) ?? KeyCodes.fallbackName(keyCode) ?? "#\(keyCode)")
    }
}

public enum ShortcutValidation: Equatable, Sendable {
    case valid
    /// Plain keys (or only ⇧) would hijack normal typing.
    case needsModifier
    /// Keys that the recorder reserves (Esc cancels, ⌫ clears).
    case reserved
}

extension Shortcut {
    public var validation: ShortcutValidation {
        if KeyCodes.isFunctionKey(keyCode) { return .valid }
        let meaningful: ModifierSet = [.command, .control, .option]
        if modifiers.intersection(meaningful).isEmpty {
            if keyCode == KeyCodes.escape || keyCode == KeyCodes.delete || keyCode == KeyCodes.forwardDelete {
                return .reserved
            }
            return .needsModifier
        }
        return .valid
    }
}

/// Virtual key codes (Carbon `kVK_*`) and US-ANSI fallback names.
public enum KeyCodes {
    public static let escape: UInt32 = 0x35
    public static let delete: UInt32 = 0x33
    public static let forwardDelete: UInt32 = 0x75
    public static let `return`: UInt32 = 0x24
    public static let tab: UInt32 = 0x30
    public static let space: UInt32 = 0x31

    /// Key codes of the digit row keys 1...9 (index 0 = "1").
    public static let digitRow: [UInt32] = [0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19]

    /// Key code of digit `n` (1...9) on the main row.
    public static func digit(_ n: Int) -> UInt32? {
        (1...9).contains(n) ? digitRow[n - 1] : nil
    }

    static let functionKeys: [UInt32: String] = [
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5", 0x61: "F6",
        0x62: "F7", 0x64: "F8", 0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
        0x69: "F13", 0x6B: "F14", 0x71: "F15", 0x6A: "F16", 0x40: "F17", 0x4F: "F18",
        0x50: "F19", 0x5A: "F20",
    ]

    /// Keys whose names do not come from the keyboard layout.
    public static let specialNames: [UInt32: String] = [
        0x24: "↩", 0x30: "⇥", 0x31: "Space", 0x33: "⌫", 0x35: "⎋", 0x75: "⌦",
        0x73: "↖", 0x77: "↘", 0x74: "⇞", 0x79: "⇟",
        0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",
        0x4C: "⌤", 0x47: "⌧",
    ]

    /// US-ANSI key names, used when the current layout cannot be queried.
    static let ansiNames: [UInt32: String] = [
        0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H", 0x05: "G", 0x06: "Z", 0x07: "X",
        0x08: "C", 0x09: "V", 0x0A: "§", 0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R",
        0x10: "Y", 0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x16: "6", 0x17: "5",
        0x18: "=", 0x19: "9", 0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]", 0x1F: "O",
        0x20: "U", 0x21: "[", 0x22: "I", 0x23: "P", 0x25: "L", 0x26: "J", 0x27: "'", 0x28: "K",
        0x29: ";", 0x2A: "\\", 0x2B: ",", 0x2C: "/", 0x2D: "N", 0x2E: "M", 0x2F: ".", 0x32: "`",
        0x41: "Num.", 0x43: "Num*", 0x45: "Num+", 0x4B: "Num/", 0x4E: "Num-", 0x51: "Num=",
        0x52: "Num0", 0x53: "Num1", 0x54: "Num2", 0x55: "Num3", 0x56: "Num4", 0x57: "Num5",
        0x58: "Num6", 0x59: "Num7", 0x5B: "Num8", 0x5C: "Num9",
    ]

    /// Keypad keys: the layout translation returns plain digits, so keep a distinct name.
    public static func isKeypad(_ keyCode: UInt32) -> Bool {
        [0x41, 0x43, 0x45, 0x4B, 0x4E, 0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5B, 0x5C]
            .contains(keyCode)
    }

    public static func isFunctionKey(_ keyCode: UInt32) -> Bool {
        functionKeys[keyCode] != nil
    }

    /// Name independent of the keyboard layout, or nil if the key is unknown.
    public static func fallbackName(_ keyCode: UInt32) -> String? {
        functionKeys[keyCode] ?? specialNames[keyCode] ?? ansiNames[keyCode]
    }

    /// Name for keys that must not be translated through the keyboard layout.
    public static func fixedName(_ keyCode: UInt32) -> String? {
        if let f = functionKeys[keyCode] { return f }
        if let s = specialNames[keyCode] { return s }
        if isKeypad(keyCode) { return ansiNames[keyCode] }
        return nil
    }
}
