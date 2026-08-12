// swift-tools-version: 6.0
import PackageDescription

// `swift test` builds every target in the package, not only what the tests
// depend on, so a conditional dependency is not enough to keep the SwiftUI app
// out of a Linux or Windows build: the target has to be absent there. The
// manifest is evaluated on the host, so this is decided by which machine is
// building.
#if os(macOS)
let interfaceTargets: [Target] = [
    // Not "ModRunner": the CLI product is "modrunner", and on a
    // case-insensitive filesystem the two executables would be the same
    // file in the build directory — whichever linked last would win, and
    // running `modrunner` could open the app instead.
    .executableTarget(
        name: "ModRunnerApp",
        dependencies: ["ModRunnerKit"],
        path: "Sources/ModRunner",
        swiftSettings: [.swiftLanguageMode(.v5)]
    )
]
#else
let interfaceTargets: [Target] = []
#endif

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
    targets: interfaceTargets + [
        // Loader, replayer, output and the interface strings. No AppKit, no
        // SwiftUI: everything here runs without a window server.
        .target(
            name: "ModRunnerKit",
            path: "Sources/ModRunnerKit",
            resources: [.process("Resources")],
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
            dependencies: [
                // The interface is SwiftUI and AppKit, so it only exists on
                // macOS. The loader, replayer, localisation and CLI suites do
                // not need it and run on every platform the toolchain covers.
                .target(name: "ModRunnerApp", condition: .when(platforms: [.macOS])),
                "ModRunnerKit",
                "ModRunnerCLI"
            ],
            path: "Tests/ModRunnerTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
