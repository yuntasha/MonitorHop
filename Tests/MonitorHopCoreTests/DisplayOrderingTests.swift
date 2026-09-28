import CoreGraphics
import Testing
@testable import MonitorHopCore

@Suite("DisplayOrdering")
struct DisplayOrderingTests {
    // Cocoa coordinates.
    let builtIn = DisplayDescriptor(key: "BUILTIN", frame: CGRect(x: 0, y: 0, width: 1710, height: 1112))
    let left = DisplayDescriptor(key: "LEFT", frame: CGRect(x: -1920, y: 327, width: 1920, height: 1080))
    let right = DisplayDescriptor(key: "RIGHT", frame: CGRect(x: 1710, y: 0, width: 2560, height: 1440))
    let above = DisplayDescriptor(key: "ABOVE", frame: CGRect(x: 0, y: 1112, width: 1710, height: 1112))

    @Test func spatialOrderIsLeftToRight() {
        let ordered = DisplayOrdering.spatialOrder([builtIn, right, left]).map(\.key)
        #expect(ordered == ["LEFT", "BUILTIN", "RIGHT"])
    }

    @Test func stackedDisplaysAreTopToBottom() {
        let ordered = DisplayOrdering.spatialOrder([builtIn, above]).map(\.key)
        #expect(ordered == ["ABOVE", "BUILTIN"])
    }

    @Test func emptySavedOrderIsSpatial() {
        #expect(DisplayOrdering.resolve([builtIn, left], savedOrder: []).map(\.key) == ["LEFT", "BUILTIN"])
    }

    @Test func savedOrderWins() {
        #expect(DisplayOrdering.resolve([builtIn, left], savedOrder: ["BUILTIN", "LEFT"]).map(\.key) == ["BUILTIN", "LEFT"])
    }

    @Test func disconnectedSavedDisplaysAreSkipped() {
        let resolved = DisplayOrdering.resolve([builtIn, left], savedOrder: ["RIGHT", "BUILTIN", "LEFT"])
        #expect(resolved.map(\.key) == ["BUILTIN", "LEFT"])
    }

    @Test func unknownDisplaysAreInsertedByPosition() {
        // Only BUILTIN was ordered. LEFT is left of it; ABOVE shares its x but is higher
        // (top → bottom), so both go in front of it; RIGHT goes after it.
        let resolved = DisplayOrdering.resolve([builtIn, left, right, above], savedOrder: ["BUILTIN"])
        #expect(resolved.map(\.key) == ["LEFT", "ABOVE", "BUILTIN", "RIGHT"])
    }

    @Test func mergeAnchorsDisconnectedDisplays() {
        // RIGHT (disconnected) sat in front of LEFT: it stays anchored in front of LEFT.
        let merged = DisplayOrdering.merge(newConnectedOrder: ["LEFT", "BUILTIN"], into: ["BUILTIN", "RIGHT", "LEFT"])
        #expect(merged == ["RIGHT", "LEFT", "BUILTIN"])
        // Trailing disconnected displays stay at the end.
        #expect(DisplayOrdering.merge(newConnectedOrder: ["B", "A"], into: ["A", "B", "C"]) == ["B", "A", "C"])
    }

    @Test func mergeRemovesDuplicates() {
        #expect(DisplayOrdering.merge(newConnectedOrder: ["A", "A", "B"], into: ["B", "C", "C"]) == ["A", "B", "C"])
    }

    /// Laptop used at two desks: office monitor WORK and home monitor HOME, both left of the laptop.
    @Test func twoDesksKeepTheirOwnOrder() {
        let work = DisplayDescriptor(key: "WORK", frame: CGRect(x: -2560, y: 0, width: 2560, height: 1440))
        let home = DisplayDescriptor(key: "HOME", frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080))
        var config = AppConfig.default

        // Office: user makes the laptop monitor 1.
        config.setDisplayOrder(connected: ["BUILTIN", "WORK"])
        // Home, never ordered: the unknown HOME goes by position (left of the laptop).
        var atHome = DisplayOrdering.resolve([builtIn, home], savedOrder: config.displayOrder,
                                             configurationOrders: config.displayOrdersByConfiguration)
        #expect(atHome.map(\.key) == ["HOME", "BUILTIN"])
        // User prefers the laptop first at home too, then HOME first again — last choice wins.
        config.setDisplayOrder(connected: ["BUILTIN", "HOME"])
        config.setDisplayOrder(connected: ["HOME", "BUILTIN"])
        atHome = DisplayOrdering.resolve([builtIn, home], savedOrder: config.displayOrder,
                                         configurationOrders: config.displayOrdersByConfiguration)
        #expect(atHome.map(\.key) == ["HOME", "BUILTIN"])
        // Back at the office the office order is intact.
        let atWork = DisplayOrdering.resolve([builtIn, work], savedOrder: config.displayOrder,
                                             configurationOrders: config.displayOrdersByConfiguration)
        #expect(atWork.map(\.key) == ["BUILTIN", "WORK"])
    }

    @Test func exactConfigurationWinsOverGlobalOrder() {
        let configs = [DisplayOrdering.configurationKey(["LEFT", "BUILTIN", "RIGHT"]): ["BUILTIN", "RIGHT", "LEFT"]]
        let resolved = DisplayOrdering.resolve([left, builtIn, right], savedOrder: ["LEFT", "BUILTIN", "RIGHT"],
                                               configurationOrders: configs)
        #expect(resolved.map(\.key) == ["BUILTIN", "RIGHT", "LEFT"])
        #expect(DisplayOrdering.configurationKey(["B", "A"]) == DisplayOrdering.configurationKey(["A", "B"]))
    }

    @Test func identicalMonitorsGetPositionalSuffixes() {
        let a = DisplayDescriptor(key: "SAME", frame: CGRect(x: 1710, y: 0, width: 1920, height: 1080))
        let b = DisplayDescriptor(key: "SAME", frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080))
        // Input order (NSScreen order) must not matter: the left one is always #0.
        let keys1 = DisplayOrdering.disambiguate([builtIn, a, b]).map(\.key)
        let keys2 = DisplayOrdering.disambiguate([builtIn, b, a]).map(\.key)
        #expect(keys1 == ["BUILTIN", "SAME#1", "SAME#0"])
        #expect(keys2 == ["BUILTIN", "SAME#0", "SAME#1"])
        #expect(DisplayOrdering.disambiguate([builtIn, left]).map(\.key) == ["BUILTIN", "LEFT"])
    }

    @Test func moveSwapsNeighbours() {
        #expect(DisplayOrdering.move(["A", "B", "C"], from: 0, to: 1) == ["B", "A", "C"])
        #expect(DisplayOrdering.move(["A", "B", "C"], from: 2, to: 0) == ["C", "A", "B"])
        #expect(DisplayOrdering.move(["A", "B", "C"], from: 0, to: 3) == ["A", "B", "C"])
        #expect(DisplayOrdering.move(["A", "B", "C"], from: -1, to: 0) == ["A", "B", "C"])
    }

    @Test func duplicateKeysDoNotCrash() {
        let dup = DisplayDescriptor(key: "BUILTIN", frame: CGRect(x: 5000, y: 0, width: 10, height: 10))
        let resolved = DisplayOrdering.resolve([builtIn, dup], savedOrder: ["BUILTIN"])
        #expect(resolved.count == 2)
    }
}
