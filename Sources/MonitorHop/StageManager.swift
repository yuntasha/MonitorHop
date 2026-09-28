import Foundation

enum StageManager {
    /// Whether Stage Manager is turned on (System Settings › Desktop & Dock).
    static var isEnabled: Bool {
        UserDefaults(suiteName: "com.apple.WindowManager")?.bool(forKey: "GloballyEnabled") ?? false
    }
}
