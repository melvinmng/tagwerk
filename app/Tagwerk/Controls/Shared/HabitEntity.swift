import AppIntents
import Foundation
import TagwerkCore

/// A habit as Siri, Shortcuts and the control's configuration dialog see it: only its name, never streaks or rates.
/// Compiled into the app and into the widget extension (the control asks for the habit there).
struct HabitEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Gewohnheit"
    static let defaultQuery = HabitEntityQuery()

    var id: UUID
    @Property(title: "Name") var name: String
    /// SF Symbol of the habit; not part of what Siri sees, only of the control.
    var symbol: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: LocalizedStringResource(stringLiteral: name)) }

    init(_ habit: Habit) {
        id = habit.id
        symbol = habit.symbol
        name = habit.name
    }

    init(_ habit: ControlHabit) {
        id = habit.id
        symbol = habit.symbol
        name = habit.name
    }
}

/// Where the habits come from. The app installs the source at launch (the live habits of the one model container);
/// the widget extension has none and reads the short list the app keeps in the App Group (`ControlState`).
@MainActor
enum HabitEntitySource {
    static var activeHabits: (@MainActor () -> [Habit])?

    static func entities() -> [HabitEntity] {
        if let activeHabits { return activeHabits().map(HabitEntity.init) }
        return (ControlState.live()?.habits() ?? []).map(HabitEntity.init)
    }
}

struct HabitEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [HabitEntity] {
        HabitEntitySource.entities().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [HabitEntity] {
        HabitEntitySource.entities()
    }
}
