// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PulseCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PulseCore", targets: ["PulseCore"]),
        .executable(name: "pulse-cli", targets: ["pulse-cli"]),
    ],
    targets: [
        .target(name: "PulseCore", swiftSettings: [.swiftLanguageMode(.v6)]),
        .executableTarget(name: "pulse-cli", dependencies: ["PulseCore"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(
            name: "PulseCoreTests",
            dependencies: ["PulseCore"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
