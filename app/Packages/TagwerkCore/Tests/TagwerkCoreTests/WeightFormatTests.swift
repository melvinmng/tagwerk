import Foundation
import Testing
@testable import TagwerkCore

struct WeightFormatTests {
    private let de = Locale(identifier: "de_DE")
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    @Test func kilograms_useTheLocaleSeparator() {
        #expect(WeightFormat.kilograms(81.94, locale: de) == "81,9 kg")
    }

    @Test func change_hasATrueMinusSignAndNoSignAtZero() {
        #expect(WeightFormat.change(-2.5, locale: de) == "\u{2212}2,5 kg")
        #expect(WeightFormat.change(0.3, locale: de) == "+0,3 kg")
        #expect(WeightFormat.change(0.02, locale: de) == "0,0 kg")
        #expect(WeightFormat.changePerWeek(-0.34, locale: de) == "\u{2212}0,3 kg/Woche")
    }

    @Test func projection_namesTheThirdOfTheMonth() {
        func text(_ day: Int) -> String {
            let projection = WeightTrend.Projection(day: PlanDay(year: 2027, month: 2, day: day), daysAhead: 90)
            return WeightFormat.projection(projection, calendar: calendar, locale: de)
        }
        #expect(text(4) == "Bei diesem Tempo etwa Anfang Februar 2027.")
        #expect(text(15) == "Bei diesem Tempo etwa Mitte Februar 2027.")
        #expect(text(27) == "Bei diesem Tempo etwa Ende Februar 2027.")
    }

    @Test func paceHint_takesItsNumbersFromTheConstants() {
        let text = WeightFormat.paceHint(trend: -1.04, limit: 0.8, locale: de)
        #expect(text.contains("1,0 kg Abnahme pro Woche"))
        #expect(text.contains("1 % des Körpergewichts") && text.contains("1,0 kg pro Woche"))
        #expect(text.contains("keine Leitlinie"))
    }

    @Test func morningCaption_listsWhatIsKnown() {
        #expect(WeightFormat.morningCaption(yesterday: 82.3, mean: 82.1, locale: de) == "Gestern 82,3 kg · 7-Tage-Mittel 82,1 kg")
        #expect(WeightFormat.morningCaption(yesterday: nil, mean: 82.1, locale: de) == "7-Tage-Mittel 82,1 kg")
        #expect(WeightFormat.morningCaption(yesterday: nil, mean: nil, locale: de) == nil)
    }

    @Test func overview_collectsTodayYesterdayAndMean() {
        let today = PlanDay(year: 2026, month: 11, day: 21)
        func day(_ offset: Int, _ kg: Double) -> (PlanDay, DayWeight) {
            let day = today.adding(days: offset, calendar: calendar)
            return (day, DayWeight(day: day, kilograms: kg))
        }
        let overview = WeightOverview.make(Dictionary(uniqueKeysWithValues: [day(0, 80), day(-1, 81), day(-2, 82)]), today: today,
                                           calendar: calendar)
        #expect(overview.today == 80 && overview.yesterday == 81 && overview.mean == 81 && overview.latest == 80)
        let sparse = WeightOverview.make(Dictionary(uniqueKeysWithValues: [day(-3, 79)]), today: today, calendar: calendar)
        #expect(sparse.today == nil && sparse.yesterday == nil && sparse.mean == nil && sparse.latest == 79)
    }

    // MARK: Weekly review

    @Test func targetLine_namesTheDistanceOnlyWhenTheMeanIsKnown() {
        #expect(WeightFormat.targetLine(targetKg: 78, remaining: -3.4, locale: de) == "78,0 kg · noch 3,4 kg")
        #expect(WeightFormat.targetLine(targetKg: 78, remaining: 2, locale: de) == "78,0 kg · noch 2,0 kg")
        #expect(WeightFormat.targetLine(targetKg: 78, remaining: nil, locale: de) == "78,0 kg")
    }

    @Test func latestLine_namesTheWeekday() {
        // Thursday, 19 Nov 2026.
        let day = DayWeight(day: PlanDay(year: 2026, month: 11, day: 19), kilograms: 82.4)
        #expect(WeightFormat.latestLine(day, calendar: calendar, locale: de) == "Letzte Messung 82,4 kg (Do)")
    }

    @Test func measurementsInWeek_countsOrSaysThereIsNone() {
        #expect(WeightFormat.measurementsInWeek(4) == "4 Messungen in dieser Woche")
        #expect(WeightFormat.measurementsInWeek(1) == "1 Messung in dieser Woche")
        #expect(WeightFormat.measurementsInWeek(0) == "Keine Messung in dieser Woche")
    }
}
