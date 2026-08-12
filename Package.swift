// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ModRunner",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [
        // The engine, for anything that wants to load or render a module
        // without an interface.
        .library(name: "ModRunnerKit", targets: ["ModRunnerKit"]),
        .executable(name: "modrunner", targets: ["ModRunnerCLI"]),
    ],
    targets: [
        // Loader, replayer, output and the interface strings. No AppKit, no
        // SwiftUI: everything here runs without a window server.
        .target(
            name: "ModRunnerKit",
            path: "Sources/ModRunnerKit",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "ModRunner",
            dependencies: ["ModRunnerKit"],
            path: "Sources/ModRunner",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The directory cannot be called "modrunner": macOS is case-insensitive
        // by default, so it would be the same directory as the GUI target's.
        // The product is named modrunner, which is what the binary is called.
        .executableTarget(
            name: "ModRunnerCLI",
            dependencies: ["ModRunnerKit"],
            path: "Sources/ModRunnerCLI",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ModRunnerTests",
            dependencies: ["ModRunner", "ModRunnerKit", "ModRunnerCLI"],
            path: "Tests/ModRunnerTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
