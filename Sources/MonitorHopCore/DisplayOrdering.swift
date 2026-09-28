import CoreGraphics

/// Minimal description of a connected display, used for ordering.
public struct DisplayDescriptor: Equatable, Sendable {
    /// Stable identifier that survives reconnects/reboots (display UUID string).
    public var key: String
    /// Frame in Cocoa global coordinates (bottom-left origin).
    public var frame: CGRect

    public init(key: String, frame: CGRect) {
        self.key = key
        self.frame = frame
    }
}

/// Decides which display is "monitor 1", "monitor 2", ...
///
/// Two layers of memory, like macOS remembers display arrangements:
/// 1. an exact order per *set* of connected displays (office desk vs. home desk), and
/// 2. a global order used for sets never ordered before; displays unknown to it are
///    inserted by their physical (left → right) position.
public enum DisplayOrdering {
    /// Identifies a set of connected displays, independent of order.
    public static func configurationKey(_ keys: [String]) -> String {
        keys.sorted().joined(separator: "|")
    }

    /// Automatic order: left to right; for displays starting at the same x, top to bottom.
    public static func spatialOrder(_ displays: [DisplayDescriptor]) -> [DisplayDescriptor] {
        spatialIndices(displays).map { displays[$0] }
    }

    /// Final order. Every input display appears exactly once, even with duplicate keys.
    public static func resolve(
        _ displays: [DisplayDescriptor],
        savedOrder: [String],
        configurationOrders: [String: [String]] = [:]
    ) -> [DisplayDescriptor] {
        // 1. Exact order remembered for this set of displays.
        if let exact = configurationOrders[configurationKey(displays.map(\.key))] {
            let (picked, used) = pick(displays, following: exact)
            if !used.contains(false) { return picked.map { displays[$0] } }
        }

        // 2. Global order, with unknown displays inserted by physical position.
        let (known, used) = pick(displays, following: savedOrder)
        let spatial = spatialIndices(displays)
        var rank = [Int](repeating: 0, count: displays.count)
        for (r, i) in spatial.enumerated() { rank[i] = r }

        var result = known
        for i in spatial where !used[i] {
            let position = result.firstIndex { rank[$0] > rank[i] } ?? result.count
            result.insert(i, at: position)
        }
        return result.map { displays[$0] }
    }

    /// Updates the global order with a new user-chosen order of the *connected* displays.
    /// Disconnected displays stay anchored in front of the connected display they preceded.
    public static func merge(newConnectedOrder: [String], into saved: [String]) -> [String] {
        let connected = Set(newConnectedOrder)
        var before: [String: [String]] = [:]
        var pending: [String] = []
        for key in saved {
            if connected.contains(key) {
                if !pending.isEmpty {
                    before[key, default: []].append(contentsOf: pending)
                    pending = []
                }
            } else {
                pending.append(key)
            }
        }
        var seen = Set<String>()
        var result: [String] = []
        for key in newConnectedOrder {
            for anchored in before[key] ?? [] where seen.insert(anchored).inserted { result.append(anchored) }
            if seen.insert(key).inserted { result.append(key) }
        }
        for key in pending where seen.insert(key).inserted { result.append(key) }
        return result
    }

    /// Returns `keys` with the element at `from` moved to position `to` (both 0-based,
    /// `to` interpreted as the final index). Out-of-range input returns `keys` unchanged.
    public static func move(_ keys: [String], from: Int, to: Int) -> [String] {
        guard keys.indices.contains(from), keys.indices.contains(to), from != to else { return keys }
        var k = keys
        let item = k.remove(at: from)
        k.insert(item, at: to)
        return k
    }

    /// Makes keys unique. Identical monitors can report the same UUID; members of such a group
    /// get "#0", "#1", … by their physical position inside the group, which — unlike display IDs
    /// or NSScreen order — stays the same across reboots and reconnects. Order is preserved.
    public static func disambiguate(_ displays: [DisplayDescriptor]) -> [DisplayDescriptor] {
        var groups: [String: [Int]] = [:]
        for (i, d) in displays.enumerated() { groups[d.key, default: []].append(i) }
        var result = displays
        for (key, members) in groups where members.count > 1 {
            let ordered = spatialIndices(members.map { displays[$0] }).map { members[$0] }
            for (rank, index) in ordered.enumerated() { result[index].key = "\(key)#\(rank)" }
        }
        return result
    }

    // MARK: - Helpers

    private static func spatialIndices(_ displays: [DisplayDescriptor]) -> [Int] {
        displays.indices.sorted { ia, ib in
            let a = displays[ia], b = displays[ib]
            if a.frame.minX != b.frame.minX { return a.frame.minX < b.frame.minX }
            // Cocoa y grows upward: the higher display has the larger maxY.
            if a.frame.maxY != b.frame.maxY { return a.frame.maxY > b.frame.maxY }
            if a.key != b.key { return a.key < b.key }
            return ia < ib
        }
    }

    /// Indices of `displays` in the order given by `keys`, plus which displays were used.
    private static func pick(_ displays: [DisplayDescriptor], following keys: [String]) -> ([Int], [Bool]) {
        var used = [Bool](repeating: false, count: displays.count)
        var picked: [Int] = []
        for key in keys {
            if let i = displays.indices.first(where: { !used[$0] && displays[$0].key == key }) {
                used[i] = true
                picked.append(i)
            }
        }
        return (picked, used)
    }
}
