// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HealthBridge",
    platforms: [.iOS("27.0")],
    products: [
        .library(name: "HealthBridge", targets: ["HealthBridge"])
    ],
    dependencies: [
        .package(path: "../TagwerkCore")
    ],
    targets: [
        .target(name: "HealthBridge", dependencies: ["TagwerkCore"]),
        .testTarget(name: "HealthBridgeTests", dependencies: ["HealthBridge", "TagwerkCore"])
    ]
)
