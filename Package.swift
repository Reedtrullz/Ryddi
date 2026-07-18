// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Ryddi",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ReclaimerCore", targets: ["ReclaimerCore"]),
        .library(name: "RyddiProtectCore", targets: ["RyddiProtectCore"]),
        .executable(name: "reclaimer", targets: ["reclaimer"]),
        .executable(name: "RyddiApp", targets: ["MacDiskReclaimerApp"]),
        .executable(name: "MacDiskReclaimerApp", targets: ["MacDiskReclaimerApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.4")
    ],
    targets: [
        .target(
            name: "ReclaimerCore",
            resources: [
                .process("Resources")
            ]
        ),
        .target(
            name: "RyddiProtectCore",
            dependencies: []
        ),
        .target(
            name: "RyddiProtectAuth",
            dependencies: ["RyddiProtectCore"]
        ),
        .executableTarget(
            name: "reclaimer",
            dependencies: ["ReclaimerCore"]
        ),
        .executableTarget(
            name: "MacDiskReclaimerApp",
            dependencies: [
                "ReclaimerCore",
                "RyddiProtectCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@loader_path/../Frameworks"])
            ]
        ),
        .testTarget(
            name: "ReclaimerCoreTests",
            dependencies: ["ReclaimerCore"],
            exclude: ["Fixtures"]
        ),
        .testTarget(
            name: "RyddiProtectCoreTests",
            dependencies: ["RyddiProtectCore", "ReclaimerCore"]
        ),
        .testTarget(
            name: "RyddiProtectAuthTests",
            dependencies: ["RyddiProtectAuth", "RyddiProtectCore"]
        ),
        .testTarget(
            name: "ReclaimerCLITests",
            dependencies: ["reclaimer", "ReclaimerCore"]
        ),
        .testTarget(
            name: "MacDiskReclaimerAppTests",
            dependencies: ["MacDiskReclaimerApp", "ReclaimerCore", "RyddiProtectCore"]
        )
    ]
)
