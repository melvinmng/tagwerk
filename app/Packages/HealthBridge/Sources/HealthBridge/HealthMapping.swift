import Foundation
import HealthKit
import TagwerkCore

/// Pure mapping between Tagwerk entries and HealthKit metadata, types and identifiers.
public enum HealthMapping {
    /// Every Tagwerk sample carries its entry UUID, so one predicate finds all samples of an entry.
    public static let entryIDKey = "TagwerkEntryID"
    /// Marks samples written by Tagwerk (in addition to the source check).
    public static let markerKey = "TagwerkEntry"
    /// Marks values that came from an AI estimate.
    public static let estimatedKey = "TagwerkEstimated"

    /// The nutrient samples of a meal. The first four belong to the core group (`HealthShareKind`); the others are written
    /// only with the permission of their own group (`HealthAccessGroup.moreNutrients`).
    public enum Nutrient: String, Sendable, CaseIterable {
        case energy, protein, carbs, fat, fiber, sugar, saturatedFat, sodium

        /// The core write kind, `nil` for the nutrients of the group `moreNutrients`.
        var shareKind: HealthShareKind? {
            switch self {
            case .energy: .energy
            case .protein: .protein
            case .carbs: .carbs
            case .fat: .fat
            case .fiber, .sugar, .saturatedFat, .sodium: nil
            }
        }

        var isCore: Bool { shareKind != nil }

        var identifier: HKQuantityTypeIdentifier {
            switch self {
            case .energy: .dietaryEnergyConsumed
            case .protein: .dietaryProtein
            case .carbs: .dietaryCarbohydrates
            case .fat: .dietaryFatTotal
            case .fiber: .dietaryFiber
            case .sugar: .dietarySugar
            case .saturatedFat: .dietaryFatSaturated
            case .sodium: .dietarySodium
            }
        }

        /// The unit of the written value; sodium is stored in milligrams.
        var unit: HKUnit {
            switch self {
            case .energy: .kilocalorie()
            case .sodium: .gramUnit(with: .milli)
            default: .gram()
            }
        }
    }

    /// "tagwerk.<kind>.<UUID>[.<part>]".
    public static func syncIdentifier(_ kind: HealthEntryKind, id: UUID, part: String? = nil) -> String {
        "tagwerk.\(kind.rawValue).\(id.uuidString)" + (part.map { ".\($0)" } ?? "")
    }

    /// Metadata of one sample. Created and consumed locally; never crosses a concurrency boundary.
    static func metadata(syncIdentifier: String, entryID: UUID, version: Int, estimated: Bool,
                         userEntered: Bool) -> [String: Any] {
        var metadata: [String: Any] = [
            HKMetadataKeySyncIdentifier: syncIdentifier,
            HKMetadataKeySyncVersion: version,
            entryIDKey: entryID.uuidString,
            markerKey: 1,
        ]
        if estimated { metadata[estimatedKey] = 1 }
        if userEntered { metadata[HKMetadataKeyWasUserEntered] = true }
        return metadata
    }

    /// Nutrients above zero are written; the others are removed, so an edit to 0 or to "unknown" leaves no stale sample.
    /// Values are in the unit of the nutrient (`Nutrient.unit`): salt becomes sodium in milligrams.
    static func nutrientPlan(for meal: HealthMeal) -> (writes: [(nutrient: Nutrient, value: Double)], removals: [Nutrient]) {
        var writes: [(nutrient: Nutrient, value: Double)] = []
        var removals: [Nutrient] = []
        for nutrient in Nutrient.allCases {
            let value: Double? = switch nutrient {
            case .energy: meal.kcal
            case .protein: meal.protein
            case .carbs: meal.carbs
            case .fat: meal.fat
            case .fiber: meal.fiber
            case .sugar: meal.sugar
            case .saturatedFat: meal.saturatedFat
            case .sodium: meal.salt.map { NutrientValues.sodiumGrams(fromSalt: $0) * 1000 }
            }
            if let value, value > 0 { writes.append((nutrient, value)) } else { removals.append(nutrient) }
        }
        return (writes, removals)
    }

    /// What a save of a meal does with the permissions at hand: only permitted nutrients are written or removed. A meal counts as
    /// mirrored (`isComplete`) unless it has core values and none of them may be written; a nutrient of an optional group that is
    /// not allowed is skipped without keeping the meal marked for retry. (A later grant resets the meals, see `IntakeStore`.)
    static func mealWrite(plan: (writes: [(nutrient: Nutrient, value: Double)], removals: [Nutrient]),
                          mayWrite: (Nutrient) -> Bool)
        -> (writes: [(nutrient: Nutrient, value: Double)], removals: [Nutrient], isComplete: Bool) {
        let writes = plan.writes.filter { mayWrite($0.nutrient) }
        let removals = plan.removals.filter(mayWrite)
        let hasCoreValues = plan.writes.contains { $0.nutrient.isCore }
        let isComplete = !hasCoreValues || writes.contains { $0.nutrient.isCore }
        return (writes, removals, isComplete)
    }

    /// Quantity types of an entry kind outside the core `HealthShareKind` list; deleting an entry removes them as well.
    static func extraDeleteIdentifiers(for kind: HealthEntryKind) -> [HKQuantityTypeIdentifier] {
        switch kind {
        case .meal: Nutrient.allCases.filter { !$0.isCore }.map(\.identifier)
        case .weight: WeightPart.allCases.map(\.identifier)
        case .drink, .workout: []
        }
    }

    /// The samples of a weight entry; each has its own sync identifier part.
    enum WeightPart: String, CaseIterable, Sendable {
        case mass, bodyFat

        var identifier: HKQuantityTypeIdentifier { self == .mass ? .bodyMass : .bodyFatPercentage }
        var unit: HKUnit { self == .mass ? .gramUnit(with: .kilo) : .percent() }
    }

    /// What a save of a weight writes or removes with the permissions at hand. `isComplete` is `false` only when the weight itself
    /// may not be written (the entry stays marked for a retry); a denied body fat sample is skipped. Body fat is stored as a
    /// fraction (25 % is 0.25); without a body fat value an older sample of the entry is removed.
    static func weightWrite(for weight: HealthWeight, mayWrite: (WeightPart) -> Bool)
        -> (writes: [(part: WeightPart, value: Double)], removals: [WeightPart], isComplete: Bool) {
        var writes: [(part: WeightPart, value: Double)] = []
        var removals: [WeightPart] = []
        if mayWrite(.mass) { writes.append((.mass, weight.kilograms)) }
        if let fat = weight.bodyFatPercent, fat > 0 {
            if mayWrite(.bodyFat) { writes.append((.bodyFat, fat / 100)) }
        } else if mayWrite(.bodyFat) {
            removals.append(.bodyFat)
        }
        return (writes, removals, mayWrite(.mass))
    }

    /// The nutrition types read from other apps, with the unit the value is read in.
    enum ForeignType: CaseIterable, Sendable {
        case energy, protein, carbs, fat, fiber, sugar, saturatedFat, sodium, water

        var identifier: HKQuantityTypeIdentifier {
            switch self {
            case .energy: .dietaryEnergyConsumed
            case .protein: .dietaryProtein
            case .carbs: .dietaryCarbohydrates
            case .fat: .dietaryFatTotal
            case .fiber: .dietaryFiber
            case .sugar: .dietarySugar
            case .saturatedFat: .dietaryFatSaturated
            case .sodium: .dietarySodium
            case .water: .dietaryWater
            }
        }

        /// Sodium in milligrams (converted to salt), water in millilitres, energy in kilocalories, the rest in grams.
        var unit: HKUnit {
            switch self {
            case .energy: .kilocalorie()
            case .sodium: .gramUnit(with: .milli)
            case .water: .literUnit(with: .milli)
            default: .gram()
            }
        }
    }

    /// Everything but Tagwerk's own samples: no marker in the metadata and not from the own source. A statistics query cannot filter
    /// afterwards, so the exclusion is part of its predicate. Whether HealthKit accepts the negation inside a statistics query is
    /// checked on a device; the fallback is `separateBySource` and a sum over all sources except the own one.
    static func foreignPredicate(ownSource: NSPredicate) -> NSPredicate {
        let marked = HKQuery.predicateForObjects(withMetadataKey: markerKey)
        return NSCompoundPredicate(andPredicateWithSubpredicates: [NSCompoundPredicate(notPredicateWithSubpredicate: marked),
                                                                   NSCompoundPredicate(notPredicateWithSubpredicate: ownSource)])
    }

    /// Matches samples of this app's own source. `HKSource.default()` needs a host app with a bundle identifier, so the predicate
    /// is passed to `foreignPredicate(ownSource:)` and a test can stand in for it.
    static func ownSourcePredicate() -> NSPredicate {
        HKQuery.predicateForObjects(from: [HKSource.default()])
    }

    /// The day sums of one nutrition type with the names of the sources that contributed.
    struct ForeignSeries {
        var type: ForeignType
        var days: [(start: Date, value: Double?, sources: [String])]
    }

    /// Joins the series of all nutrition types into day totals. A type without a value on a day stays `nil` there (no entry is
    /// not 0); a day without any value is dropped. Sodium becomes salt.
    static func foreignDays(_ series: [ForeignSeries]) -> [DailyForeignNutrition] {
        var days: [Date: (intake: ForeignIntake, sources: Set<String>)] = [:]
        for entry in series {
            for day in entry.days {
                guard let value = day.value else { continue }
                var current = days[day.start] ?? (ForeignIntake(), [])
                switch entry.type {
                case .energy: current.intake.kcal = value
                case .protein: current.intake.protein = value
                case .carbs: current.intake.carbs = value
                case .fat: current.intake.fat = value
                case .fiber: current.intake.nutrients.fiber = value
                case .sugar: current.intake.nutrients.sugar = value
                case .saturatedFat: current.intake.nutrients.saturatedFat = value
                case .sodium: current.intake.nutrients.salt = NutrientValues.salt(fromSodiumGrams: value / 1000)
                case .water: current.intake.waterMilliliters = value
                }
                current.sources.formUnion(day.sources)
                days[day.start] = current
            }
        }
        return days.keys.sorted().compactMap { start in
            guard var entry = days[start] else { return nil }
            entry.intake.sources = entry.sources.sorted()
            return DailyForeignNutrition(start: start, intake: entry.intake)
        }
    }

    /// The result of one read of the profile, `nil` when it throws or Health has nothing: one failing field must not empty the rest.
    static func profileField<Value>(_ read: () throws -> Value?) -> Value? {
        (try? read()) ?? nil
    }

    /// The most recent height in centimetres from measurements in metres; implausible values (0 or less) are ignored.
    static func latestHeightCm(_ measurements: [(date: Date, meters: Double)]) -> Double? {
        measurements.filter { $0.meters > 0 }.max { $0.date < $1.date }.map { $0.meters * 100 }
    }

    /// Female and male map to the formula's constants; "other" and "not set" give `nil`.
    static func formulaSex(_ sex: HKBiologicalSex?) -> FormulaSex? {
        switch sex {
        case .female: .female
        case .male: .male
        default: nil
        }
    }

    /// A weight sample as read from Health, before the own ones are filtered out.
    struct WeightSample {
        var id: UUID
        var date: Date
        var kilograms: Double
        var metadata: [String: Any]?
        var sourceBundleID: String
        var sourceName: String
    }

    /// A body fat sample as read from Health (a fraction of the body mass: 0.25 is 25 %).
    struct BodyFatSample {
        var date: Date
        var fraction: Double
        var metadata: [String: Any]?
        var sourceBundleID: String
        var sourceName: String
    }

    /// A body fat value belongs to a weight when the same source wrote it within this many seconds of the weight.
    static let bodyFatPairingWindow: TimeInterval = 120

    /// The weights of other sources, oldest first; own samples (by source or marker) are dropped. A body fat sample of the same
    /// source close to a weight (a smart scale writes both) becomes the weight's body fat; a fat value without a weight is dropped.
    static func foreignWeights(_ samples: [WeightSample], bodyFat: [BodyFatSample] = [], ownBundleID: String?) -> [ForeignWeight] {
        let foreignFat = bodyFat.filter {
            !isOwn(metadata: $0.metadata, sourceBundleID: $0.sourceBundleID, ownBundleID: ownBundleID) && $0.fraction > 0
        }
        return samples
            .filter { !isOwn(metadata: $0.metadata, sourceBundleID: $0.sourceBundleID, ownBundleID: ownBundleID) }
            .sorted { $0.date < $1.date }
            .map { sample in
                let fat = foreignFat
                    .filter { $0.sourceBundleID == sample.sourceBundleID && abs($0.date.timeIntervalSince(sample.date)) <= bodyFatPairingWindow }
                    .min { abs($0.date.timeIntervalSince(sample.date)) < abs($1.date.timeIntervalSince(sample.date)) }
                return ForeignWeight(id: sample.id, date: sample.date, kilograms: sample.kilograms, sourceName: sample.sourceName,
                                     bodyFatPercent: fat.map { $0.fraction * 100 })
            }
    }

    static func activityType(_ activity: WorkoutActivity) -> HKWorkoutActivityType {
        switch activity {
        case .strength: .traditionalStrengthTraining
        case .running: .running
        case .cycling: .cycling
        case .walking: .walking
        case .hiking: .hiking
        case .swimming: .swimming
        case .yoga: .yoga
        case .hiit: .highIntensityIntervalTraining
        case .other: .other
        }
    }

    /// The Tagwerk activity for a Health type, if one fits.
    static func activity(for type: HKWorkoutActivityType) -> WorkoutActivity? {
        switch type {
        case .traditionalStrengthTraining, .functionalStrengthTraining: .strength
        case .running: .running
        case .cycling: .cycling
        case .walking: .walking
        case .hiking: .hiking
        case .swimming: .swimming
        case .yoga: .yoga
        case .highIntensityIntervalTraining: .hiit
        default: nil
        }
    }

    /// Name of a Health workout type in the app language; common types only, otherwise "Training".
    static func activityName(_ type: HKWorkoutActivityType) -> String {
        if let activity = activity(for: type) { return activity.displayName }
        return switch type {
        case .elliptical: String(localized: "Crosstrainer", bundle: .module)
        case .rowing: String(localized: "Rudern", bundle: .module)
        case .stairClimbing, .stairs: String(localized: "Treppensteigen", bundle: .module)
        case .dance, .socialDance, .cardioDance: String(localized: "Tanzen", bundle: .module)
        case .pilates: String(localized: "Pilates", bundle: .module)
        case .coreTraining: String(localized: "Rumpftraining", bundle: .module)
        case .crossTraining: String(localized: "Cross-Training", bundle: .module)
        case .mixedCardio: String(localized: "Gemischtes Cardio", bundle: .module)
        case .soccer: String(localized: "Fußball", bundle: .module)
        case .tennis: String(localized: "Tennis", bundle: .module)
        case .climbing: String(localized: "Klettern", bundle: .module)
        case .cooldown: String(localized: "Cool-down", bundle: .module)
        default: String(localized: "Training", bundle: .module)
        }
    }

    /// Whether a sample was written by Tagwerk: by its source first, by the marker as a fallback.
    static func isOwn(metadata: [String: Any]?, sourceBundleID: String, ownBundleID: String?) -> Bool {
        if let ownBundleID, sourceBundleID == ownBundleID { return true }
        return metadata?[markerKey] != nil
    }

    /// Whether the system sheet was shown for a set of types: the one rule behind the core access, the groups and the steps.
    ///
    /// `unnecessary` is asked and `shouldRequest` is not. `unknown` (HealthKit could not tell, e.g. while the phone is locked)
    /// must not flip an answered state back to "not asked", which made the consent card reappear after every answer. It counts as
    /// asked, unless the set has write types and none of them was ever answered: then nothing was asked yet.
    static func isAsked(_ status: HKAuthorizationRequestStatus, shareStatuses: [HKAuthorizationStatus]) -> Bool {
        switch status {
        case .shouldRequest: false
        case .unnecessary: true
        case .unknown: shareStatuses.isEmpty || shareStatuses.contains { $0 != .notDetermined }
        @unknown default: true
        }
    }

    /// The access row state from the request status and the write status of every core type.
    static func access(status: HKAuthorizationRequestStatus, shareStatuses: [HealthShareKind: HKAuthorizationStatus]) -> HealthAccess {
        let asked = isAsked(status, shareStatuses: Array(shareStatuses.values))
        let denied = Set(shareStatuses.filter { $0.value != .sharingAuthorized }.keys)
        return access(shouldRequest: !asked, denied: denied)
    }

    /// The access row state from the request status and the share types that are not authorized.
    static func access(shouldRequest: Bool, denied: Set<HealthShareKind>) -> HealthAccess {
        if shouldRequest { return .notDetermined }
        if denied.isEmpty { return .authorized }
        if denied.count == HealthShareKind.allCases.count { return .denied }
        return .partial(HealthShareKind.allCases.filter(denied.contains))
    }

    /// A group counts as asked once iOS would no longer show its sheet; an unknown status does not bring the button back.
    static func groupAccess(_ status: HKAuthorizationRequestStatus, shareStatuses: [HKAuthorizationStatus] = []) -> HealthGroupAccess {
        isAsked(status, shareStatuses: shareStatuses) ? .asked : .notAsked
    }

    /// Steps count as asked once iOS would no longer show the sheet; an unknown status does not bring the button back.
    static func stepsAccess(_ status: HKAuthorizationRequestStatus) -> StepsAccess {
        isAsked(status, shareStatuses: []) ? .asked : .notAsked
    }

    /// The write permission of one type from its authorization status.
    static func writeAccess(_ status: HKAuthorizationStatus) -> HealthWriteAccess {
        switch status {
        case .sharingAuthorized: .allowed
        case .sharingDenied: .denied
        case .notDetermined: .notAsked
        @unknown default: .notAsked
        }
    }

    /// Day sums of the active energy; days without statistics are dropped (no value, not 0).
    static func dailyActiveEnergy(_ sums: [(start: Date, value: Double?)]) -> [DailyActiveEnergy] {
        sums.compactMap { sum in sum.value.map { DailyActiveEnergy(start: sum.start, kilocalories: max(0, $0)) } }
    }

    /// Day sums rounded to whole steps; days without statistics are dropped (no value, not 0).
    static func dailySteps(_ sums: [(start: Date, count: Double?)]) -> [DailySteps] {
        sums.compactMap { sum in sum.count.map { DailySteps(start: sum.start, count: Int($0.rounded())) } }
    }
}
