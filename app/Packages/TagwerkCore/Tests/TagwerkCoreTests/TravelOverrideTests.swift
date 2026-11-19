import Foundation
import Testing
@testable import TagwerkCore

/// Manual travel time per event: which override applies, how a change is stored and how the value is bounded.
struct TravelOverrideTests {
    private let start = instant(2026, 11, 19, 10, 0)

    private func mode(_ overrides: [TravelOverride], eventID: String = "s|100", series: String = "s",
                      start: Date? = nil) -> TravelOverrideMode {
        TravelOverrideRules.mode(eventID: eventID, seriesID: series, start: start ?? self.start, overrides: overrides)
    }

    // MARK: Which override applies

    @Test func withoutOverrides_isAutomatic() {
        #expect(mode([]) == .automatic)
    }

    @Test func occurrenceOverride_appliesToThatOccurrenceOnly() {
        let overrides = [TravelOverride(eventKey: "s|100", seriesFrom: nil, mode: .none)]
        #expect(mode(overrides, eventID: "s|100") == .none)
        #expect(mode(overrides, eventID: "s|200") == .automatic)
    }

    @Test func singleEvent_isFoundByItsOwnID() {
        let overrides = [TravelOverride(eventKey: "single", seriesFrom: nil, mode: .fixed(minutes: 20))]
        #expect(mode(overrides, eventID: "single", series: "single") == .fixed(minutes: 20))
    }

    @Test func seriesOverride_appliesFromItsDateOn() {
        let overrides = [TravelOverride(eventKey: "s", seriesFrom: start, mode: .fixed(minutes: 15))]
        #expect(mode(overrides, start: start.addingTimeInterval(-60)) == .automatic)
        #expect(mode(overrides, start: start) == .fixed(minutes: 15))
        #expect(mode(overrides, start: start.addingTimeInterval(86_400 * 7)) == .fixed(minutes: 15))
    }

    @Test func seriesOverride_ofAnotherSeries_isIgnored() {
        let overrides = [TravelOverride(eventKey: "other", seriesFrom: start, mode: .none)]
        #expect(mode(overrides) == .automatic)
    }

    @Test func latestSeriesOverride_wins() {
        let overrides = [TravelOverride(eventKey: "s", seriesFrom: start, mode: .none),
                         TravelOverride(eventKey: "s", seriesFrom: start.addingTimeInterval(86_400 * 7), mode: .fixed(minutes: 30))]
        #expect(mode(overrides, start: start.addingTimeInterval(86_400)) == .none)
        #expect(mode(overrides, start: start.addingTimeInterval(86_400 * 8)) == .fixed(minutes: 30))
    }

    @Test func occurrenceOverride_beatsSeriesOverride() {
        let overrides = [TravelOverride(eventKey: "s", seriesFrom: start, mode: .none),
                         TravelOverride(eventKey: "s|100", seriesFrom: nil, mode: .fixed(minutes: 10))]
        #expect(mode(overrides, eventID: "s|100", start: start.addingTimeInterval(3600)) == .fixed(minutes: 10))
    }

    @Test func automaticOccurrence_beatsSeriesNone() {
        let overrides = [TravelOverride(eventKey: "s", seriesFrom: start, mode: .none),
                         TravelOverride(eventKey: "s|100", seriesFrom: nil, mode: .automatic)]
        #expect(mode(overrides, eventID: "s|100", start: start.addingTimeInterval(3600)) == .automatic)
    }

    // MARK: Changing an override

    private func updated(_ overrides: [TravelOverride], to newMode: TravelOverrideMode, series: Bool,
                         eventID: String = "s|100") -> [TravelOverride] {
        TravelOverrideRules.updated(overrides, eventID: eventID, seriesID: "s", start: start, mode: newMode, series: series)
    }

    @Test func update_storesOccurrenceOverride() {
        let result = updated([], to: .fixed(minutes: 20), series: false)
        #expect(result == [TravelOverride(eventKey: "s|100", seriesFrom: nil, mode: .fixed(minutes: 20))])
    }

    @Test func update_storesSeriesOverrideFromTheOccurrence() {
        let result = updated([], to: .none, series: true)
        #expect(result == [TravelOverride(eventKey: "s", seriesFrom: start, mode: .none)])
    }

    @Test func update_replacesTheOverrideOfTheSameKey() {
        let first = updated([], to: .none, series: false)
        let second = updated(first, to: .fixed(minutes: 25), series: false)
        #expect(second == [TravelOverride(eventKey: "s|100", seriesFrom: nil, mode: .fixed(minutes: 25))])
    }

    @Test func update_toAutomatic_removesTheOverride() {
        let first = updated([], to: .none, series: false)
        #expect(updated(first, to: .automatic, series: false).isEmpty)
    }

    @Test func update_toAutomaticWithNothingToOverride_storesNothing() {
        #expect(updated([], to: .automatic, series: false).isEmpty)
        #expect(updated([], to: .automatic, series: true).isEmpty)
    }

    @Test func update_toAutomaticBelowASeriesOverride_isKept() {
        // "Only this one: automatic" must beat the series override "none".
        let series = updated([], to: .none, series: true)
        let result = updated(series, to: .automatic, series: false)
        #expect(result.count == 2)
        #expect(mode(result, eventID: "s|100", start: start) == .automatic)
        #expect(mode(result, eventID: "s|200", start: start.addingTimeInterval(86_400)) == .none)
    }

    @Test func update_seriesToAutomatic_endsTheSeriesOverride() {
        let earlier = [TravelOverride(eventKey: "s", seriesFrom: start.addingTimeInterval(-86_400 * 7), mode: .none)]
        let result = updated(earlier, to: .automatic, series: true)
        #expect(mode(result, start: start.addingTimeInterval(-86_400)) == .none)
        #expect(mode(result, start: start) == .automatic)
        #expect(mode(result, start: start.addingTimeInterval(86_400 * 7)) == .automatic)
    }

    @Test func update_leavesOverridesOfOtherEventsAlone() {
        let other = TravelOverride(eventKey: "other", seriesFrom: nil, mode: .none)
        #expect(updated([other], to: .fixed(minutes: 10), series: false).contains(other))
    }

    // MARK: Bounds

    @Test func fixedMinutes_areRoundedToFiveAndBounded() {
        #expect(TravelOverrideRules.clampedFixedMinutes(0) == 5)
        #expect(TravelOverrideRules.clampedFixedMinutes(-30) == 5)
        #expect(TravelOverrideRules.clampedFixedMinutes(7) == 5)
        #expect(TravelOverrideRules.clampedFixedMinutes(8) == 10)
        #expect(TravelOverrideRules.clampedFixedMinutes(25) == 25)
        #expect(TravelOverrideRules.clampedFixedMinutes(180) == 180)
        #expect(TravelOverrideRules.clampedFixedMinutes(500) == TravelPlausibility.maximumTravelMinutes)
    }

    @Test func fixedMode_isBoundedWhenRead() {
        #expect(TravelOverrideMode(storedName: "fixed", minutes: 23) == .fixed(minutes: 25))
        #expect(TravelOverrideMode(storedName: "fixed", minutes: 9_999) == .fixed(minutes: 180))
    }

    // MARK: Storage names

    @Test func mode_roundTripsThroughStorage() {
        for value in [TravelOverrideMode.automatic, .none, .fixed(minutes: 35)] {
            #expect(TravelOverrideMode(storedName: value.storedName, minutes: value.storedMinutes) == value)
        }
    }

    @Test func unknownStoredName_readsAsAutomatic() {
        #expect(TravelOverrideMode(storedName: "teleport", minutes: 10) == .automatic)
        #expect(TravelOverrideMode(storedName: "", minutes: 0) == .automatic)
    }

    @Test func key_matchesTheOtherEventMarks() {
        #expect(TravelOverride(eventKey: "s|100", seriesFrom: nil, mode: .none).key == "s|100")
        #expect(TravelOverride(eventKey: "s", seriesFrom: Date(timeIntervalSince1970: 1_800_000_000), mode: .none).key
                == "s|from 1800000000")
    }
}
