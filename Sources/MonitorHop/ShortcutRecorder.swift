import AppKit
import SwiftUI
import MonitorHopCore

/// A push button that records a key combination when clicked.
/// Esc cancels, ⌫ clears. Global hotkeys are suspended while recording so the
/// currently assigned combination can be typed without triggering it.
final class ShortcutRecorderButton: NSButton {
    var shortcut: Shortcut? {
        didSet { if oldValue != shortcut { refresh() } }
    }
    var onChange: ((Shortcut?) -> Void)?
    var onMessage: ((String?) -> Void)?

    private(set) var isRecording = false
    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var liveModifiers: ModifierSet = []
    private static weak var active: ShortcutRecorderButton?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(clicked)
        lineBreakMode = .byTruncatingTail
        setAccessibilityLabel("단축키 녹화")
        refresh()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 140, height: super.intrinsicContentSize.height)
    }

    @objc private func clicked() {
        isRecording ? stopRecording() : startRecording()
    }

    /// Stops whichever recorder is currently recording (e.g. before clearing or resetting).
    static func cancelActive() {
        active?.stopRecording()
    }

    func startRecording() {
        guard !isRecording else { return }
        Self.active?.stopRecording()
        Self.active = self
        isRecording = true
        liveModifiers = []
        HotkeyCenter.shared.suspend()
        // Local monitors run on the main thread; the closure inherits the main-actor context.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
        if let window {
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.stopRecording() }
            }
        }
        onMessage?(nil)
        refresh()
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        if Self.active === self { Self.active = nil }
        HotkeyCenter.shared.resume()
        refresh()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopRecording() }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard isRecording else { return event }
        let modifiers = ModifierSet(cocoaFlags: event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue)
        if event.type == .flagsChanged {
            liveModifiers = modifiers
            refresh()
            return nil
        }
        let keyCode = UInt32(event.keyCode)
        if modifiers.isEmpty && keyCode == KeyCodes.escape {
            stopRecording()
            return nil
        }
        if modifiers.isEmpty && (keyCode == KeyCodes.delete || keyCode == KeyCodes.forwardDelete) {
            stopRecording()
            onChange?(nil)
            return nil
        }
        let candidate = Shortcut(keyCode: keyCode, modifiers: modifiers)
        switch candidate.validation {
        case .valid:
            stopRecording()
            onChange?(candidate)
        case .needsModifier, .reserved:
            NSSound.beep()
            onMessage?(Shortcut.validationHint)
        }
        return nil
    }

    private func refresh() {
        if isRecording {
            title = liveModifiers.isEmpty ? "키 조합 입력…" : liveModifiers.symbols + " …"
            bezelColor = .controlAccentColor
            contentTintColor = .white
            toolTip = "원하는 키 조합을 누르세요. Esc: 취소, ⌫: 지우기"
        } else {
            title = shortcut?.displayString(keyName: KeyNames.name(for:)) ?? "없음"
            bezelColor = nil
            contentTintColor = shortcut == nil ? .secondaryLabelColor : nil
            toolTip = "클릭한 뒤 새 단축키를 누르세요"
        }
    }
}

/// SwiftUI wrapper around `ShortcutRecorderButton`.
struct ShortcutRecorder: NSViewRepresentable {
    var shortcut: Shortcut?
    var onChange: (Shortcut?) -> Void
    var onMessage: (String?) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton(frame: .zero)
        button.shortcut = shortcut
        button.onChange = onChange
        button.onMessage = onMessage
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.onChange = onChange
        button.onMessage = onMessage
        // Always take the model value (refresh() still shows the recording prompt while recording),
        // so a change made elsewhere during recording (ⓧ, reset) is not lost.
        button.shortcut = shortcut
    }

    static func dismantleNSView(_ button: ShortcutRecorderButton, coordinator: ()) {
        button.stopRecording()
    }
}
