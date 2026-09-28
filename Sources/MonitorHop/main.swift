import AppKit

MainActor.assumeIsolated {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if let command = CLI.parse(arguments) {
        exit(CLI.run(command))
    }

    // Single GUI instance: a second launch asks the running one to show its settings.
    guard InstanceLock.acquire() else {
        RemoteControl.requestShowSettings()
        exit(0)
    }
    // Listen before anything else so requests sent while we start up are not dropped
    // (they are queued until applicationDidFinishLaunching calls markReady()).
    RemoteControl.startListening()

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
