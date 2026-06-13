// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "PeakHalo",
    defaultLocalization: "en",
    platforms: [
        .macOS("15.0")
    ],
    products: [
        .executable(name: "PeakHalo", targets: ["PeakHalo"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.3.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0")
    ],
    targets: [
        .executableTarget(
            name: "PeakHalo",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/PeakHalo",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("Accelerate"),
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("IOBluetooth"),
                .linkedFramework("UserNotifications")
            ]
        ),
        .testTarget(
            name: "PeakHaloTests",
            dependencies: ["PeakHalo"],
            path: "Tests/PeakHaloTests"
        )
    ]
)
