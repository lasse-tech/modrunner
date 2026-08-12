// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ModRunner",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ModRunner",
            path: "Sources/ModRunner",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ModRunnerTests",
            dependencies: ["ModRunner"],
            path: "Tests/ModRunnerTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
