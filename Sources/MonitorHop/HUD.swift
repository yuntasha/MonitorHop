import AppKit

/// Small non-activating overlays: switch feedback, error messages and "identify monitors".
@MainActor
final class HUD {
    static let shared = HUD()

    private var messagePanel: NSPanel?
    private var messageGeneration = 0
    private var identifyPanels: [NSPanel] = []
    private var identifyGeneration = 0

    /// Big monitor number, used when switching.
    func showNumber(_ number: Int, detail: String?, on monitor: Monitor?) {
        show(title: "\(number)", subtitle: detail, titleSize: 64, size: NSSize(width: 200, height: 150),
             on: monitor, verticalPosition: 0.5, duration: 0.7)
    }

    /// One-line message (errors, hints).
    func showMessage(_ text: String, on monitor: Monitor?) {
        let font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        let width = min(max((text as NSString).size(withAttributes: [.font: font]).width + 64, 240), 720)
        show(title: text, subtitle: nil, titleSize: 15, size: NSSize(width: width, height: 56),
             on: monitor, verticalPosition: 0.22, duration: 2.2)
    }

    /// Shows each monitor's number and name on that monitor.
    func identify(_ monitors: [Monitor], duration: TimeInterval = 2.5) {
        identifyGeneration += 1
        let generation = identifyGeneration
        identifyPanels.forEach { $0.orderOut(nil) }
        identifyPanels = monitors.map { monitor in
            let size = NSSize(width: 300, height: 230)
            let panel = Self.makePanel()
            panel.contentView = Self.makeContent(title: "\(monitor.number)", subtitle: monitor.name, titleSize: 120, size: size)
            panel.setFrame(Self.rect(size: size, on: monitor.frame, verticalPosition: 0.5), display: true)
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            return panel
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard generation == self.identifyGeneration else { return }
            self.fadeOut(self.identifyPanels) { [weak self] in
                guard let self, generation == self.identifyGeneration else { return }
                self.identifyPanels.forEach { $0.orderOut(nil) }
                self.identifyPanels = []
            }
        }
    }

    // MARK: - Internals

    private func show(title: String, subtitle: String?, titleSize: CGFloat, size: NSSize,
                      on monitor: Monitor?, verticalPosition: CGFloat, duration: TimeInterval) {
        guard let frame = monitor?.frame ?? NSScreen.main?.frame else { return }
        messageGeneration += 1
        let generation = messageGeneration
        let panel = messagePanel ?? Self.makePanel()
        messagePanel = panel
        panel.contentView = Self.makeContent(title: title, subtitle: subtitle, titleSize: titleSize, size: size)
        panel.setFrame(Self.rect(size: size, on: frame, verticalPosition: verticalPosition), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard generation == self.messageGeneration else { return }
            self.fadeOut([panel]) { [weak self] in
                guard let self, generation == self.messageGeneration else { return }
                panel.orderOut(nil)
            }
        }
    }

    private func fadeOut(_ panels: [NSPanel], completion: @escaping @MainActor () -> Void) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panels.forEach { $0.animator().alphaValue = 0 }
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            completion()
        }
    }

    private static func rect(size: NSSize, on frame: CGRect, verticalPosition: CGFloat) -> NSRect {
        NSRect(x: (frame.midX - size.width / 2).rounded(),
               y: (frame.minY + frame.height * verticalPosition - size.height / 2).rounded(),
               width: size.width, height: size.height)
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }

    private static func makeContent(title: String, subtitle: String?, titleSize: CGFloat, size: NSSize) -> NSView {
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = min(22, size.height / 2)
        effect.layer?.masksToBounds = true

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: titleSize, weight: titleSize > 30 ? .heavy : .semibold)
        titleLabel.alignment = .center
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        var views: [NSView] = [titleLabel]
        if let subtitle {
            let label = NSTextField(labelWithString: subtitle)
            label.font = .systemFont(ofSize: 15, weight: .medium)
            label.textColor = .secondaryLabelColor
            label.alignment = .center
            label.lineBreakMode = .byTruncatingTail
            views.append(label)
        }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: effect.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: effect.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: effect.trailingAnchor, constant: -16),
        ])
        for view in views {
            view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        return effect
    }
}
