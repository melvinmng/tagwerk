// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GitHubKit",
    platforms: [.iOS("27.0")],
    products: [
        .library(name: "GitHubKit", targets: ["GitHubKit"])
    ],
    dependencies: [
        .package(path: "../TagwerkCore")
    ],
    targets: [
        .target(name: "GitHubKit", dependencies: ["TagwerkCore"]),
        .testTarget(name: "GitHubKitTests", dependencies: ["GitHubKit", "TagwerkCore"])
    ]
)
