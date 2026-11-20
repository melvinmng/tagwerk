import Foundation
import SwiftUI

/// Simulator-only mode for the UI tests, enabled with the launch argument `-TagwerkUITest`.
/// It opens an in-memory SwiftData store (every launch starts fresh), creates the demo data including a
/// demo shopping list, never writes into the App Group container and turns animations off.
/// The argument is only read in debug builds for the simulator; everywhere else `isActive` is `false`,
/// so the mode can never be active on a device.
///
/// Two more arguments serve the accessibility audit: `-TagwerkUITestTextSize <size>` forces a Dynamic Type size
/// (e.g. `accessibility5`) and `-TagwerkUITestDark` forces dark mode, both only for the app, not for the simulator.
enum UITestMode {
    static let launchArgument = "-TagwerkUITest"
    static let textSizeArgument = "-TagwerkUITestTextSize"
    static let darkArgument = "-TagwerkUITestDark"

    #if DEBUG && targetEnvironment(simulator)
    static var isActive: Bool { ProcessInfo.processInfo.arguments.contains(launchArgument) }

    static var dynamicTypeSize: DynamicTypeSize? {
        let arguments = ProcessInfo.processInfo.arguments
        guard isActive, let index = arguments.firstIndex(of: textSizeArgument), index + 1 < arguments.count else { return nil }
        let sizes: [String: DynamicTypeSize] = ["accessibility1": .accessibility1, "accessibility2": .accessibility2,
                                                "accessibility3": .accessibility3, "accessibility4": .accessibility4,
                                                "accessibility5": .accessibility5]
        return sizes[arguments[index + 1]]
    }

    static var colorScheme: ColorScheme? {
        isActive && ProcessInfo.processInfo.arguments.contains(darkArgument) ? .dark : nil
    }
    #else
    static var isActive: Bool { false }
    static var dynamicTypeSize: DynamicTypeSize? { nil }
    static var colorScheme: ColorScheme? { nil }
    #endif
}

/// Applies the text size and color scheme of the UI test mode; changes nothing without those launch arguments.
struct UITestAppearance: ViewModifier {
    func body(content: Content) -> some View {
        content
            .transformEnvironment(\.dynamicTypeSize) { size in
                if let forced = UITestMode.dynamicTypeSize { size = forced }
            }
            .preferredColorScheme(UITestMode.colorScheme)
    }
}
