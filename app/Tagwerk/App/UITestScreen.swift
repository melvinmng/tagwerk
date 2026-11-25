import Foundation
import GitHubKit
import SwiftUI

/// Screens the UI test mode can open at launch with `-TagwerkUITestScreen <name>`, so an audit does not have to scroll to a
/// settings page row by row. The names are stable identifiers of the tests, not routes of the app: the argument is only read in
/// debug builds for the simulator (`UITestMode.screen`), so no `tagwerk://` link and no release build can reach it.
enum UITestScreen: String, CaseIterable {
    case settingsLanguages = "settings.languages"
    case settingsAIVoice = "settings.ai.voice"
    case settingsCapture = "settings.capture"
    case settingsShopping = "settings.shopping"
    case settingsSiri = "settings.siri"
    case githubRepositoryPicker = "github.repositoryPicker"
    case githubProjectPicker = "github.projectPicker"

    /// The screen named by the value after `-TagwerkUITestScreen` in `arguments`; `nil` without the argument, without a value
    /// and for a name that is not listed (the app then starts on its first screen, and the test that asked fails on the missing page).
    static func named(in arguments: [String]) -> UITestScreen? {
        guard let index = arguments.firstIndex(of: UITestMode.screenArgument), index + 1 < arguments.count else { return nil }
        return UITestScreen(rawValue: arguments[index + 1])
    }

    /// The pages pushed onto the stack of the "Einstellungen" tab, outermost first.
    var settingsPath: [SettingsDestination] {
        switch self {
        case .settingsLanguages: [.languages]
        case .settingsAIVoice: [.ai, .aiVoice]
        case .settingsCapture: [.capture]
        case .settingsShopping: [.shopping]
        case .settingsSiri: [.siri]
        case .githubRepositoryPicker, .githubProjectPicker: []
        }
    }

    /// The screens that are sheets over the tabs (the pickers of a GitHub issue need a catalog from GitHub, which UI tests do not have:
    /// they show the sheet with invented repositories and projects).
    var isPickerSheet: Bool {
        switch self {
        case .githubRepositoryPicker, .githubProjectPicker: true
        default: false
        }
    }
}

extension UITestScreen: Identifiable {
    var id: String { rawValue }
}

#if DEBUG && targetEnvironment(simulator)
extension AppEnvironment {
    /// UI test mode only: opens the screen of `-TagwerkUITestScreen`, with the mechanism of `openShopping()` and the other router
    /// targets (a typed navigation path plus `requestedTab`). Called once before the app reports itself as ready, so the screen
    /// and the "demo data ready" marker appear in the same update.
    func openUITestScreen() {
        guard let screen = UITestMode.screen else { return }
        if screen.isPickerSheet {
            uiTestPickerSheet = screen
            return
        }
        settingsPath = screen.settingsPath
        requestedTab = 2
    }
}

/// UI test mode only: the picker sheets of a GitHub issue with invented data, opened over the tabs by `-TagwerkUITestScreen`.
struct UITestPickerSheets: ViewModifier {
    @Environment(AppEnvironment.self) private var environment

    func body(content: Content) -> some View {
        content.sheet(item: Bindable(environment).uiTestPickerSheet) { screen in
            switch screen {
            case .githubProjectPicker:
                ProjectPickerSheet(projects: Self.projects, linkedProjectIDs: ["PVT_1"], linkedRepository: "beispiel/app",
                                   initialSelection: ["PVT_1"]) { _ in }
            default:
                RepositoryPickerSheet(repositories: Self.repositories, selected: "beispiel/app",
                                      recent: ["beispiel/app", "beispiel/studium"]) { _ in }
            }
        }
    }

    private static let repositories: [String] = ["beispiel/app", "beispiel/studium", "beispiel/web"]
        + (1...25).map { "beispiel/repository-\($0)" }

    private static let projects: [ProjectInfo] = [
        ProjectInfo(id: "PVT_1", number: 1, title: "App", fields: [ProjectField(id: "F", name: "Status",
            orderedOptions: ["Backlog", "Ready", "In progress", "Done"].map { ProjectFieldOption(id: $0, name: $0) })],
            repositories: ["beispiel/app"]),
        ProjectInfo(id: "PVT_2", number: 2, title: "Studium und Klausuren", fields: [], repositories: []),
        ProjectInfo(id: "PVT_3", number: 3, title: "Privat und Haushalt", fields: [], repositories: []),
    ]
}
#endif

extension View {
    /// Adds the picker sheets of the UI test mode; changes nothing outside it.
    func uiTestPickerSheets() -> some View {
        #if DEBUG && targetEnvironment(simulator)
        modifier(UITestPickerSheets())
        #else
        self
        #endif
    }
}
