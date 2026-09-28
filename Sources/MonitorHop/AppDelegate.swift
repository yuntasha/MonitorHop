import AppKit
import Combine
import MonitorHopCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusMenu: StatusMenuController?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainMenu.install()

        ScreenRegistry.shared.start()

        let hotkeys = HotkeyCenter.shared
        hotkeys.install()
        hotkeys.onTrigger = { action in
            ActionPerformer.shared.perform(action)
        }
        // `$config` emits the new value in willSet: use the emitted value.
        SettingsStore.shared.$config
            .map(\.bindings)
            .removeDuplicates()
            .sink { bindings in
                let resolved = bindings.compactMap { key, value in ActionID(key: key).map { ($0, value) } }
                    .sorted { $0.0 < $1.0 }
                hotkeys.apply(resolved)
            }
            .store(in: &cancellables)

        statusMenu = StatusMenuController()

        if !AccessibilityPermission.isTrusted {
            PermissionWindowController.shared.show()
        }
        RemoteControl.markReady()
        logger.info("MonitorHop \(AppInfo.version, privacy: .public) started, \(hotkeys.registeredCount) hotkeys")
    }

    /// Opening the app again (Finder, Spotlight, `open`) shows the settings window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyCenter.shared.unregisterAll()
    }

    @objc func openSettings(_ sender: Any?) {
        SettingsWindowController.shared.show()
    }
}

/// Minimal main menu so ⌘W / ⌘Q / ⌘, work while a MonitorHop window is key.
enum MainMenu {
    @MainActor
    static func install() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "MonitorHop")
        appMenu.addItem(withTitle: "설정…", action: #selector(AppDelegate.openSettings(_:)), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "MonitorHop 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "윈도우")
        windowMenu.addItem(withTitle: "닫기", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "최소화", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }
}
