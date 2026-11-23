import Foundation
import HealthBridge
import Observation
import TagwerkCore

/// Height, birth year and the sex of the formula for the cross-check of goals (decision PV4b): per field the value last read from
/// Health, else the value the user typed.
///
/// Health is read only after a tap ("Aus Health lesen") and again when the section opens or the data sheet of the goal planning is
/// about to show; never in the background. iOS does not tell a denied read from a missing value, so a silent answer keeps what was
/// read before. Only whole centimetres, the birth year and the sex are stored, never the date of birth.
@MainActor
@Observable
final class BodyProfileStore {
    /// What the last reading brought.
    enum ReadResult: Equatable {
        /// The group was not asked yet; nothing was read.
        case notAsked
        /// Health delivered at least one value.
        case delivered
        /// Health delivered nothing: the data is missing in Health or reading is not allowed; iOS does not say which.
        case nothingDelivered
    }

    private let settings: AppSettings
    private let health: any HealthStoring
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: () -> Date
    private(set) var lastRead: ReadResult?

    init(settings: AppSettings, health: any HealthStoring, calendar: Calendar = .tagwerk, now: @escaping () -> Date = Date.init) {
        self.settings = settings
        self.health = health
        self.calendar = calendar
        self.now = now
    }

    /// The values of the three fields with their sources.
    var profile: BodyProfile {
        BodyProfile.resolved(health: settings.healthBodyValues, typed: settings.typedBodyValues)
    }

    /// The year of today, for the age and the range of the birth year.
    var currentYear: Int { calendar.component(.year, from: now()) }

    /// Reads Health when the group `bodyProfile` was asked before; otherwise it reads nothing. Changes a stored value only where
    /// Health delivers one.
    @discardableResult
    func refresh() async -> ReadResult {
        guard await health.groupAccess(.bodyProfile) == .asked else {
            lastRead = .notAsked
            return .notAsked
        }
        return await read()
    }

    /// "Aus Health lesen": asks for the group once (system sheet, only after this tap) and reads.
    @discardableResult
    func readFromHealth() async -> ReadResult {
        if await health.groupAccess(.bodyProfile) == .notAsked {
            try? await health.requestAuthorization(for: .bodyProfile)
        }
        return await refresh()
    }

    private func read() async -> ReadResult {
        let delivered = Self.values(from: await health.bodyProfile(), years: BodyProfile.birthYearRange(currentYear: currentYear))
        guard !delivered.isEmpty else {
            lastRead = .nothingDelivered
            return .nothingDelivered
        }
        settings.healthBodyValues = settings.healthBodyValues.updated(with: delivered)
        settings.healthBodyProfileReadAt = now()
        lastRead = .delivered
        return .delivered
    }

    /// The Health values as whole centimetres and a year, each only when it lies inside the limits of the input fields.
    static func values(from health: HealthBodyProfile, years: ClosedRange<Int>) -> BodyProfileValues {
        let height = health.heightCm.map { Int($0.rounded()) }.flatMap { BodyProfile.heightRangeCm.contains($0) ? $0 : nil }
        let year = health.birthYear.flatMap { years.contains($0) ? $0 : nil }
        return BodyProfileValues(heightCm: height, birthYear: year, sex: health.sex)
    }

    // MARK: Typed values

    /// Writes one typed field; a value outside the limits is ignored. `nil` clears the field.
    func setTypedHeight(_ centimetres: Int?) {
        guard centimetres.map(BodyProfile.heightRangeCm.contains) ?? true else { return }
        settings.bodyHeightCm = centimetres
    }

    func setTypedBirthYear(_ year: Int?) {
        guard year.map(BodyProfile.birthYearRange(currentYear: currentYear).contains) ?? true else { return }
        settings.birthYear = year
    }

    func setTypedSex(_ sex: FormulaSex?) {
        settings.formulaSexRaw = sex?.rawValue
    }
}
