// swift-tools-version: 6.0
import PackageDescription

// Keychain access is tested in the hosted app test bundle (TagwerkTests),
// because unhosted test runners may lack keychain entitlements.
let package = Package(
    name: "SecureStore",
    platforms: [.iOS("27.0")],
    products: [
        .library(name: "SecureStore", targets: ["SecureStore"])
    ],
    targets: [
        .target(name: "SecureStore")
    ]
)
