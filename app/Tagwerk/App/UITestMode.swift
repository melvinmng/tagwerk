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
    static let clockArgument = "-TagwerkUITestNow"
    /// `-TagwerkUITestScan <pages>`: "Dokument scannen" delivers that many test pages instead of opening the document camera.
    static let scanArgument = "-TagwerkUITestScan"

    #if DEBUG && targetEnvironment(simulator)
    static var isActive: Bool { ProcessInfo.processInfo.arguments.contains(launchArgument) }

    /// The current time of the app. `-TagwerkUITestNow HH:mm` pins the time of day (the date stays today's), so a run
    /// that depends on the position of the "now" marker (the hour grid of "Planen" scrolls to it) gives the same result
    /// at every hour. Without the argument this is the real time.
    static func now() -> Date {
        let arguments = ProcessInfo.processInfo.arguments
        guard isActive, let index = arguments.firstIndex(of: clockArgument), index + 1 < arguments.count else { return Date() }
        let parts = arguments[index + 1].split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return Date() }
        return Calendar.tagwerk.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: Date()) ?? Date()
    }

    static var dynamicTypeSize: DynamicTypeSize? {
        let arguments = ProcessInfo.processInfo.arguments
        guard isActive, let index = arguments.firstIndex(of: textSizeArgument), index + 1 < arguments.count else { return nil }
        let sizes: [String: DynamicTypeSize] = ["xxxLarge": .xxxLarge, "accessibility1": .accessibility1, "accessibility2": .accessibility2,
                                                "accessibility3": .accessibility3, "accessibility4": .accessibility4,
                                                "accessibility5": .accessibility5]
        return sizes[arguments[index + 1]]
    }

    static var colorScheme: ColorScheme? {
        isActive && ProcessInfo.processInfo.arguments.contains(darkArgument) ? .dark : nil
    }

    /// The number of test pages that stand in for the document camera, or `nil` for the real camera.
    static var scanPageCount: Int? {
        let arguments = ProcessInfo.processInfo.arguments
        guard isActive, let index = arguments.firstIndex(of: scanArgument), index + 1 < arguments.count else { return nil }
        return Int(arguments[index + 1]).map { min(max($0, 1), 10) }
    }
    #else
    static var isActive: Bool { false }
    static func now() -> Date { Date() }
    static var dynamicTypeSize: DynamicTypeSize? { nil }
    static var colorScheme: ColorScheme? { nil }
    static var scanPageCount: Int? { nil }
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
