import AppKit

MainActor.assumeIsolated {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if let command = CLI.parse(arguments) {
        exit(CLI.run(command))
    }

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
