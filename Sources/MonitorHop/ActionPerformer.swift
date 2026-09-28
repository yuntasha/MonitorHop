import AppKit
import MonitorHopCore

enum ActionOutcome: Equatable {
    case done(String)
    case failed(String)

    var message: String {
        switch self {
        case .done(let m), .failed(let m): return m
        }
    }

    var isSuccess: Bool {
        if case .done = self { return true }
        return false
    }
}

/// Where keyboard focus should go on a monitor.
private struct FocusTarget {
    let pid: pid_t
    let window: AXWindow?
    let frame: CGRect
    let appName: String
}

/// Implements the two MonitorHop actions.
@MainActor
final class ActionPerformer {
    static let shared = ActionPerformer()

    private let registry = ScreenRegistry.shared
    private var config: AppConfig { SettingsStore.shared.config }
    private var verification: Task<Void, Never>?
    /// Set by the CLI: never open windows, just report.
    var isCommandLine = false

    @discardableResult
    func perform(_ action: ActionID) -> ActionOutcome {
        // A new action supersedes the focus check of the previous one.
        verification?.cancel()
        verification = nil

        let outcome: ActionOutcome
        switch action.kind {
        case .focus: outcome = focusMonitor(action.slot)
        case .move: outcome = moveFocusedWindow(toMonitor: action.slot)
        }
        switch outcome {
        case .done(let message):
            logger.info("\(action.key, privacy: .public): \(message, privacy: .public)")
        case .failed(let message):
            logger.error("\(action.key, privacy: .public) failed: \(message, privacy: .public)")
            HUD.shared.showMessage(message, on: registry.monitor(number: action.slot) ?? registry.monitorUnderCursor)
        }
        return outcome
    }

    private func missingMonitor(_ number: Int) -> ActionOutcome {
        .failed("\(number)번 모니터가 없습니다. (연결된 모니터 \(registry.monitors.count)대)")
    }

    /// Windows the user can actually see on `monitor`, front to back.
    /// A window counts when its center is on the monitor, or when a real part of it (at least
    /// 40×40 pt) is visible there — windows parked off-screen or in a corner never count.
    func visibleWindows(on monitor: Monitor, includeOwn: Bool = false) -> [WindowInfo] {
        WindowFinder.visibleWindows(includeOwn: includeOwn).filter { isVisible($0.bounds, on: monitor) }
    }

    private func isVisible(_ bounds: CGRect, on monitor: Monitor) -> Bool {
        guard registry.monitor(forAXRect: bounds)?.id == monitor.id else { return false }
        if Geometry.contains(monitor.axFrame, Geometry.center(of: bounds)) { return true }
        let visible = bounds.intersection(monitor.axFrame)
        return !visible.isNull && visible.width >= 40 && visible.height >= 40
    }

    // MARK: - 1. Focus monitor N

    func focusMonitor(_ number: Int) -> ActionOutcome {
        registry.refresh()
        guard let monitor = registry.monitor(number: number) else { return missingMonitor(number) }

        let trusted = AccessibilityPermission.isTrusted
        let windows = visibleWindows(on: monitor, includeOwn: !isCommandLine)

        // MonitorHop's own window (Settings) in front: focus it with AppKit, never AX on ourselves.
        if let first = windows.first, first.pid == getpid() {
            return focusOwnWindow(first, on: monitor, number: number)
        }

        let others = windows.filter { $0.pid != getpid() }
        guard let target = findFocusTarget(in: others, on: monitor, trusted: trusted) else {
            if config.moveCursor { Cursor.warp(to: Geometry.center(of: monitor.axVisibleFrame)) }
            HUD.shared.showNumber(number, detail: "열린 창 없음", on: monitor)
            return .done("\(number)번 모니터에 열린 창이 없어 커서만 옮겼습니다.")
        }

        // Without a concrete AX window we can only activate the app. If that app is already
        // frontmost with its key window on another monitor, activation changes nothing.
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if target.window == nil, frontPID == target.pid,
           let appFront = WindowFinder.visibleWindows().first(where: { $0.pid == target.pid }),
           !isVisible(appFront.bounds, on: monitor) {
            if !trusted && !isCommandLine { PermissionWindowController.shared.show() }
            return .failed(trusted
                ? "\(target.appName)의 \(number)번 모니터 창에 포커스를 줄 수 없습니다."
                : "같은 앱의 다른 모니터 창으로 옮기려면 접근성 권한이 필요합니다.")
        }

        let staleWindowID = trusted ? AXWindow.focusedWindow(of: target.pid)?.windowID : nil
        activate(target)
        if config.moveCursor {
            let visible = target.frame.intersection(monitor.axFrame)
            let point = visible.isNull || visible.isEmpty ? Geometry.center(of: monitor.axVisibleFrame) : Geometry.center(of: visible)
            Cursor.warp(to: Geometry.clamp(point, into: monitor.axFrame))
        }
        if config.showSwitchHUD { HUD.shared.showNumber(number, detail: target.appName, on: monitor) }
        verifyFocus(target, previousFront: frontPID, staleWindowID: staleWindowID, on: monitor)
        let permissionNote = trusted ? "" : " (접근성 권한이 없어 앱 단위로 전환했습니다)"
        return .done("\(number)번 모니터: \(target.appName)\(permissionNote)")
    }

    /// Picks the front-most window on the monitor that can actually take focus.
    private func findFocusTarget(in windows: [WindowInfo], on monitor: Monitor, trusted: Bool) -> FocusTarget? {
        guard let first = windows.first else { return nil }
        guard trusted else {
            return FocusTarget(pid: first.pid, window: nil, frame: first.bounds, appName: first.ownerName)
        }

        var cache: [pid_t: [AXWindow]] = [:]
        func axWindows(_ pid: pid_t) -> [AXWindow] {
            if let cached = cache[pid] { return cached }
            let list = AXWindow.windows(of: pid)
            cache[pid] = list
            return list
        }

        // Front to back: the first window-server window that maps to a real AX window wins.
        // Auxiliary windows (tab-bar strips, overlays) have no AX window and are skipped.
        for info in windows {
            let candidates = axWindows(info.pid)
            let match = candidates.first(where: { $0.windowID == info.windowID })
                ?? candidates.first(where: { window in
                    window.frame.map { Geometry.approximatelyEqual($0, info.bounds, tolerance: 2) } ?? false
                })
            if let match, !match.isMinimized {
                return FocusTarget(pid: info.pid, window: match, frame: match.frame ?? info.bounds, appName: info.ownerName)
            }
        }

        // Nothing matched exactly: take any usable AX window of those apps visible on this monitor.
        for info in windows {
            let onMonitor = axWindows(info.pid).first(where: { window in
                guard !window.isMinimized, let frame = window.frame else { return false }
                return isVisible(frame, on: monitor)
            })
            if let onMonitor {
                return FocusTarget(pid: info.pid, window: onMonitor, frame: onMonitor.frame ?? info.bounds, appName: info.ownerName)
            }
        }
        return FocusTarget(pid: first.pid, window: nil, frame: first.bounds, appName: first.ownerName)
    }

    /// Layered activation: every step is best effort, later steps cover failures of earlier ones.
    private func activate(_ target: FocusTarget) {
        target.window?.becomeMain()                     // make it the app's main/key window
        let broughtToFront = AppActivator.bringToFront(pid: target.pid) // activate app, front window only
        target.window?.raise()                          // put the chosen window on top
        if !broughtToFront { AppActivator.activateFallback(pid: target.pid) }
    }

    /// Re-checks at 150 / 300 / 500 ms that the target really got focus and repairs it if not —
    /// but only while nothing else changed focus in the meantime (the user may have switched on
    /// purpose, or the app opened a new window).
    private func verifyFocus(_ target: FocusTarget, previousFront: pid_t?, staleWindowID: CGWindowID?, on monitor: Monitor) {
        verification?.cancel()
        verification = Task { @MainActor [weak self] in
            for delay: UInt64 in [150, 150, 200] {
                try? await Task.sleep(nanoseconds: delay * 1_000_000)
                guard !Task.isCancelled, let self else { return }

                let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
                if front != target.pid {
                    // Activation did not happen yet. Retry only if the old app is still in front.
                    guard front == previousFront else { return }
                    logger.info("Focus check: app not frontmost yet, retrying")
                    target.window?.becomeMain()
                    if !AppActivator.bringToFront(pid: target.pid) { AppActivator.activateFallback(pid: target.pid) }
                    target.window?.raise()
                    continue
                }

                guard let window = target.window, let wanted = window.windowID,
                      let focused = AXWindow.focusedWindow(of: target.pid), let focusedID = focused.windowID else { return }
                if focusedID == wanted { return }
                let focusedElsewhere = focused.frame.map { !self.isVisible($0, on: monitor) } ?? false
                guard focusedID == staleWindowID || focusedElsewhere else { return }
                logger.info("Focus check: another window of the app has focus, raising target")
                window.becomeMain()
                window.raise()
            }
        }
    }

    private func focusOwnWindow(_ info: WindowInfo, on monitor: Monitor, number: Int) -> ActionOutcome {
        guard let window = NSApp.windows.first(where: { $0.windowNumber == Int(info.windowID) }) else {
            return .failed("MonitorHop 창을 찾지 못했습니다.")
        }
        AppActivator.bringToFront(pid: getpid())
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if config.moveCursor { warpCursor(into: info.bounds, on: monitor) }
        if config.showSwitchHUD { HUD.shared.showNumber(number, detail: AppInfo.name, on: monitor) }
        return .done("\(number)번 모니터: \(AppInfo.name)")
    }

    // MARK: - 2. Move the focused window to monitor N

    func moveFocusedWindow(toMonitor number: Int) -> ActionOutcome {
        registry.refresh()
        guard let target = registry.monitor(number: number) else { return missingMonitor(number) }

        if let own = ownFrontWindow() { return moveOwnWindow(own, to: target) }

        guard AccessibilityPermission.isTrusted else {
            if !isCommandLine { PermissionWindowController.shared.show() }
            return .failed("창을 옮기려면 접근성 권한이 필요합니다.")
        }
        guard let window = focusedWindow() else { return .failed("옮길 창을 찾지 못했습니다.") }
        if window.isFullScreen { return .failed("전체 화면 창은 옮길 수 없습니다. 전체 화면을 먼저 끄세요.") }
        guard let frame = window.frame else { return .failed("창의 위치를 읽을 수 없습니다.") }
        guard window.canMove else { return .failed("이 창은 위치를 바꿀 수 없습니다.") }
        guard let source = registry.monitor(forAXRect: frame) else { return .failed("창이 있는 모니터를 찾지 못했습니다.") }

        if source.id == target.id {
            return pullIntoMonitor(window, frame: frame, monitor: target, number: number)
        }

        let desired = Placement.targetFrame(
            window: frame, source: source.axVisibleFrame, target: target.axVisibleFrame, mode: config.placement
        )
        var actual = window.setFrame(desired)
        if !landed(actual, on: target) {
            // Some apps (Electron, Java) apply geometry asynchronously; give them a moment.
            usleep(80_000)
            actual = window.frame
            if !landed(actual, on: target) { actual = window.setFrame(desired) }
        }
        guard var final = actual, landed(final, on: target) else {
            // Leave no side effects: undo a resize the app accepted while it refused the move.
            if let now = window.frame, !Geometry.approximatelyEqual(now, frame, tolerance: 1) {
                window.setFrame(frame)
            }
            return .failed("앱이 창 이동을 허용하지 않았습니다.")
        }
        // Windows with a minimum size larger than the target area: keep them on screen.
        if !target.axVisibleFrame.insetBy(dx: -1, dy: -1).contains(final) {
            let fixed = Placement.reposition(final, into: target.axVisibleFrame)
            if fixed.origin != final.origin {
                window.setPosition(fixed.origin)
                final = window.frame ?? fixed
            }
        }

        window.becomeMain()
        window.raise()
        AppActivator.bringToFront(pid: window.pid)
        if config.moveCursor { warpCursor(into: final, on: target) }
        if config.showSwitchHUD { HUD.shared.showNumber(number, detail: "창을 옮겼습니다", on: target) }
        return .done("창을 \(number)번 모니터로 옮겼습니다.")
    }

    /// "Move to the monitor it is already on": pull a window that sticks out fully onto it.
    private func pullIntoMonitor(_ window: AXWindow, frame: CGRect, monitor: Monitor, number: Int) -> ActionOutcome {
        var final = frame
        let sticksOut = !monitor.axVisibleFrame.insetBy(dx: -1, dy: -1).contains(frame)
        if sticksOut {
            if window.canResize {
                final = window.setFrame(Placement.clamp(frame, into: monitor.axVisibleFrame)) ?? frame
            } else {
                window.setPosition(Placement.reposition(frame, into: monitor.axVisibleFrame).origin)
                final = window.frame ?? frame
            }
        }
        if config.moveCursor { warpCursor(into: final, on: monitor) }
        if config.showSwitchHUD {
            HUD.shared.showNumber(number, detail: sticksOut ? "화면 안으로 옮겼습니다" : "이미 이 모니터에 있음", on: monitor)
        }
        return .done(sticksOut ? "창을 \(number)번 모니터 안으로 옮겼습니다." : "이미 \(number)번 모니터에 있습니다.")
    }

    private func landed(_ frame: CGRect?, on monitor: Monitor) -> Bool {
        guard let frame else { return false }
        return registry.monitor(forAXRect: frame)?.id == monitor.id
    }

    private func warpCursor(into frame: CGRect, on monitor: Monitor) {
        let visible = frame.intersection(monitor.axFrame)
        let point = visible.isNull || visible.isEmpty ? Geometry.center(of: monitor.axVisibleFrame) : Geometry.center(of: visible)
        Cursor.warp(to: point)
    }

    /// The window that currently has keyboard focus (in another app).
    private func focusedWindow() -> AXWindow? {
        if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() {
            let pid = app.processIdentifier
            if let window = AXWindow.focusedWindow(of: pid), window.frame != nil { return window }
            // Some apps do not report a focused window; use their front-most on-screen window.
            if let info = WindowFinder.visibleWindows().first(where: { $0.pid == pid }) {
                let windows = AXWindow.windows(of: pid)
                if let match = windows.first(where: { $0.windowID == info.windowID })
                    ?? windows.first(where: { w in w.frame.map { Geometry.approximatelyEqual($0, info.bounds, tolerance: 2) } ?? false }) {
                    return match
                }
            }
        }
        return AXWindow.systemFocusedWindow()
    }

    // MARK: Own windows (e.g. the settings window) — moved with AppKit, never via AX on ourselves.

    private func ownFrontWindow() -> NSWindow? {
        guard let app = NSApp, app.isActive, let window = app.keyWindow ?? app.mainWindow,
              window.isVisible, !(window is NSPanel) else { return nil }
        return window
    }

    private func moveOwnWindow(_ window: NSWindow, to target: Monitor) -> ActionOutcome {
        if window.screen?.displayID == target.displayID {
            return .done("이미 \(target.number)번 모니터에 있습니다.")
        }
        let source = window.screen?.visibleFrame ?? target.visibleFrame
        // Fixed-size windows snap back to their content size, so never ask them to grow.
        var mode = config.placement
        if !window.styleMask.contains(.resizable), mode == .fill || mode == .proportional { mode = .keepSize }
        // Cocoa coordinates on both sides: Placement is coordinate-system agnostic.
        let frame = Placement.targetFrame(window: window.frame, source: source, target: target.visibleFrame, mode: mode)
        window.setFrame(frame, display: true)
        if config.moveCursor, let primaryHeight = NSScreen.screens.first?.frame.height {
            Cursor.warp(to: Geometry.flip(Geometry.center(of: frame), primaryHeight: primaryHeight))
        }
        if config.showSwitchHUD { HUD.shared.showNumber(target.number, detail: "창을 옮겼습니다", on: target) }
        return .done("창을 \(target.number)번 모니터로 옮겼습니다.")
    }
}
