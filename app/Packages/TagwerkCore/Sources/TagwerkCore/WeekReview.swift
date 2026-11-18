import Foundation

/// The weekly review of the "Erfassen" tab (phase 4 design §5.6): Monday to Sunday in local time.
public struct WeekReview: Sendable, Hashable {
    public struct Goals: Sendable, Hashable {
        public var kcal: Int
        public var waterMilliliters: Int
        /// 0 means no training goal.
        public var workoutMinutesPerWeek: Int
        /// 0 means no step goal; no day then counts as reaching it.
        public var stepsPerDay: Int
        /// `nil` while the protein goal is off; the review then shows no protein.
        public var proteinGrams: Int?

        public init(kcal: Int, waterMilliliters: Int, workoutMinutesPerWeek: Int, stepsPerDay: Int, proteinGrams: Int?) {
            self.kcal = kcal
            self.waterMilliliters = waterMilliliters
            self.workoutMinutesPerWeek = workoutMinutesPerWeek
            self.stepsPerDay = stepsPerDay
            self.proteinGrams = proteinGrams
        }
    }

    public struct Day: Sendable, Hashable, Identifiable {
        public var id: PlanDay { day }
        public var day: PlanDay
        /// `nil` when no meal was recorded (shown as "keine Einträge", not as 0).
        public var kcal: Double?
        public var hasEstimate: Bool
        public var waterMilliliters: Int?
        public var protein: Double?
        /// Steps from Health; `nil` without a value (shown dashed, never as 0) and for later days.
        public var steps: Int?
        /// Later days of the current week.
        public var isFuture: Bool
    }

    public var weekStart: PlanDay
    public var days: [Day]
    public var goals: Goals
    public var daysWithMeals: Int
    public var averageKcal: Double?
    public var hasEstimate: Bool
    public var waterGoalDays: Int
    public var daysWithWater: Int
    public var averageWaterMilliliters: Int?
    /// Workouts of at least `IntakeRules.minimumWorkoutMinutes`, shown as an addition to the minutes.
    public var workoutCount: Int
    /// All workouts of the week, short ones included.
    public var workoutMinutes: Int
    public var daysWithSteps: Int
    /// Rounded mean over the days with a step value; `nil` without any.
    public var averageSteps: Int?
    public var stepGoalDays: Int
    public var averageProtein: Double?
    public var completedTasks: Int
    public var isCurrentWeek: Bool

    /// Nothing recorded in Tagwerk or as a workout; steps alone do not count, they arrive without any entry.
    public var isEmpty: Bool { daysWithMeals == 0 && daysWithWater == 0 && workoutMinutes == 0 && completedTasks == 0 }

    /// `workouts` are own and Health workouts; `steps` are Health day sums; `completedDates` are completion moments of
    /// reminders and local tasks.
    public static func make(weekStart: PlanDay, now: Date, meals: [MealValue], drinks: [DrinkValue], workouts: [WorkoutValue],
                            steps: [PlanDay: Int] = [:], completedDates: [Date], goals: Goals,
                            calendar: Calendar) -> WeekReview {
        let today = PlanDay(date: now, calendar: calendar)
        let start = weekStart.startDate(in: calendar)
        let end = weekStart.adding(days: 7, calendar: calendar).startDate(in: calendar)
        let inWeek = { (date: Date) in date >= start && date < end }
        let mealsByDay = Dictionary(grouping: meals.filter { inWeek($0.date) }) { PlanDay(date: $0.date, calendar: calendar) }
        let drinksByDay = Dictionary(grouping: drinks.filter { inWeek($0.date) }) { PlanDay(date: $0.date, calendar: calendar) }

        let days = (0..<7).map { offset -> Day in
            let day = weekStart.adding(days: offset, calendar: calendar)
            let dayMeals = mealsByDay[day] ?? []
            let dayDrinks = drinksByDay[day] ?? []
            let intake = IntakeRules.dayIntake(meals: dayMeals, drinks: dayDrinks)
            let isFuture = day > today
            return Day(day: day, kcal: dayMeals.isEmpty ? nil : intake.kcal, hasEstimate: intake.hasEstimate,
                       waterMilliliters: dayDrinks.isEmpty ? nil : intake.waterMilliliters,
                       protein: dayMeals.isEmpty ? nil : intake.protein, steps: isFuture ? nil : steps[day], isFuture: isFuture)
        }

        let kcalDays = days.compactMap(\.kcal)
        let waterDays = days.compactMap(\.waterMilliliters)
        let proteinDays = days.compactMap(\.protein)
        let stepDays = days.compactMap(\.steps)
        let weekWorkouts = workouts.filter { inWeek($0.start) }
        return WeekReview(
            weekStart: weekStart, days: days, goals: goals,
            daysWithMeals: kcalDays.count,
            averageKcal: kcalDays.isEmpty ? nil : kcalDays.reduce(0, +) / Double(kcalDays.count),
            hasEstimate: days.contains { $0.kcal != nil && $0.hasEstimate },
            waterGoalDays: waterDays.filter { $0 >= goals.waterMilliliters }.count,
            daysWithWater: waterDays.count,
            averageWaterMilliliters: waterDays.isEmpty ? nil : waterDays.reduce(0, +) / waterDays.count,
            workoutCount: weekWorkouts.filter { $0.minutes >= IntakeRules.minimumWorkoutMinutes }.count,
            workoutMinutes: IntakeRules.workoutMinutes(weekWorkouts, in: DateInterval(start: start, end: end)),
            daysWithSteps: stepDays.count,
            averageSteps: stepDays.isEmpty ? nil : Int((Double(stepDays.reduce(0, +)) / Double(stepDays.count)).rounded()),
            stepGoalDays: goals.stepsPerDay > 0 ? stepDays.filter { $0 >= goals.stepsPerDay }.count : 0,
            averageProtein: goals.proteinGrams == nil || proteinDays.isEmpty
                ? nil : proteinDays.reduce(0, +) / Double(proteinDays.count),
            completedTasks: completedDates.filter(inWeek).count,
            isCurrentWeek: (weekStart...weekStart.adding(days: 6, calendar: calendar)).contains(today))
    }

    /// "KW 47 · 16.–22. Nov" or "KW 49 · 30. Nov – 6. Dez" across months (ISO week number); the English texts
    /// order week, month and day as the language does.
    public static func title(weekStart: PlanDay, calendar: Calendar, locale: Locale = .current) -> String {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = calendar.timeZone
        let start = weekStart.startDate(in: calendar)
        let endDay = weekStart.adding(days: 6, calendar: calendar)
        let week = iso.component(.weekOfYear, from: start)
        let month = DateFormatter()
        month.locale = locale
        month.timeZone = calendar.timeZone
        month.dateFormat = "MMM"
        let startMonth = month.string(from: start).replacingOccurrences(of: ".", with: "")
        let endMonth = month.string(from: endDay.startDate(in: calendar)).replacingOccurrences(of: ".", with: "")
        let firstDay = weekStart.day, lastDay = endDay.day
        return startMonth == endMonth
            ? String(localized: "KW \(week) · \(firstDay).–\(lastDay). \(endMonth)", bundle: .module)
            : String(localized: "KW \(week) · \(firstDay). \(startMonth) – \(lastDay). \(endMonth)", bundle: .module)
    }
}

extension IntakeFormat {
    /// The line in the head of "Planen" (phase 4 design §5.7): "~1.240 / 2.300 kcal · 1,2 / 2,0 l", with today's steps
    /// appended when known ("· 6.412 Schritte"); `nil` before the first entry of the day.
    public static func planHeaderLine(intake: DayIntake, goalKcal: Int, goalWaterMilliliters: Int, hasEntries: Bool,
                                      steps: Int? = nil, locale: Locale = .current) -> String? {
        guard hasEntries else { return nil }
        let energy = kcalNumber(intake.kcal, estimated: intake.hasEstimate, locale: locale)
        let goalEnergy = grouped(goalKcal, locale: locale)
        let water = intake.waterMilliliters == 0 ? "0" : litersNumber(intake.waterMilliliters, locale: locale)
        let goalWater = liters(goalWaterMilliliters, locale: locale)
        let line = String(localized: "\(energy) / \(goalEnergy) kcal · \(water) / \(goalWater)", bundle: .module)
        guard let steps else { return line }
        let count = self.steps(steps, locale: locale)
        return line + " · " + String(localized: "\(count) Schritte", bundle: .module)
    }

    /// Training in the weekly review: "2 h 7 min / 2 h 30 min · 3 Trainings"; the count only names workouts of at least
    /// 10 min, the goal part is left out when the goal is 0.
    public static func weekTraining(minutes: Int, count: Int, goal: Int) -> String {
        guard minutes > 0 else { return String(localized: "Kein Training", bundle: .module) }
        let time = goal > 0 ? duration(minutes: minutes, goal: goal) : duration(minutes: minutes)
        guard count > 0 else { return time }
        return time + " · " + String(localized: "\(count) Trainings", bundle: .module)
    }

    /// Steps in the weekly review: "Ø 6.801 pro Tag · Ziel an 1 von 3 Tagen"; without a goal only the mean.
    public static func weekSteps(average: Int?, goalDays: Int, elapsedDays: Int, goal: Int, locale: Locale = .current) -> String {
        guard let average else { return String(localized: "Keine Schritte aus Health", bundle: .module) }
        let mean = String(localized: "Ø \(steps(average, locale: locale)) pro Tag", bundle: .module)
        guard goal > 0 else { return mean }
        return mean + " · " + String(localized: "Ziel an \(goalDays) von \(elapsedDays) Tagen", bundle: .module)
    }
}
