import Foundation
import GitHubKit
import SwiftUI
import TagwerkCore

/// Simulator-only mode for the UI tests, enabled with the launch argument `-TagwerkUITest`.
/// It opens an in-memory SwiftData store (every launch starts fresh), creates the demo data including a
/// demo shopping list, never writes into the App Group container and turns animations off.
/// The argument is only read in debug builds for the simulator; everywhere else `isActive` is `false`,
/// so the mode can never be active on a device.
///
/// Two more arguments serve the accessibility audit: `-TagwerkUITestTextSize <size>` forces a Dynamic Type size
/// (e.g. `accessibility5`) and `-TagwerkUITestDark` forces dark mode, both only for the app, not for the simulator.
/// `-TagwerkUITestScreen <name>` opens a screen directly at launch (see `UITestScreen`).
/// `-TagwerkUITestNow HH:mm` pins the time of day of the app (the date stays today's). `-TagwerkUITestWeekday <1...7>` (1 = Sunday)
/// is the weekday that the parts of the app that offer something only on one weekday ("Tagesabschluss" offers the weekly planning
/// on Sundays) take for the day they show, so they look the same on every day of the run. The date itself does not move: models that
/// count with the real date (the task list) would otherwise show other tasks.
enum UITestMode {
    static let launchArgument = "-TagwerkUITest"
    static let textSizeArgument = "-TagwerkUITestTextSize"
    static let darkArgument = "-TagwerkUITestDark"
    static let clockArgument = "-TagwerkUITestNow"
    static let lockAuthenticationArgument = "-TagwerkUITestLockAuthentication"
    static let screenArgument = "-TagwerkUITestScreen"
    static let weekdayArgument = "-TagwerkUITestWeekday"
    /// `-TagwerkUITestScan <pages>`: "Dokument scannen" delivers that many test pages instead of opening the document camera.
    static let scanArgument = "-TagwerkUITestScan"
    /// `-TagwerkUITestGitHubCatalog`: the search finds invented repositories and projects, as if GitHub were connected.
    static let githubCatalogArgument = "-TagwerkUITestGitHubCatalog"

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

    /// The weekday that `-TagwerkUITestWeekday` names, `nil` without the argument.
    static var weekdayOverride: Int? {
        let arguments = ProcessInfo.processInfo.arguments
        guard isActive, let index = arguments.firstIndex(of: weekdayArgument), index + 1 < arguments.count else { return nil }
        return Int(arguments[index + 1])
    }

    /// The fixed answers of the device check for the note lock: a comma separated list of `succeed` and `fail` ("succeed,fail":
    /// the first check passes, every later one fails); the last answer repeats. `nil` uses the system check.
    static var lockAuthentication: [Bool]? {
        let arguments = ProcessInfo.processInfo.arguments
        guard isActive, let index = arguments.firstIndex(of: lockAuthenticationArgument), index + 1 < arguments.count else { return nil }
        let answers = arguments[index + 1].split(separator: ",").compactMap { answer -> Bool? in
            switch answer {
            case "succeed": true
            case "fail": false
            default: nil
            }
        }
        return answers.isEmpty ? nil : answers
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

    /// The screen to open at launch; `nil` without the argument or with a name that is not known.
    static var screen: UITestScreen? {
        isActive ? UITestScreen.named(in: ProcessInfo.processInfo.arguments) : nil
    }

    /// The number of test pages that stand in for the document camera, or `nil` for the real camera.
    static var scanPageCount: Int? {
        let arguments = ProcessInfo.processInfo.arguments
        guard isActive, let index = arguments.firstIndex(of: scanArgument), index + 1 < arguments.count else { return nil }
        return Int(arguments[index + 1]).map { min(max($0, 1), 10) }
    }

    /// The invented repositories and projects of `-TagwerkUITestGitHubCatalog` (UI tests have no GitHub account), `nil` without it.
    static var githubCatalog: GitHubCatalog? {
        guard isActive, ProcessInfo.processInfo.arguments.contains(githubCatalogArgument) else { return nil }
        let status = ProjectField(id: "F", name: "Status", orderedOptions: ["Backlog", "Ready", "In progress", "Done"].map { ProjectFieldOption(id: $0, name: $0) })
        return GitHubCatalog(
            repositories: ["beispiel/app", "beispiel/studium"],
            projects: [ProjectInfo(id: "PVT_1", number: 1, title: "App", fields: [status], repositories: ["beispiel/app"]),
                       ProjectInfo(id: "PVT_2", number: 2, title: "Studium und Klausuren", fields: [], repositories: ["beispiel/studium"])],
            fetchedAt: Date())
    }
    #else
    static var isActive: Bool { false }
    static func now() -> Date { Date() }
    static var weekdayOverride: Int? { nil }
    static var lockAuthentication: [Bool]? { nil }
    static var dynamicTypeSize: DynamicTypeSize? { nil }
    static var colorScheme: ColorScheme? { nil }
    static var screen: UITestScreen? { nil }
    static var scanPageCount: Int? { nil }
    static var githubCatalog: GitHubCatalog? { nil }
    #endif

    /// The weekday (1 = Sunday ... 7 = Saturday) a part of the app takes for a day: the pinned weekday of the UI test mode when it is
    /// a valid weekday, else the real one.
    static func weekday(actual: Int, pinned: Int?) -> Int {
        if let pinned, (1...7).contains(pinned) { return pinned }
        return actual
    }

    /// The weekday of a day for the parts of the app that offer something on one weekday only.
    static func weekday(of day: PlanDay, calendar: Calendar) -> Int {
        weekday(actual: day.weekday(in: calendar), pinned: weekdayOverride)
    }
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
