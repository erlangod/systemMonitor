// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SystemMonitor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "SystemMonitor",
            targets: ["SystemMonitor"]
        )
    ],
    targets: [
        .executableTarget(
            name: "SystemMonitor",
            path: "Sources/SystemMonitor"
        )
    ]
)
