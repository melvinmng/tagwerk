import Testing
@testable import TagwerkCore

struct BodyProfileTests {
    @Test func resolved_prefersHealthValuePerField() {
        let profile = BodyProfile.resolved(health: BodyProfileValues(heightCm: 181, birthYear: nil, sex: .male),
                                           typed: BodyProfileValues(heightCm: 175, birthYear: 1990, sex: .female))
        #expect(profile.height == BodyValue(value: 181, source: .health))
        #expect(profile.birthYear == BodyValue(value: 1990, source: .typed))
        #expect(profile.sex == BodyValue(value: .male, source: .health))
    }

    @Test func resolved_fallsBackToTypedPerField() {
        let profile = BodyProfile.resolved(health: .empty, typed: BodyProfileValues(heightCm: 175, birthYear: 1990, sex: .female))
        #expect(profile.height.source == .typed && profile.birthYear.source == .typed && profile.sex.source == .typed)
        #expect(profile.isComplete)
    }

    @Test func resolved_missingField_reportsWhichOneIsMissing() {
        let profile = BodyProfile.resolved(health: BodyProfileValues(heightCm: 181), typed: BodyProfileValues(birthYear: 1990))
        #expect(profile.sex == BodyValue(value: nil, source: .missing))
        #expect(profile.missingFields == [.sex])
        #expect(!profile.isComplete)
        #expect(BodyProfile.resolved(health: .empty, typed: .empty).missingFields == [.height, .birthYear, .sex])
    }

    @Test func resolved_overriddenField_prefersTheTypedValueOverHealth() {
        let health = BodyProfileValues(heightCm: 180, birthYear: 1994, sex: .male)
        let typed = BodyProfileValues(heightCm: 181, birthYear: 1995, sex: .female)
        let profile = BodyProfile.resolved(health: health, typed: typed, overridden: [.birthYear, .sex])
        #expect(profile.height == BodyValue(value: 180, source: .health), "a field without an override keeps Health first")
        #expect(profile.birthYear == BodyValue(value: 1995, source: .typed))
        #expect(profile.sex == BodyValue(value: .female, source: .typed))
    }

    @Test func resolved_overrideWithoutATypedValue_fallsBackToHealth() {
        let profile = BodyProfile.resolved(health: BodyProfileValues(birthYear: 1994), typed: .empty, overridden: [.birthYear])
        #expect(profile.birthYear == BodyValue(value: 1994, source: .health))
    }

    @Test func resolved_staleTypedValueWithoutOverride_staysAFallbackOnly() {
        // A value typed while Health was silent must not come back once Health delivers: only an override marker wins.
        let profile = BodyProfile.resolved(health: BodyProfileValues(birthYear: 1994), typed: BodyProfileValues(birthYear: 1980))
        #expect(profile.birthYear == BodyValue(value: 1994, source: .health))
    }

    @Test func updated_silentAnswerKeepsLastValue() {
        let stored = BodyProfileValues(heightCm: 181, birthYear: 1990, sex: .male)
        #expect(stored.updated(with: .empty) == stored)
        #expect(stored.updated(with: BodyProfileValues(heightCm: 183)) == BodyProfileValues(heightCm: 183, birthYear: 1990, sex: .male))
    }

    @Test func age_fromBirthYear() {
        let profile = BodyProfile.resolved(health: .empty, typed: BodyProfileValues(birthYear: 1990))
        #expect(profile.ageYears(inYear: 2026) == 36)
        #expect(profile.ageYears(inYear: 1989) == nil, "a birth year in the future gives no age")
        #expect(BodyProfile.resolved(health: .empty, typed: .empty).ageYears(inYear: 2026) == nil)
    }

    @Test func values_roundTripThroughResolved() {
        let values = BodyProfileValues(heightCm: 180, birthYear: 1992, sex: .female)
        #expect(BodyProfile.resolved(health: values, typed: .empty).values == values)
    }

    @Test func birthYearRange_endsAtTheCurrentYear() {
        #expect(BodyProfile.birthYearRange(currentYear: 2026) == 1900...2026)
    }
}
