import Foundation

/// Where one value of the body profile comes from.
public enum BodyValueSource: String, Sendable, Hashable {
    /// Last read from Health.
    case health
    /// Typed in the settings.
    case typed
    /// Neither Health nor the user gave a value.
    case missing
}

/// The three body values the cross-check of goals needs (resting energy by Mifflin–St Jeor, protein per kilogram).
public enum BodyField: String, Sendable, CaseIterable, Hashable {
    case height, birthYear, sex
}

/// Height, birth year and the sex of the formula as plain values; `nil` is "not known". The same shape holds what Health
/// delivered and what the user typed.
public struct BodyProfileValues: Sendable, Hashable {
    public var heightCm: Int?
    public var birthYear: Int?
    public var sex: FormulaSex?

    public init(heightCm: Int? = nil, birthYear: Int? = nil, sex: FormulaSex? = nil) {
        self.heightCm = heightCm
        self.birthYear = birthYear
        self.sex = sex
    }

    public static let empty = BodyProfileValues()

    /// True when no field has a value.
    public var isEmpty: Bool { heightCm == nil && birthYear == nil && sex == nil }

    /// These values with every field that `newer` delivers replaced; a field that `newer` leaves out keeps its value. iOS
    /// reports a denied read like a missing value, so a silent answer must never erase what was read earlier.
    public func updated(with newer: BodyProfileValues) -> BodyProfileValues {
        BodyProfileValues(heightCm: newer.heightCm ?? heightCm, birthYear: newer.birthYear ?? birthYear, sex: newer.sex ?? sex)
    }
}

/// One field with the source of its value.
public struct BodyValue<Value: Sendable & Hashable>: Sendable, Hashable {
    public var value: Value?
    public var source: BodyValueSource

    public init(value: Value?, source: BodyValueSource) {
        self.value = value
        self.source = source
    }
}

/// The body profile as the app uses it: per field the value of Health where Health delivered one, else the typed value, else
/// "missing" (decision PV4b; Health wins, the typed value is only the fallback). A field the user changed on purpose is an
/// override (decision 4A, #317): its typed value wins over Health, because iOS does not let apps write birth date and sex.
public struct BodyProfile: Sendable, Hashable {
    public var height: BodyValue<Int>
    public var birthYear: BodyValue<Int>
    public var sex: BodyValue<FormulaSex>

    /// The limits of the input fields; a Health value outside them counts as not delivered, so a faulty entry in Health never
    /// reaches the formula.
    public static let heightRangeCm = 100...250
    public static let oldestBirthYear = 1900

    /// The years a birth year may have, for the input field of `year`.
    public static func birthYearRange(currentYear: Int) -> ClosedRange<Int> { oldestBirthYear...max(oldestBirthYear, currentYear) }

    /// `overridden` names the fields whose typed value wins over Health. A typed value without that marker stays a fallback, so a
    /// value typed while Health was silent never resurfaces once Health delivers.
    public static func resolved(health: BodyProfileValues, typed: BodyProfileValues, overridden: Set<BodyField> = []) -> BodyProfile {
        func pick<Value: Sendable & Hashable>(_ field: BodyField, _ fromHealth: Value?, _ fromUser: Value?) -> BodyValue<Value> {
            if overridden.contains(field), let fromUser { return BodyValue(value: fromUser, source: .typed) }
            if let fromHealth { return BodyValue(value: fromHealth, source: .health) }
            if let fromUser { return BodyValue(value: fromUser, source: .typed) }
            return BodyValue(value: nil, source: .missing)
        }
        return BodyProfile(height: pick(.height, health.heightCm, typed.heightCm),
                           birthYear: pick(.birthYear, health.birthYear, typed.birthYear),
                           sex: pick(.sex, health.sex, typed.sex))
    }

    /// The fields without a value, in the order of `BodyField.allCases`.
    public var missingFields: [BodyField] {
        BodyField.allCases.filter { field in
            switch field {
            case .height: height.value == nil
            case .birthYear: birthYear.value == nil
            case .sex: sex.value == nil
            }
        }
    }

    /// True when the resting energy can be computed.
    public var isComplete: Bool { missingFields.isEmpty }

    /// The age in whole years from the birth year alone: the month is not kept, so the value can be one year too high until the
    /// birthday. The formula is an estimate of ±10 % and more anyway.
    public func ageYears(inYear year: Int) -> Int? {
        guard let birthYear = birthYear.value, year >= birthYear else { return nil }
        return year - birthYear
    }

    /// The values behind the fields, for the data package and the cross-check.
    public var values: BodyProfileValues {
        BodyProfileValues(heightCm: height.value, birthYear: birthYear.value, sex: sex.value)
    }
}
