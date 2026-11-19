import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct HabitStoreTests {
    let container: ModelContainer
    let store: HabitStore
    let calendar = testCalendar()

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        store = HabitStore(context: container.mainContext, now: { testNow() })
    }

    private func day(_ month: Int, _ day: Int) -> PlanDay { PlanDay(year: 2026, month: month, day: day) }

    private func habit(_ name: String = "Lesen 20 min", order: Int = 0) -> Habit {
        Habit(name: name, symbol: "book", order: order, start: day(11, 1))
    }

    @Test func save_cutsNameToFortyCharacters() {
        var long = habit(String(repeating: "x", count: 60))
        long.id = UUID()
        store.save(long)
        #expect(store.habits().first?.name.count == 40)
    }

    @Test func save_updatesByID() {
        var first = habit()
        store.save(first)
        first.name = "Lesen"
        first.daysPerWeek = 3
        store.save(first)
        #expect(store.habits().count == 1)
        #expect(store.habits().first?.name == "Lesen" && store.habits().first?.daysPerWeek == 3)
    }

    @Test func delete_removesChecksOfTheHabit() {
        let kept = habit("Bleibt")
        let removed = habit("Weg")
        store.save(kept)
        store.save(removed)
        store.setCheck(kept.id, on: day(11, 17), checked: true, at: testNow())
        store.setCheck(removed.id, on: day(11, 17), checked: true, at: testNow())
        store.delete(removed.id)
        #expect(store.habits().map(\.name) == ["Bleibt"])
        #expect(store.checks(in: day(11, 1)...day(11, 30)) == [kept.id: [day(11, 17)]])
    }

    @Test func setCheck_twice_keepsOneRecord() {
        let reading = habit()
        store.save(reading)
        #expect(store.setCheck(reading.id, on: day(11, 17), checked: true, at: testNow()))
        #expect(!store.setCheck(reading.id, on: day(11, 17), checked: true, at: testNow()))
        let count = (try? container.mainContext.fetchCount(FetchDescriptor<HabitCheckRecord>())) ?? 0
        #expect(count == 1)
    }

    @Test func setCheck_false_removesTheManualCheck() {
        let reading = habit()
        store.save(reading)
        store.setCheck(reading.id, on: day(11, 17), checked: true, at: testNow())
        #expect(store.setCheck(reading.id, on: day(11, 17), checked: false, at: testNow()))
        #expect(!store.setCheck(reading.id, on: day(11, 17), checked: false, at: testNow()))
        #expect(store.checks(in: day(11, 1)...day(11, 30)).isEmpty)
    }

    @Test func checks_onlyReturnTheRange() {
        let reading = habit()
        store.save(reading)
        store.setCheck(reading.id, on: day(10, 1), checked: true, at: testNow())
        store.setCheck(reading.id, on: day(11, 17), checked: true, at: testNow())
        #expect(store.checks(in: day(11, 1)...day(11, 30)) == [reading.id: [day(11, 17)]])
    }

    @Test func pauseAndResume_recordsTheClosedPause() {
        let reading = habit()
        store.save(reading)
        store.setPaused(reading.id, true, today: day(11, 16), calendar: calendar)
        #expect(store.habits().first?.pausedSince == day(11, 16))
        store.setPaused(reading.id, false, today: day(11, 18), calendar: calendar)
        let stored = store.habits().first
        #expect(stored?.pausedSince == nil)
        #expect(stored?.pauses == [HabitPause(from: day(11, 16), to: day(11, 17))])
    }

    @Test func pauseAndResume_onTheSameDay_recordsNothing() {
        let reading = habit()
        store.save(reading)
        store.setPaused(reading.id, true, today: day(11, 18), calendar: calendar)
        store.setPaused(reading.id, false, today: day(11, 18), calendar: calendar)
        #expect(store.habits().first?.pauses.isEmpty == true && store.habits().first?.pausedSince == nil)
    }

    @Test func reorder_writesOrder() {
        let first = habit("A", order: 0)
        let second = habit("B", order: 1)
        store.save(first)
        store.save(second)
        store.reorder([second.id, first.id])
        #expect(store.habits().map(\.name) == ["B", "A"])
    }

    @Test func schema_containsTheHabitTypes() {
        let names = Set(ModelContainerFactory.schema.entities.map(\.name))
        #expect(names.isSuperset(of: ["HabitRecord", "HabitCheckRecord"]))
    }
}
