import AppKit
import MonitorHopCore

/// The menu bar icon and its menu (rebuilt every time it opens).
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "display.2", accessibilityDescription: "MonitorHop")
                ?? NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "MonitorHop")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "MonitorHop"
        }
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild(menu)
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()
        let registry = ScreenRegistry.shared
        registry.refresh()
        let config = SettingsStore.shared.config

        menu.addItem(header("모니터로 포커스 이동"))
        for monitor in registry.monitors {
            menu.addItem(actionItem(ActionID(.focus, monitor.number), title: "\(monitor.number)  \(monitor.name)", config: config))
        }
        menu.addItem(.separator())
        menu.addItem(header("현재 창을 모니터로 보내기"))
        for monitor in registry.monitors {
            menu.addItem(actionItem(ActionID(.move, monitor.number), title: "\(monitor.number)  \(monitor.name)", config: config))
        }
        menu.addItem(.separator())

        let identify = NSMenuItem(title: "모니터 번호 보기", action: #selector(identifyMonitors), keyEquivalent: "")
        identify.target = self
        menu.addItem(identify)
        menu.addItem(.separator())

        if AccessibilityPermission.isTrusted {
            let ok = NSMenuItem(title: "접근성 권한 허용됨", action: nil, keyEquivalent: "")
            ok.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: nil)
            ok.isEnabled = false
            menu.addItem(ok)
        } else {
            let needed = NSMenuItem(title: "접근성 권한 필요…", action: #selector(showPermission), keyEquivalent: "")
            needed.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
            needed.target = self
            menu.addItem(needed)
        }
        let failures = HotkeyCenter.shared.failures.count
        if failures > 0 {
            let warn = NSMenuItem(title: "등록 실패한 단축키 \(failures)개…", action: #selector(openShortcutSettings), keyEquivalent: "")
            warn.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
            warn.target = self
            menu.addItem(warn)
        }

        let settings = NSMenuItem(title: "설정…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "MonitorHop 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    private func header(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func actionItem(_ action: ActionID, title: String, config: AppConfig) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(runAction(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = action.key
        item.indentationLevel = 1
        if let shortcut = config.shortcut(for: action), let (key, mask) = shortcut.menuKeyEquivalent {
            item.keyEquivalent = key
            item.keyEquivalentModifierMask = mask
        }
        return item
    }

    @objc private func runAction(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        // Menu actions keep numbers beyond the bindable range working too.
        let parts = key.split(separator: ".")
        guard parts.count == 2, let kind = ActionKind(rawValue: String(parts[0])), let slot = Int(parts[1]) else { return }
        ActionPerformer.shared.perform(ActionID(kind, slot))
    }

    @objc private func identifyMonitors() {
        HUD.shared.identify(ScreenRegistry.shared.monitors)
    }

    @objc private func showPermission() {
        PermissionWindowController.shared.show()
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func openShortcutSettings() {
        SettingsWindowController.shared.show(tab: .shortcuts)
    }
}

extension Shortcut {
    /// Key equivalent for displaying the shortcut next to a menu item, when representable.
    var menuKeyEquivalent: (String, NSEvent.ModifierFlags)? {
        guard !KeyCodes.isKeypad(keyCode), let name = KeyNames.name(for: keyCode), name.count == 1,
              let scalar = name.unicodeScalars.first, scalar.isASCII else { return nil }
        return (name.lowercased(), NSEvent.ModifierFlags(rawValue: modifiers.cocoaFlags))
    }
}
