// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Statsy",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "StatsyKit"),
        .executableTarget(name: "Statsy", dependencies: ["StatsyKit"]),
        .executableTarget(name: "statsy-probe", dependencies: ["StatsyKit"]),
        .testTarget(name: "StatsyKitTests", dependencies: ["StatsyKit"]),
    ]
)
