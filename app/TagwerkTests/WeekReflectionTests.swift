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
        store.saveReflection(WeekReflection(wentWell: "Sport", burdens: "Klausur", calendarPlanned: true), weekStart: monday, at: testNow())
        let previous = monday.adding(days: -7, calendar: testCalendar())
        store.saveReflection(WeekReflection(wentWell: "Vorwoche"), weekStart: previous, at: testNow())
        #expect(store.reflection(weekStart: monday).wentWell == "Sport")
        #expect(store.reflection(weekStart: monday).calendarPlanned)
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

    @Test func reflection_roundTripsTheNewFields() {
        let value = WeekReflection(wentWell: "a", burdens: "b", goalsProgress: "Projekt läuft", calendarPlanned: true,
                                   tasksPlanned: true, gratitudeTaken: true)
        store.saveReflection(value, weekStart: monday, at: testNow())
        #expect(store.reflection(weekStart: monday) == value)
    }

    private func legacyRecord(appointments: Bool, habits: Bool, tasks: Bool = false) -> WeekReflectionRecord {
        let record = WeekReflectionRecord(weekStart: monday, updatedAt: testNow())
        record.wentWell = "Viel geschafft"
        record.burdens = "Wenig Schlaf"
        record.plannedAppointments = appointments
        record.plannedHabits = habits
        record.plannedTasks = tasks
        container.mainContext.insert(record)
        try? container.mainContext.save()
        return record
    }

    @Test func reflection_legacyWeek_mapsBothCalendarFlags() {
        _ = legacyRecord(appointments: true, habits: true, tasks: true)
        let both = store.reflection(weekStart: monday)
        #expect(both.calendarPlanned && both.tasksPlanned)
        #expect(!both.gratitudeTaken && both.goalsProgress.isEmpty)
        // Just one of the two earlier checks: the new point shows open (design point D4).
        let other = monday.adding(days: -7, calendar: testCalendar())
        let record = WeekReflectionRecord(weekStart: other, updatedAt: testNow())
        record.plannedAppointments = true
        container.mainContext.insert(record)
        try? container.mainContext.save()
        #expect(!store.reflection(weekStart: other).calendarPlanned)
    }

    @Test func reflection_legacyTexts_stayUnchanged() throws {
        let record = legacyRecord(appointments: true, habits: false)
        let shown = store.reflection(weekStart: monday)
        #expect(shown.wentWell == "Viel geschafft" && shown.burdens == "Wenig Schlaf")
        // Saving what is shown changes nothing, not even the two earlier flags.
        store.saveReflection(shown, weekStart: monday, at: testNow().addingTimeInterval(60))
        #expect(record.wentWell == "Viel geschafft" && record.burdens == "Wenig Schlaf")
        #expect(record.plannedAppointments && !record.plannedHabits)
    }

    @Test func schema_containsTheReflection() {
        #expect(ModelContainerFactory.schema.entities.map(\.name).contains("WeekReflectionRecord"))
    }
}
