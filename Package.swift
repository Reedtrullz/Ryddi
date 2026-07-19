// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Ryddi",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ReclaimerCore", targets: ["ReclaimerCore"]),
        .executable(name: "RyddiApp", targets: ["RyddiApp"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "ReclaimerCore",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "RyddiApp",
            dependencies: ["ReclaimerCore"]
        ),
        .testTarget(
            name: "ReclaimerCoreTests",
            dependencies: ["ReclaimerCore"]
        )
    ]
)
