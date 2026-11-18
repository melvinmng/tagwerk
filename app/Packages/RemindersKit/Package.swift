// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RemindersKit",
    defaultLocalization: "de",
    platforms: [.iOS("27.0")],
    products: [
        .library(name: "RemindersKit", targets: ["RemindersKit"])
    ],
    dependencies: [
        .package(path: "../TagwerkCore")
    ],
    targets: [
        .target(name: "RemindersKit", dependencies: ["TagwerkCore"], resources: [.process("Resources")]),
        .testTarget(name: "RemindersKitTests", dependencies: ["RemindersKit", "TagwerkCore"])
    ]
)
