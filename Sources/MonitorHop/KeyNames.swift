import Carbon
import MonitorHopCore

/// Layout-aware key names for display ("⌃⌥1", "⌘⇧K").
enum KeyNames {
    static func name(for keyCode: UInt32) -> String? {
        if let fixed = KeyCodes.fixedName(keyCode) { return fixed }
        return translate(keyCode) ?? KeyCodes.fallbackName(keyCode)
    }

    /// Uses the current ASCII-capable layout so a Korean input source still shows Latin keys.
    private static func translate(_ keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)

        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = UCKeyTranslate(
            layout,
            UInt16(keyCode),
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysMask),
            &deadKeyState,
            chars.count,
            &length,
            &chars
        )
        guard status == noErr, length > 0 else { return nil }
        let string = String(utf16CodeUnits: chars, count: length)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        // Keys like Help/Insert, Menu or the input-language keys translate to control characters.
        guard !string.isEmpty, !string.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) else {
            return nil
        }
        return string
    }
}
