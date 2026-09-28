import Foundation
import os

enum AppInfo {
    static let bundleID = "com.alencup.MonitorHop"
    static let name = "MonitorHop"

    static var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
    }

    static var build: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "0"
    }

    /// True when running from the assembled MonitorHop.app bundle.
    static var isBundled: Bool { Bundle.main.bundleIdentifier == bundleID }

    /// Same preferences domain whether launched as an app, from the CLI inside the bundle,
    /// or via `swift run` during development.
    static let defaults: UserDefaults = {
        if Bundle.main.bundleIdentifier == bundleID { return .standard }
        return UserDefaults(suiteName: bundleID) ?? .standard
    }()
}

let logger = Logger(subsystem: AppInfo.bundleID, category: "app")
