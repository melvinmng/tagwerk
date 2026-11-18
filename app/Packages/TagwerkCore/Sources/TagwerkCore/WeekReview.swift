import Foundation

/// The weekly review of the "Erfassen" tab (phase 4 design §5.6): Monday to Sunday in local time.
public struct WeekReview: Sendable, Hashable {
    public struct Goals: Sendable, Hashable {
        public var kcal: Int
        public var waterMilliliters: Int
        public var workoutsPerWeek: Int
        /// `nil` while the protein goal is off; the review then shows no protein.
        public var proteinGrams: Int?

        public init(kcal: Int, waterMilliliters: Int, workoutsPerWeek: Int, proteinGrams: Int?) {
            self.kcal = kcal
            self.waterMilliliters = waterMilliliters
            self.workoutsPerWeek = workoutsPerWeek
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
    public var workoutCount: Int
    public var workoutMinutes: Int
    public var averageProtein: Double?
    public var completedTasks: Int
    public var isCurrentWeek: Bool

    public var isEmpty: Bool { daysWithMeals == 0 && daysWithWater == 0 && workoutCount == 0 && completedTasks == 0 }

    /// `workouts` are own and Health workouts; `completedDates` are completion moments of reminders and local tasks.
    public static func make(weekStart: PlanDay, now: Date, meals: [MealValue], drinks: [DrinkValue], workouts: [WorkoutValue],
                            completedDates: [Date], goals: Goals, calendar: Calendar) -> WeekReview {
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
            return Day(day: day, kcal: dayMeals.isEmpty ? nil : intake.kcal, hasEstimate: intake.hasEstimate,
                       waterMilliliters: dayDrinks.isEmpty ? nil : intake.waterMilliliters,
                       protein: dayMeals.isEmpty ? nil : intake.protein, isFuture: day > today)
        }

        let kcalDays = days.compactMap(\.kcal)
        let waterDays = days.compactMap(\.waterMilliliters)
        let proteinDays = days.compactMap(\.protein)
        let counted = workouts.filter { inWeek($0.start) && $0.minutes >= IntakeRules.minimumWorkoutMinutes }
        return WeekReview(
            weekStart: weekStart, days: days, goals: goals,
            daysWithMeals: kcalDays.count,
            averageKcal: kcalDays.isEmpty ? nil : kcalDays.reduce(0, +) / Double(kcalDays.count),
            hasEstimate: days.contains { $0.kcal != nil && $0.hasEstimate },
            waterGoalDays: waterDays.filter { $0 >= goals.waterMilliliters }.count,
            daysWithWater: waterDays.count,
            averageWaterMilliliters: waterDays.isEmpty ? nil : waterDays.reduce(0, +) / waterDays.count,
            workoutCount: counted.count,
            workoutMinutes: counted.reduce(0) { $0 + $1.minutes },
            averageProtein: goals.proteinGrams == nil || proteinDays.isEmpty
                ? nil : proteinDays.reduce(0, +) / Double(proteinDays.count),
            completedTasks: completedDates.filter(inWeek).count,
            isCurrentWeek: (weekStart...weekStart.adding(days: 6, calendar: calendar)).contains(today))
    }

    /// "KW 47 · 16.–22. Nov." or "KW 49 · 30. Nov. – 6. Dez." across months (ISO week number).
    public static func title(weekStart: PlanDay, calendar: Calendar) -> String {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = calendar.timeZone
        let start = weekStart.startDate(in: calendar)
        let endDay = weekStart.adding(days: 6, calendar: calendar)
        let week = iso.component(.weekOfYear, from: start)
        let month = DateFormatter()
        month.locale = Locale(identifier: "de_DE")
        month.timeZone = calendar.timeZone
        month.dateFormat = "MMM"
        let startMonth = month.string(from: start)
        let endMonth = month.string(from: endDay.startDate(in: calendar))
        let range = startMonth == endMonth
            ? "\(weekStart.day).–\(endDay.day). \(endMonth)"
            : "\(weekStart.day). \(startMonth) – \(endDay.day). \(endMonth)"
        return "KW \(week) · \(range)"
    }
}

extension IntakeFormat {
    /// The line in the head of "Planen" (phase 4 design §5.7): "~1.240 / 2.300 kcal · 1,2 / 2,0 l";
    /// `nil` before the first entry of the day.
    public static func planHeaderLine(intake: DayIntake, goalKcal: Int, goalWaterMilliliters: Int, hasEntries: Bool) -> String? {
        guard hasEntries else { return nil }
        let water = liters(intake.waterMilliliters).replacingOccurrences(of: " l", with: "")
        return "\(kcalNumber(intake.kcal, estimated: intake.hasEstimate)) / \(grouped(goalKcal)) kcal · "
            + "\(water) / \(liters(goalWaterMilliliters))"
    }
}
