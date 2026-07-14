// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Ryddi",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ReclaimerCore", targets: ["ReclaimerCore"]),
        .executable(name: "reclaimer", targets: ["reclaimer"]),
        .executable(name: "RyddiApp", targets: ["MacDiskReclaimerApp"]),
        .executable(name: "MacDiskReclaimerApp", targets: ["MacDiskReclaimerApp"])
    ],
    targets: [
        .target(
            name: "ReclaimerCore",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "reclaimer",
            dependencies: ["ReclaimerCore"]
        ),
        .executableTarget(
            name: "MacDiskReclaimerApp",
            dependencies: ["ReclaimerCore"]
        ),
        .testTarget(
            name: "ReclaimerCoreTests",
            dependencies: ["ReclaimerCore"],
            exclude: ["Fixtures"]
        ),
        .testTarget(
            name: "ReclaimerCLITests",
            dependencies: ["reclaimer", "ReclaimerCore"]
        ),
        .testTarget(
            name: "MacDiskReclaimerAppTests",
            dependencies: ["MacDiskReclaimerApp", "ReclaimerCore"]
        )
    ]
)
