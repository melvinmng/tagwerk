// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GitHubKit",
    defaultLocalization: "de",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [
        .library(name: "GitHubKit", targets: ["GitHubKit"])
    ],
    dependencies: [
        .package(path: "../TagwerkCore")
    ],
    targets: [
        .target(name: "GitHubKit", dependencies: ["TagwerkCore"], resources: [.process("Resources")]),
        .testTarget(name: "GitHubKitTests", dependencies: ["GitHubKit", "TagwerkCore"])
    ]
)
