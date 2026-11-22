import Foundation

/// Screens the UI test mode can open at launch with `-TagwerkUITestScreen <name>`, so an audit does not have to scroll to a
/// settings page row by row. The names are stable identifiers of the tests, not routes of the app: the argument is only read in
/// debug builds for the simulator (`UITestMode.screen`), so no `tagwerk://` link and no release build can reach it.
enum UITestScreen: String, CaseIterable {
    case settingsLanguages = "settings.languages"
    case settingsAIVoice = "settings.ai.voice"
    case settingsCapture = "settings.capture"
    case settingsShopping = "settings.shopping"
    case settingsSiri = "settings.siri"

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
        }
    }
}

#if DEBUG && targetEnvironment(simulator)
extension AppEnvironment {
    /// UI test mode only: opens the screen of `-TagwerkUITestScreen`, with the mechanism of `openShopping()` and the other router
    /// targets (a typed navigation path plus `requestedTab`). Called once before the app reports itself as ready, so the screen
    /// and the "demo data ready" marker appear in the same update.
    func openUITestScreen() {
        guard let screen = UITestMode.screen else { return }
        settingsPath = screen.settingsPath
        requestedTab = 2
    }
}
#endif
