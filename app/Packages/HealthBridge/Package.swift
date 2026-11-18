// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HealthBridge",
    defaultLocalization: "de",
    platforms: [.iOS("27.0")],
    products: [
        .library(name: "HealthBridge", targets: ["HealthBridge"])
    ],
    dependencies: [
        .package(path: "../TagwerkCore")
    ],
    targets: [
        .target(name: "HealthBridge", dependencies: ["TagwerkCore"], resources: [.process("Resources")]),
        .testTarget(name: "HealthBridgeTests", dependencies: ["HealthBridge", "TagwerkCore"])
    ]
)
