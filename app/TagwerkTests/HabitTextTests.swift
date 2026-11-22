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

    @Test func subtitle_dailyWithoutCountingDays_hasNoZeroOverZero() {
        let fresh = habit(start: today)
        #expect(HabitText.subtitle(fresh, today: today, facts: .empty, calendar: calendar).hasPrefix("7 Tage – · 30 Tage –"))
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

    @Test func sourceDetail_movement_namesWhatCounted() {
        let german = Locale(identifier: "de_DE")
        let movement = habit(start: day(11, 1), source: .movement)
        var data = HabitFacts.empty
        data.goalSteps = 8000
        data.steps[today] = 10_412
        // A step goal reached on a day without a workout: the steps are named.
        #expect(HabitText.sourceDetail(movement, on: today, facts: data, workout: nil, locale: german) == "10.412 von 8.000 Schritten")
        // A counted workout names itself, also when the step goal is reached too.
        data.workoutDays = [today]
        let run = WorkoutValue(id: "1", activity: .running, start: testNow(), minutes: 42, kilocalories: nil, sourceName: nil, isOwn: true)
        #expect(HabitText.sourceDetail(movement, on: today, facts: data, workout: run, locale: german) == "Laufen 42 min")
        // Without a step goal and without workout details there is nothing to name.
        #expect(HabitText.sourceDetail(movement, on: today, facts: .empty, workout: nil, locale: german) == nil)
        #expect(HabitText.sourceTitle(.movement) == "Bewegung")
        #expect(HabitText.sourceSubtitle(.movement) == "Training erfasst oder Schrittziel erreicht" && HabitText.sourceSubtitle(.water) == nil)
    }

    // MARK: States of a row

    private let german = Locale(identifier: "de_DE")

    private func row(_ habit: Habit, _ state: HabitsModel.Row.State) -> HabitsModel.Row {
        HabitsModel.Row(habit: habit, isFulfilled: state == .automaticDone || state == .manualDone, isAutomatic: state == .automaticDone, state: state)
    }

    @Test func sourceProgress_waterAndSteps() {
        var data = HabitFacts.empty
        data.goalWaterMilliliters = 2000
        data.waterMilliliters[today] = 500
        data.goalSteps = 8000
        data.steps[today] = 5600
        #expect(HabitText.sourceProgress(habit(start: day(11, 1), source: .water), on: today, facts: data) == 0.25)
        #expect(HabitText.sourceProgress(habit(start: day(11, 1), source: .steps), on: today, facts: data) == 0.7)
        #expect(HabitText.sourceProgress(habit(start: day(11, 1), source: .movement), on: today, facts: data) == 0.7)
        data.steps[today] = 20_000
        #expect(HabitText.sourceProgress(habit(start: day(11, 1), source: .steps), on: today, facts: data) == 1)
        // No goal, nothing to measure against.
        data.goalWaterMilliliters = 0
        data.goalSteps = 0
        #expect(HabitText.sourceProgress(habit(start: day(11, 1), source: .water), on: today, facts: data) == nil)
        #expect(HabitText.sourceProgress(habit(start: day(11, 1), source: .movement), on: today, facts: data) == nil)
    }

    @Test func sourceProgress_binarySources_nil() {
        var data = HabitFacts.empty
        data.goalWaterMilliliters = 2000
        data.goalSteps = 8000
        for source in [HabitSource.manual, .workout, .daylight, .eveningClosed, .journal, .bibleStudy] {
            #expect(HabitText.sourceProgress(habit(start: day(11, 1), source: source), on: today, facts: data) == nil, "\(source)")
        }
    }

    @Test func stateLine_perState() {
        var data = HabitFacts.empty
        data.goalWaterMilliliters = 2000
        data.waterMilliliters[today] = 2100
        data.goalSteps = 8000
        data.steps[today] = 5600
        func line(_ habit: Habit, _ state: HabitsModel.Row.State) -> String? {
            HabitText.stateLine(row(habit, state), on: today, facts: data, workout: nil, locale: german)
        }
        let water = habit(start: day(11, 1), source: .water)
        let steps = habit(start: day(11, 1), source: .steps)
        let journal = habit(start: day(11, 1), source: .journal)
        #expect(line(water, .automaticDone) == "Automatisch erfüllt · 2,1 l von 2,0 l")
        #expect(line(journal, .automaticDone) == "Automatisch erfüllt")
        #expect(line(steps, .automaticPending(progress: 0.7)) == "5.600 von 8.000 Schritten · hakt sich selbst ab")
        #expect(line(journal, .automaticPending(progress: nil)) == "Tagebuch noch offen · hakt sich selbst ab")
        #expect(line(journal, .manualDoneSourcePending) == "Von Hand abgehakt · Tagebuch noch offen")
        #expect(line(habit(start: day(11, 1)), .manualOpen) == nil && line(habit(start: day(11, 1)), .manualDone) == nil)
    }

    @Test func accessibilityValue_namesState() {
        #expect(HabitText.accessibilityState(.manualOpen) == "offen")
        #expect(HabitText.accessibilityState(.manualDone) == "erledigt")
        #expect(HabitText.accessibilityState(.automaticDone) == "automatisch erfüllt")
        #expect(HabitText.accessibilityState(.automaticPending(progress: 0.5)) == "offen, hakt sich selbst ab")
        #expect(HabitText.accessibilityState(.manualDoneSourcePending) == "von Hand abgehakt")
    }

    @Test func sourceNoun_existsForEveryAutomaticSource() {
        for source in HabitSource.allCases where source != .manual { #expect(!HabitText.sourceNoun(source).isEmpty, "\(source)") }
    }

    @Test func automaticHint_namesSource() {
        #expect(HabitText.automaticHint(.water) == "Automatisch erfüllt durch das Wasserziel. Lässt sich nicht abwählen.")
        #expect(HabitText.automaticHint(.eveningClosed) == "Automatisch erfüllt durch den Tagesabschluss. Lässt sich nicht abwählen.")
        #expect(HabitText.automaticHint(.manual) == nil)
        // Every automatic source has its own sentence, and each one says it cannot be unchecked.
        let hints = HabitSource.allCases.filter { $0 != .manual }.compactMap(HabitText.automaticHint)
        #expect(hints.count == HabitSource.allCases.count - 1 && Set(hints).count == hints.count)
        #expect(hints.allSatisfy { $0.hasSuffix("Lässt sich nicht abwählen.") && $0.hasPrefix("Automatisch erfüllt durch ") })
    }

    @Test func symbolName_coversEverySymbol() {
        for symbol in HabitText.symbols {
            let name = HabitText.symbolName(symbol)
            #expect(!name.isEmpty && name != symbol, "No name for \(symbol)")
        }
        let names = HabitText.symbols.map(HabitText.symbolName)
        #expect(Set(names).count == names.count)
        #expect(HabitText.symbolName("figure.walk") == "Gehen")
        #expect(HabitText.symbolName("unknown.symbol") == "unknown.symbol")
    }

    @Test func footer_matchesDecision() {
        #expect(HabitText.sourceFooter == "Automatische Quellen haken sich selbst ab, auch an Tagen ohne App-Start. Bis dahin kannst du von Hand abhaken; ein automatisch gesetzter Haken lässt sich nicht abwählen. Jede Quelle gilt für höchstens eine Gewohnheit.")
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
