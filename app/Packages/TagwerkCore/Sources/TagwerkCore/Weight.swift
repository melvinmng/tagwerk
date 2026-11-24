import Foundation

/// A body weight Tagwerk keeps itself ("Gewicht", decision KG2a). Health holds a mirrored copy.
public struct WeightValue: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var date: Date
    public var kilograms: Double
    /// Body fat in percent of the body mass (25 means 25 %); `nil` when not measured or switched off. Never 0 for "unknown".
    public var bodyFatPercent: Double?

    public init(id: UUID, date: Date, kilograms: Double, bodyFatPercent: Double? = nil) {
        self.id = id
        self.date = date
        self.kilograms = kilograms
        self.bodyFatPercent = bodyFatPercent
    }
}

/// One measurement as the history shows it: an own entry or one that another app (a smart scale, the Health app) wrote to Health.
public struct WeightMeasurement: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var date: Date
    public var kilograms: Double
    public var bodyFatPercent: Double?
    /// Name of the other source; `nil` for an own entry.
    public var sourceName: String?

    public init(id: UUID, date: Date, kilograms: Double, bodyFatPercent: Double? = nil, sourceName: String? = nil) {
        self.id = id
        self.date = date
        self.kilograms = kilograms
        self.bodyFatPercent = bodyFatPercent
        self.sourceName = sourceName
    }

    public var isOwn: Bool { sourceName == nil }

    public init(_ value: WeightValue) {
        self.init(id: value.id, date: value.date, kilograms: value.kilograms, bodyFatPercent: value.bodyFatPercent)
    }
}

/// The weight of one day: the earliest measurement of that day (own and foreign together).
public struct DayWeight: Sendable, Hashable {
    public var day: PlanDay
    public var kilograms: Double
    public var bodyFatPercent: Double?

    public init(day: PlanDay, kilograms: Double, bodyFatPercent: Double? = nil) {
        self.day = day
        self.kilograms = kilograms
        self.bodyFatPercent = bodyFatPercent
    }
}

/// Limits of the entry and the rules that turn measurements into day values (decisions KG1c, KG2a).
public enum WeightRules {
    /// What the entry accepts, in kilograms; the step of the entry is 0.1 kg.
    public static let minimumKilograms = 20.0
    public static let maximumKilograms = 400.0
    public static let stepKilograms = 0.1
    /// The weight sheet starts here when there is no earlier value.
    public static let startKilograms = 70.0
    /// Body fat in percent; the optional second field of the sheet.
    public static let minimumBodyFatPercent = 2.0
    public static let maximumBodyFatPercent = 70.0
    public static let stepBodyFatPercent = 0.1

    /// `kilograms` rounded to 0.1 kg and held inside the limits.
    public static func clamped(_ kilograms: Double) -> Double {
        let rounded = (kilograms * 10).rounded() / 10
        return min(maximumKilograms, max(minimumKilograms, rounded))
    }

    /// `percent` rounded to 0.1 and held inside the limits; `nil` stays unknown.
    public static func clampedBodyFat(_ percent: Double?) -> Double? {
        guard let percent else { return nil }
        let rounded = (percent * 10).rounded() / 10
        return min(maximumBodyFatPercent, max(minimumBodyFatPercent, rounded))
    }

    /// Own and foreign measurements in one list, oldest first, without duplicates: a foreign entry with the id of an earlier one, or
    /// one that repeats an own entry (same moment, same value), is dropped. Own entries win, because Tagwerk knows them best.
    public static func merge(own: [WeightMeasurement], foreign: [WeightMeasurement]) -> [WeightMeasurement] {
        var result = own
        var seen = Set(own.map(\.id))
        for candidate in foreign.sorted(by: { $0.date < $1.date }) {
            guard seen.insert(candidate.id).inserted else { continue }
            let repeatsOwn = own.contains {
                abs($0.date.timeIntervalSince(candidate.date)) < 1 && abs($0.kilograms - candidate.kilograms) < 0.05
            }
            if !repeatsOwn { result.append(candidate) }
        }
        // An own entry first at the same moment, so the order does not depend on the input order.
        return result.sorted { ($0.date, $0.isOwn ? 0 : 1, $0.id.uuidString) < ($1.date, $1.isOwn ? 0 : 1, $1.id.uuidString) }
    }

    /// The weight of each day: the earliest measurement of the day in `calendar`. A later measurement of the same day is kept in
    /// the list of measurements but does not count here, so a second weighing in the evening does not move the day.
    public static func dayValues(_ measurements: [WeightMeasurement], calendar: Calendar) -> [PlanDay: DayWeight] {
        var earliest: [PlanDay: WeightMeasurement] = [:]
        for measurement in measurements {
            let day = PlanDay(date: measurement.date, calendar: calendar)
            if let current = earliest[day], current.date <= measurement.date { continue }
            earliest[day] = measurement
        }
        return earliest.mapValues { measurement in
            DayWeight(day: PlanDay(date: measurement.date, calendar: calendar), kilograms: measurement.kilograms,
                      bodyFatPercent: measurement.bodyFatPercent)
        }
    }
}
