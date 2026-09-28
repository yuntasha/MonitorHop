import CoreGraphics
import Foundation
import MonitorHopCore

/// Lets the CLI (and a second launch) talk to the running GUI instance, so commands run with
/// the GUI's Accessibility permission and the CLI never has to check in as the app.
///
/// Protocol (distributed notifications, `object` = request id):
///   CLI → GUI  perform   {action, acceptBy}   acceptBy: systemUptime deadline for accepting
///   GUI → CLI  accepted  {}                    sent as soon as the request is taken
///   GUI → CLI  result    {ok, message}
/// A request the GUI sees after `acceptBy` (e.g. while its menu was open, when distributed
/// notifications are not delivered) is dropped, so a CLI that gave up never gets a late action.
enum RemoteControl {
    static let performRequest = Notification.Name("com.alencup.MonitorHop.perform")
    static let performAccepted = Notification.Name("com.alencup.MonitorHop.accepted")
    static let performResult = Notification.Name("com.alencup.MonitorHop.result")
    static let showSettingsRequest = Notification.Name("com.alencup.MonitorHop.showSettings")

    private static let identifyKey = "identify"
    private static let reloadKey = "reload"
    private static let renderPrefix = "render:"
    private static let pressPrefix = "press:"
    private static let setFramePrefix = "setframe:"
    private static let acceptWindow: TimeInterval = 1.5
    private static let resultTimeout: TimeInterval = 10

    private static var observers: [NSObjectProtocol] = []
    /// Requests that arrive before the app finished launching run once it has.
    private static var isReady = false
    private static var pending: [() -> Void] = []

    // MARK: GUI side

    /// Registers the observers. Call as early as possible (before NSApplication is created):
    /// notifications posted while no observer exists are dropped by the system.
    static func startListening() {
        guard observers.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        observers.append(center.addObserver(forName: performRequest, object: nil, queue: .main) { note in
            let requestID = note.object as? String
            let key = note.userInfo?["action"] as? String
            let acceptBy = note.userInfo?["acceptBy"] as? Double
            let rawPID = note.userInfo?["pid"]
            let requiredPID = (rawPID as? Int).flatMap { pid_t(exactly: $0) }
            let invalidPID = rawPID != nil && (requiredPID ?? 0) <= 0
            MainActor.assumeIsolated {
                if let acceptBy, ProcessInfo.processInfo.systemUptime > acceptBy {
                    logger.info("Dropping expired remote request \(key ?? "?", privacy: .public)")
                    return
                }
                if let requestID {
                    center.postNotificationName(performAccepted, object: requestID, userInfo: nil, deliverImmediately: true)
                }
                whenReady {
                    let outcome = invalidPID ? .failed("잘못된 pid입니다.") : handle(key, requiredFrontPID: requiredPID)
                    guard let requestID else { return }
                    center.postNotificationName(
                        performResult, object: requestID,
                        userInfo: ["ok": outcome.isSuccess, "message": outcome.message],
                        deliverImmediately: true
                    )
                }
            }
        })
        observers.append(center.addObserver(forName: showSettingsRequest, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { whenReady { SettingsWindowController.shared.show() } }
        })
    }

    /// Called at the end of applicationDidFinishLaunching.
    @MainActor
    static func markReady() {
        isReady = true
        let queued = pending
        pending = []
        queued.forEach { $0() }
    }

    @MainActor
    private static func whenReady(_ work: @escaping () -> Void) {
        if isReady { work() } else { pending.append(work) }
    }

    @MainActor
    private static func handle(_ key: String?, requiredFrontPID: pid_t?) -> ActionOutcome {
        guard let key else { return .failed("알 수 없는 요청입니다.") }
        if key == identifyKey {
            HUD.shared.identify(ScreenRegistry.shared.monitors)
            return .done("모니터 번호를 표시했습니다.")
        }
        if key == reloadKey {
            SettingsStore.shared.reloadFromDefaults()
            return .done("설정을 다시 읽었습니다.")
        }
        if key.hasPrefix(pressPrefix), let action = parseAction(String(key.dropFirst(pressPrefix.count))) {
            return DevTools.pressShortcut(of: action)
        }
        if key.hasPrefix(setFramePrefix) {
            guard DevTools.isEnabled else { return .failed("개발용 기능이 꺼져 있습니다.") }
            guard let (id, frame) = parseFrameSpec(String(key.dropFirst(setFramePrefix.count))) else {
                return .failed("형식: <windowID> <x> <y> <w> <h>")
            }
            return DevTools.setFrame(windowID: id, to: frame)
        }
        if key.hasPrefix(renderPrefix) {
            ScreenRegistry.shared.refresh()
            return .done(CLI.render(String(key.dropFirst(renderPrefix.count)), insideApp: true))
        }
        if let action = parseAction(key) {
            return ActionPerformer.shared.perform(action, requiredFrontPID: requiredFrontPID)
        }
        return .failed("알 수 없는 요청입니다.")
    }

    // MARK: CLI side

    enum SendError: Error {
        /// No GUI took the request in time (not running, still starting, or its menu is open).
        case notAccepted
        /// The GUI accepted but did not finish in time.
        case noResult
    }

    static func perform(_ action: ActionID, requiredFrontPID: pid_t? = nil) -> Result<ActionOutcome, SendError> {
        send(action.key, extra: requiredFrontPID.map { ["pid": Int($0)] } ?? [:])
    }
    static func performIdentify() -> Result<ActionOutcome, SendError> { send(identifyKey) }
    static func reloadSettings() -> Result<ActionOutcome, SendError> { send(reloadKey) }
    static func pressShortcut(of action: ActionID) -> Result<ActionOutcome, SendError> { send(pressPrefix + action.key) }
    static func setFrame(_ spec: [String]) -> Result<ActionOutcome, SendError> { send(setFramePrefix + spec.joined(separator: " ")) }

    /// Output of `--list` / `--list-json` / `--check` rendered by the running GUI.
    static func render(_ key: String) -> Result<String, SendError> {
        send(renderPrefix + key).map(\.message)
    }

    private static func send(_ key: String, extra: [String: Any] = [:]) -> Result<ActionOutcome, SendError> {
        let requestID = UUID().uuidString
        let center = DistributedNotificationCenter.default()
        var accepted = false
        var outcome: ActionOutcome?
        let acceptToken = center.addObserver(forName: performAccepted, object: requestID, queue: nil) { _ in
            accepted = true
        }
        let resultToken = center.addObserver(forName: performResult, object: requestID, queue: nil) { note in
            accepted = true
            let ok = note.userInfo?["ok"] as? Bool ?? false
            let message = note.userInfo?["message"] as? String ?? ""
            outcome = ok ? .done(message) : .failed(message)
        }
        defer {
            center.removeObserver(acceptToken)
            center.removeObserver(resultToken)
        }
        let acceptBy = ProcessInfo.processInfo.systemUptime + acceptWindow
        var userInfo: [String: Any] = ["action": key, "acceptBy": acceptBy]
        userInfo.merge(extra) { a, _ in a }
        center.postNotificationName(performRequest, object: requestID, userInfo: userInfo, deliverImmediately: true)

        let acceptDeadline = Date(timeIntervalSinceNow: acceptWindow + 0.3)
        while !accepted && Date() < acceptDeadline { spinOnce() }
        guard accepted else { return .failure(.notAccepted) }
        let resultDeadline = Date(timeIntervalSinceNow: resultTimeout)
        while outcome == nil && Date() < resultDeadline { spinOnce() }
        guard let outcome else { return .failure(.noResult) }
        return .success(outcome)
    }

    private static func spinOnce() {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
    }

    static func requestShowSettings() {
        DistributedNotificationCenter.default().postNotificationName(
            showSettingsRequest, object: nil, userInfo: nil, deliverImmediately: true
        )
    }

    /// "<windowID> <x> <y> <w> <h>" with an integer id and finite numbers (never traps).
    static func parseFrameSpec(_ text: String) -> (CGWindowID, CGRect)? {
        let parts = text.split(separator: " ")
        guard parts.count == 5, let id = UInt32(parts[0]), id > 0 else { return nil }
        let numbers = parts.dropFirst().compactMap { Double($0) }
        guard numbers.count == 4, numbers.allSatisfy(\.isFinite), numbers[2] > 0, numbers[3] > 0 else { return nil }
        return (id, CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3]))
    }

    /// "focus.2" / "move.10" — any positive monitor number (the menu allows more than 9).
    static func parseAction(_ key: String) -> ActionID? {
        let parts = key.split(separator: ".")
        guard parts.count == 2, let kind = ActionKind(rawValue: String(parts[0])),
              let slot = Int(parts[1]), slot >= 1 else { return nil }
        return ActionID(kind, slot)
    }
}

extension RemoteControl.SendError {
    var message: String {
        switch self {
        case .notAccepted:
            return "실행 중인 MonitorHop 앱이 요청을 받지 않았습니다. (메뉴가 열려 있다면 닫고 다시 시도하세요)"
        case .noResult:
            return "MonitorHop 앱이 바빠서 제시간에 끝내지 못했습니다."
        }
    }
}
