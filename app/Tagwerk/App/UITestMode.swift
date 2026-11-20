import Foundation

/// Simulator-only mode for the UI tests, enabled with the launch argument `-TagwerkUITest`.
/// It opens an in-memory SwiftData store (every launch starts fresh), creates the demo data including a
/// demo shopping list, never writes into the App Group container and turns animations off.
/// The argument is only read in debug builds for the simulator; everywhere else `isActive` is `false`,
/// so the mode can never be active on a device.
enum UITestMode {
    static let launchArgument = "-TagwerkUITest"

    #if DEBUG && targetEnvironment(simulator)
    static var isActive: Bool { ProcessInfo.processInfo.arguments.contains(launchArgument) }
    #else
    static var isActive: Bool { false }
    #endif
}
