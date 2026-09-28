import AppKit
import MonitorHopCore

/// Command-line mode: `MonitorHop.app/Contents/MacOS/MonitorHop --list` etc.
/// Handy for scripts (Raycast, Shortcuts, skhd) and for diagnosing problems.
@MainActor
enum CLI {
    enum Command: Equatable {
        case list, listJSON, focus(Int), move(Int), identify, check, help, version, invalid(String)
    }

    static let usage = """
    MonitorHop — 모니터 단위 포커스/창 이동

    사용법: MonitorHop [명령]
      (명령 없음)        메뉴 막대 앱으로 실행
      --list             연결된 모니터를 번호 순서대로 표시
      --list-json        위 정보를 JSON으로 출력 (스크립트용)
      --focus N          N번 모니터로 포커스 이동
      --move N           현재 포커스된 창을 N번 모니터로 보내기
      --identify         각 모니터에 번호 표시
      --check            권한·단축키·API 상태 진단
      --version          버전 표시
      --help             이 도움말
    """

    /// Returns nil when the app should start normally (no recognised command).
    static func parse(_ arguments: [String]) -> Command? {
        guard let first = arguments.first, first.hasPrefix("-") else { return nil }
        func number() -> Command {
            guard arguments.count > 1, let n = Int(arguments[1]), n >= 1 else {
                return .invalid("\(first) 뒤에 1 이상의 모니터 번호가 필요합니다.")
            }
            return first == "--focus" ? .focus(n) : .move(n)
        }
        switch first {
        case "--list": return .list
        case "--list-json": return .listJSON
        case "--focus", "--move": return number()
        case "--identify": return .identify
        case "--check": return .check
        case "--help", "-h": return .help
        case "--version": return .version
        default:
            // Unknown flags (e.g. -NSDocumentRevisionsDebugMode, -psn_...) start the app.
            return first.hasPrefix("--") ? .invalid("알 수 없는 명령: \(first)") : nil
        }
    }

    static func run(_ command: Command) -> Int32 {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        ActionPerformer.shared.isCommandLine = true
        let registry = ScreenRegistry.shared
        registry.refresh()

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
        case .list:
            printMonitors()
            return 0
        case .listJSON:
            printJSON()
            return 0
        case .identify:
            HUD.shared.identify(registry.monitors, duration: 2.5)
            spin(3.0)
            return 0
        case .focus(let n):
            return report(ActionPerformer.shared.perform(ActionID(.focus, n)))
        case .move(let n):
            return report(ActionPerformer.shared.perform(ActionID(.move, n)))
        case .check:
            return check()
        }
    }

    private static func report(_ outcome: ActionOutcome) -> Int32 {
        print(outcome.isSuccess ? outcome.message : "실패: \(outcome.message)")
        spin(outcome.isSuccess ? 0.6 : 2.4) // let focus verification / HUD run
        return outcome.isSuccess ? 0 : 1
    }

    private static func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
    }

    private static func describe(_ r: CGRect) -> String {
        "(\(Int(r.minX)), \(Int(r.minY))) \(Int(r.width))×\(Int(r.height))"
    }

    private static func printMonitors() {
        let registry = ScreenRegistry.shared
        let config = SettingsStore.shared.config
        let windows = WindowFinder.visibleWindows()
        print("모니터 \(registry.monitors.count)대 · 순서: \(config.hasCustomDisplayOrder ? "사용자 지정" : "자동 (왼쪽 → 오른쪽)")")
        for m in registry.monitors {
            print("  \(m.number). \(m.name)\(m.isPrimary ? " [주 모니터]" : "")")
            print("     AX 영역 \(describe(m.axFrame))  사용 가능 \(describe(m.axVisibleFrame))  @\(Int(m.scale))x")
            print("     id \(m.id)")
            let front = windows.first { registry.monitor(forAXRect: $0.bounds)?.id == m.id }
            print("     맨 앞 창: \(front.map { "\($0.ownerName) \(describe($0.bounds))" } ?? "없음")")
        }
    }

    private static func printJSON() {
        func rect(_ r: CGRect) -> [Double] { [Double(r.minX), Double(r.minY), Double(r.width), Double(r.height)] }
        let monitors: [[String: Any]] = ScreenRegistry.shared.monitors.map { m in
            [
                "number": m.number, "name": m.name, "id": m.id, "primary": m.isPrimary,
                "axFrame": rect(m.axFrame), "axVisibleFrame": rect(m.axVisibleFrame), "scale": Double(m.scale),
            ]
        }
        let payload: [String: Any] = [
            "version": AppInfo.version,
            "trusted": AccessibilityPermission.isTrusted,
            "customOrder": SettingsStore.shared.config.hasCustomDisplayOrder,
            "monitors": monitors,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            print(text)
        }
    }

    private static func check() -> Int32 {
        let config = SettingsStore.shared.config
        print("MonitorHop \(AppInfo.version) (\(AppInfo.build)) · 번들 \(AppInfo.isBundled ? "O" : "X (개발 실행)")")
        print("접근성 권한: \(AccessibilityPermission.isTrusted ? "허용됨" : "없음 (이 프로세스 기준)")")
        print("창 ID 매핑(_AXUIElementGetWindow): \(AXWindow.canResolveWindowIDs ? "사용 가능" : "없음 → 위치로 매칭")")
        print("앱 전환(SetFrontProcessWithOptions): \(AppActivator.hasProcessManager ? "사용 가능" : "없음 → 대체 경로 사용")")
        print("로그인 시 실행: \(LoginItem.status == .enabled ? "켜짐" : "꺼짐") (status \(LoginItem.status.rawValue))")
        print("")
        printMonitors()
        print("")
        let bindings = config.resolvedBindings
        let failures = HotkeyCenter.shared.probe(bindings)
        let appRunning = NSRunningApplication.runningApplications(withBundleIdentifier: AppInfo.bundleID)
            .contains { $0.processIdentifier != getpid() }
        print("단축키 \(bindings.count)개:")
        for (action, shortcut) in bindings {
            let status = failures[action].map { "등록 불가 (\($0))" } ?? "OK"
            print("  \(shortcut.displayString(keyName: KeyNames.name(for:)).padding(toLength: 8, withPad: " ", startingAt: 0)) \(action.title) — \(status)")
        }
        if !failures.isEmpty && appRunning {
            print("  ※ MonitorHop 앱이 실행 중이면 앱이 이미 등록한 단축키는 여기서 ‘등록 불가’로 보입니다.")
        }
        return 0
    }
}
