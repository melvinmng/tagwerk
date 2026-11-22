import Foundation
import TagwerkCore

/// Pages pushed onto the navigation stack of the "Aufgaben" tab (phase 5).
enum TasksDestination: Hashable {
    case shopping
    case shoppingSettings
    case shoppingCategories
    case notes
    case notesFolder(NotesScope)
    case note(UUID)
    /// A day of "Tagesstart" that only has gratitude and no note.
    case morningDay(PlanDay)
}
