// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TagwerkCore",
    defaultLocalization: "de",
    platforms: [.iOS("27.0"), .watchOS("27.0")],
    products: [
        .library(name: "TagwerkCore", targets: ["TagwerkCore"])
    ],
    dependencies: [
        // Pinned to an exact release (0.9.0, published 2026-09-21): the notes render Markdown through its parser.
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.9.0")
    ],
    targets: [
        .target(name: "TagwerkCore", dependencies: [.product(name: "Markdown", package: "swift-markdown")],
                resources: [.process("Resources")]),
        .testTarget(name: "TagwerkCoreTests", dependencies: ["TagwerkCore"])
    ]
)
