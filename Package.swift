// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Statsy",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "StatsyKit"),
        .target(name: "StatsyControl", dependencies: ["StatsyKit"]),
        .target(name: "StatsyWindowing"),
        .executableTarget(name: "Statsy", dependencies: ["StatsyKit", "StatsyWindowing"]),
        .executableTarget(name: "StatsyMenu", dependencies: ["StatsyControl"]),
        .executableTarget(name: "statsy-probe", dependencies: ["StatsyKit"]),
        .testTarget(
            name: "StatsyKitTests",
            dependencies: ["StatsyKit"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "StatsyControlTests", dependencies: ["StatsyControl", "StatsyKit"]),
        .testTarget(name: "StatsyWindowingTests", dependencies: ["StatsyWindowing"]),
    ]
)
