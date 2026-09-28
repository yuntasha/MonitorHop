import Foundation
import Testing
@testable import MonitorHopCore

@Suite("AppConfig")
struct AppConfigTests {
    @Test func defaultBindings() {
        let config = AppConfig.default
        #expect(config.bindings.count == 8)
        #expect(config.shortcut(for: ActionID(.focus, 1)) == Shortcut(keyCode: 0x12, modifiers: [.control, .option]))
        #expect(config.shortcut(for: ActionID(.move, 2)) == Shortcut(keyCode: 0x13, modifiers: [.control, .option, .shift]))
        #expect(config.shortcut(for: ActionID(.focus, 5)) == nil)
        #expect(Set(config.bindings.values).count == config.bindings.count, "defaults must not collide")
        #expect(config.bindings.values.allSatisfy { $0.validation == .valid })
    }

    @Test func actionIDKeys() {
        #expect(ActionID(key: "focus.3") == ActionID(.focus, 3))
        #expect(ActionID(key: "move.9") == ActionID(.move, 9))
        #expect(ActionID(key: "focus.0") == nil)
        #expect(ActionID(key: "move.10") == nil)
        #expect(ActionID(key: "jump.1") == nil)
        #expect(ActionID(key: "focus") == nil)
        #expect(ActionID(.move, 4).key == "move.4")
        #expect(ActionID.all.count == 18)
        #expect(ActionID.all.first == ActionID(.focus, 1))
    }

    @Test func jsonRoundTrip() throws {
        var config = AppConfig.default
        config.setDisplayOrder(connected: ["B", "A"])
        #expect(config.hasCustomDisplayOrder)
        config.placement = .proportional
        config.moveCursor = false
        config.showSwitchHUD = true
        config.bindings[ActionID(.focus, 7).key] = Shortcut(keyCode: 0x7A, modifiers: [])
        let data = try JSONEncoder().encode(config)
        #expect(try JSONDecoder().decode(AppConfig.self, from: data) == config)
        config.resetDisplayOrder()
        #expect(!config.hasCustomDisplayOrder)
    }

    @Test func tolerantDecoding() throws {
        #expect(try JSONDecoder().decode(AppConfig.self, from: Data("{}".utf8)) == .default)

        let json = """
        {"placement": "bogus", "moveCursor": false, "extra": 1,
         "bindings": {"focus.1": {"keyCode": 18, "modifiers": 4}, "bogus.x": {"keyCode": 1, "modifiers": 1},
                      "move.1": {"keyCode": 13, "modifiers": 1}}}
        """
        let decoded = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        #expect(decoded.placement == AppConfig.default.placement)
        #expect(decoded.moveCursor == false)
        #expect(decoded.bindings.count == 1)
        #expect(decoded.shortcut(for: ActionID(.focus, 1)) == Shortcut(keyCode: 18, modifiers: [.control]))
    }

    @Test func conflictLookup() {
        let config = AppConfig.default
        let s = Shortcut(keyCode: 0x12, modifiers: [.control, .option])
        #expect(config.action(using: s) == ActionID(.focus, 1))
        #expect(config.action(using: s, excluding: ActionID(.focus, 1)) == nil)
        #expect(config.action(using: Shortcut(keyCode: 0x00, modifiers: [.command])) == nil)
    }

    @Test func resolvedBindingsAreSortedAndValid() {
        var config = AppConfig.default
        config.bindings["garbage"] = Shortcut(keyCode: 1, modifiers: [.command])
        let resolved = config.resolvedBindings
        #expect(resolved.count == 8)
        #expect(resolved.first?.0 == ActionID(.focus, 1))
        #expect(resolved.last?.0 == ActionID(.move, 4))
    }
}
