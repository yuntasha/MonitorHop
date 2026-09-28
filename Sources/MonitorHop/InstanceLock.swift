import Foundation

/// Guarantees a single GUI instance with an exclusive `flock` held for the process lifetime.
/// The kernel releases the lock when the process exits, even after a crash.
enum InstanceLock {
    private static var descriptor: Int32 = -1

    private static var path: String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent(AppInfo.name, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("gui.lock").path
    }

    /// Takes the GUI lock. Returns false when another GUI instance holds it.
    static func acquire() -> Bool {
        if descriptor >= 0 { return true }
        let fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0o644)
        guard fd >= 0 else { return true } // cannot lock: do not block startup
        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
            descriptor = fd
            return true
        }
        close(fd)
        return false
    }

    /// True when a GUI instance is running (used by the CLI to forward commands).
    static var isHeldByAnotherProcess: Bool {
        let fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0o644)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
            flock(fd, LOCK_UN)
            return false
        }
        return true
    }
}
