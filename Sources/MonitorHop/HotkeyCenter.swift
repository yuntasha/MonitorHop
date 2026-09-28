import Carbon
import Combine
import MonitorHopCore

private let hotKeySignature: OSType = 0x4D48_6F70 // 'MHop'

/// Carbon event handler for all MonitorHop hotkeys. Runs on the main thread.
private func hotKeyHandler(
    _ callRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr, hotKeyID.signature == hotKeySignature else { return OSStatus(eventNotHandledErr) }
    let id = hotKeyID.id
    // Leave the Carbon callback quickly; do the work on the next main-queue turn.
    DispatchQueue.main.async {
        MainActor.assumeIsolated { HotkeyCenter.shared.fire(id) }
    }
    return noErr
}

/// Registers global hotkeys with `RegisterEventHotKey`.
/// This API needs no Accessibility / Input Monitoring permission.
@MainActor
final class HotkeyCenter: ObservableObject {
    static let shared = HotkeyCenter()

    /// Bindings that could not be registered (usually taken by another app), with the OSStatus.
    @Published private(set) var failures: [ActionID: OSStatus] = [:]
    var onTrigger: ((ActionID) -> Void)?

    private var bindings: [(ActionID, Shortcut)] = []
    private var registered: [UInt32: (action: ActionID, ref: EventHotKeyRef)] = [:]
    private var handlerRef: EventHandlerRef?
    private var suspensions = 0
    private var nextID: UInt32 = 1

    var isSuspended: Bool { suspensions > 0 }
    var registeredCount: Int { registered.count }

    func install() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &spec, nil, &handlerRef)
        if status != noErr {
            logger.error("InstallEventHandler failed: \(status)")
        }
    }

    /// Replaces all hotkeys with `bindings`.
    func apply(_ bindings: [(ActionID, Shortcut)]) {
        self.bindings = bindings
        if suspensions == 0 { registerAll() }
    }

    /// Temporarily releases every hotkey (e.g. while recording a new shortcut). Nestable.
    func suspend() {
        suspensions += 1
        if suspensions == 1 { unregisterAll() }
    }

    func resume() {
        guard suspensions > 0 else { return }
        suspensions -= 1
        if suspensions == 0 { registerAll() }
    }

    func unregisterAll() {
        for entry in registered.values { UnregisterEventHotKey(entry.ref) }
        registered.removeAll()
    }

    /// Registers and immediately releases each binding; reports the ones that fail.
    func probe(_ bindings: [(ActionID, Shortcut)]) -> [ActionID: OSStatus] {
        var failed: [ActionID: OSStatus] = [:]
        for (action, shortcut) in bindings {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                shortcut.keyCode, shortcut.modifiers.carbonFlags,
                EventHotKeyID(signature: hotKeySignature, id: 0xFFFF_0000 | UInt32(truncatingIfNeeded: failed.count)),
                GetApplicationEventTarget(), 0, &ref
            )
            if status == noErr, let ref { UnregisterEventHotKey(ref) } else { failed[action] = status }
        }
        return failed
    }

    private func registerAll() {
        unregisterAll()
        var failed: [ActionID: OSStatus] = [:]
        for (action, shortcut) in bindings {
            var ref: EventHotKeyRef?
            let id = nextID
            nextID = nextID >= 0xFFFF ? 1 : nextID + 1
            let status = RegisterEventHotKey(
                shortcut.keyCode, shortcut.modifiers.carbonFlags,
                EventHotKeyID(signature: hotKeySignature, id: id),
                GetApplicationEventTarget(), 0, &ref
            )
            if status == noErr, let ref {
                registered[id] = (action, ref)
            } else {
                failed[action] = status
                logger.error("Hotkey \(action.key, privacy: .public) failed to register: \(status)")
            }
        }
        if failed != failures { failures = failed }
    }

    fileprivate func fire(_ id: UInt32) {
        guard suspensions == 0, let entry = registered[id] else { return }
        onTrigger?(entry.action)
    }
}
