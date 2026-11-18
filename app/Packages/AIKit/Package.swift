// swift-tools-version: 6.0
import PackageDescription

// Credentials are persisted through the `ChatGPTCredentialStore` protocol. The keychain
// implementation and its test live in the app (TagwerkTests), like GitHubKit's credential store.
let package = Package(
    name: "AIKit",
    defaultLocalization: "de",
    platforms: [.iOS("27.0")],
    products: [
        .library(name: "AIKit", targets: ["AIKit"])
    ],
    targets: [
        .target(name: "AIKit", resources: [.process("Resources")]),
        .testTarget(name: "AIKitTests", dependencies: ["AIKit"], resources: [.copy("Fixtures")])
    ]
)
