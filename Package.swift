// swift-tools-version: 6.0
import PackageDescription

// `swift test` builds every target in the package, not only what the tests
// depend on, so a conditional dependency is not enough to keep the SwiftUI app
// out of a Linux or Windows build: the target has to be absent there. The
// manifest is evaluated on the host, so this is decided by which machine is
// building.
#if os(macOS)
// Naming the target in the test dependencies is itself a reference SwiftPM
// insists on resolving, so this list has to disappear along with the target.
let interfaceTestDependencies: [Target.Dependency] = ["ModRunnerApp"]
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
let interfaceTestDependencies: [Target.Dependency] = []
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
        // miniaudio, vendored: one header that is also its own implementation.
        // It is what plays sound on Linux and Windows, and it is built on macOS
        // too — not because anything uses it there by default, but so the path
        // the other platforms depend on is compiled and runnable on the machine
        // this is developed on. `MODRUNNER_AUDIO_BACKEND=miniaudio` selects it.
        //
        // Everything above device output is switched off. miniaudio can decode
        // WAV, FLAC and MP3, mix graphs and synthesise tones; this project has
        // its own replayer and its own WAV writer, and the unused half is a
        // slow compile and a larger binary for nothing.
        .target(
            name: "CMiniaudio",
            path: "Sources/CMiniaudio",
            cSettings: [
                .define("MA_NO_DECODING"),
                .define("MA_NO_ENCODING"),
                .define("MA_NO_WAV"),
                .define("MA_NO_FLAC"),
                .define("MA_NO_MP3"),
                .define("MA_NO_GENERATION"),
                .define("MA_NO_RESOURCE_MANAGER"),
                .define("MA_NO_NODE_GRAPH"),
                .define("MA_NO_ENGINE")
            ],
            linkerSettings: [
                // miniaudio opens the system's audio library itself, so there
                // is nothing to link against for ALSA or PulseAudio — but it
                // needs the loader and the threads to do it with.
                .linkedLibrary("dl", .when(platforms: [.linux])),
                .linkedLibrary("m", .when(platforms: [.linux])),
                .linkedLibrary("pthread", .when(platforms: [.linux]))
            ]
        ),
        // Loader, replayer, output and the interface strings. No AppKit, no
        // SwiftUI: everything here runs without a window server.
        .target(
            name: "ModRunnerKit",
            dependencies: ["CMiniaudio"],
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
            // The interface is SwiftUI and AppKit, so it only exists on macOS.
            // The loader, replayer, localisation and CLI suites do not need it
            // and run on every platform the toolchain covers.
            //
            // ModRunnerCLI is deliberately not a dependency either. The CLI
            // suite runs the built binary as a subprocess rather than calling
            // into it, and linking an executable target into the test bundle
            // gives Windows two `main` symbols to choose from. `swift test`
            // builds every target in the package anyway, so the binary is
            // there when the suite looks for it.
            dependencies: interfaceTestDependencies + ["ModRunnerKit"],
            path: "Tests/ModRunnerTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
