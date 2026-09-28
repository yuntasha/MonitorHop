import Foundation
import MonitorHopCore

/// Lets the CLI (and a second launch) talk to the running GUI instance, so commands run with
/// the GUI's Accessibility permission and the CLI never has to check in as the app.
enum RemoteControl {
    static let performRequest = Notification.Name("com.alencup.MonitorHop.perform")
    static let performResult = Notification.Name("com.alencup.MonitorHop.result")
    static let showSettingsRequest = Notification.Name("com.alencup.MonitorHop.showSettings")

    private static var observers: [NSObjectProtocol] = []

    /// GUI side: start listening.
    @MainActor
    static func startListening() {
        guard observers.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        observers.append(center.addObserver(forName: performRequest, object: nil, queue: .main) { note in
            let requestID = note.object as? String
            let key = note.userInfo?["action"] as? String
            MainActor.assumeIsolated {
                let outcome: ActionOutcome
                if key == identifyKey {
                    HUD.shared.identify(ScreenRegistry.shared.monitors)
                    outcome = .done("모니터 번호를 표시했습니다.")
                } else if key == reloadKey {
                    SettingsStore.shared.reloadFromDefaults()
                    outcome = .done("설정을 다시 읽었습니다.")
                } else if let key, key.hasPrefix(pressPrefix), let action = parseAction(String(key.dropFirst(pressPrefix.count))) {
                    outcome = DevTools.pressShortcut(of: action)
                } else if let key, key.hasPrefix(renderPrefix) {
                    ScreenRegistry.shared.refresh()
                    outcome = .done(CLI.render(String(key.dropFirst(renderPrefix.count)), insideApp: true))
                } else if let key, let action = parseAction(key) {
                    outcome = ActionPerformer.shared.perform(action)
                } else {
                    outcome = .failed("알 수 없는 요청입니다.")
                }
                guard let requestID else { return }
                center.postNotificationName(
                    performResult, object: requestID,
                    userInfo: ["ok": outcome.isSuccess, "message": outcome.message],
                    deliverImmediately: true
                )
            }
        })
        observers.append(center.addObserver(forName: showSettingsRequest, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { SettingsWindowController.shared.show() }
        })
    }

    private static let identifyKey = "identify"
    private static let reloadKey = "reload"
    private static let renderPrefix = "render:"
    private static let pressPrefix = "press:"

    /// CLI side: make the running GUI press the bound shortcut of `action` (real hotkey path).
    static func pressShortcut(of action: ActionID) -> ActionOutcome {
        send(pressPrefix + action.key) ?? .failed("실행 중인 MonitorHop 앱이 응답하지 않습니다.")
    }

    /// CLI side: output of `--list` / `--list-json` / `--check` rendered by the running GUI.
    static func render(_ key: String) -> String? {
        guard case .done(let text)? = send(renderPrefix + key) else { return nil }
        return text
    }

    /// CLI side: make the running GUI re-read its settings.
    static func reloadSettings() -> ActionOutcome {
        send(reloadKey) ?? .failed("실행 중인 MonitorHop 앱이 응답하지 않습니다.")
    }


    /// CLI side: ask the running GUI to show the monitor numbers.
    static func performIdentify() -> ActionOutcome {
        send(identifyKey) ?? .failed("실행 중인 MonitorHop 앱이 응답하지 않습니다.")
    }

    /// CLI side: ask the running GUI to perform `action`; nil when it did not answer in time.
    static func perform(_ action: ActionID, timeout: TimeInterval = 3) -> ActionOutcome? {
        send(action.key, timeout: timeout)
    }

    private static func send(_ key: String, timeout: TimeInterval = 3) -> ActionOutcome? {
        let requestID = UUID().uuidString
        let center = DistributedNotificationCenter.default()
        var outcome: ActionOutcome?
        let token = center.addObserver(forName: performResult, object: requestID, queue: nil) { note in
            let ok = note.userInfo?["ok"] as? Bool ?? false
            let message = note.userInfo?["message"] as? String ?? ""
            outcome = ok ? .done(message) : .failed(message)
        }
        defer { center.removeObserver(token) }
        center.postNotificationName(performRequest, object: requestID, userInfo: ["action": key], deliverImmediately: true)
        let deadline = Date(timeIntervalSinceNow: timeout)
        while outcome == nil && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        return outcome
    }

    static func requestShowSettings() {
        DistributedNotificationCenter.default().postNotificationName(
            showSettingsRequest, object: nil, userInfo: nil, deliverImmediately: true
        )
    }

    /// "focus.2" / "move.10" — any positive monitor number (the menu allows more than 9).
    static func parseAction(_ key: String) -> ActionID? {
        let parts = key.split(separator: ".")
        guard parts.count == 2, let kind = ActionKind(rawValue: String(parts[0])),
              let slot = Int(parts[1]), slot >= 1 else { return nil }
        return ActionID(kind, slot)
    }
}
