// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TagwerkCore",
    platforms: [.iOS("27.0")],
    products: [
        .library(name: "TagwerkCore", targets: ["TagwerkCore"])
    ],
    targets: [
        .target(name: "TagwerkCore"),
        .testTarget(name: "TagwerkCoreTests", dependencies: ["TagwerkCore"])
    ]
)
