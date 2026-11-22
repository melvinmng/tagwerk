import Foundation
import Testing
@testable import TagwerkCore

struct DayHealthTests {
    private let day = PlanDay(year: 2026, month: 11, day: 20)

    private func health(active: Double?, percent: Int = 50, foreignKcal: Double? = nil, sources: [String] = [],
                        fiber: Double? = nil) -> DayHealth {
        DayHealth(day: day, activeKcal: active, creditPercent: percent,
                  foreign: ForeignIntake(kcal: foreignKcal, nutrients: NutrientValues(fiber: fiber), sources: sources))
    }

    @Test func pastDay_unreadableHealth_keepsTheLastKnownValues() {
        let stored = health(active: 520, percent: 75, foreignKcal: 340, sources: ["Yazio"], fiber: 12)
        let merged = stored.merged(with: health(active: nil, percent: 50), overwritingUnknown: false)
        #expect(merged.activeKcal == 520)
        #expect(merged.foreign.kcal == 340 && merged.foreign.nutrients.fiber == 12)
        #expect(merged.foreign.sources == ["Yazio"])
        #expect(merged.creditPercent == 75, "a past day keeps the share it was counted with")
    }

    @Test func pastDay_newValuesReplaceOldOnes() {
        let stored = health(active: 400, percent: 75, foreignKcal: 340, sources: ["Yazio"])
        let merged = stored.merged(with: health(active: 450, percent: 50, foreignKcal: 360, sources: ["Yazio", "Lifesum"]),
                                   overwritingUnknown: false)
        #expect(merged.activeKcal == 450 && merged.foreign.kcal == 360)
        #expect(merged.foreign.sources == ["Yazio", "Lifesum"])
        #expect(merged.creditPercent == 75)
    }

    @Test func today_isOverwrittenEvenByUnknown() {
        // An entry deleted in the other app must disappear from today's sum at the next load.
        let stored = health(active: 400, percent: 50, foreignKcal: 340, sources: ["Yazio"], fiber: 5)
        let merged = stored.merged(with: health(active: 410, percent: 75), overwritingUnknown: true)
        #expect(merged.activeKcal == 410)
        #expect(merged.foreign.kcal == nil && merged.foreign.nutrients.fiber == nil && merged.foreign.sources.isEmpty)
        #expect(merged.creditPercent == 75)
    }

    @Test func unknownStaysUnknown_notZero() {
        let merged = health(active: nil).merged(with: health(active: nil), overwritingUnknown: false)
        #expect(merged.activeKcal == nil && merged.foreign.kcal == nil)
        #expect(!merged.foreign.hasValues)
    }
}
