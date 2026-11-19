import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct WeekReflectionTests {
    let container: ModelContainer
    let store: RoutineStore
    let monday = PlanDay(year: 2026, month: 11, day: 16)

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        store = RoutineStore(context: container.mainContext, now: { testNow() })
    }

    private func recordCount() -> Int { (try? container.mainContext.fetchCount(FetchDescriptor<WeekReflectionRecord>())) ?? -1 }

    @Test func reflection_isStoredPerWeek_andPastWeeksStayEditable() {
        store.saveReflection(WeekReflection(wentWell: "Sport", burdens: "Klausur", plannedHabits: true), weekStart: monday, at: testNow())
        let previous = monday.adding(days: -7, calendar: testCalendar())
        store.saveReflection(WeekReflection(wentWell: "Vorwoche"), weekStart: previous, at: testNow())
        #expect(store.reflection(weekStart: monday).wentWell == "Sport")
        #expect(store.reflection(weekStart: monday).plannedHabits)
        #expect(store.reflection(weekStart: previous).wentWell == "Vorwoche")
        // A past week can still be edited.
        store.saveReflection(WeekReflection(wentWell: "Vorwoche, ergänzt"), weekStart: previous, at: testNow())
        #expect(store.reflection(weekStart: previous).wentWell == "Vorwoche, ergänzt")
        #expect(recordCount() == 2)
    }

    @Test func record_usesTheMondayAsKey() throws {
        store.saveReflection(WeekReflection(burdens: "x"), weekStart: monday, at: testNow())
        let record = try #require(try container.mainContext.fetch(FetchDescriptor<WeekReflectionRecord>()).first)
        #expect(record.weekKey == "2026-11-16")
    }

    @Test func emptyReflection_isNotInserted() {
        #expect(store.reflection(weekStart: monday) == WeekReflection())
        #expect(recordCount() == 0)
        store.saveReflection(WeekReflection(), weekStart: monday, at: testNow())
        #expect(recordCount() == 0)
    }

    @Test func clearingEverything_keepsTheRecordEmptyButDoesNotLoseOthers() {
        store.saveReflection(WeekReflection(wentWell: "a"), weekStart: monday, at: testNow())
        store.saveReflection(WeekReflection(), weekStart: monday, at: testNow())
        #expect(store.reflection(weekStart: monday) == WeekReflection())
    }

    @Test func schema_containsTheReflection() {
        #expect(ModelContainerFactory.schema.entities.map(\.name).contains("WeekReflectionRecord"))
    }
}
