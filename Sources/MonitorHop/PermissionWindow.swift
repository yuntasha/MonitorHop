import AppKit
import SwiftUI

@MainActor
final class PermissionModel: ObservableObject {
    @Published var trusted = AccessibilityPermission.isTrusted
    private var poll: Task<Void, Never>?
    var onGranted: (() -> Void)?

    func startPolling() {
        poll?.cancel()
        poll = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 700_000_000)
                guard let self else { return }
                let now = AccessibilityPermission.isTrusted
                if now != self.trusted {
                    self.trusted = now
                    if now { self.onGranted?() }
                }
            }
        }
    }

    func stopPolling() {
        poll?.cancel()
        poll = nil
    }
}

struct PermissionView: View {
    @ObservedObject var model: PermissionModel
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: model.trusted ? "checkmark.shield.fill" : "hand.raised.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(model.trusted ? Color.green : Color.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text("접근성 권한").font(.title2.bold())
                    Text(model.trusted
                         ? "허용되었습니다. 이제 모든 기능을 쓸 수 있습니다."
                         : "다른 앱의 창에 포커스를 주고 창을 옮기려면 필요합니다.")
                        .foregroundStyle(.secondary)
                }
            }

            if !model.trusted {
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. 아래 ‘시스템 설정 열기’를 누릅니다.")
                    Text("2. 개인정보 보호 및 보안 › 손쉬운 사용에서 MonitorHop을 켭니다.")
                    Text("3. 켜면 이 창이 자동으로 닫힙니다.")
                }
                .font(.callout)

                Text("이미 켜져 있는데 동작하지 않으면 목록에서 MonitorHop을 ‘−’ 버튼으로 지운 뒤 다시 추가하세요. 앱을 새로 빌드하면 서명이 바뀌어 이 과정이 필요할 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                if model.trusted {
                    Button("닫기", action: close).keyboardShortcut(.defaultAction)
                } else {
                    Button("나중에", action: close)
                    Button("시스템 설정 열기") {
                        AccessibilityPermission.request()
                        AccessibilityPermission.openSystemSettings()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 470)
    }
}

@MainActor
final class PermissionWindowController: NSObject, NSWindowDelegate {
    static let shared = PermissionWindowController()

    private var window: NSWindow?
    private let model = PermissionModel()

    func show() {
        model.trusted = AccessibilityPermission.isTrusted
        if window == nil {
            let hosting = NSHostingController(rootView: PermissionView(model: model) { [weak self] in self?.close() })
            let window = NSWindow(contentViewController: hosting)
            window.title = "MonitorHop"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.delegate = self
            self.window = window
        }
        model.onGranted = { [weak self] in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                self?.close()
            }
        }
        model.startPolling()
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        model.stopPolling()
    }
}
