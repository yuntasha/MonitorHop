import AppKit
import Combine
import MonitorHopCore

/// A connected monitor with its user-facing number.
struct Monitor: Identifiable, Equatable {
    /// Stable key (display UUID) used to remember the order.
    let id: String
    let displayID: CGDirectDisplayID
    let name: String
    /// 1-based monitor number (position in the user's order).
    let number: Int
    /// Cocoa coordinates (bottom-left origin).
    let frame: CGRect
    let visibleFrame: CGRect
    /// Quartz / Accessibility coordinates (top-left origin).
    let axFrame: CGRect
    let axVisibleFrame: CGRect
    let isPrimary: Bool
    let scale: CGFloat
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

/// Keeps the ordered list of connected monitors up to date.
@MainActor
final class ScreenRegistry: ObservableObject {
    static let shared = ScreenRegistry()

    @Published private(set) var monitors: [Monitor] = []
    private var cancellables = Set<AnyCancellable>()
    private var started = false

    /// Starts observing display changes and the saved order.
    func start() {
        guard !started else { return }
        started = true
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        // `$config` publishes in willSet, so use the emitted value rather than re-reading the store.
        SettingsStore.shared.$config
            .removeDuplicates {
                $0.displayOrder == $1.displayOrder && $0.displayOrdersByConfiguration == $1.displayOrdersByConfiguration
            }
            .sink { [weak self] config in self?.refresh(config: config) }
            .store(in: &cancellables)
        refresh()
    }

    /// Re-reads NSScreen and recomputes monitor numbers.
    func refresh(config: AppConfig? = nil) {
        let config = config ?? SettingsStore.shared.config
        let screens = NSScreen.screens
        // screens[0] is the primary display (menu bar, origin 0,0); its height defines the AX flip.
        guard let primaryHeight = screens.first?.frame.height else {
            if !monitors.isEmpty { monitors = [] }
            return
        }
        let mainID = CGMainDisplayID()

        // Identical monitors may share a UUID: disambiguate by physical position (stable), not by
        // display ID or NSScreen order (both change across reboots / menu-bar moves).
        let descriptors = DisplayOrdering.disambiguate(
            screens.map { DisplayDescriptor(key: Self.stableKey(for: $0.displayID), frame: $0.frame) }
        )
        var entries: [String: (NSScreen, CGDirectDisplayID)] = [:]
        for (screen, descriptor) in zip(screens, descriptors) {
            entries[descriptor.key] = (screen, screen.displayID)
        }

        let ordered = DisplayOrdering.resolve(
            descriptors, savedOrder: config.displayOrder, configurationOrders: config.displayOrdersByConfiguration
        )
        var result: [Monitor] = []
        for (index, descriptor) in ordered.enumerated() {
            guard let (screen, id) = entries[descriptor.key] else { continue }
            result.append(Monitor(
                id: descriptor.key,
                displayID: id,
                name: screen.localizedName,
                number: index + 1,
                frame: screen.frame,
                visibleFrame: screen.visibleFrame,
                axFrame: Geometry.flip(screen.frame, primaryHeight: primaryHeight),
                axVisibleFrame: Geometry.flip(screen.visibleFrame, primaryHeight: primaryHeight),
                isPrimary: id == mainID,
                scale: screen.backingScaleFactor
            ))
        }
        if result != monitors { monitors = result }
    }

    func monitor(number: Int) -> Monitor? {
        monitors.first { $0.number == number }
    }

    /// The monitor that owns a rect given in AX coordinates (center first, then overlap).
    func monitor(forAXRect rect: CGRect) -> Monitor? {
        Geometry.bestMatch(for: rect, in: monitors.map(\.axFrame)).map { monitors[$0] }
    }

    func monitor(forAXPoint point: CGPoint) -> Monitor? {
        Geometry.bestMatch(for: point, in: monitors.map(\.axFrame)).map { monitors[$0] }
    }

    /// The monitor under the mouse cursor.
    var monitorUnderCursor: Monitor? {
        let location = NSEvent.mouseLocation // Cocoa coordinates
        return Geometry.bestMatch(for: location, in: monitors.map(\.frame)).map { monitors[$0] }
    }

    func screen(for monitor: Monitor) -> NSScreen? {
        NSScreen.screens.first { $0.displayID == monitor.displayID }
    }

    /// A key that stays the same for a physical display across reconnects and reboots.
    static func stableKey(for id: CGDirectDisplayID) -> String {
        if let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
           let string = CFUUIDCreateString(nil, uuid) as String? {
            return string
        }
        return "display-\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))"
    }
}
