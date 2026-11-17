// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RemindersKit",
    platforms: [.iOS("27.0")],
    products: [
        .library(name: "RemindersKit", targets: ["RemindersKit"])
    ],
    dependencies: [
        .package(path: "../TagwerkCore")
    ],
    targets: [
        .target(name: "RemindersKit", dependencies: ["TagwerkCore"]),
        .testTarget(name: "RemindersKitTests", dependencies: ["RemindersKit", "TagwerkCore"])
    ]
)
