import Foundation
import Testing
@testable import TagwerkCore

struct HabitSuggestionsTests {
    private let today = PlanDay(year: 2026, month: 11, day: 19)

    private func habit(_ name: String, source: HabitSource = .manual, order: Int = 0, paused: Bool = false) -> Habit {
        Habit(name: name, symbol: "checkmark.circle", order: order, source: source, start: today, pausedSince: paused ? today : nil)
    }

    private func suggestion(_ key: String) -> HabitSuggestion { HabitSuggestions.all.first { $0.key == key }! }

    @Test func all_hasTheTenHabitsWithSourcesAndSymbols() {
        let all = HabitSuggestions.all
        #expect(all.map(\.name) == ["Tag reflektieren", "Bett machen", "Bewegung", "Journal schreiben", "Duschen", "Sonnenlicht",
                                    "Wasser trinken", "Lernen", "Lesen", "Bible Study"])
        #expect(all.count == HabitRules.maximumActive)
        #expect(all.map(\.source) == [.eveningClosed, .manual, .movement, .journal, .manual, .manual, .water, .manual, .manual, .bibleStudy])
        #expect(all.first { $0.key == "sunlight" }?.source == .manual)
        #expect(Set(all.map(\.key)).count == 10 && all.allSatisfy { !$0.symbol.isEmpty })
        // Each automatic source is wanted by one suggestion only.
        let automatic = all.map(\.source).filter { $0 != .manual }
        #expect(Set(automatic).count == automatic.count)
    }

    @Test func missing_comparesNamesWithoutCaseAndSpace() {
        let existing = [habit("  wasser TRINKEN "), habit("Lesen"), habit("Etwas anderes")]
        let missing = HabitSuggestions.missing(existing: existing).map(\.key)
        #expect(!missing.contains("water") && !missing.contains("read"))
        #expect(missing.count == 8)
        #expect(HabitSuggestions.missing(existing: []).count == 10)
        #expect(HabitSuggestions.missing(existing: HabitSuggestions.all.enumerated().map { habit($1.name, order: $0) }).isEmpty)
    }

    @Test func plan_takesAllSelectedWhenThereIsRoom() {
        let plan = HabitSuggestions.plan(selected: HabitSuggestions.all, existing: [])
        #expect(plan.adoptions.count == 10 && plan.leftOut.isEmpty)
        #expect(plan.adoptions.allSatisfy { !$0.fellBackToManual })
        #expect(plan.adoptions.map(\.source) == HabitSuggestions.all.map(\.source))
    }

    @Test func plan_respectsTheMaximumOfActiveHabits_pausedOnesDoNotCount() {
        let existing = (0..<8).map { habit("Eigene \($0)", order: $0) } + [habit("Pausiert", order: 8, paused: true)]
        let plan = HabitSuggestions.plan(selected: [suggestion("bed"), suggestion("shower"), suggestion("read")], existing: existing)
        #expect(plan.adoptions.map(\.suggestion.key) == ["bed", "shower"])
        #expect(plan.leftOut.map(\.key) == ["read"])
        let full = (0..<10).map { habit("Eigene \($0)", order: $0) }
        let none = HabitSuggestions.plan(selected: [suggestion("bed")], existing: full)
        #expect(none.adoptions.isEmpty && none.leftOut.count == 1)
    }

    @Test func plan_aTakenAutomaticSourceBecomesManual() {
        let existing = [habit("Mein Wasser", source: .water), habit("Pausierte Bewegung", source: .movement, order: 1, paused: true)]
        let plan = HabitSuggestions.plan(selected: [suggestion("water"), suggestion("movement"), suggestion("journal")], existing: existing)
        #expect(plan.adoptions.map(\.source) == [.manual, .manual, .journal])
        #expect(plan.adoptions.map(\.fellBackToManual) == [true, true, false])
    }

    @Test func suggestion_movementUsesCombinedSource() {
        #expect(HabitSuggestions.all.first { $0.key == "movement" }?.source == .movement)
    }

    @Test func plan_movementDoesNotClashWithWorkoutOrSteps() {
        let existing = [habit("Training", source: .workout), habit("Schritte", source: .steps, order: 1)]
        let plan = HabitSuggestions.plan(selected: [suggestion("movement")], existing: existing)
        #expect(plan.adoptions.map(\.source) == [.movement] && plan.adoptions.map(\.fellBackToManual) == [false])
    }

    @Test func formerMovementName_isGermanOrEnglishWithoutCaseAndSpace() {
        #expect(HabitSuggestions.isFormerMovementName("Bewegung") && HabitSuggestions.isFormerMovementName("  bewegung "))
        #expect(HabitSuggestions.isFormerMovementName("Exercise"))
        #expect(!HabitSuggestions.isFormerMovementName("Bewegung 30 min") && !HabitSuggestions.isFormerMovementName("Training"))
    }

    @Test func plan_theSameSourceTwiceInOneSelectionOnlyServesTheFirst() {
        let twin = HabitSuggestion(key: "twin", name: "Zweites Wasser", symbol: "drop", source: .water)
        let plan = HabitSuggestions.plan(selected: [suggestion("water"), twin], existing: [])
        #expect(plan.adoptions.map(\.source) == [.water, .manual])
    }

    @Test func habits_continueTheOrderAndStartToday() {
        let existing = [habit("A", order: 4), habit("B", order: 2)]
        let plan = HabitSuggestions.plan(selected: [suggestion("bed"), suggestion("bible")], existing: existing)
        let habits = HabitSuggestions.habits(for: plan, existing: existing, today: today)
        #expect(habits.map(\.name) == ["Bett machen", "Bible Study"] && habits.map(\.order) == [5, 6])
        #expect(habits.map(\.source) == [.manual, .bibleStudy] && habits.allSatisfy { $0.start == today && $0.daysPerWeek == 7 })
    }
}
