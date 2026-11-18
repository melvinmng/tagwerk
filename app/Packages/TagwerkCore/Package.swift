// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TagwerkCore",
    defaultLocalization: "de",
    platforms: [.iOS("27.0")],
    products: [
        .library(name: "TagwerkCore", targets: ["TagwerkCore"])
    ],
    targets: [
        .target(name: "TagwerkCore", resources: [.process("Resources")]),
        .testTarget(name: "TagwerkCoreTests", dependencies: ["TagwerkCore"])
    ]
)
