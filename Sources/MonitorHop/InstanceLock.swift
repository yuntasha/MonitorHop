import AppKit

/// Guarantees a single GUI instance with an exclusive `flock` held for the process lifetime.
/// The kernel releases the lock when the process exits, even after a crash.
enum InstanceLock {
    private static var descriptor: Int32 = -1

    private static var path: String? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = base.appendingPathComponent(AppInfo.name, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("gui.lock").path
    }

    private enum LockResult { case locked, heldByOther, unavailable }

    private static func tryLock(_ fd: Int32) -> LockResult {
        if flock(fd, LOCK_EX | LOCK_NB) == 0 { return .locked }
        return errno == EWOULDBLOCK ? .heldByOther : .unavailable
    }

    /// Takes the GUI lock. Returns false when another GUI instance holds it.
    static func acquire() -> Bool {
        if descriptor >= 0 { return true }
        guard let path else { return !otherGUIRunning() }
        let fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0o644)
        guard fd >= 0 else {
            logger.error("Instance lock unavailable (open errno \(errno)); falling back to process list")
            return !otherGUIRunning()
        }
        // A CLI probe holds the lock for microseconds, a GUI forever: retry briefly.
        for attempt in 0..<10 {
            switch tryLock(fd) {
            case .locked:
                descriptor = fd
                return true
            case .unavailable:
                close(fd)
                logger.error("Instance lock unavailable (flock errno \(errno)); falling back to process list")
                return !otherGUIRunning()
            case .heldByOther:
                if attempt < 9 { usleep(20_000) }
            }
        }
        close(fd)
        return false
    }

    /// True when a GUI instance is running (used by the CLI to forward commands).
    static var isHeldByAnotherProcess: Bool {
        guard let path else { return otherGUIRunning() }
        let fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0o644)
        guard fd >= 0 else { return otherGUIRunning() }
        defer { close(fd) }
        switch tryLock(fd) {
        case .locked:
            flock(fd, LOCK_UN)
            return false
        case .heldByOther:
            return true
        case .unavailable:
            return otherGUIRunning()
        }
    }

    /// Fallback when locking is impossible (e.g. network home without flock support).
    private static func otherGUIRunning() -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: AppInfo.bundleID)
            .contains { $0.processIdentifier != getpid() && !$0.isTerminated && $0.isFinishedLaunching }
    }
}
