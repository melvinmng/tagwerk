import Foundation

/// Pages pushed onto the navigation stack of the "Einstellungen" tab. Only the pages that something other than a tap on their row
/// has to open are listed (the UI test mode jumps to them, see `UITestScreen`); the other rows keep their own `NavigationLink`.
enum SettingsDestination: Hashable {
    case languages
    case ai
    case aiVoice
    case capture
    case shopping
    case siri
}
