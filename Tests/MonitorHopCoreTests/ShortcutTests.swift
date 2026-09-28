import Testing
@testable import MonitorHopCore

@Suite("Shortcut")
struct ShortcutTests {
    @Test func carbonFlags() {
        #expect(ModifierSet([.control, .option]).carbonFlags == 0x1800)
        #expect(ModifierSet([.command]).carbonFlags == 0x0100)
        #expect(ModifierSet([.shift]).carbonFlags == 0x0200)
        #expect(ModifierSet([.control, .option, .shift, .command]).carbonFlags == 0x1B00)
    }

    @Test func cocoaFlagsRoundTrip() {
        let all: [ModifierSet] = [[], [.command], [.control, .option], [.control, .option, .shift, .command]]
        for set in all {
            #expect(ModifierSet(cocoaFlags: set.cocoaFlags) == set)
        }
        // Caps lock (1 << 16) and device-dependent bits are ignored.
        #expect(ModifierSet(cocoaFlags: (1 << 16) | (1 << 18) | 0x1) == [.control])
    }

    @Test func symbolsUseAppleOrder() {
        #expect(ModifierSet([.command, .shift, .option, .control]).symbols == "⌃⌥⇧⌘")
    }

    @Test func displayString() {
        let s = Shortcut(keyCode: KeyCodes.digit(1)!, modifiers: [.control, .option])
        #expect(s.displayString() == "⌃⌥1")
        #expect(Shortcut(keyCode: 0x7B, modifiers: [.command]).displayString() == "⌘←")
        #expect(Shortcut(keyCode: 0x7A, modifiers: []).displayString() == "F1")
        #expect(Shortcut(keyCode: 0xFF, modifiers: [.command]).displayString() == "⌘#255")
    }

    @Test func validation() {
        let a: UInt32 = 0x00
        #expect(Shortcut(keyCode: a, modifiers: []).validation == .needsModifier)
        #expect(Shortcut(keyCode: a, modifiers: [.shift]).validation == .needsModifier)
        #expect(Shortcut(keyCode: a, modifiers: [.control]).validation == .valid)
        #expect(Shortcut(keyCode: a, modifiers: [.option, .shift]).validation == .valid)
        #expect(Shortcut(keyCode: 0x60, modifiers: []).validation == .valid) // F5
        #expect(Shortcut(keyCode: KeyCodes.escape, modifiers: []).validation == .reserved)
        #expect(Shortcut(keyCode: KeyCodes.delete, modifiers: []).validation == .reserved)
        #expect(Shortcut(keyCode: KeyCodes.escape, modifiers: [.command]).validation == .valid)
    }

    @Test func digitKeyCodes() {
        #expect(KeyCodes.digit(1) == 0x12)
        #expect(KeyCodes.digit(5) == 0x17)
        #expect(KeyCodes.digit(6) == 0x16)
        #expect(KeyCodes.digit(9) == 0x19)
        #expect(KeyCodes.digit(0) == nil)
        #expect(KeyCodes.digit(10) == nil)
        for n in 1...9 {
            #expect(KeyCodes.fallbackName(KeyCodes.digit(n)!) == "\(n)")
        }
    }

    @Test func keypadKeepsDistinctName() {
        #expect(KeyCodes.isKeypad(0x53))
        #expect(KeyCodes.fixedName(0x53) == "Num1")
        #expect(KeyCodes.fixedName(0x12) == nil) // main-row 1 comes from the layout
    }
}
