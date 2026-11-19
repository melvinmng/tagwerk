import Foundation
import Testing
@testable import TagwerkCore

struct HabitRulesTests {
    let calendar = makeCalendar()
    let today = PlanDay(year: 2026, month: 11, day: 18)   // Wednesday

    private func day(_ month: Int, _ day: Int) -> PlanDay { PlanDay(year: 2026, month: month, day: day) }

    private func habit(start: PlanDay, source: HabitSource = .manual, daysPerWeek: Int = 7, pauses: [HabitPause] = [],
                       pausedSince: PlanDay? = nil, daylightMinutes: Int = 20) -> Habit {
        Habit(id: UUID(), name: "Lesen 20 min", symbol: "book", order: 0, source: source, daysPerWeek: daysPerWeek,
              daylightMinutes: daylightMinutes, start: start, pausedSince: pausedSince, pauses: pauses)
    }

    private func facts(_ habit: Habit, checked days: [PlanDay]) -> HabitFacts {
        var facts = HabitFacts.empty
        facts.manualChecks[habit.id] = Set(days)
        return facts
    }

    @Test func active_respectsStartPausesAndFuture() {
        let paused = habit(start: day(11, 10), pauses: [HabitPause(from: day(11, 12), to: day(11, 13))])
        #expect(!HabitRules.isActive(paused, on: day(11, 9), today: today))
        #expect(HabitRules.isActive(paused, on: day(11, 10), today: today))
        #expect(!HabitRules.isActive(paused, on: day(11, 12), today: today))
        #expect(HabitRules.isActive(paused, on: day(11, 14), today: today))
        #expect(!HabitRules.isActive(paused, on: day(11, 19), today: today))
        let open = habit(start: day(11, 10), pausedSince: day(11, 17))
        #expect(HabitRules.isActive(open, on: day(11, 16), today: today))
        #expect(!HabitRules.isActive(open, on: day(11, 17), today: today))
        #expect(!HabitRules.isActive(open, on: day(11, 18), today: today))
    }

    @Test func fulfilled_byManualCheckOrSource() {
        var water = habit(start: day(11, 1), source: .water)
        var data = HabitFacts.empty
        data.goalWaterMilliliters = 2000
        data.waterMilliliters[today] = 2100
        #expect(HabitRules.isFulfilled(water, on: today, facts: data))
        data.waterMilliliters[today] = 1900
        #expect(!HabitRules.isFulfilled(water, on: today, facts: data))
        data.goalWaterMilliliters = 0
        data.waterMilliliters[today] = 5000
        #expect(!HabitRules.isFulfilled(water, on: today, facts: data))
        data.manualChecks[water.id] = [today]
        #expect(HabitRules.isFulfilled(water, on: today, facts: data))
        water.source = .workout
        var workoutData = HabitFacts.empty
        workoutData.workoutDays = [today]
        #expect(HabitRules.isFulfilled(water, on: today, facts: workoutData))
        let steps = habit(start: day(11, 1), source: .steps)
        var stepData = HabitFacts.empty
        stepData.goalSteps = 8000
        stepData.steps[today] = 8000
        #expect(HabitRules.isFulfilled(steps, on: today, facts: stepData))
        let daylight = habit(start: day(11, 1), source: .daylight)
        var lightData = HabitFacts.empty
        #expect(!HabitRules.isFulfilled(daylight, on: today, facts: lightData))
        lightData.daylightMinutes[today] = 25
        #expect(HabitRules.isFulfilled(daylight, on: today, facts: lightData))
    }

    @Test func progress_todayCountsOnlyOnceFulfilled() {
        let reading = habit(start: day(11, 1))
        let base = facts(reading, checked: [day(11, 12), day(11, 13), day(11, 15), day(11, 16), day(11, 17)])
        let open = HabitRules.progress(reading, lastDays: 7, today: today, facts: base, calendar: calendar)
        #expect(open.done == 5 && open.counting == 6)
        let withToday = facts(reading, checked: [day(11, 12), day(11, 13), day(11, 15), day(11, 16), day(11, 17), today])
        let done = HabitRules.progress(reading, lastDays: 7, today: today, facts: withToday, calendar: calendar)
        #expect(done.done == 6 && done.counting == 7)
    }

    @Test func rate_usesTargetDays() {
        let training = habit(start: day(10, 21), daysPerWeek: 3)
        // 28 counting days (21.10. ... 17.11.), target 28 * 3 / 7 = 12
        let nineDays = (0..<9).map { day(10, 21).adding(days: $0, calendar: calendar) }
        #expect(HabitRules.rate(training, lastDays: 30, today: today, facts: facts(training, checked: nineDays),
                                calendar: calendar) == 75)
    }

    @Test func rate_capsAtHundred() {
        let training = habit(start: day(10, 21), daysPerWeek: 3)
        let fifteen = (0..<15).map { day(10, 21).adding(days: $0, calendar: calendar) }
        #expect(HabitRules.rate(training, lastDays: 30, today: today, facts: facts(training, checked: fifteen),
                                calendar: calendar) == 100)
    }

    @Test func rate_withoutCountingDays_isNil() {
        let fresh = habit(start: today)
        #expect(HabitRules.rate(fresh, lastDays: 30, today: today, facts: .empty, calendar: calendar) == nil)
    }

    @Test func dailyStreak_runsToYesterdayAndIncludesFulfilledToday() {
        let reading = habit(start: day(11, 1))
        let three = facts(reading, checked: [day(11, 15), day(11, 16), day(11, 17)])
        #expect(HabitRules.streak(reading, today: today, facts: three, calendar: calendar) == .days(3, isCapped: false))
        let four = facts(reading, checked: [day(11, 15), day(11, 16), day(11, 17), today])
        #expect(HabitRules.streak(reading, today: today, facts: four, calendar: calendar) == .days(4, isCapped: false))
        let broken = facts(reading, checked: [day(11, 13), day(11, 15), day(11, 16), day(11, 17)])
        #expect(HabitRules.streak(reading, today: today, facts: broken, calendar: calendar) == .days(3, isCapped: false))
    }

    @Test func dailyStreak_skipsPausedDays() {
        let reading = habit(start: day(11, 1), pauses: [HabitPause(from: day(11, 14), to: day(11, 14))])
        let data = facts(reading, checked: [day(11, 13), day(11, 15), day(11, 16), day(11, 17)])
        #expect(HabitRules.streak(reading, today: today, facts: data, calendar: calendar) == .days(4, isCapped: false))
    }

    @Test func weekGoal_isProratedAndAtLeastOne() {
        #expect(HabitRules.weekGoal(daysPerWeek: 3, countingDays: 7) == 3)
        #expect(HabitRules.weekGoal(daysPerWeek: 3, countingDays: 4) == 2)
        #expect(HabitRules.weekGoal(daysPerWeek: 3, countingDays: 1) == 1)
        #expect(HabitRules.weekGoal(daysPerWeek: 5, countingDays: 2) == 1)
        #expect(HabitRules.weekGoal(daysPerWeek: 2, countingDays: 1) == 1)
    }

    @Test func weeklyStreak_countsWeeksThatReachedTheGoal() {
        let training = habit(start: day(10, 26), daysPerWeek: 3)
        let checks = [day(10, 26), day(10, 28), day(10, 30), day(11, 2), day(11, 4), day(11, 6),
                      day(11, 9), day(11, 11), day(11, 13), day(11, 16), day(11, 17)]
        #expect(HabitRules.streak(training, today: today, facts: facts(training, checked: checks), calendar: calendar)
                == .weeks(3, isCapped: false))
        #expect(HabitRules.streak(training, today: today, facts: facts(training, checked: checks + [today]), calendar: calendar)
                == .weeks(4, isCapped: false))
        let broken = [day(10, 26), day(10, 28), day(10, 30), day(11, 2), day(11, 4), day(11, 6), day(11, 9), day(11, 10)]
        #expect(HabitRules.streak(training, today: today, facts: facts(training, checked: broken), calendar: calendar)
                == .weeks(0, isCapped: false))
    }

    @Test func streak_capsAtTheWindow() {
        let start = PlanDay(year: 2026, month: 8, day: 1)
        let everyDay = (0..<110).map { start.adding(days: $0, calendar: calendar) }.filter { $0 <= today }
        let daily = habit(start: start)
        #expect(HabitRules.streak(daily, today: today, facts: facts(daily, checked: everyDay), calendar: calendar)
                == .days(90, isCapped: true))
        let weekly = habit(start: start, daysPerWeek: 3)
        #expect(HabitRules.streak(weekly, today: today, facts: facts(weekly, checked: everyDay), calendar: calendar)
                == .weeks(12, isCapped: true))
    }

    @Test func counter_countsWeeklyGoalReachedAsDone() {
        let first = habit(start: day(11, 1))
        let second = habit(start: day(11, 1))
        let third = habit(start: day(11, 1), daysPerWeek: 2)
        var data = HabitFacts.empty
        data.manualChecks[first.id] = [today]
        data.manualChecks[third.id] = [day(11, 16), day(11, 17)]
        let counter = HabitRules.counter([first, second, third], today: today, facts: data, calendar: calendar)
        #expect(counter == HabitCounter(done: 2, total: 3))
    }

    @Test func counter_withoutActiveHabits_isNil() {
        let paused = habit(start: day(11, 1), pausedSince: day(11, 10))
        #expect(HabitRules.counter([paused], today: today, facts: .empty, calendar: calendar) == nil)
    }

    @Test func weekSummaries_dailyHabit_runningWeek() {
        let reading = habit(start: day(11, 1))
        let data = facts(reading, checked: [day(11, 16), day(11, 17)])
        let summaries = HabitRules.weekSummaries([reading], weekStart: day(11, 16), today: today, facts: data, calendar: calendar)
        #expect(summaries.count == 1)
        #expect(summaries[0].done == 2 && summaries[0].total == 2 && summaries[0].isRunning)
    }

    @Test func weekSummaries_weeklyHabit_usesTheWeekGoal() {
        let training = habit(start: day(11, 1), daysPerWeek: 3)
        let data = facts(training, checked: [day(11, 16), day(11, 17)])
        let summary = HabitRules.weekSummaries([training], weekStart: day(11, 16), today: today, facts: data, calendar: calendar)[0]
        #expect(summary.done == 2 && summary.total == 3)
    }

    @Test func weekSummaries_skipHabitsNotActiveInTheWeek() {
        let later = habit(start: day(11, 23))
        let paused = habit(start: day(11, 1), pausedSince: day(11, 10))
        let summaries = HabitRules.weekSummaries([later, paused], weekStart: day(11, 16), today: today, facts: .empty, calendar: calendar)
        #expect(summaries.isEmpty)
    }

    @Test func dayKey_roundTrips() {
        #expect(PlanDay(year: 2026, month: 11, day: 8).dayKey == "2026-11-08")
        #expect(PlanDay(dayKey: "2026-11-08") == PlanDay(year: 2026, month: 11, day: 8))
        #expect(PlanDay(dayKey: "nope") == nil)
    }
}
