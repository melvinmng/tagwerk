import Foundation

public extension PlanDay {
    /// "YYYY-MM-DD"; the same key notes use.
    var dayKey: String { NoteDayKey.string(self) }

    init?(dayKey: String) {
        guard let day = NoteDayKey.day(dayKey) else { return nil }
        self = day
    }
}

/// What fulfils a habit besides a manual check.
public enum HabitSource: String, Sendable, Codable, CaseIterable {
    case manual, water, workout, steps, daylight
}

/// A closed pause of a habit; both ends are included.
public struct HabitPause: Sendable, Hashable, Codable {
    public var from: PlanDay
    public var to: PlanDay

    public init(from: PlanDay, to: PlanDay) {
        self.from = from
        self.to = to
    }
}

/// A habit as the rules see it (phase 7 design §5.1).
public struct Habit: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var symbol: String
    public var order: Int
    public var source: HabitSource
    public var daysPerWeek: Int
    public var daylightMinutes: Int
    public var start: PlanDay
    public var pausedSince: PlanDay?
    public var pauses: [HabitPause]

    public init(id: UUID = UUID(), name: String, symbol: String, order: Int, source: HabitSource = .manual,
                daysPerWeek: Int = 7, daylightMinutes: Int = 20, start: PlanDay, pausedSince: PlanDay? = nil,
                pauses: [HabitPause] = []) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.order = order
        self.source = source
        self.daysPerWeek = daysPerWeek
        self.daylightMinutes = daylightMinutes
        self.start = start
        self.pausedSince = pausedSince
        self.pauses = pauses
    }
}

/// The values the rules read; the app fills them from its stores and from Health.
public struct HabitFacts: Sendable, Equatable {
    public var manualChecks: [UUID: Set<PlanDay>]
    public var waterMilliliters: [PlanDay: Int]
    /// Days with a workout of at least `IntakeRules.minimumWorkoutMinutes`.
    public var workoutDays: Set<PlanDay>
    public var steps: [PlanDay: Int]
    public var daylightMinutes: [PlanDay: Int]
    public var goalWaterMilliliters: Int
    public var goalSteps: Int

    public init(manualChecks: [UUID: Set<PlanDay>] = [:], waterMilliliters: [PlanDay: Int] = [:], workoutDays: Set<PlanDay> = [],
                steps: [PlanDay: Int] = [:], daylightMinutes: [PlanDay: Int] = [:], goalWaterMilliliters: Int = 0,
                goalSteps: Int = 0) {
        self.manualChecks = manualChecks
        self.waterMilliliters = waterMilliliters
        self.workoutDays = workoutDays
        self.steps = steps
        self.daylightMinutes = daylightMinutes
        self.goalWaterMilliliters = goalWaterMilliliters
        self.goalSteps = goalSteps
    }

    public static let empty = HabitFacts()
}

/// A streak in days (daily habits) or in weeks (fewer than seven days per week). `isCapped` means "or longer".
public enum HabitStreak: Sendable, Hashable {
    case days(Int, isCapped: Bool)
    case weeks(Int, isCapped: Bool)
}

/// "✓ 3 von 5".
public struct HabitCounter: Sendable, Hashable, Codable {
    public var done: Int
    public var total: Int

    public init(done: Int, total: Int) {
        self.done = done
        self.total = total
    }
}

/// One habit in the weekly review.
public struct HabitWeekSummary: Sendable, Hashable, Identifiable {
    public var id: UUID { habit.id }
    public var habit: Habit
    public var done: Int
    public var total: Int
    public var isRunning: Bool

    public init(habit: Habit, done: Int, total: Int, isRunning: Bool) {
        self.habit = habit
        self.done = done
        self.total = total
        self.isRunning = isRunning
    }
}

/// Pure rules of the habits (phase 7 design §6, rules 1–8). All calculations read at most `windowDays` days back.
public enum HabitRules {
    public static let windowDays = 90
    public static let maximumActive = 10
    public static let nameLimit = 40
    /// Longest streak shown in weeks ("12+").
    public static let windowWeeks = 12

    /// `today − 89 … today`.
    public static func window(today: PlanDay, calendar: Calendar) -> ClosedRange<PlanDay> {
        today.adding(days: -(windowDays - 1), calendar: calendar)...today
    }

    /// Rule 1: started, not paused, not in the future.
    public static func isActive(_ habit: Habit, on day: PlanDay, today: PlanDay) -> Bool {
        day <= today && isCountable(habit, on: day)
    }

    /// Started and not paused, whether or not the day has come yet.
    static func isCountable(_ habit: Habit, on day: PlanDay) -> Bool {
        guard habit.start <= day else { return false }
        if let since = habit.pausedSince, day >= since { return false }
        return !habit.pauses.contains { $0.from <= day && day <= $0.to }
    }

    public static func isSourceFulfilled(_ habit: Habit, on day: PlanDay, facts: HabitFacts) -> Bool {
        switch habit.source {
        case .manual: false
        case .water: facts.goalWaterMilliliters > 0 && (facts.waterMilliliters[day] ?? 0) >= facts.goalWaterMilliliters
        case .workout: facts.workoutDays.contains(day)
        case .steps: facts.goalSteps > 0 && (facts.steps[day] ?? 0) >= facts.goalSteps
        case .daylight: facts.daylightMinutes[day].map { $0 >= habit.daylightMinutes } ?? false
        }
    }

    /// Rule 2.
    public static func isFulfilled(_ habit: Habit, on day: PlanDay, facts: HabitFacts) -> Bool {
        facts.manualChecks[habit.id]?.contains(day) == true || isSourceFulfilled(habit, on: day, facts: facts)
    }

    /// Rule 3: the days of the last `lastDays` days that count (active; today only once fulfilled) and how many of
    /// them are fulfilled.
    public static func progress(_ habit: Habit, lastDays: Int, today: PlanDay, facts: HabitFacts,
                                calendar: Calendar) -> (done: Int, counting: Int) {
        let range = window(today: today, calendar: calendar)
        let first = max(range.lowerBound, today.adding(days: -(lastDays - 1), calendar: calendar))
        var done = 0
        var counting = 0
        var day = first
        while day <= today {
            if isActive(habit, on: day, today: today) {
                let fulfilled = isFulfilled(habit, on: day, facts: facts)
                if day != today || fulfilled {
                    counting += 1
                    if fulfilled { done += 1 }
                }
            }
            day = day.adding(days: 1, calendar: calendar)
        }
        return (done, counting)
    }

    /// Rule 4: percent of the target days, at most 100; `nil` without counting days.
    public static func rate(_ habit: Habit, lastDays: Int, today: PlanDay, facts: HabitFacts, calendar: Calendar) -> Int? {
        let result = progress(habit, lastDays: lastDays, today: today, facts: facts, calendar: calendar)
        guard result.counting > 0 else { return nil }
        let target = Double(result.counting * habit.daysPerWeek) / 7
        return min(100, Int((Double(result.done) / target * 100).rounded()))
    }

    /// Rule 6: the week goal; prorated (rounded, at least 1) for weeks with fewer than seven counting days.
    public static func weekGoal(daysPerWeek: Int, countingDays: Int) -> Int {
        guard countingDays > 0 else { return 0 }
        if countingDays >= 7 { return daysPerWeek }
        return min(countingDays, max(1, Int((Double(daysPerWeek * countingDays) / 7).rounded())))
    }

    /// Fulfilled active days of the Monday-to-Sunday week containing `day`, its goal and the counting days of rule 3.
    /// Future days of the running week belong to the goal: the week is not over.
    public static func weekProgress(_ habit: Habit, weekContaining day: PlanDay, today: PlanDay, facts: HabitFacts,
                                    calendar: Calendar) -> (done: Int, goal: Int, counting: Int) {
        let monday = PlanDay(date: IntakeRules.weekStart(containing: day.startDate(in: calendar), calendar: calendar), calendar: calendar)
        var done = 0
        var counting = 0
        var countable = 0
        for offset in 0..<7 {
            let current = monday.adding(days: offset, calendar: calendar)
            guard isCountable(habit, on: current) else { continue }
            countable += 1
            guard current <= today else { continue }
            let fulfilled = isFulfilled(habit, on: current, facts: facts)
            if fulfilled { done += 1 }
            if current != today || fulfilled { counting += 1 }
        }
        return (done, weekGoal(daysPerWeek: habit.daysPerWeek, countingDays: countable), counting)
    }

    /// Rules 5–7.
    public static func streak(_ habit: Habit, today: PlanDay, facts: HabitFacts, calendar: Calendar) -> HabitStreak {
        let range = window(today: today, calendar: calendar)
        let hiddenHistory = habit.start < range.lowerBound
        if habit.daysPerWeek >= 7 {
            var count = isFulfilled(habit, on: today, facts: facts) && isActive(habit, on: today, today: today) ? 1 : 0
            var day = today.adding(days: -1, calendar: calendar)
            while day >= range.lowerBound {
                if isActive(habit, on: day, today: today) {
                    guard isFulfilled(habit, on: day, facts: facts) else { return .days(count, isCapped: false) }
                    count += 1
                } else if day < habit.start {
                    return .days(count, isCapped: false)
                }
                day = day.adding(days: -1, calendar: calendar)
            }
            return .days(count, isCapped: hiddenHistory)
        }
        var count = 0
        var monday = PlanDay(date: IntakeRules.weekStart(containing: today.startDate(in: calendar), calendar: calendar), calendar: calendar)
        var isRunningWeek = true
        while monday >= range.lowerBound || isRunningWeek {
            let week = weekProgress(habit, weekContaining: monday, today: today, facts: facts, calendar: calendar)
            if week.goal > 0 {
                if week.done >= week.goal {
                    count += 1
                    if count >= windowWeeks { return .weeks(windowWeeks, isCapped: true) }
                } else if !isRunningWeek {
                    return .weeks(count, isCapped: false)
                }
            } else if monday.adding(days: 6, calendar: calendar) < habit.start {
                return .weeks(count, isCapped: false)
            }
            isRunningWeek = false
            monday = monday.adding(days: -7, calendar: calendar)
        }
        return .weeks(count, isCapped: hiddenHistory)
    }

    /// Rule 8: habits active today; a habit counts as done when fulfilled today or, with fewer than seven days per
    /// week, when its week goal is reached. `nil` without an active habit.
    public static func counter(_ habits: [Habit], today: PlanDay, facts: HabitFacts, calendar: Calendar) -> HabitCounter? {
        let active = habits.filter { isActive($0, on: today, today: today) }
        guard !active.isEmpty else { return nil }
        let done = active.filter { habit in
            if isFulfilled(habit, on: today, facts: facts) { return true }
            guard habit.daysPerWeek < 7 else { return false }
            let week = weekProgress(habit, weekContaining: today, today: today, facts: facts, calendar: calendar)
            return week.goal > 0 && week.done >= week.goal
        }.count
        return HabitCounter(done: done, total: active.count)
    }

    /// Habits active on at least one day of the week. Daily habits: fulfilled of counting days; fewer than seven days
    /// per week: fulfilled days of the week goal.
    public static func weekSummaries(_ habits: [Habit], weekStart: PlanDay, today: PlanDay, facts: HabitFacts,
                                     calendar: Calendar) -> [HabitWeekSummary] {
        let weekEnd = weekStart.adding(days: 6, calendar: calendar)
        let isRunning = weekStart <= today && today <= weekEnd
        return habits.compactMap { habit in
            let wasActive = (0..<7).contains { isActive(habit, on: weekStart.adding(days: $0, calendar: calendar), today: today) }
            guard wasActive else { return nil }
            let week = weekProgress(habit, weekContaining: weekStart, today: today, facts: facts, calendar: calendar)
            let total = habit.daysPerWeek >= 7 ? week.counting : week.goal
            return HabitWeekSummary(habit: habit, done: week.done, total: total, isRunning: isRunning)
        }
    }
}
