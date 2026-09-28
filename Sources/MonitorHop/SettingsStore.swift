import Combine
import Foundation
import MonitorHopCore

/// Owns the persisted `AppConfig`. All mutations go through here so they are saved.
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    private static let storageKey = "config.v1"

    @Published private(set) var config: AppConfig
    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppInfo.defaults) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(AppConfig.self, from: data) {
            config = decoded
        } else {
            config = .default
        }
    }

    func update(_ change: (inout AppConfig) -> Void) {
        var next = config
        change(&next)
        guard next != config else { return }
        config = next
        persist()
    }

    private func persist() {
        do {
            defaults.set(try JSONEncoder().encode(config), forKey: Self.storageKey)
        } catch {
            logger.error("Failed to save settings: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Assigns (or clears, with nil) the shortcut of `action`.
    /// Returns a user-facing error message when the shortcut is rejected.
    @discardableResult
    func setShortcut(_ shortcut: Shortcut?, for action: ActionID) -> String? {
        guard let shortcut else {
            update { $0.bindings[action.key] = nil }
            return nil
        }
        guard shortcut.validation == .valid else {
            return "⌘ · ⌃ · ⌥ 중 하나 이상과 함께 눌러 주세요. (F1–F20은 단독 사용 가능)"
        }
        if let other = config.action(using: shortcut, excluding: action) {
            return "\(shortcut.displayString(keyName: KeyNames.name(for:)))은(는) 이미 ‘\(other.title)’에 쓰이고 있습니다."
        }
        update { $0.bindings[action.key] = shortcut }
        return nil
    }

    func resetShortcuts() {
        update { $0.bindings = AppConfig.defaultBindings }
    }

    /// Saves a new order for the currently connected monitors (display keys, first = monitor 1).
    func setDisplayOrder(connected keys: [String]) {
        update { $0.setDisplayOrder(connected: keys) }
    }

    func resetDisplayOrder() {
        update { $0.resetDisplayOrder() }
    }

    func resetAll() {
        update { $0 = .default }
    }
}

extension ActionID {
    /// User-facing name, e.g. "2번 모니터로 포커스 이동".
    var title: String {
        switch kind {
        case .focus: return "\(slot)번 모니터로 포커스 이동"
        case .move: return "현재 창을 \(slot)번 모니터로 보내기"
        }
    }
}

extension PlacementMode {
    var title: String {
        switch self {
        case .keepSize: return "크기 유지"
        case .proportional: return "비율 맞춤"
        case .center: return "가운데 배치"
        case .fill: return "화면 채우기"
        }
    }

    var detail: String {
        switch self {
        case .keepSize:
            return "창 크기를 그대로 두고 화면 안의 상대 위치를 유지합니다. 최대화된 창은 새 모니터에서도 가득 찹니다."
        case .proportional:
            return "모니터 크기 비율에 맞춰 창의 위치와 크기를 함께 늘리거나 줄입니다."
        case .center:
            return "창 크기를 유지하고 새 모니터의 가운데에 놓습니다."
        case .fill:
            return "새 모니터의 사용 가능한 영역을 가득 채웁니다."
        }
    }
}
