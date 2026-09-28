import AppKit
import MonitorHopCore

/// Command-line mode: `MonitorHop.app/Contents/MacOS/MonitorHop --focus 2` etc.
///
/// When the MonitorHop app is running, `--focus` / `--move` are forwarded to it, so they run
/// with the app's Accessibility permission (the calling terminal / skhd / Raycast needs none).
/// The CLI never checks in as the app (no NSApplication) except for `--identify`, so it can
/// not block a GUI launch while it runs.
@MainActor
enum CLI {
    enum Command: Equatable {
        case list, listJSON, focus(Int), move(Int, pid: Int32?), identify, check, reload, help, version, invalid(String)
        case loginItem(String), simulateHotkey(String), renderSettings(String), setFrame([String])
    }

    static let usage = """
    MonitorHop — 모니터 단위 포커스/창 이동

    사용법: MonitorHop [명령]
      (명령 없음)        메뉴 막대 앱으로 실행
      --focus N          N번 모니터로 포커스 이동
      --move N [--pid P] 현재 포커스된 창을 N번 모니터로 보내기 (--pid: 그 프로세스가 맨 앞일 때만)
      --list             연결된 모니터를 번호 순서대로 표시
      --list-json        위 정보를 JSON으로 출력 (스크립트용)
      --identify         각 모니터에 번호 표시
      --check            권한·단축키·API 상태 진단
      --reload           실행 중인 앱이 설정을 다시 읽게 함 (defaults로 직접 바꾼 경우)
      --login-item on|off|status   로그인 시 자동 실행 켜기/끄기/확인
      --version          버전 표시
      --help             이 도움말

    개발용:
      --simulate-hotkey focus.N|move.N   실행 중인 앱이 그 단축키를 실제로 누르게 함 (등록된 단축키만)
      --render-settings DIR              설정 화면의 각 탭을 DIR/settings-*.png로 저장
      --set-frame ID X Y W H             창(CGWindowID)의 위치·크기 지정 (AX 좌표, 테스트 복구용)
      개발용 명령은 앱을 MONITORHOP_DEVTOOLS=1 환경으로 실행했을 때만 동작합니다.

    앱이 실행 중이면 --focus / --move 는 앱에 전달되어 앱의 접근성 권한으로 실행됩니다.
    """

    /// Returns nil when the app should start normally (no arguments besides ones macOS injects).
    static func parse(_ arguments: [String]) -> Command? {
        // Drop arguments macOS or developer tools may inject: -psn_…, and -NS…/-Apple… value pairs.
        var args: [String] = []
        var i = 0
        while i < arguments.count {
            let a = arguments[i]
            if a.hasPrefix("-psn_") { i += 1; continue }
            if !a.hasPrefix("--"), a.hasPrefix("-NS") || a.hasPrefix("-Apple") { i += 2; continue }
            args.append(a)
            i += 1
        }
        guard let first = args.first else { return nil }

        func number() -> Command {
            guard args.count >= 2, let n = Int(args[1]), n >= 1 else {
                return .invalid("\(first) 뒤에 1 이상의 모니터 번호 하나가 필요합니다.")
            }
            if first == "--focus" {
                return args.count == 2 ? .focus(n) : .invalid("--focus에는 모니터 번호만 필요합니다.")
            }
            if args.count == 2 { return .move(n, pid: nil) }
            guard args.count == 4, args[2] == "--pid", let pid = Int32(args[3]), pid > 0 else {
                return .invalid("사용법: --move N [--pid P]")
            }
            return .move(n, pid: pid)
        }
        func single(_ command: Command) -> Command {
            args.count == 1 ? command : .invalid("\(first)에는 추가 인자가 필요 없습니다: \(args.dropFirst().joined(separator: " "))")
        }
        switch first {
        case "--focus", "--move": return number()
        case "--list": return single(.list)
        case "--list-json": return single(.listJSON)
        case "--identify": return single(.identify)
        case "--check": return single(.check)
        case "--reload": return single(.reload)
        case "--login-item":
            guard args.count == 2, ["on", "off", "status"].contains(args[1]) else {
                return .invalid("--login-item 뒤에 on, off, status 중 하나가 필요합니다.")
            }
            return .loginItem(args[1])
        case "--simulate-hotkey":
            guard args.count == 2, RemoteControl.parseAction(args[1]) != nil else {
                return .invalid("--simulate-hotkey 뒤에 focus.N 또는 move.N이 필요합니다.")
            }
            return .simulateHotkey(args[1])
        case "--set-frame":
            guard args.count == 6, args.dropFirst().allSatisfy({ Double($0) != nil }) else {
                return .invalid("--set-frame 뒤에 창 ID와 X Y W H가 필요합니다.")
            }
            return .setFrame(Array(args.dropFirst()))
        case "--render-settings":
            guard args.count == 2 else { return .invalid("--render-settings 뒤에 저장할 폴더가 필요합니다.") }
            return .renderSettings(args[1])
        case "--help", "-h": return .help
        case "--version", "-v": return .version
        default: return .invalid("알 수 없는 명령: \(args.joined(separator: " "))")
        }
    }

    static func run(_ command: Command) -> Int32 {
        ActionPerformer.shared.isCommandLine = true
        ScreenRegistry.shared.refresh()

        switch command {
        case .help:
            print(usage)
            return 0
        case .invalid(let message):
            FileHandle.standardError.write(Data((message + "\n\n" + usage + "\n").utf8))
            return 2
        case .version:
            print("MonitorHop \(AppInfo.version) (\(AppInfo.build))")
            return 0
        case .list, .listJSON, .check:
            let key = command == .list ? "list" : command == .listJSON ? "list-json" : "check"
            if InstanceLock.isHeldByAnotherProcess {
                // The running app renders it, so the numbers are exactly the ones it uses.
                switch RemoteControl.render(key) {
                case .success(let text):
                    print(text)
                    return 0
                case .failure(let error):
                    FileHandle.standardError.write(Data("실패: \(error.message)\n".utf8))
                    return 1
                }
            }
            // Without NSApplication, NSScreen.visibleFrame ignores the menu bar on secondary displays.
            _ = NSApplication.shared
            ScreenRegistry.shared.refresh()
            print(render(key, insideApp: false))
            return 0
        case .identify:
            if InstanceLock.isHeldByAnotherProcess {
                // Let the running app draw it (no LaunchServices check-in from here).
                return report(RemoteControl.performIdentify())
            }
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            HUD.shared.identify(ScreenRegistry.shared.monitors, duration: 2.5)
            spin(3.0)
            return 0
        case .focus(let n):
            return runAction(ActionID(.focus, n))
        case .move(let n, let pid):
            return runAction(ActionID(.move, n), requiredFrontPID: pid)
        case .loginItem(let mode):
            if mode != "status" {
                do {
                    try LoginItem.setEnabled(mode == "on")
                } catch {
                    FileHandle.standardError.write(Data("실패: \(error.localizedDescription)\n".utf8))
                    return 1
                }
            }
            let status = LoginItem.status
            let label: String
            switch status {
            case .enabled: label = "켜짐"
            case .requiresApproval: label = "승인 필요 (시스템 설정 › 일반 › 로그인 항목)"
            case .notRegistered: label = "꺼짐"
            case .notFound: label = "꺼짐 (등록된 적 없음)"
            @unknown default: label = "알 수 없음 (\(status.rawValue))"
            }
            print("로그인 시 실행: \(label)")
            return 0
        case .simulateHotkey(let key):
            guard InstanceLock.isHeldByAnotherProcess, let action = RemoteControl.parseAction(key) else {
                FileHandle.standardError.write(Data("실패: MonitorHop 앱이 실행 중이어야 합니다.\n".utf8))
                return 1
            }
            return report(RemoteControl.pressShortcut(of: action))
        case .setFrame(let spec):
            guard InstanceLock.isHeldByAnotherProcess else {
                FileHandle.standardError.write(Data("실패: MonitorHop 앱이 실행 중이어야 합니다.\n".utf8))
                return 1
            }
            return report(RemoteControl.setFrame(spec))
        case .renderSettings(let path):
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            ScreenRegistry.shared.refresh()
            let files = DevTools.renderSettings(to: URL(fileURLWithPath: path))
            files.forEach { print($0.path) }
            return files.isEmpty ? 1 : 0
        case .reload:
            guard InstanceLock.isHeldByAnotherProcess else {
                print("앱이 실행 중이 아닙니다. 다음 실행 때 설정을 읽습니다.")
                return 0
            }
            return report(RemoteControl.reloadSettings())
        }
    }

    private static func runAction(_ action: ActionID, requiredFrontPID: pid_t? = nil) -> Int32 {
        if InstanceLock.isHeldByAnotherProcess {
            return report(RemoteControl.perform(action, requiredFrontPID: requiredFrontPID))
        }
        // No app running: do it here (Accessibility is judged for this process's parent app).
        _ = NSApplication.shared // accurate visible frames, HUD available
        ScreenRegistry.shared.refresh()
        let outcome = ActionPerformer.shared.perform(action, requiredFrontPID: requiredFrontPID)
        let code = report(outcome)
        // Success: let the 150/300/500 ms focus check run. Failure: keep the error HUD readable.
        spin(outcome.isSuccess ? 0.6 : 2.5)
        return code
    }

    private static func report(_ outcome: ActionOutcome) -> Int32 {
        print(outcome.isSuccess ? outcome.message : "실패: \(outcome.message)")
        return outcome.isSuccess ? 0 : 1
    }

    private static func report(_ result: Result<ActionOutcome, RemoteControl.SendError>) -> Int32 {
        switch result {
        case .success(let outcome):
            return report(outcome)
        case .failure(let error):
            FileHandle.standardError.write(Data("실패: \(error.message)\n".utf8))
            return 1
        }
    }

    private static func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
    }

    private static func describe(_ r: CGRect) -> String {
        "(\(Int(r.minX)), \(Int(r.minY))) \(Int(r.width))×\(Int(r.height))"
    }

    /// Text for `--list`, `--list-json` or `--check`. `insideApp`: rendered by the running GUI.
    static func render(_ key: String, insideApp: Bool) -> String {
        switch key {
        case "list": return monitorsText()
        case "list-json": return jsonText(insideApp: insideApp)
        default: return checkText(insideApp: insideApp)
        }
    }

    private static func monitorsText() -> String {
        let registry = ScreenRegistry.shared
        let config = SettingsStore.shared.config
        var out = ["모니터 \(registry.monitors.count)대 · 순서: \(config.hasCustomDisplayOrder ? "사용자 지정" : "자동 (왼쪽 → 오른쪽)")"]
        for m in registry.monitors {
            out.append("  \(m.number). \(m.name)\(m.isPrimary ? " [주 모니터]" : "")")
            out.append("     AX 영역 \(describe(m.axFrame))  사용 가능 \(describe(m.axVisibleFrame))  @\(Int(m.scale))x")
            out.append("     id \(m.id)")
            let front = ActionPerformer.shared.visibleWindows(on: m).first
            out.append("     맨 앞 창: \(front.map { "\($0.ownerName) \(describe($0.bounds))" } ?? "없음")")
        }
        return out.joined(separator: "\n")
    }

    private static func jsonText(insideApp: Bool) -> String {
        func rect(_ r: CGRect) -> [Double] { [Double(r.minX), Double(r.minY), Double(r.width), Double(r.height)] }
        let monitors: [[String: Any]] = ScreenRegistry.shared.monitors.map { m in
            [
                "number": m.number, "name": m.name, "id": m.id, "primary": m.isPrimary,
                "axFrame": rect(m.axFrame), "axVisibleFrame": rect(m.axVisibleFrame), "scale": Double(m.scale),
            ]
        }
        var payload: [String: Any] = [
            "version": AppInfo.version,
            "trusted": AccessibilityPermission.isTrusted,
            "appRunning": insideApp,
            "customOrder": SettingsStore.shared.config.hasCustomDisplayOrder,
            "monitors": monitors,
        ]
        if insideApp {
            // Identity of the running app, so scripts can tell which build answered.
            payload["appTrusted"] = AccessibilityPermission.isTrusted
            payload["pid"] = Int(getpid())
            payload["bundlePath"] = Bundle.main.bundlePath
            payload["build"] = AppInfo.build
            payload["devTools"] = DevTools.isEnabled
            if let url = Bundle.main.executableURL,
               let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate {
                payload["executableMTime"] = date.timeIntervalSince1970
            }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    private static func checkText(insideApp: Bool) -> String {
        let config = SettingsStore.shared.config
        var out: [String] = []
        out.append("MonitorHop \(AppInfo.version) (\(AppInfo.build)) · 번들 \(AppInfo.isBundled ? "O" : "X (개발 실행)")")
        out.append("앱 실행 중: \(insideApp ? "예 (--focus/--move는 앱으로 전달)" : "아니오")")
        out.append("접근성 권한\(insideApp ? "(앱)" : "(이 프로세스 기준)"): \(AccessibilityPermission.isTrusted ? "허용됨" : "없음")")
        out.append("창 ID 매핑(_AXUIElementGetWindow): \(AXWindow.canResolveWindowIDs ? "사용 가능" : "없음 → 위치로 매칭")")
        out.append("앱 전환(SetFrontProcessWithOptions): \(AppActivator.hasProcessManager ? "사용 가능" : "없음 → 대체 경로 사용")")
        out.append("로그인 시 실행: \(LoginItem.status == .enabled ? "켜짐" : "꺼짐") (status \(LoginItem.status.rawValue))")
        out.append("")
        out.append(monitorsText())
        out.append("")
        let bindings = config.resolvedBindings
        // Inside the app, report its real registrations; standalone, try registering each one.
        let failures = insideApp ? HotkeyCenter.shared.failures : HotkeyCenter.shared.probe(bindings)
        let system = SystemShortcuts.enabled()
        out.append("단축키 \(bindings.count)개\(insideApp ? " (앱에 등록된 상태)" : ""):")
        for (action, shortcut) in bindings {
            var notes: [String] = []
            if let status = failures[action] { notes.append("macOS가 등록 거부 (\(status))") }
            if SystemShortcuts.isTaken(shortcut, in: system) { notes.append("시스템 단축키와 겹침") }
            if shortcut.validation != .valid { notes.append("권장하지 않는 조합") }
            let name = shortcut.displayString(keyName: KeyNames.name(for:)).padding(toLength: 8, withPad: " ", startingAt: 0)
            out.append("  \(name) \(action.title) — \(notes.isEmpty ? "OK" : notes.joined(separator: ", "))")
        }
        out.append("  ※ 다른 앱이 등록한 전역 단축키와의 충돌은 macOS가 알려 주지 않아 확인할 수 없습니다.")
        return out.joined(separator: "\n")
    }
}
