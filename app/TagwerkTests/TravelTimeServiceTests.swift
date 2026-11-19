import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct TravelTimeServiceTests {
    let estimator = FakeTravelEstimator()
    let clock = Clock()
    let fileURL = FileManager.default.temporaryDirectory.appending(path: "travel-\(UUID().uuidString).json")

    final class Clock { var now = Date(timeIntervalSince1970: 1_800_000_000) }

    /// The home place as the settings hold it once the address was checked (Berlin).
    let home = TravelPlace(text: "Zuhause, Berlin", latitude: 52.52, longitude: 13.405)
    let munich = TravelCoordinate(latitude: 48.137, longitude: 11.575)

    private func service(fileURL: URL? = nil) -> TravelTimeService {
        let clock = self.clock
        return TravelTimeService(estimator: estimator, cacheURL: fileURL, now: { clock.now })
    }

    private func leg(_ id: String = "e1", to: String = "Büro, Berlin") -> TravelLeg {
        TravelLeg(eventID: id, origin: .home, from: home, to: TravelPlace(text: to), arrival: clock.now.addingTimeInterval(3600))
    }

    @Test func cachedValue_isReturnedWithoutRequest() async {
        var cache = TravelTimeCache(fileURL: fileURL)
        let known = leg()
        cache.store(minutes: 20, forTrip: TravelTimeCache.tripKey(from: known.from, to: known.to, transport: .automobile), now: clock.now)
        cache.save()
        let service = service(fileURL: fileURL)
        #expect(service.cachedMinutes(for: [known], transport: .automobile) == ["e1": 20])
        #expect(await service.fetchMissing(legs: [known], transport: .automobile, home: home) == false)
        #expect(estimator.tripCalls.isEmpty)
        #expect(service.revision == 0)
    }

    @Test func missingValue_isFetchedOnce() async {
        let service = service()
        let trip = leg()
        #expect(service.cachedMinutes(for: [trip], transport: .automobile).isEmpty)
        #expect(await service.fetchMissing(legs: [trip], transport: .automobile, home: home))
        #expect(service.cachedMinutes(for: [trip], transport: .automobile) == ["e1": 25])
        #expect(service.revision == 1)
        // The second call finds the value in the cache: no request, no new value, no reload.
        #expect(await service.fetchMissing(legs: [trip], transport: .automobile, home: home) == false)
        #expect(estimator.tripCalls.count == 1)
        #expect(service.revision == 1)
    }

    @Test func sameTripOfTwoEvents_isFetchedOnce() async {
        let service = service()
        #expect(await service.fetchMissing(legs: [leg("e1"), leg("e2")], transport: .automobile, home: home))
        #expect(estimator.tripCalls.count == 1)
        #expect(service.cachedMinutes(for: [leg("e1"), leg("e2")], transport: .automobile) == ["e1": 25, "e2": 25])
    }

    @Test func failedRequest_isNotCachedAndNotRetriedInSameSession() async {
        estimator.failingTexts = ["Büro, Berlin"]
        let service = service(fileURL: fileURL)
        let trip = leg()
        #expect(await service.fetchMissing(legs: [trip], transport: .automobile, home: home) == false)
        #expect(service.cachedMinutes(for: [trip], transport: .automobile).isEmpty)
        let callsAfterFirst = estimator.tripCalls.count + estimator.geocodeCalls.count
        #expect(await service.fetchMissing(legs: [trip], transport: .automobile, home: home) == false)
        #expect(estimator.tripCalls.count + estimator.geocodeCalls.count == callsAfterFirst)
        #expect(service.revision == 0)
        // A new session (network is back) tries again.
        estimator.failingTexts = []
        let nextSession = self.service(fileURL: fileURL)
        #expect(await nextSession.fetchMissing(legs: [trip], transport: .automobile, home: home))
        #expect(nextSession.cachedMinutes(for: [trip], transport: .automobile) == ["e1": 25])
    }

    @Test func expiredEntry_isFetchedAgain() async {
        let service = service()
        let trip = leg()
        _ = await service.fetchMissing(legs: [trip], transport: .automobile, home: home)
        clock.now = clock.now.addingTimeInterval(13 * 86_400)
        #expect(service.cachedMinutes(for: [trip], transport: .automobile) == ["e1": 25])
        clock.now = clock.now.addingTimeInterval(2 * 86_400)
        #expect(service.cachedMinutes(for: [trip], transport: .automobile).isEmpty)
        estimator.minutes = 30
        #expect(await service.fetchMissing(legs: [trip], transport: .automobile, home: home))
        #expect(service.cachedMinutes(for: [trip], transport: .automobile) == ["e1": 30])
    }

    @Test func cache_dropsOldestBeyondLimit() {
        var cache = TravelTimeCache(fileURL: nil)
        for index in 0...TravelTimeCache.maximumEntries {
            cache.store(minutes: index, forTrip: "trip-\(index)", now: clock.now.addingTimeInterval(TimeInterval(index)))
        }
        let now = clock.now.addingTimeInterval(1000)
        #expect(cache.entries.count == TravelTimeCache.maximumEntries)
        #expect(cache.minutes(forTrip: "trip-0", now: now) == nil)
        #expect(cache.minutes(forTrip: "trip-1", now: now) == 1)
        #expect(cache.minutes(forTrip: "trip-\(TravelTimeCache.maximumEntries)", now: now) == TravelTimeCache.maximumEntries)
    }

    @Test func cache_roundTripsThroughFile() {
        var cache = TravelTimeCache(fileURL: fileURL)
        cache.store(minutes: 15, forTrip: "a|b|automobile", now: clock.now)
        cache.store(latitude: 52.5, longitude: 13.4, forPlace: "place|text:büro", now: clock.now)
        cache.save()
        let loaded = TravelTimeCache(fileURL: fileURL)
        #expect(loaded.minutes(forTrip: "a|b|automobile", now: clock.now) == 15)
        let place = loaded.coordinates(forPlace: "place|text:büro", now: clock.now)
        #expect(place?.latitude == 52.5)
        #expect(place?.longitude == 13.4)
        try? FileManager.default.removeItem(at: fileURL)
        #expect(TravelTimeCache(fileURL: fileURL).entries.isEmpty)
    }

    @Test func cache_withUnreadableFile_startsEmpty() throws {
        try Data("not json".utf8).write(to: fileURL)
        #expect(TravelTimeCache(fileURL: fileURL).entries.isEmpty)
        try? FileManager.default.removeItem(at: fileURL)
    }

    @Test func transportChange_usesSeparateEntries() async {
        let service = service()
        let trip = leg()
        _ = await service.fetchMissing(legs: [trip], transport: .automobile, home: home)
        #expect(service.cachedMinutes(for: [trip], transport: .walking).isEmpty)
        estimator.minutes = 45
        #expect(await service.fetchMissing(legs: [trip], transport: .walking, home: home))
        #expect(service.cachedMinutes(for: [trip], transport: .walking) == ["e1": 45])
        #expect(service.cachedMinutes(for: [trip], transport: .automobile) == ["e1": 25])
    }

    @Test func placesWithoutCoordinates_areLookedUpOnceAndKept() async {
        let service = service()
        #expect(await service.fetchMissing(legs: [leg("e1", to: "Büro, Berlin")], transport: .automobile, home: home))
        // The home place has coordinates and is never looked up; each text is looked up once.
        #expect(await service.fetchMissing(legs: [leg("e2", to: "Kunde, Potsdam")], transport: .automobile, home: home))
        #expect(estimator.geocodeCalls.sorted() == ["Büro, Berlin", "Kunde, Potsdam"])
    }

    @Test func placesWithCoordinates_areNotLookedUp() async {
        let service = service()
        let located = TravelLeg(eventID: "e1", origin: .home, from: TravelPlace(text: "A", latitude: 52.5, longitude: 13.4),
                                to: TravelPlace(text: "B", latitude: 52.6, longitude: 13.5), arrival: clock.now.addingTimeInterval(60))
        #expect(await service.fetchMissing(legs: [located], transport: .transit, home: home))
        #expect(estimator.geocodeCalls.isEmpty)
    }

    @Test func fetch_isLimitedPerRun() async {
        let service = service()
        let legs = (0..<25).map { leg("e\($0)", to: "Ort \($0)") }
        #expect(await service.fetchMissing(legs: legs, transport: .automobile, home: home))
        #expect(estimator.tripCalls.count == TravelTimeService.requestsPerRun)
        // The next run continues with the rest.
        #expect(await service.fetchMissing(legs: legs, transport: .automobile, home: home))
        #expect(estimator.tripCalls.count == 25)
    }

    // MARK: Plausibility of text lookups

    @Test func lookupFarFromHome_isRejectedAndNotStored() async {
        estimator.locations = ["Bibliothek": munich]
        let service = service(fileURL: fileURL)
        let trip = leg("e1", to: "Bibliothek")
        #expect(await service.fetchMissing(legs: [trip], transport: .automobile, home: home) == false)
        #expect(service.cachedMinutes(for: [trip], transport: .automobile).isEmpty)
        #expect(estimator.tripCalls.isEmpty)
        #expect(service.revision == 0)
        // Neither the place nor the trip reached the file: a new session starts without them.
        #expect(TravelTimeCache(fileURL: fileURL).entries.isEmpty)
        // Failed for the session like other failures: no second lookup.
        #expect(await service.fetchMissing(legs: [trip], transport: .automobile, home: home) == false)
        #expect(estimator.geocodeCalls == ["Bibliothek"])
    }

    @Test func lookupNearHome_isAccepted() async {
        estimator.locations = ["Mensa": TravelCoordinate(latitude: 52.51, longitude: 13.33)]
        let service = service()
        let trip = leg("e1", to: "Mensa")
        #expect(await service.fetchMissing(legs: [trip], transport: .automobile, home: home))
        #expect(service.cachedMinutes(for: [trip], transport: .automobile) == ["e1": 25])
        #expect(estimator.geocodeReferences == [TravelCoordinate(latitude: 52.52, longitude: 13.405)])
    }

    @Test func textOnlyLeg_withoutAnyReference_isNotLookedUp() async {
        let service = service()
        let textOnlyHome = TravelPlace(text: "Zuhause, Berlin")
        let trip = TravelLeg(eventID: "e1", origin: .home, from: textOnlyHome, to: TravelPlace(text: "Raum 2.14"),
                             arrival: clock.now.addingTimeInterval(3600))
        #expect(await service.fetchMissing(legs: [trip], transport: .automobile, home: textOnlyHome) == false)
        #expect(await service.fetchMissing(legs: [trip], transport: .automobile) == false)
        #expect(estimator.geocodeCalls.isEmpty)
        #expect(estimator.tripCalls.isEmpty)
        #expect(service.cachedMinutes(for: [trip], transport: .automobile).isEmpty)
    }

    @Test func textLookup_usesTheOtherEndAsReferenceWhenHomeHasNoCoordinates() async {
        let service = service()
        let campus = TravelPlace(text: "Campus", latitude: 52.51, longitude: 13.33)
        let trip = TravelLeg(eventID: "e1", origin: .previousEvent(id: "e0"), from: campus, to: TravelPlace(text: "Hörsaal A"),
                             arrival: clock.now.addingTimeInterval(3600))
        #expect(await service.fetchMissing(legs: [trip], transport: .automobile, home: TravelPlace(text: "Zuhause")))
        #expect(estimator.geocodeReferences == [TravelCoordinate(latitude: 52.51, longitude: 13.33)])
    }

    @Test func lookupFarFromOtherEnd_isRejectedWithoutHomeCoordinates() async {
        estimator.locations = ["Hörsaal A": munich]
        let service = service()
        let campus = TravelPlace(text: "Campus", latitude: 52.51, longitude: 13.33)
        let trip = TravelLeg(eventID: "e1", origin: .previousEvent(id: "e0"), from: campus, to: TravelPlace(text: "Hörsaal A"),
                             arrival: clock.now.addingTimeInterval(3600))
        #expect(await service.fetchMissing(legs: [trip], transport: .automobile) == false)
        #expect(estimator.tripCalls.isEmpty)
    }

    @Test func cachedPlaceFarFromReference_isRejected() async {
        // A coordinate cached before the rule existed must not slip through.
        var cache = TravelTimeCache(fileURL: fileURL)
        let place = TravelPlace(text: "Bibliothek")
        cache.store(latitude: munich.latitude, longitude: munich.longitude, forPlace: TravelTimeCache.placeKey(place), now: clock.now)
        cache.save()
        let service = service(fileURL: fileURL)
        let trip = leg("e1", to: "Bibliothek")
        #expect(await service.fetchMissing(legs: [trip], transport: .automobile, home: home) == false)
        #expect(estimator.geocodeCalls.isEmpty)
        #expect(estimator.tripCalls.isEmpty)
    }

    @Test func rejectedPlace_isCheckedAgainForAnotherReference() async {
        estimator.locations = ["Bibliothek": munich]
        let service = service()
        let berlinTrip = leg("e1", to: "Bibliothek")
        #expect(await service.fetchMissing(legs: [berlinTrip], transport: .automobile, home: home) == false)
        // The same text, but home has no coordinates now and the other end is in Munich: the reference is Munich.
        let hotel = TravelPlace(text: "Hotel", latitude: 48.14, longitude: 11.58)
        let munichTrip = TravelLeg(eventID: "e2", origin: .previousEvent(id: "e1"), from: hotel, to: TravelPlace(text: "Bibliothek"),
                                   arrival: clock.now.addingTimeInterval(7200))
        #expect(await service.fetchMissing(legs: [munichTrip], transport: .automobile, home: TravelPlace(text: "Zuhause")))
    }

    @Test func tripLongerThanThreeHours_isDiscarded() async {
        estimator.minutes = 185
        let service = service(fileURL: fileURL)
        let trip = leg()
        #expect(await service.fetchMissing(legs: [trip], transport: .automobile, home: home) == false)
        #expect(service.cachedMinutes(for: [trip], transport: .automobile).isEmpty)
        #expect(service.revision == 0)
        #expect(TravelTimeCache(fileURL: fileURL).entries.isEmpty)
        // Not retried in the same session.
        #expect(await service.fetchMissing(legs: [trip], transport: .automobile, home: home) == false)
        #expect(estimator.tripCalls.count == 1)
    }

    @Test func tripOfExactlyThreeHours_isKept() async {
        estimator.minutes = 180
        let service = service()
        let trip = leg()
        #expect(await service.fetchMissing(legs: [trip], transport: .automobile, home: home))
        #expect(service.cachedMinutes(for: [trip], transport: .automobile) == ["e1": 180])
    }

    @Test func structuredCoordinates_areNotChecked() async {
        // Far apart on purpose: only free-text lookups are checked, not what the calendar app resolved.
        let service = service()
        let far = TravelLeg(eventID: "e1", origin: .home, from: home,
                            to: TravelPlace(text: "Messe München", latitude: munich.latitude, longitude: munich.longitude),
                            arrival: clock.now.addingTimeInterval(60))
        #expect(await service.fetchMissing(legs: [far], transport: .transit))
        #expect(estimator.geocodeCalls.isEmpty)
        #expect(service.cachedMinutes(for: [far], transport: .transit) == ["e1": 25])
    }
}
