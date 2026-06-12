// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "PeakHalo",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PeakHalo", targets: ["PeakHalo"])
    ],
    targets: [
        .executableTarget(
            name: "PeakHalo",
            path: "Sources/PeakHalo",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("IOBluetooth")
            ]
        )
    ]
)
