import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

struct HabitTextTests {
    let calendar = testCalendar()
    let today = PlanDay(year: 2026, month: 11, day: 18)

    private func day(_ month: Int, _ day: Int) -> PlanDay { PlanDay(year: 2026, month: month, day: day) }

    private func habit(start: PlanDay, source: HabitSource = .manual, daysPerWeek: Int = 7) -> Habit {
        Habit(name: "Lesen 20 min", symbol: "book", order: 0, source: source, daysPerWeek: daysPerWeek, start: start)
    }

    private func facts(_ habit: Habit, checked: [PlanDay]) -> HabitFacts {
        var facts = HabitFacts.empty
        facts.manualChecks[habit.id] = Set(checked)
        return facts
    }

    @Test func subtitle_daily() {
        let reading = habit(start: day(11, 4))
        let checked = [day(11, 4), day(11, 5), day(11, 6), day(11, 7), day(11, 8), day(11, 9),
                       day(11, 13), day(11, 14), day(11, 16), day(11, 17), day(11, 18)]
        #expect(HabitText.subtitle(reading, today: today, facts: facts(reading, checked: checked), calendar: calendar)
                == "7 Tage 5/7 · 30 Tage 73 % · Serie 3")
    }

    @Test func subtitle_weekly() {
        let training = habit(start: day(10, 26), daysPerWeek: 3)
        // Weeks 26.10., 2.11. and 9.11. reached 3 days, the running week has 2 of 3.
        let checked = [day(10, 26), day(10, 28), day(10, 30), day(11, 2), day(11, 4), day(11, 6),
                       day(11, 9), day(11, 11), day(11, 13), day(11, 16), day(11, 17)]
        let text = HabitText.subtitle(training, today: today, facts: facts(training, checked: checked), calendar: calendar)
        #expect(text.hasPrefix("Diese Woche 2 von 3 · 30 Tage "))
        #expect(text.hasSuffix(" · Serie 3 Wochen"))
    }

    @Test func subtitle_withoutCountingDays_showsDash() {
        let fresh = habit(start: today)
        #expect(HabitText.subtitle(fresh, today: today, facts: .empty, calendar: calendar).contains("30 Tage –"))
    }

    @Test func streak_capped() {
        #expect(HabitText.streak(.days(90, isCapped: true)) == "Serie 90+")
        #expect(HabitText.streak(.weeks(12, isCapped: true)) == "Serie 12+ Wochen")
        #expect(HabitText.streak(.days(3, isCapped: false)) == "Serie 3")
        #expect(HabitText.streak(.weeks(1, isCapped: false)) == "Serie 1 Woche")
        #expect(HabitText.streak(.weeks(4, isCapped: false)) == "Serie 4 Wochen")
    }

    @Test func sourceDetail_water() {
        let water = habit(start: day(11, 1), source: .water)
        var data = HabitFacts.empty
        data.goalWaterMilliliters = 2000
        data.waterMilliliters[today] = 2100
        #expect(HabitText.sourceDetail(water, on: today, facts: data, workout: nil, locale: Locale(identifier: "de_DE")) == "2,1 l von 2,0 l")
    }

    @Test func sourceDetail_healthWorkout() {
        let training = habit(start: day(11, 1), source: .workout)
        let workout = WorkoutValue(id: "1", activity: .running, start: testNow(), minutes: 42, kilocalories: nil,
                                   sourceName: "Apple Watch", isOwn: false)
        #expect(HabitText.sourceDetail(training, on: today, facts: .empty, workout: workout, locale: Locale(identifier: "de_DE"))
                == "Laufen 42 min aus Health")
        let own = WorkoutValue(id: "2", activity: .running, start: testNow(), minutes: 30, kilocalories: nil, sourceName: nil, isOwn: true)
        #expect(HabitText.sourceDetail(training, on: today, facts: .empty, workout: own, locale: Locale(identifier: "de_DE"))
                == "Laufen 30 min")
    }

    @Test func sourceDetail_manualHabit_hasNone() {
        #expect(HabitText.sourceDetail(habit(start: day(11, 1)), on: today, facts: .empty, workout: nil) == nil)
    }

    @Test func header_withAndWithoutCounter() {
        #expect(HabitText.header(HabitCounter(done: 3, total: 5)) == "Gewohnheiten · 3 von 5")
        #expect(HabitText.header(nil) == "Gewohnheiten")
    }

    @Test func symbols_offerAtLeastTwelveUniqueChoices() {
        #expect(HabitText.symbols.count >= 12 && Set(HabitText.symbols).count == HabitText.symbols.count)
    }

    @Test func rhythmFooter_namesTheDays() {
        #expect(HabitText.rhythm(7) == "Täglich")
        #expect(HabitText.rhythm(3) == "3 Tage pro Woche")
        #expect(HabitText.rhythm(1) == "1 Tag pro Woche")
    }
}
