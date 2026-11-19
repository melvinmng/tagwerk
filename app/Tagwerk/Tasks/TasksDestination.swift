import Foundation

/// Pages pushed onto the navigation stack of the "Aufgaben" tab (phase 5).
enum TasksDestination: Hashable {
    case shopping
    case shoppingSettings
    case shoppingCategories
    case notes
    case note(UUID)
}
