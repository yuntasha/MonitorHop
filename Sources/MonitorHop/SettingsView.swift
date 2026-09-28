import AppKit
import SwiftUI
import MonitorHopCore

enum SettingsTab: Hashable {
    case shortcuts, monitors, general
}

@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var tab: SettingsTab = .shortcuts
}

struct SettingsView: View {
    @ObservedObject var navigation: SettingsNavigation

    var body: some View {
        TabView(selection: $navigation.tab) {
            ShortcutsSettingsView()
                .tabItem { Label("단축키", systemImage: "keyboard") }
                .tag(SettingsTab.shortcuts)
            MonitorsSettingsView()
                .tabItem { Label("모니터", systemImage: "display.2") }
                .tag(SettingsTab.monitors)
            GeneralSettingsView()
                .tabItem { Label("일반", systemImage: "gearshape") }
                .tag(SettingsTab.general)
        }
        .frame(width: 620, height: 600)
    }
}

// MARK: - Shortcuts

struct ShortcutsSettingsView: View {
    @ObservedObject private var store = SettingsStore.shared
    @ObservedObject private var registry = ScreenRegistry.shared
    @State private var showAllSlots = false

    private var visibleSlots: [Int] {
        if showAllSlots { return Array(AppConfig.slots) }
        let bound = store.config.resolvedBindings.map(\.0.slot).max() ?? 0
        let count = max(registry.monitors.count, bound, AppConfig.defaultBoundSlots.upperBound)
        return Array(AppConfig.slots.lowerBound...min(count, AppConfig.slots.upperBound))
    }

    var body: some View {
        Form {
            Section {
                ForEach(visibleSlots, id: \.self) { slot in
                    ShortcutRow(action: ActionID(.focus, slot))
                }
            } header: {
                Text("N번 모니터로 포커스 이동")
            } footer: {
                Text("그 모니터에서 가장 앞에 있는 창을 활성화하고 커서를 옮깁니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                ForEach(visibleSlots, id: \.self) { slot in
                    ShortcutRow(action: ActionID(.move, slot))
                }
            } header: {
                Text("현재 창을 N번 모니터로 보내기")
            } footer: {
                Text("지금 포커스된 창을 그 모니터로 옮깁니다. 배치 방식은 ‘일반’ 탭에서 고릅니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("5–9번 모니터 단축키도 표시", isOn: $showAllSlots)
                HStack(alignment: .firstTextBaseline) {
                    Text("버튼을 누른 뒤 원하는 키 조합을 입력하세요. Esc는 취소, ⌫는 지우기입니다.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("기본값으로 복원") { store.resetShortcuts() }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct ShortcutRow: View {
    let action: ActionID
    @ObservedObject private var store = SettingsStore.shared
    @ObservedObject private var registry = ScreenRegistry.shared
    @ObservedObject private var hotkeys = HotkeyCenter.shared
    @State private var message: String?

    var body: some View {
        let monitor = registry.monitor(number: action.slot)
        let shortcut = store.config.shortcut(for: action)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                NumberBadge(number: action.slot, active: monitor != nil)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(action.slot)번 모니터")
                    Text(monitor?.name ?? "연결 안 됨")
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if hotkeys.failures[action] != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .help("다른 앱이 이미 이 단축키를 쓰고 있어 등록하지 못했습니다. 다른 조합을 지정하세요.")
                }
                ShortcutRecorder(
                    shortcut: shortcut,
                    onChange: { newValue in message = store.setShortcut(newValue, for: action) },
                    onMessage: { message = $0 }
                )
                .frame(width: 150)
                Button {
                    message = store.setShortcut(nil, for: action)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .disabled(shortcut == nil)
                .help("단축키 지우기")
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.red)
            }
        }
        .task(id: message) {
            guard message != nil else { return }
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            message = nil
        }
    }
}

struct NumberBadge: View {
    let number: Int
    var active = true
    var size: CGFloat = 22

    var body: some View {
        Text("\(number)")
            .font(.system(size: size * 0.55, weight: .bold, design: .rounded))
            .foregroundStyle(active ? Color.white : Color.secondary)
            .frame(width: size, height: size)
            .background(Circle().fill(active ? Color.accentColor : Color.secondary.opacity(0.2)))
    }
}

// MARK: - Monitors (order)

struct MonitorsSettingsView: View {
    @ObservedObject private var store = SettingsStore.shared
    @ObservedObject private var registry = ScreenRegistry.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("모니터 번호 순서").font(.headline)
            Text("목록의 위에서부터 1번, 2번, 3번… 모니터가 됩니다. 행을 드래그하거나 화살표 버튼으로 순서를 바꾸세요.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List {
                ForEach(registry.monitors) { monitor in
                    MonitorRow(monitor: monitor, count: registry.monitors.count, move: move)
                }
                .onMove { source, destination in
                    var keys = registry.monitors.map(\.id)
                    keys.move(fromOffsets: source, toOffset: destination)
                    store.setDisplayOrder(connected: keys)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .frame(minHeight: 220)

            HStack {
                Button {
                    HUD.shared.identify(registry.monitors)
                } label: {
                    Label("모니터 번호 보기", systemImage: "number.circle")
                }
                Button {
                    store.resetDisplayOrder()
                } label: {
                    Label("왼쪽부터 자동 정렬", systemImage: "arrow.left.arrow.right")
                }
                .disabled(!store.config.hasCustomDisplayOrder)
                Spacer()
                Text(store.config.hasCustomDisplayOrder ? "사용자 지정 순서" : "자동 정렬 (왼쪽 → 오른쪽)")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Text("연결을 해제한 모니터의 순서도 기억해 두었다가 다시 연결하면 그대로 복원합니다.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .onAppear { registry.refresh() }
    }

    private func move(_ monitor: Monitor, by offset: Int) {
        let keys = registry.monitors.map(\.id)
        guard let index = keys.firstIndex(of: monitor.id) else { return }
        store.setDisplayOrder(connected: DisplayOrdering.move(keys, from: index, to: index + offset))
    }
}

struct MonitorRow: View {
    let monitor: Monitor
    let count: Int
    let move: (Monitor, Int) -> Void

    var body: some View {
        HStack(spacing: 12) {
            NumberBadge(number: monitor.number, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(monitor.name).font(.body.weight(.medium)).lineLimit(1)
                    if monitor.isPrimary {
                        Text("주 모니터")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                    }
                }
                Text("\(Int(monitor.frame.width)) × \(Int(monitor.frame.height)) · @\(Int(monitor.scale))x")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { move(monitor, -1) } label: { Image(systemName: "chevron.up") }
                .disabled(monitor.number == 1)
                .help("앞으로 (번호 줄이기)")
            Button { move(monitor, 1) } label: { Image(systemName: "chevron.down") }
                .disabled(monitor.number == count)
                .help("뒤로 (번호 늘리기)")
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 4)
    }
}

// MARK: - General

@MainActor
final class SystemStatusModel: ObservableObject {
    @Published var trusted = AccessibilityPermission.isTrusted
    @Published var loginEnabled = LoginItem.isEnabled
    @Published var loginNote: String? = LoginItem.note
    private var poll: Task<Void, Never>?

    func start() {
        refresh()
        poll?.cancel()
        poll = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard let self else { return }
                self.refresh()
            }
        }
    }

    func stop() {
        poll?.cancel()
        poll = nil
    }

    func refresh() {
        let trustedNow = AccessibilityPermission.isTrusted
        if trustedNow != trusted { trusted = trustedNow }
        let loginNow = LoginItem.isEnabled
        if loginNow != loginEnabled { loginEnabled = loginNow }
    }

    func setLogin(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
            loginNote = LoginItem.note
        } catch {
            loginNote = "변경하지 못했습니다: \(error.localizedDescription)"
        }
        loginEnabled = LoginItem.isEnabled
    }
}

struct GeneralSettingsView: View {
    @ObservedObject private var store = SettingsStore.shared
    @StateObject private var system = SystemStatusModel()
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section("창 보내기") {
                Picker("배치 방식", selection: binding(\.placement)) {
                    ForEach(PlacementMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Text(store.config.placement.detail)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("동작") {
                Toggle("포커스·창 이동 후 마우스 커서도 함께 옮기기", isOn: binding(\.moveCursor))
                Toggle("전환할 때 모니터 번호를 잠깐 표시", isOn: binding(\.showSwitchHUD))
            }

            Section("시스템") {
                Toggle("로그인할 때 자동으로 실행", isOn: Binding(
                    get: { system.loginEnabled },
                    set: { system.setLogin($0) }
                ))
                .disabled(!AppInfo.isBundled)
                if let note = system.loginNote {
                    HStack {
                        Text(note).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if LoginItem.status == .requiresApproval {
                            Button("로그인 항목 열기") { LoginItem.openSystemSettings() }
                        }
                    }
                }
                HStack {
                    Label(system.trusted ? "접근성 권한 허용됨" : "접근성 권한 필요",
                          systemImage: system.trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(system.trusted ? Color.green : Color.orange)
                    Spacer()
                    if system.trusted {
                        Button("시스템 설정 열기") { AccessibilityPermission.openSystemSettings() }
                    } else {
                        Button("권한 설정…") { PermissionWindowController.shared.show() }
                    }
                }
            }

            Section("정보") {
                LabeledContent("버전", value: "\(AppInfo.version) (\(AppInfo.build))")
                HStack {
                    Spacer()
                    Button("모든 설정 초기화…", role: .destructive) { confirmReset = true }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { system.start() }
        .onDisappear { system.stop() }
        .alert("모든 설정을 초기화할까요?", isPresented: $confirmReset) {
            Button("초기화", role: .destructive) { store.resetAll() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("단축키, 모니터 순서, 배치 방식이 기본값으로 돌아갑니다.")
        }
    }

    private func binding<Value: Equatable>(_ keyPath: WritableKeyPath<AppConfig, Value>) -> Binding<Value> {
        Binding(
            get: { store.config[keyPath: keyPath] },
            set: { newValue in store.update { $0[keyPath: keyPath] = newValue } }
        )
    }
}

// MARK: - Window

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private let navigation = SettingsNavigation()

    func show(tab: SettingsTab? = nil) {
        if let tab { navigation.tab = tab }
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(navigation: navigation))
            let window = NSWindow(contentViewController: hosting)
            window.title = "MonitorHop 설정"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        ScreenRegistry.shared.refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
