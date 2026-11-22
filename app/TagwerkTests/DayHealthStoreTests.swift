import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct DayHealthStoreTests {
    let container: ModelContainer
    let store: DayHealthStore
    let day = PlanDay(year: 2026, month: 11, day: 20)

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        store = DayHealthStore(context: container.mainContext, now: { Date(timeIntervalSince1970: 1_000) })
    }

    private func reading(on day: PlanDay? = nil, active: Double?, percent: Int = 50, foreignKcal: Double? = nil) -> DayHealth {
        DayHealth(day: day ?? self.day, activeKcal: active, creditPercent: percent, foreign: ForeignIntake(kcal: foreignKcal))
    }

    @Test func record_upsertsPerDay() throws {
        store.record(reading(active: 400), isToday: true)
        store.record(reading(active: 450), isToday: true)
        #expect(try container.mainContext.fetch(FetchDescriptor<DayHealthRecord>()).count == 1)
        #expect(store.value(on: day)?.activeKcal == 450)
        #expect(store.value(on: PlanDay(year: 2026, month: 11, day: 21)) == nil)
    }

    @Test func record_keepsLastKnownWhenHealthUnreadable() {
        store.record(reading(active: 520, percent: 75, foreignKcal: 340), isToday: false)
        let stored = store.record(reading(active: nil, percent: 50), isToday: false)
        #expect(stored.activeKcal == 520 && stored.foreign.kcal == 340 && stored.creditPercent == 75)
        #expect(store.value(on: day)?.activeKcal == 520)
    }

    @Test func record_today_followsHealthAtEveryLoad() {
        store.record(reading(active: 520, foreignKcal: 340), isToday: true)
        store.record(reading(active: 530, foreignKcal: nil), isToday: true)
        #expect(store.value(on: day)?.foreign.kcal == nil)
        #expect(store.value(on: day)?.activeKcal == 530)
    }

    @Test func record_unknownIsStoredAsUnknownNotZero() {
        store.record(reading(active: nil), isToday: false)
        #expect(store.value(on: day)?.activeKcal == nil)
        #expect(store.value(on: day)?.foreign.hasValues == false)
    }

    @Test func values_listsTheRangeOldestFirst() {
        for offset in [3, 1, 2, 5] {
            store.record(reading(on: PlanDay(year: 2026, month: 11, day: 10 + offset), active: Double(offset)), isToday: false)
        }
        let values = store.values(from: PlanDay(year: 2026, month: 11, day: 11), to: PlanDay(year: 2026, month: 11, day: 13))
        #expect(values.map(\.day.day) == [11, 12, 13])
    }

    @Test func record_roundTripsEveryField() {
        let full = DayHealth(day: day, activeKcal: 512.5, creditPercent: 75,
                             foreign: ForeignIntake(kcal: 340, protein: 12, carbs: 40, fat: 9,
                                                    nutrients: NutrientValues(fiber: 5, sugar: 11, saturatedFat: 3, salt: 1.5),
                                                    waterMilliliters: 250, sources: ["Yazio", "Lifesum"]))
        store.record(full, isToday: true)
        #expect(store.value(on: day) == full)
    }
}
