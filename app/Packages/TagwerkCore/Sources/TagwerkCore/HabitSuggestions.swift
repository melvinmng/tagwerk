import Foundation

/// One habit of the suggested set (#181): the name, the symbol and what fulfils it.
public struct HabitSuggestion: Sendable, Equatable, Identifiable {
    public let key: String
    public let name: String
    public let symbol: String
    public let source: HabitSource

    public var id: String { key }
}

/// The ten habits of the former Notion tracker and the rules for taking them over. Pure; the app reads the names when the
/// sheet opens, like `RoutineSchedule.suggestedItems`, so they follow the app language of that moment.
public enum HabitSuggestions {
    public static var all: [HabitSuggestion] {
        [HabitSuggestion(key: "reflect", name: String(localized: "Tag reflektieren", bundle: .module), symbol: "moon.stars", source: .eveningClosed),
         HabitSuggestion(key: "bed", name: String(localized: "Bett machen", bundle: .module), symbol: "bed.double", source: .manual),
         HabitSuggestion(key: "movement", name: String(localized: "Bewegung", bundle: .module), symbol: "figure.walk", source: .movement),
         HabitSuggestion(key: "journal", name: String(localized: "Journal schreiben", bundle: .module), symbol: "book.closed", source: .journal),
         HabitSuggestion(key: "shower", name: String(localized: "Duschen", bundle: .module), symbol: "shower", source: .manual),
         // The daylight source is not built yet, so this one is ticked by hand.
         HabitSuggestion(key: "sunlight", name: String(localized: "Sonnenlicht", bundle: .module), symbol: "sun.max", source: .manual),
         HabitSuggestion(key: "water", name: String(localized: "Wasser trinken", bundle: .module), symbol: "drop", source: .water),
         HabitSuggestion(key: "learn", name: String(localized: "Lernen", bundle: .module), symbol: "graduationcap", source: .manual),
         HabitSuggestion(key: "read", name: String(localized: "Lesen", bundle: .module), symbol: "book", source: .manual),
         HabitSuggestion(key: "bible", name: String(localized: "Bible Study", bundle: .module), symbol: "book.pages", source: .bibleStudy)]
    }

    /// The suggestions whose name no existing habit has (compared without case, accents and surrounding space).
    public static func missing(existing: [Habit]) -> [HabitSuggestion] {
        let names = Set(existing.map { normalize($0.name) })
        return all.filter { !names.contains(normalize($0.name)) }
    }

    /// Whether a habit name is the old suggestion "Bewegung" (German or English, compared without case, accents and surrounding
    /// space). Only the one-time switch to the source `.movement` uses it.
    public static func isFormerMovementName(_ name: String) -> Bool {
        ["Bewegung", "Exercise"].contains { normalize($0) == normalize(name) }
    }

    /// A suggestion as it will be taken over.
    public struct Adoption: Sendable, Equatable {
        public let suggestion: HabitSuggestion
        /// The source the new habit gets; `.manual` when the wanted automatic source is already used by another habit.
        public let source: HabitSource
        /// The wanted automatic source was taken, so the habit is ticked by hand.
        public var fellBackToManual: Bool { source != suggestion.source }
    }

    public struct Plan: Sendable, Equatable {
        public let adoptions: [Adoption]
        /// Selected suggestions that do not fit under `HabitRules.maximumActive`.
        public let leftOut: [HabitSuggestion]
    }

    /// Takes the selected suggestions in the given order, as far as `HabitRules.maximumActive` allows (paused habits do not
    /// count). Every automatic source serves one habit: a source that an existing habit (paused ones included) or an earlier
    /// suggestion already has turns the suggestion into a manual habit.
    public static func plan(selected: [HabitSuggestion], existing: [Habit]) -> Plan {
        let capacity = max(0, HabitRules.maximumActive - existing.filter { $0.pausedSince == nil }.count)
        var taken = Set(existing.map(\.source).filter { $0 != .manual })
        var adoptions: [Adoption] = []
        var leftOut: [HabitSuggestion] = []
        for suggestion in selected {
            guard adoptions.count < capacity else { leftOut.append(suggestion); continue }
            var source = suggestion.source
            if source != .manual {
                if taken.contains(source) { source = .manual } else { taken.insert(source) }
            }
            adoptions.append(Adoption(suggestion: suggestion, source: source))
        }
        return Plan(adoptions: adoptions, leftOut: leftOut)
    }

    /// The habits to save for a plan: after the existing ones in the list, counting from `today`.
    public static func habits(for plan: Plan, existing: [Habit], today: PlanDay) -> [Habit] {
        let first = (existing.map(\.order).max() ?? -1) + 1
        return plan.adoptions.enumerated().map { offset, adoption in
            Habit(name: adoption.suggestion.name, symbol: adoption.suggestion.symbol, order: first + offset,
                  source: adoption.source, start: today)
        }
    }

    static func normalize(_ name: String) -> String {
        SearchText.fold(name.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
