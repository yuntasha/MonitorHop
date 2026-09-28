import ServiceManagement

/// "Launch at login" through SMAppService (macOS 13+). Only works for the bundled app.
enum LoginItem {
    static var status: SMAppService.Status { SMAppService.mainApp.status }
    static var isEnabled: Bool { status == .enabled }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// Extra explanation for states the user has to act on.
    static var note: String? {
        switch status {
        case .requiresApproval:
            return "시스템 설정 › 일반 › 로그인 항목에서 MonitorHop을 허용해 주세요."
        case .notFound:
            return AppInfo.isBundled ? nil : "앱 번들(MonitorHop.app)로 실행할 때만 설정할 수 있습니다."
        default:
            return nil
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
