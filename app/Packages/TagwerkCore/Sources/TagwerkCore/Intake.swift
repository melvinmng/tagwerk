import Foundation

/// The meal slot of an entry, guessed from the time and changeable by the user (phase 3 design §5.1).
public enum MealKind: String, Sendable, Codable, CaseIterable, Hashable {
    case breakfast, lunch, dinner, snack

    public var germanName: String {
        switch self {
        case .breakfast: "Frühstück"
        case .lunch: "Mittagessen"
        case .dinner: "Abendessen"
        case .snack: "Snack"
        }
    }

    /// 05:00–10:29 breakfast, 11:30–14:29 lunch, 17:30–21:29 dinner, otherwise snack.
    public static func forTime(_ date: Date, calendar: Calendar) -> MealKind {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        switch minutes {
        case 300..<630: return .breakfast
        case 690..<870: return .lunch
        case 1050..<1290: return .dinner
        default: return .snack
        }
    }
}

/// Whether the values of a meal came from an AI estimate or were typed in.
public enum MealOrigin: String, Sendable, Codable, Hashable {
    case estimated, manual
}

/// One part of a meal. Values are per portion; `factor` scales them (quantity stepper).
public struct MealItem: Sendable, Hashable, Codable, Identifiable {
    /// Stable identity for lists; items stored before it existed get a new one when decoded.
    public var id: UUID
    public var name: String
    public var amount: String
    public var factor: Double
    public var kcalMin: Double
    public var kcal: Double
    public var kcalMax: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    /// `true` while the values come from the AI; typing over them makes the item exact (shown without "~").
    public var isEstimated: Bool

    public init(name: String, amount: String, factor: Double = 1, kcalMin: Double, kcal: Double, kcalMax: Double,
                protein: Double, carbs: Double, fat: Double, isEstimated: Bool = false, id: UUID = UUID()) {
        self.id = id
        self.name = name
        self.amount = amount
        self.factor = factor
        self.kcalMin = kcalMin
        self.kcal = kcal
        self.kcalMax = kcalMax
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.isEstimated = isEstimated
    }

    /// The item with typed values: exact, so min, value and max are equal.
    public func overridden(kcal: Double, protein: Double, carbs: Double, fat: Double) -> MealItem {
        MealItem(name: name, amount: amount, factor: factor, kcalMin: kcal, kcal: kcal, kcalMax: kcal,
                 protein: protein, carbs: carbs, fat: fat, isEstimated: false, id: id)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, amount, factor, kcalMin, kcal, kcalMax, protein, carbs, fat, isEstimated
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        amount = try container.decode(String.self, forKey: .amount)
        factor = try container.decodeIfPresent(Double.self, forKey: .factor) ?? 1
        kcalMin = try container.decode(Double.self, forKey: .kcalMin)
        kcal = try container.decode(Double.self, forKey: .kcal)
        kcalMax = try container.decode(Double.self, forKey: .kcalMax)
        protein = try container.decode(Double.self, forKey: .protein)
        carbs = try container.decode(Double.self, forKey: .carbs)
        fat = try container.decode(Double.self, forKey: .fat)
        isEstimated = try container.decodeIfPresent(Bool.self, forKey: .isEstimated) ?? false
    }

    public var totalKcal: Double { kcal * factor }
    public var totalKcalMin: Double { kcalMin * factor }
    public var totalKcalMax: Double { kcalMax * factor }
    public var totalProtein: Double { protein * factor }
    public var totalCarbs: Double { carbs * factor }
    public var totalFat: Double { fat * factor }

    /// Allowed quantity factors of the stepper.
    public static let factorRange: ClosedRange<Double> = 0.5...3
    public static let factorStep: Double = 0.5
}

/// A meal as the rules see it, independent of storage.
public struct MealValue: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var date: Date
    public var kind: MealKind
    public var title: String
    public var items: [MealItem]
    public var origin: MealOrigin

    public init(id: UUID, date: Date, kind: MealKind, title: String, items: [MealItem], origin: MealOrigin) {
        self.id = id
        self.date = date
        self.kind = kind
        self.title = title
        self.items = items
        self.origin = origin
    }

    public var kcal: Double { items.reduce(0) { $0 + $1.totalKcal } }
    public var kcalMin: Double { items.reduce(0) { $0 + $1.totalKcalMin } }
    public var kcalMax: Double { items.reduce(0) { $0 + $1.totalKcalMax } }
    public var protein: Double { items.reduce(0) { $0 + $1.totalProtein } }
    public var carbs: Double { items.reduce(0) { $0 + $1.totalCarbs } }
    public var fat: Double { items.reduce(0) { $0 + $1.totalFat } }
    /// Any item still carries AI values; totals are then shown with "~".
    public var hasEstimate: Bool { items.contains(where: \.isEstimated) }
}

/// One water entry.
public struct DrinkValue: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var date: Date
    public var milliliters: Int

    public init(id: UUID, date: Date, milliliters: Int) {
        self.id = id
        self.date = date
        self.milliliters = milliliters
    }

    /// Quick buttons of the tab (mockup E4a).
    public static let quickAmounts = [250, 330, 500]
}

/// Workout types offered for manual entries (mockup E5a).
public enum WorkoutActivity: String, Sendable, Codable, CaseIterable, Hashable {
    case strength, running, cycling, walking, hiking, swimming, yoga, hiit, other

    public var germanName: String {
        switch self {
        case .strength: "Krafttraining"
        case .running: "Laufen"
        case .cycling: "Radfahren"
        case .walking: "Gehen"
        case .hiking: "Wandern"
        case .swimming: "Schwimmen"
        case .yoga: "Yoga"
        case .hiit: "HIIT"
        case .other: "Sonstiges"
        }
    }

    public var symbolName: String {
        switch self {
        case .strength: "dumbbell"
        case .running: "figure.run"
        case .cycling: "figure.outdoor.cycle"
        case .walking: "figure.walk"
        case .hiking: "figure.hiking"
        case .swimming: "figure.pool.swim"
        case .yoga: "figure.yoga"
        case .hiit: "figure.highintensity.intervaltraining"
        case .other: "figure.mixed.cardio"
        }
    }
}

/// A workout, either entered in Tagwerk (`isOwn`) or read from Health.
public struct WorkoutValue: Sendable, Hashable, Identifiable {
    public var id: String
    public var activity: WorkoutActivity
    public var start: Date
    public var minutes: Int
    public var kilocalories: Double?
    /// Name of the Health source ("Apple Watch"); `nil` for own entries.
    public var sourceName: String?
    public var isOwn: Bool
    /// Name of a Health workout type without a Tagwerk activity ("Rudern"); `nil` uses the activity name.
    public var customName: String?

    public init(id: String, activity: WorkoutActivity, start: Date, minutes: Int, kilocalories: Double?,
                sourceName: String?, isOwn: Bool, customName: String? = nil) {
        self.id = id
        self.activity = activity
        self.start = start
        self.minutes = minutes
        self.kilocalories = kilocalories
        self.sourceName = sourceName
        self.isOwn = isOwn
        self.customName = customName
    }

    public var displayName: String { customName ?? activity.germanName }
    public var end: Date { start.addingTimeInterval(TimeInterval(minutes * 60)) }
    public var interval: DateInterval { DateInterval(start: start, end: end) }
}

/// Totals of one day (own entries only, design E11).
public struct DayIntake: Sendable, Hashable {
    public var kcal: Double
    public var kcalMin: Double
    public var kcalMax: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    public var waterMilliliters: Int
    /// At least one meal value is an estimate; totals are shown with "~".
    public var hasEstimate: Bool

    public init(kcal: Double, kcalMin: Double, kcalMax: Double, protein: Double, carbs: Double, fat: Double,
                waterMilliliters: Int, hasEstimate: Bool) {
        self.kcal = kcal
        self.kcalMin = kcalMin
        self.kcalMax = kcalMax
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.waterMilliliters = waterMilliliters
        self.hasEstimate = hasEstimate
    }

    public static let empty = DayIntake(kcal: 0, kcalMin: 0, kcalMax: 0, protein: 0, carbs: 0, fat: 0, waterMilliliters: 0,
                                        hasEstimate: false)
}

/// Pure rules of the "Erfassen" tab (phase 3 design §5).
public enum IntakeRules {
    /// Workouts shorter than this do not count for the weekly goal.
    public static let minimumWorkoutMinutes = 10
    /// Meals older than this are not offered for repeating.
    public static let repeatWindowDays = 30
    public static let repeatLimit = 8

    public static func dayIntake(meals: [MealValue], drinks: [DrinkValue]) -> DayIntake {
        DayIntake(kcal: meals.reduce(0) { $0 + $1.kcal },
                  kcalMin: meals.reduce(0) { $0 + $1.kcalMin },
                  kcalMax: meals.reduce(0) { $0 + $1.kcalMax },
                  protein: meals.reduce(0) { $0 + $1.protein },
                  carbs: meals.reduce(0) { $0 + $1.carbs },
                  fat: meals.reduce(0) { $0 + $1.fat },
                  waterMilliliters: drinks.reduce(0) { $0 + $1.milliliters },
                  hasEstimate: meals.contains { $0.hasEstimate })
    }

    /// Start of the Monday-to-Sunday week containing `date`, regardless of the calendar's first weekday.
    public static func weekStart(containing date: Date, calendar: Calendar) -> Date {
        let day = PlanDay(date: date, calendar: calendar)
        let daysSinceMonday = (day.weekday(in: calendar) + 5) % 7
        return day.adding(days: -daysSinceMonday, calendar: calendar).startDate(in: calendar)
    }

    /// Workouts of at least 10 minutes in the current Monday-to-Sunday week, own and from Health.
    public static func workoutsThisWeek(_ workouts: [WorkoutValue], now: Date, calendar: Calendar) -> Int {
        let start = weekStart(containing: now, calendar: calendar)
        let end = PlanDay(date: start, calendar: calendar).adding(days: 7, calendar: calendar).startDate(in: calendar)
        return workouts.filter { $0.minutes >= minimumWorkoutMinutes && $0.start >= start && $0.start < end }.count
    }

    /// The first Health workout that overlaps `interval`; touching end and start do not overlap.
    public static func overlappingWorkout(_ interval: DateInterval, in workouts: [WorkoutValue]) -> WorkoutValue? {
        workouts.first { $0.start < interval.end && interval.start < $0.end }
    }

    /// Lower-cased title without surrounding white space; groups repeated meals.
    public static func normalizedTitle(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// "Zuletzt und häufig": the latest meal of each title from the last 30 days, ranked by count, then recency.
    public static func repeatSuggestions(meals: [MealValue], hidden: Set<String>, filter: String, now: Date,
                                         calendar: Calendar, limit: Int = repeatLimit) -> [MealValue] {
        let cutoff = calendar.date(byAdding: .day, value: -repeatWindowDays, to: now) ?? now
        let query = normalizedTitle(filter)
        var groups: [String: (latest: MealValue, count: Int)] = [:]
        for meal in meals where meal.date >= cutoff && meal.date <= now {
            let key = normalizedTitle(meal.title)
            guard !key.isEmpty, !hidden.contains(key), query.isEmpty || key.contains(query) else { continue }
            if let existing = groups[key] {
                groups[key] = (meal.date > existing.latest.date ? meal : existing.latest, existing.count + 1)
            } else {
                groups[key] = (meal, 1)
            }
        }
        return groups.values
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                if lhs.latest.date != rhs.latest.date { return lhs.latest.date > rhs.latest.date }
                return lhs.latest.title < rhs.latest.title
            }
            .prefix(limit)
            .map(\.latest)
    }
}

/// The AI answer for a meal estimate (JSON schema `meal_estimate`).
public struct MealEstimateOutput: Sendable, Hashable, Decodable {
    public struct Item: Sendable, Hashable, Decodable {
        public var name: String
        public var amount: String
        public var kcalMin: Double
        public var kcal: Double
        public var kcalMax: Double
        public var proteinG: Double
        public var carbsG: Double
        public var fatG: Double

        enum CodingKeys: String, CodingKey {
            case name, amount, kcal
            case kcalMin = "kcal_min"
            case kcalMax = "kcal_max"
            case proteinG = "protein_g"
            case carbsG = "carbs_g"
            case fatG = "fat_g"
        }
    }

    public var title: String
    public var items: [Item]

    /// Items above this value are treated as nonsense and dropped.
    public static let maximumItemKcal: Double = 5000
    public static let maximumItems = 20

    public static func decode(_ data: Data) throws -> MealEstimateOutput {
        try JSONDecoder().decode(MealEstimateOutput.self, from: data)
    }

    /// Clamps negative values, orders min ≤ value ≤ max, drops absurd items and caps the item count.
    /// `nil` when nothing usable is left ("Darin war kein Essen zu erkennen.").
    public func normalized() -> NormalizedMealEstimate? {
        let cleaned: [MealItem] = items.compactMap { item in
            let values = [item.kcalMin, item.kcal, item.kcalMax].map { max(0, $0) }
            guard let highest = values.max(), highest <= Self.maximumItemKcal else { return nil }
            let kcal = values[1]
            return MealItem(name: item.name.trimmingCharacters(in: .whitespacesAndNewlines),
                            amount: item.amount.trimmingCharacters(in: .whitespacesAndNewlines),
                            kcalMin: min(values[0], values[2], kcal), kcal: kcal, kcalMax: max(values[0], values[2], kcal),
                            protein: max(0, item.proteinG), carbs: max(0, item.carbsG), fat: max(0, item.fatG),
                            isEstimated: true)
        }
        guard !cleaned.isEmpty else { return nil }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return NormalizedMealEstimate(title: trimmedTitle.isEmpty ? cleaned[0].name : trimmedTitle,
                                      items: Array(cleaned.prefix(Self.maximumItems)))
    }
}

/// A checked AI estimate, ready for the editable preview.
public struct NormalizedMealEstimate: Sendable, Hashable {
    public var title: String
    public var items: [MealItem]

    public init(title: String, items: [MealItem]) {
        self.title = title
        self.items = items
    }
}
