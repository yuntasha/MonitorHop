// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MonitorHop",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MonitorHop", targets: ["MonitorHop"]),
    ],
    targets: [
        // Pure logic (geometry, ordering, placement, shortcut model, config). No AppKit.
        .target(name: "MonitorHopCore"),
        // The menu bar app (AppKit + SwiftUI + Accessibility + Carbon hotkeys).
        .executableTarget(
            name: "MonitorHop",
            dependencies: ["MonitorHopCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(name: "MonitorHopCoreTests", dependencies: ["MonitorHopCore"]),
    ]
)
