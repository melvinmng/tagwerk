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
        /// `nil` while the protein goal is off; the review then shows the mean without a goal.
        public var proteinGrams: Int?
        /// Fibre target and sugar limit of the plan that holds now; `nil` without one.
        public var fiberGrams: Int?
        public var sugarLimitGrams: Int?

        public init(kcal: Int, waterMilliliters: Int, workoutMinutesPerWeek: Int, stepsPerDay: Int, proteinGrams: Int?,
                    fiberGrams: Int? = nil, sugarLimitGrams: Int? = nil) {
            self.kcal = kcal
            self.waterMilliliters = waterMilliliters
            self.workoutMinutesPerWeek = workoutMinutesPerWeek
            self.stepsPerDay = stepsPerDay
            self.proteinGrams = proteinGrams
            self.fiberGrams = fiberGrams
            self.sugarLimitGrams = sugarLimitGrams
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
        /// `nil` without a meal (or a value of another app) that day, like `protein`.
        public var carbs: Double?
        public var fat: Double?
        /// The further nutrients of the day; a nutrient no meal knows stays `nil` (never 0).
        public var nutrients: NutrientValues
        /// Energy budget of the day: the base goal of the plan that held on it plus the credited activity (a later day: the base goal).
        public var goalKcal: Int
        /// Carbohydrate and fat goal of the day, grown with the credited activity (decision BU3c); `nil` without a goal or budget.
        public var goalCarbs: Int?
        public var goalFat: Int?
        /// Water and step goals of the plan that held on that day.
        public var goalWaterMilliliters: Int
        public var goalSteps: Int
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
    /// Means per day over the days that know the macro, and how many days that are.
    public var averageProtein: Double?
    public var averageCarbs: Double?
    public var averageFat: Double?
    public var proteinDays: Int
    public var carbsDays: Int
    public var fatDays: Int
    /// Mean of the carbohydrate and fat goals of the days that know the macro; `nil` without a goal.
    public var averageGoalCarbs: Int?
    public var averageGoalFat: Int?
    /// Days with a meal whose eaten energy did not exceed the budget of that day; counted out of `daysWithMeals`.
    public var daysWithinBudget: Int
    /// Mean budget of the days with a meal; `nil` without one.
    public var averageBudgetKcal: Double?
    /// Mean per day over the days that know the nutrient, and how many days that are. Meals without a value are not in the sum, so
    /// the mean is a lower bound.
    public var averageNutrients: NutrientValues
    public var nutrientDays: [Nutrient: Int]
    public var completedTasks: Int
    public var isCurrentWeek: Bool

    /// Nothing recorded in Tagwerk or as a workout; steps alone do not count, they arrive without any entry.
    public var isEmpty: Bool { daysWithMeals == 0 && daysWithWater == 0 && workoutMinutes == 0 && completedTasks == 0 }

    /// `workouts` are own and Health workouts; `steps` are Health day sums; `completedDates` are completion moments of
    /// reminders and local tasks.
    ///
    /// `totals` are what each day counts as eaten (own entries plus, when switched on, other apps' entries), `budgets` the energy
    /// budget of each day and `plans` the goal plan that held on it. A day without an entry there uses the own entries and the
    /// single `goals`, so the review of a week stays what it was while a caller does not know the budget.
    public static func make(weekStart: PlanDay, now: Date, meals: [MealValue], drinks: [DrinkValue], workouts: [WorkoutValue],
                            steps: [PlanDay: Int] = [:], completedDates: [Date], goals: Goals,
                            totals: [PlanDay: IntakeTotals] = [:], budgets: [PlanDay: EnergyBudget] = [:],
                            plans: [PlanDay: GoalPlan] = [:], calendar: Calendar) -> WeekReview {
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
            let own = IntakeRules.dayIntake(meals: dayMeals, drinks: dayDrinks)
            let total = totals[day] ?? IntakeTotals(own: own, foreign: nil)
            let isFuture = day > today
            let foreign = total.foreign
            var nutrients = NutrientValues()
            for nutrient in Nutrient.allCases { nutrients[nutrient] = total.nutrient(nutrient).value }
            return Day(day: day, kcal: dayMeals.isEmpty && foreign?.kcal == nil ? nil : total.kcal, hasEstimate: total.hasEstimate,
                       waterMilliliters: dayDrinks.isEmpty && foreign?.waterMilliliters == nil ? nil : total.waterMilliliters,
                       protein: dayMeals.isEmpty && foreign?.protein == nil ? nil : total.protein,
                       carbs: dayMeals.isEmpty && foreign?.carbs == nil ? nil : total.carbs,
                       fat: dayMeals.isEmpty && foreign?.fat == nil ? nil : total.fat, nutrients: nutrients,
                       goalKcal: budgets[day]?.budget ?? goals.kcal,
                       goalCarbs: budgets[day]?.scaledCarbs, goalFat: budgets[day]?.scaledFat,
                       goalWaterMilliliters: plans[day]?.waterMilliliters ?? goals.waterMilliliters,
                       goalSteps: plans[day]?.stepsPerDay ?? goals.stepsPerDay,
                       steps: isFuture ? nil : steps[day], isFuture: isFuture)
        }

        let kcalDays = days.compactMap(\.kcal)
        let waterDays = days.compactMap(\.waterMilliliters)
        let proteinDays = days.compactMap(\.protein)
        let carbsDays = days.compactMap(\.carbs)
        let fatDays = days.compactMap(\.fat)
        let withMeals = days.filter { $0.kcal != nil }
        func mean(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
        func goalMean(_ values: [Int]) -> Int? { mean(values.map(Double.init)).map { Int($0.rounded()) } }
        let stepDays = days.compactMap(\.steps)
        var averageNutrients = NutrientValues()
        var nutrientDays: [Nutrient: Int] = [:]
        for nutrient in Nutrient.allCases {
            let values = days.compactMap { $0.nutrients[nutrient] }
            nutrientDays[nutrient] = values.count
            averageNutrients[nutrient] = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
        let weekWorkouts = workouts.filter { inWeek($0.start) }
        return WeekReview(
            weekStart: weekStart, days: days, goals: goals,
            daysWithMeals: kcalDays.count,
            averageKcal: kcalDays.isEmpty ? nil : kcalDays.reduce(0, +) / Double(kcalDays.count),
            hasEstimate: days.contains { $0.kcal != nil && $0.hasEstimate },
            waterGoalDays: days.filter { ($0.waterMilliliters ?? 0) >= $0.goalWaterMilliliters && $0.waterMilliliters != nil }.count,
            daysWithWater: waterDays.count,
            averageWaterMilliliters: waterDays.isEmpty ? nil : waterDays.reduce(0, +) / waterDays.count,
            workoutCount: weekWorkouts.filter { $0.minutes >= IntakeRules.minimumWorkoutMinutes }.count,
            workoutMinutes: IntakeRules.workoutMinutes(weekWorkouts, in: DateInterval(start: start, end: end)),
            daysWithSteps: stepDays.count,
            averageSteps: stepDays.isEmpty ? nil : Int((Double(stepDays.reduce(0, +)) / Double(stepDays.count)).rounded()),
            stepGoalDays: days.filter { $0.goalSteps > 0 && ($0.steps ?? -1) >= $0.goalSteps }.count,
            averageProtein: mean(proteinDays), averageCarbs: mean(carbsDays), averageFat: mean(fatDays),
            proteinDays: proteinDays.count, carbsDays: carbsDays.count, fatDays: fatDays.count,
            averageGoalCarbs: goalMean(days.filter { $0.carbs != nil }.compactMap(\.goalCarbs)),
            averageGoalFat: goalMean(days.filter { $0.fat != nil }.compactMap(\.goalFat)),
            daysWithinBudget: withMeals.filter { ($0.kcal ?? 0) <= Double($0.goalKcal) }.count,
            averageBudgetKcal: mean(withMeals.map { Double($0.goalKcal) }),
            averageNutrients: averageNutrients, nutrientDays: nutrientDays,
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
    /// "Im Budget an 4 von 5 Tagen": `total` is the number of days with a meal.
    public static func weekBudgetDays(within: Int, of total: Int) -> String {
        String(localized: "Im Budget an \(within) von \(total) Tagen", bundle: .module)
    }

    /// "Ø Budget 2.450 kcal"
    public static func weekBudgetAverage(_ kcal: Double, locale: Locale = .current) -> String {
        String(localized: "Ø Budget \(grouped(Int(kcal.rounded()), locale: locale)) kcal", bundle: .module)
    }

    /// A macro of the weekly review: "Ø ~118 g / 140 g an 5 Tagen", without a goal "Ø ~218 g an 5 Tagen"; "–" when no day knows it
    /// (never 0).
    public static func weekMacro(mean: Double?, days: Int, goal: Int?, estimated: Bool) -> String {
        guard let mean, days > 0 else { return "–" }
        let number = "\(estimated ? "~" : "")\(Int(mean.rounded()))"
        let dayCount = String(localized: "\(days) Tagen", bundle: .module)
        guard let goal else { return String(localized: "Ø \(number) g an \(dayCount)", bundle: .module) }
        return String(localized: "Ø \(number) g / \(goal) g an \(dayCount)", bundle: .module)
    }

    /// A further nutrient of the weekly review: "Ø 22 / 30 g an 4 Tagen"; a limit reads "Ø 61 / max. 50 g an 3 Tagen" as on the day
    /// card. "–" when no day knows it (never 0).
    public static func weekNutrient(_ nutrient: Nutrient, mean: Double?, days: Int, goal: Int?, locale: Locale = .current) -> String {
        guard let mean, days > 0 else { return "–" }
        let sum = NutrientSum(value: mean, known: 1, total: 1)
        let figures = Self.nutrient(nutrient, sum: sum, goal: goal.map(Double.init), isLimitGoal: nutrient.isLimit, locale: locale)
        let dayCount = String(localized: "\(days) Tagen", bundle: .module)
        return String(localized: "Ø \(figures) an \(dayCount)", bundle: .module)
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
