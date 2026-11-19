import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// The habit sources of the routines (#181) and the adoption of the suggested habits.
@MainActor
struct HabitAutomaticSourcesTests {
    final class Clock { var now = testNow() }
    let container: ModelContainer
    let habitStore: HabitStore
    let notes: NoteStore
    let routines: RoutineStore
    let settings: AppSettings
    let clock = Clock()
    let calendar = testCalendar()
    var today: PlanDay { PlanDay(year: 2026, month: 11, day: 18) }
    private let german = Locale(identifier: "de_DE")

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        let clock = self.clock
        habitStore = HabitStore(context: container.mainContext, now: { clock.now })
        notes = NoteStore(context: container.mainContext, now: { clock.now })
        routines = RoutineStore(context: container.mainContext, now: { clock.now })
        settings = try AppSettings.current(in: container.mainContext)
    }

    private func makeModel() -> HabitsModel {
        let clock = self.clock, notes = self.notes, routines = self.routines
        let sources = HabitDaySources(closedDays: { routines.closedDays(in: $0) }, journalDays: { notes.journalDays(in: $0) },
                                      bibleStudyDays: { notes.completedSessionDays(in: $0) })
        return HabitsModel(store: habitStore, intake: IntakeStore(context: container.mainContext), health: FakeHealthStore(),
                           settings: settings, daySources: sources, calendar: calendar, now: { clock.now })
    }

    private func addHabit(_ source: HabitSource) {
        habitStore.save(Habit(name: "Gewohnheit \(source.rawValue)", symbol: "book", order: habitStore.habits().count, source: source,
                              start: PlanDay(year: 2026, month: 11, day: 1)))
    }

    @Test func eveningClosed_isFulfilledByACompletedWrapUp() async throws {
        addHabit(.eveningClosed)
        let model = makeModel()
        await model.reload()
        #expect(try #require(model.rows.first).isFulfilled == false)
        routines.update(today) { $0.closeCompletedAt = clock.now }
        model.refreshLocal()
        let row = try #require(model.rows.first)
        #expect(row.isFulfilled && row.isAutomatic)
        #expect(model.todayCounter == HabitCounter(done: 1, total: 1))
    }

    @Test func journal_needsMoreThanTheTemplate() async throws {
        addHabit(.journal)
        let entry = notes.openJournalEntry(dayKey: today.dayKey, locale: german)
        let model = makeModel()
        await model.reload()
        #expect(try #require(model.rows.first).isFulfilled == false)
        notes.updateText(entry.id, text: entry.text + "Heute war ein guter Tag.")
        model.refreshLocal()
        #expect(try #require(model.rows.first).isFulfilled)
    }

    @Test func journal_aTrashedEntryDoesNotCount() async throws {
        addHabit(.journal)
        let entry = notes.openJournalEntry(dayKey: today.dayKey, locale: german)
        notes.updateText(entry.id, text: entry.text + "Text")
        notes.trash(entry.id)
        let model = makeModel()
        await model.reload()
        #expect(try #require(model.rows.first).isFulfilled == false)
    }

    @Test func bibleStudy_isFulfilledByACompletedSessionOnly() async throws {
        addHabit(.bibleStudy)
        let book = try #require(BibleBooks.book(number: 45))
        let started = notes.startSession(book: book, passage: "3,21-31", dayKey: today.dayKey, dateText: "18.11.2026", locale: german)
        let model = makeModel()
        await model.reload()
        #expect(try #require(model.rows.first).isFulfilled == false)
        notes.completeSession(started.session.id)
        model.refreshLocal()
        let row = try #require(model.rows.first)
        #expect(row.isFulfilled && row.isAutomatic)
    }

    @Test func detailTexts_forTheRoutineSources() {
        var facts = HabitFacts.empty
        facts.closedDays = [today]
        let habit = Habit(name: "x", symbol: "book", order: 0, source: .eveningClosed, start: today)
        #expect(HabitText.sourceDetail(habit, on: today, facts: facts, workout: nil) == "Tagesabschluss abgeschlossen")
        #expect(HabitText.sourceDetail(habit, on: PlanDay(year: 2026, month: 11, day: 17), facts: facts, workout: nil) == nil)
        #expect(HabitText.sourceTitle(.journal) == "Tagebuch geschrieben")
    }

    @Test func adopt_savesTheSuggestionsWithSourcesAndOrder() async throws {
        addHabit(.water)
        let model = makeModel()
        await model.reload()
        #expect(model.missingSuggestions.count == 10)
        let plan = model.adopt(model.missingSuggestions)
        // "Wasser trinken" is wanted with the water source, which the existing habit has: it becomes manual.
        #expect(plan.adoptions.count == 9 && plan.leftOut.map(\.key) == ["bible"])
        #expect(model.habits.first { $0.name == "Wasser trinken" }?.source == .manual)
        #expect(model.habits.count == 10)
        #expect(Set(model.habits.map(\.source).filter { $0 != .manual }).count == model.habits.filter { $0.source != .manual }.count)
        #expect(model.habits.map(\.order) == Array(0..<10))
        #expect(!model.canAddHabit)
    }

    @Test func adopt_isOfferedOnlyForMissingNames() async {
        habitStore.save(Habit(name: "lesen", symbol: "book", order: 0, start: today))
        let model = makeModel()
        await model.reload()
        #expect(!model.missingSuggestions.contains { $0.key == "read" } && model.missingSuggestions.count == 9)
        model.adopt(model.missingSuggestions.filter { $0.key == "bed" })
        #expect(model.habits.map(\.name).contains("Bett machen") && model.missingSuggestions.count == 8)
    }

    @Test func hasActiveHabit_ignoresPausedOnes() async {
        addHabit(.bibleStudy)
        let model = makeModel()
        await model.reload()
        #expect(model.hasActiveHabit(source: .bibleStudy))
        model.setPaused(model.habits[0].id, true)
        #expect(!model.hasActiveHabit(source: .bibleStudy))
    }
}
