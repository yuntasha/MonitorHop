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

    // MARK: - 1. Focus monitor N

    func focusMonitor(_ number: Int) -> ActionOutcome {
        registry.refresh()
        guard let monitor = registry.monitor(number: number) else { return missingMonitor(number) }

        let trusted = AccessibilityPermission.isTrusted
        let windows = WindowFinder.visibleWindows().filter { registry.monitor(forAXRect: $0.bounds)?.id == monitor.id }

        guard let target = findFocusTarget(in: windows, on: monitor, trusted: trusted) else {
            if config.moveCursor { Cursor.warp(to: Geometry.center(of: monitor.axVisibleFrame)) }
            HUD.shared.showNumber(number, detail: "열린 창 없음", on: monitor)
            return .done("\(number)번 모니터에 열린 창이 없어 커서만 옮겼습니다.")
        }

        activate(target)
        if config.moveCursor {
            let visible = target.frame.intersection(monitor.axFrame)
            let point = visible.isNull || visible.isEmpty ? Geometry.center(of: monitor.axVisibleFrame) : Geometry.center(of: visible)
            Cursor.warp(to: Geometry.clamp(point, into: monitor.axFrame))
        }
        if config.showSwitchHUD { HUD.shared.showNumber(number, detail: target.appName, on: monitor) }
        verifyFocus(target)
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

        // Nothing matched exactly: take any usable AX window of those apps on this monitor.
        for info in windows {
            let onMonitor = axWindows(info.pid).first(where: { window in
                guard !window.isMinimized, let frame = window.frame else { return false }
                return registry.monitor(forAXRect: frame)?.id == monitor.id
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

    /// Checks shortly afterwards that the app really became active and retries once if not.
    private func verifyFocus(_ target: FocusTarget) {
        verification?.cancel()
        verification = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            if NSWorkspace.shared.frontmostApplication?.processIdentifier != target.pid {
                logger.info("Focus verification: app not frontmost, retrying")
                target.window?.becomeMain()
                AppActivator.activateFallback(pid: target.pid)
                target.window?.raise()
            } else if let window = target.window, let wanted = window.windowID,
                      let focused = AXWindow.focusedWindow(of: target.pid)?.windowID, focused != wanted {
                logger.info("Focus verification: other window of the app focused, raising target")
                window.becomeMain()
                window.raise()
            }
        }
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
            if config.moveCursor { warpCursor(into: frame, on: target) }
            if config.showSwitchHUD { HUD.shared.showNumber(number, detail: "이미 이 모니터에 있음", on: target) }
            return .done("이미 \(number)번 모니터에 있습니다.")
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
            return .failed("앱이 창 이동을 허용하지 않았습니다.")
        }
        // Windows with a minimum size larger than the target area: keep them on screen.
        if !target.axVisibleFrame.contains(final) {
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
        guard NSApp.isActive, let window = NSApp.keyWindow ?? NSApp.mainWindow,
              window.isVisible, !(window is NSPanel) else { return nil }
        return window
    }

    private func moveOwnWindow(_ window: NSWindow, to target: Monitor) -> ActionOutcome {
        let source = window.screen?.visibleFrame ?? target.visibleFrame
        if window.screen?.displayID == target.displayID {
            return .done("이미 \(target.number)번 모니터에 있습니다.")
        }
        // Cocoa coordinates on both sides: Placement is coordinate-system agnostic.
        let frame = Placement.targetFrame(window: window.frame, source: source, target: target.visibleFrame, mode: config.placement)
        window.setFrame(frame, display: true)
        if config.moveCursor {
            if let primaryHeight = NSScreen.screens.first?.frame.height {
                Cursor.warp(to: Geometry.flip(Geometry.center(of: frame), primaryHeight: primaryHeight))
            }
        }
        return .done("창을 \(target.number)번 모니터로 옮겼습니다.")
    }
}
