// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FortAidar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "FortAidarCore", targets: ["FortAidarCore"]),
        .executable(name: "fortaidar", targets: ["fortaidar"]),
        .executable(name: "fortaidar-core-spec", targets: ["FortAidarCoreSpec"]),
        .executable(name: "FortAidarApp", targets: ["FortAidarApp"])
    ],
    targets: [
        .target(name: "FortAidarCore"),
        .executableTarget(
            name: "fortaidar",
            dependencies: ["FortAidarCore"]
        ),
        .executableTarget(
            name: "FortAidarCoreSpec",
            dependencies: ["FortAidarCore"]
        ),
        .executableTarget(
            name: "FortAidarApp",
            dependencies: ["FortAidarCore"],
            resources: [
                .copy("Resources/vaultdog")
            ]
        )
    ]
)
