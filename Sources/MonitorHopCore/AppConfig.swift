/// The two things MonitorHop can do with a hotkey.
public enum ActionKind: String, Codable, CaseIterable, Sendable {
    /// Move keyboard focus (and optionally the cursor) to monitor N.
    case focus
    /// Move the focused window to monitor N.
    case move
}

/// Identifies one bindable action, e.g. "focus.2".
public struct ActionID: Hashable, Codable, Sendable, CustomStringConvertible, Comparable {
    public var kind: ActionKind
    /// 1-based monitor number.
    public var slot: Int

    public init(_ kind: ActionKind, _ slot: Int) {
        self.kind = kind
        self.slot = slot
    }

    public var key: String { "\(kind.rawValue).\(slot)" }
    public var description: String { key }

    public init?(key: String) {
        let parts = key.split(separator: ".")
        guard parts.count == 2, let kind = ActionKind(rawValue: String(parts[0])),
              let slot = Int(parts[1]), AppConfig.slots.contains(slot) else { return nil }
        self.init(kind, slot)
    }

    public static func < (a: ActionID, b: ActionID) -> Bool {
        if a.kind != b.kind { return a.kind == .focus }
        return a.slot < b.slot
    }

    /// Every bindable action, focus first.
    public static var all: [ActionID] {
        ActionKind.allCases.flatMap { kind in AppConfig.slots.map { ActionID(kind, $0) } }
    }
}

/// Persisted user settings.
public struct AppConfig: Codable, Equatable, Sendable {
    /// Monitor numbers that can be bound (1...9, matching the digit keys).
    public static let slots: ClosedRange<Int> = 1...9
    /// Monitor numbers that get a shortcut out of the box.
    public static let defaultBoundSlots: ClosedRange<Int> = 1...4

    /// Shortcut per action key ("focus.1" → ⌃⌥1). Missing key = no shortcut.
    public var bindings: [String: Shortcut]
    /// Global user-defined monitor order (display keys). Empty = automatic (left to right).
    public var displayOrder: [String]
    /// Exact order per set of connected displays (`DisplayOrdering.configurationKey`).
    public var displayOrdersByConfiguration: [String: [String]]
    public var placement: PlacementMode
    /// Warp the mouse cursor to the newly focused / moved window.
    public var moveCursor: Bool
    /// Briefly show the monitor number when switching.
    public var showSwitchHUD: Bool

    public init(
        bindings: [String: Shortcut],
        displayOrder: [String],
        displayOrdersByConfiguration: [String: [String]] = [:],
        placement: PlacementMode,
        moveCursor: Bool,
        showSwitchHUD: Bool
    ) {
        self.bindings = bindings
        self.displayOrder = displayOrder
        self.displayOrdersByConfiguration = displayOrdersByConfiguration
        self.placement = placement
        self.moveCursor = moveCursor
        self.showSwitchHUD = showSwitchHUD
    }

    /// ⌃⌥N focuses monitor N, ⌃⌥⇧N moves the focused window to monitor N (N = 1...4).
    public static var defaultBindings: [String: Shortcut] {
        var b: [String: Shortcut] = [:]
        for slot in defaultBoundSlots {
            guard let key = KeyCodes.digit(slot) else { continue }
            b[ActionID(.focus, slot).key] = Shortcut(keyCode: key, modifiers: [.control, .option])
            b[ActionID(.move, slot).key] = Shortcut(keyCode: key, modifiers: [.control, .option, .shift])
        }
        return b
    }

    public static var `default`: AppConfig {
        AppConfig(bindings: defaultBindings, displayOrder: [], placement: .keepSize,
                  moveCursor: true, showSwitchHUD: false)
    }

    public func shortcut(for action: ActionID) -> Shortcut? { bindings[action.key] }

    /// True when the user reordered monitors at least once (otherwise: left → right).
    public var hasCustomDisplayOrder: Bool {
        !displayOrder.isEmpty || !displayOrdersByConfiguration.isEmpty
    }

    /// Records a user-chosen order of the currently connected displays.
    public mutating func setDisplayOrder(connected keys: [String]) {
        displayOrder = DisplayOrdering.merge(newConnectedOrder: keys, into: displayOrder)
        displayOrdersByConfiguration[DisplayOrdering.configurationKey(keys)] = keys
    }

    public mutating func resetDisplayOrder() {
        displayOrder = []
        displayOrdersByConfiguration = [:]
    }

    /// The action that already uses `shortcut`, ignoring `excluding`.
    public func action(using shortcut: Shortcut, excluding: ActionID? = nil) -> ActionID? {
        bindings
            .compactMap { key, value -> ActionID? in
                guard value == shortcut, let id = ActionID(key: key), id != excluding else { return nil }
                return id
            }
            .sorted()
            .first
    }

    /// Valid (action, shortcut) pairs, sorted, with unknown keys dropped.
    public var resolvedBindings: [(ActionID, Shortcut)] {
        bindings.compactMap { key, value in ActionID(key: key).map { ($0, value) } }
            .sorted { $0.0 < $1.0 }
    }

    // MARK: - Tolerant decoding (unknown/missing fields fall back to defaults)

    private enum CodingKeys: String, CodingKey {
        case bindings, displayOrder, displayOrdersByConfiguration, placement, moveCursor, showSwitchHUD
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppConfig.default
        let rawBindings = (try? c.decodeIfPresent([String: Shortcut].self, forKey: .bindings)) ?? nil
        bindings = (rawBindings ?? d.bindings).filter { ActionID(key: $0.key) != nil }
        displayOrder = ((try? c.decodeIfPresent([String].self, forKey: .displayOrder)) ?? nil) ?? d.displayOrder
        displayOrdersByConfiguration = ((try? c.decodeIfPresent([String: [String]].self, forKey: .displayOrdersByConfiguration)) ?? nil)
            ?? d.displayOrdersByConfiguration
        placement = ((try? c.decodeIfPresent(PlacementMode.self, forKey: .placement)) ?? nil) ?? d.placement
        moveCursor = ((try? c.decodeIfPresent(Bool.self, forKey: .moveCursor)) ?? nil) ?? d.moveCursor
        showSwitchHUD = ((try? c.decodeIfPresent(Bool.self, forKey: .showSwitchHUD)) ?? nil) ?? d.showSwitchHUD
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(bindings, forKey: .bindings)
        try c.encode(displayOrder, forKey: .displayOrder)
        try c.encode(displayOrdersByConfiguration, forKey: .displayOrdersByConfiguration)
        try c.encode(placement, forKey: .placement)
        try c.encode(moveCursor, forKey: .moveCursor)
        try c.encode(showSwitchHUD, forKey: .showSwitchHUD)
    }
}
