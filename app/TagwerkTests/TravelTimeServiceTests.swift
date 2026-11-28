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

    // MARK: Transport per event and the way home (V1)

    @Test func perLegTransport_usesItsOwnCacheKey() async {
        let service = service()
        var trip = leg()
        trip.transport = .transit
        #expect(await service.fetchMissing(legs: [trip], transport: .automobile, home: home))
        #expect(estimator.tripCalls == ["Zuhause, Berlin>Büro, Berlin>transit"])
        #expect(service.cachedMinutes(for: [trip], transport: .automobile) == ["e1": 25])
        // The same trip with the transport of the setting is another entry and still unknown.
        #expect(service.cachedMinutes(for: [leg()], transport: .automobile).isEmpty)
        // The transport of the setting applies to a leg without its own.
        #expect(await service.fetchMissing(legs: [leg()], transport: .walking, home: home))
        #expect(estimator.tripCalls.last == "Zuhause, Berlin>Büro, Berlin>walking")
    }

    @Test func returnLeg_isAskedByItsDeparture_andKeyedByItsID() async {
        let service = service()
        let office = TravelPlace(text: "Büro, Berlin", latitude: 52.51, longitude: 13.38)
        let back = TravelLeg(eventID: "e1", origin: .previousEvent(id: "e1"), from: office, to: home,
                             arrival: clock.now.addingTimeInterval(3600), direction: .returnHome)
        #expect(back.id == "e1#return")
        #expect(await service.fetchMissing(legs: [back], transport: .automobile, home: home))
        #expect(estimator.departureCalls == ["Büro, Berlin>Zuhause, Berlin>automobile"])
        #expect(service.cachedMinutes(for: [back], transport: .automobile) == ["e1#return": 25])
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

    @Test func concurrentCalls_runOneAfterTheOther_andAskOnce() async {
        let service = service()
        let trip = leg()
        async let first = service.fetchMissing(legs: [trip], transport: .automobile, home: home)
        async let second = service.fetchMissing(legs: [trip], transport: .automobile, home: home)
        let results = await [first, second]
        // The second call starts after the first one stored the value, so it finds it in the cache.
        #expect(results.filter { $0 }.count == 1)
        #expect(estimator.tripCalls.count == 1)
        #expect(service.cachedMinutes(for: [trip], transport: .automobile) == ["e1": 25])
    }

    @Test func cancelledCall_returnsWithoutRememberingAFailure() async {
        let service = service()
        let trip = leg()
        let task = Task { await service.fetchMissing(legs: [trip], transport: .automobile, home: home) }
        task.cancel()
        _ = await task.value
        // Nothing was marked as failed, so a later call still asks.
        #expect(await service.fetchMissing(legs: [trip], transport: .automobile, home: home))
        #expect(service.cachedMinutes(for: [trip], transport: .automobile) == ["e1": 25])
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

    @Test func notFound_isRememberedAndNotAskedAgain() async {
        estimator.failingTexts = ["Büro, Berlin"]
        let service = service(fileURL: fileURL)
        let trip = leg()
        // "Not found" is no network problem: no provisional block, no reload.
        #expect(await service.fetchMissing(legs: [trip], transport: .automobile, home: home) == false)
        #expect(service.resolvedTimes(for: [trip], transport: .automobile) == ResolvedTravelTimes())
        let callsAfterFirst = estimator.tripCalls.count + estimator.geocodeCalls.count
        #expect(await service.fetchMissing(legs: [trip], transport: .automobile, home: home) == false)
        #expect(estimator.tripCalls.count + estimator.geocodeCalls.count == callsAfterFirst)
        #expect(service.revision == 0)
        // The verdict survives a restart (the file holds it), so a start without network shows no provisional block either.
        estimator.failingTexts = []
        estimator.isOffline = true
        let nextSession = self.service(fileURL: fileURL)
        #expect(await nextSession.fetchMissing(legs: [trip], transport: .automobile, home: home) == false)
        #expect(nextSession.resolvedTimes(for: [trip], transport: .automobile) == ResolvedTravelTimes())
        #expect(estimator.tripCalls.count + estimator.geocodeCalls.count == callsAfterFirst)
    }

    @Test func notFound_isAskedAgainAfterOneDay() async {
        estimator.failingTexts = ["Büro, Berlin"]
        let service = service(fileURL: fileURL)
        let trip = leg()
        _ = await service.fetchMissing(legs: [trip], transport: .automobile, home: home)
        estimator.failingTexts = []
        clock.now = clock.now.addingTimeInterval(TravelTimeCache.rejectedLifetime + 60)
        let nextSession = self.service(fileURL: fileURL)
        #expect(await nextSession.fetchMissing(legs: [trip], transport: .automobile, home: home))
        #expect(nextSession.cachedMinutes(for: [trip], transport: .automobile) == ["e1": 25])
    }

    @Test func notFound_replacesAnOldValue() async {
        let service = service()
        let trip = leg()
        _ = await service.fetchMissing(legs: [trip], transport: .automobile, home: home)
        clock.now = clock.now.addingTimeInterval(15 * 86_400)
        estimator.minutes = 200  // implausible: the answer for the trip is now "no usable time"
        #expect(await service.fetchMissing(legs: [trip], transport: .automobile, home: home))
        #expect(service.resolvedTimes(for: [trip], transport: .automobile) == ResolvedTravelTimes())
    }

    @Test func oldEntry_staysUsableOffline_andIsRefreshedOnline() async {
        let service = service()
        let trip = leg()
        _ = await service.fetchMissing(legs: [trip], transport: .automobile, home: home)
        clock.now = clock.now.addingTimeInterval(30 * 86_400)
        // Offline: the value of 30 days ago is still the value, not an estimate.
        estimator.isOffline = true
        #expect(await service.fetchMissing(legs: [trip], transport: .automobile, home: home) == false)
        #expect(service.resolvedTimes(for: [trip], transport: .automobile) == ResolvedTravelTimes(minutes: ["e1": 25]))
        // Online again, after the retry interval: a different answer replaces it.
        estimator.isOffline = false
        estimator.minutes = 30
        clock.now = clock.now.addingTimeInterval(TravelTimeService.transientRetryInterval + 1)
        #expect(await service.fetchMissing(legs: [trip], transport: .automobile, home: home))
        #expect(service.cachedMinutes(for: [trip], transport: .automobile) == ["e1": 30])
    }

    @Test func refreshWithTheSameValue_changesNothingVisible() async {
        let service = service()
        let trip = leg()
        _ = await service.fetchMissing(legs: [trip], transport: .automobile, home: home)
        let revision = service.revision
        clock.now = clock.now.addingTimeInterval(15 * 86_400)
        #expect(await service.fetchMissing(legs: [trip], transport: .automobile, home: home) == false)
        #expect(service.revision == revision)
        #expect(estimator.tripCalls.count == 2)
        // The refresh restarted the clock of the entry: no new request right away.
        #expect(await service.fetchMissing(legs: [trip], transport: .automobile, home: home) == false)
        #expect(estimator.tripCalls.count == 2)
    }

    // MARK: Offline (F2)

    @Test func offline_withoutAnyValue_givesAThirtyMinuteEstimate() async {
        estimator.isOffline = true
        let service = service()
        let trip = leg()
        #expect(service.resolvedTimes(for: [trip], transport: .automobile) == ResolvedTravelTimes())
        #expect(await service.fetchMissing(legs: [trip], transport: .automobile, home: home))
        #expect(service.resolvedTimes(for: [trip], transport: .automobile) == ResolvedTravelTimes(provisionalMinutes: ["e1": 30]))
        #expect(service.cachedMinutes(for: [trip], transport: .automobile).isEmpty)
        #expect(service.revision == 1)
    }

    @Test func offline_sameFailureAgain_doesNotReloadAndIsNotRetriedAtOnce() async {
        estimator.isOffline = true
        let service = service()
        let trip = leg()
        _ = await service.fetchMissing(legs: [trip], transport: .automobile, home: home)
        let calls = estimator.tripCalls.count + estimator.geocodeCalls.count
        #expect(await service.fetchMissing(legs: [trip], transport: .automobile, home: home) == false)
        #expect(estimator.tripCalls.count + estimator.geocodeCalls.count == calls)
        // After the interval it asks again; the same answer is no change, so no reload.
        clock.now = clock.now.addingTimeInterval(TravelTimeService.transientRetryInterval + 1)
        #expect(await service.fetchMissing(legs: [trip], transport: .automobile, home: home) == false)
        #expect(estimator.tripCalls.count + estimator.geocodeCalls.count > calls)
        #expect(service.revision == 1)
        #expect(service.resolvedTimes(for: [trip], transport: .automobile).provisionalMinutes == ["e1": 30])
    }

    @Test func offline_estimateIsReplacedByTheFreshValueOnline() async {
        estimator.isOffline = true
        let service = service(fileURL: fileURL)
        let trip = leg()
        _ = await service.fetchMissing(legs: [trip], transport: .automobile, home: home)
        estimator.isOffline = false
        clock.now = clock.now.addingTimeInterval(TravelTimeService.transientRetryInterval + 1)
        #expect(await service.fetchMissing(legs: [trip], transport: .automobile, home: home))
        #expect(service.resolvedTimes(for: [trip], transport: .automobile) == ResolvedTravelTimes(minutes: ["e1": 25]))
        #expect(service.revision == 2)
    }

    @Test func offline_usesTheLastKnownTimeToTheSameDestination() async {
        let service = service()
        let known = TravelLeg(eventID: "old", origin: .previousEvent(id: "x"), from: TravelPlace(text: "Kunde, Potsdam", latitude: 52.4, longitude: 13.06),
                              to: TravelPlace(text: "Büro, Berlin"), arrival: clock.now.addingTimeInterval(3600))
        estimator.minutes = 20
        _ = await service.fetchMissing(legs: [known], transport: .automobile, home: home)
        // A trip to the same destination from home: no value of its own, the network is gone.
        estimator.isOffline = true
        let trip = leg("e2", to: "Büro, Berlin")
        #expect(await service.fetchMissing(legs: [trip], transport: .automobile, home: home))
        #expect(service.resolvedTimes(for: [trip], transport: .automobile).provisionalMinutes == ["e2": 20])
    }

    @Test func offline_ignoresOtherDestinationsAndTransports() async {
        let service = service()
        estimator.minutes = 20
        _ = await service.fetchMissing(legs: [leg("e1", to: "Büro, Berlin")], transport: .automobile, home: home)
        _ = await service.fetchMissing(legs: [leg("e2", to: "Kunde, Potsdam")], transport: .walking, home: home)
        estimator.isOffline = true
        let otherDestination = leg("e3", to: "Uni, Berlin")
        let otherTransport = leg("e4", to: "Büro, Berlin")
        #expect(await service.fetchMissing(legs: [otherDestination], transport: .automobile, home: home))
        #expect(await service.fetchMissing(legs: [otherTransport], transport: .transit, home: home))
        #expect(service.resolvedTimes(for: [otherDestination], transport: .automobile).provisionalMinutes == ["e3": 30])
        #expect(service.resolvedTimes(for: [otherTransport], transport: .transit).provisionalMinutes == ["e4": 30])
    }

    @Test func offline_afterRestart_keepsStoredValuesAndEstimatesTheRest() async {
        let service = service(fileURL: fileURL)
        let stored = leg("e1", to: "Büro, Berlin")
        _ = await service.fetchMissing(legs: [stored], transport: .automobile, home: home)
        estimator.isOffline = true
        clock.now = clock.now.addingTimeInterval(40 * 86_400)
        let restarted = self.service(fileURL: fileURL)
        let fresh = leg("e2", to: "Kunde, Potsdam")
        _ = await restarted.fetchMissing(legs: [stored, fresh], transport: .automobile, home: home)
        let resolved = restarted.resolvedTimes(for: [stored, fresh], transport: .automobile)
        #expect(resolved.minutes == ["e1": 25])
        #expect(resolved.provisionalMinutes == ["e2": 30])
    }

    @Test func offlineLookup_isNotRememberedAsUnknownPlace() async {
        // The place text cannot be looked up without network. That says nothing about the place.
        estimator.isOffline = true
        let service = service()
        let trip = leg()
        _ = await service.fetchMissing(legs: [trip], transport: .automobile, home: home)
        estimator.isOffline = false
        clock.now = clock.now.addingTimeInterval(TravelTimeService.transientRetryInterval + 1)
        #expect(await service.fetchMissing(legs: [trip], transport: .automobile, home: home))
        #expect(service.cachedMinutes(for: [trip], transport: .automobile) == ["e1": 25])
    }

    @Test func offline_unresolvableTrip_getsNoEstimate() async {
        // No starting point with coordinates: not a network problem, the trip cannot be asked at all.
        estimator.isOffline = true
        let service = service()
        let textOnlyHome = TravelPlace(text: "Zuhause, Berlin")
        let trip = TravelLeg(eventID: "e1", origin: .home, from: textOnlyHome, to: TravelPlace(text: "Raum 2.14"),
                             arrival: clock.now.addingTimeInterval(3600))
        #expect(await service.fetchMissing(legs: [trip], transport: .automobile, home: textOnlyHome) == false)
        #expect(service.resolvedTimes(for: [trip], transport: .automobile) == ResolvedTravelTimes())
    }

    // MARK: Cache

    @Test func cache_readsOldEntriesWithoutRejectedField() throws {
        let json = """
        {"a|b|automobile": {"minutes": 15, "storedAt": "2026-01-01T10:00:00Z"},
         "place|text:büro": {"latitude": 52.5, "longitude": 13.4, "storedAt": "2026-01-01T10:00:00Z"}}
        """
        try Data(json.utf8).write(to: fileURL)
        let cache = TravelTimeCache(fileURL: fileURL)
        #expect(cache.minutes(forTrip: "a|b|automobile") == 15)
        #expect(!cache.isRejected(forTrip: "a|b|automobile"))
        #expect(cache.entries.count == 2)
        try? FileManager.default.removeItem(at: fileURL)
    }

    @Test func cache_rejectedTrip_hasNoMinutesButIsKnown() {
        var cache = TravelTimeCache(fileURL: nil)
        cache.storeRejected(forTrip: "a|b|automobile", now: clock.now)
        #expect(cache.minutes(forTrip: "a|b|automobile") == nil)
        #expect(cache.isRejected(forTrip: "a|b|automobile"))
        #expect(!cache.needsRefresh(forTrip: "a|b|automobile", now: clock.now.addingTimeInterval(3600)))
        #expect(cache.needsRefresh(forTrip: "a|b|automobile", now: clock.now.addingTimeInterval(TravelTimeCache.rejectedLifetime)))
        cache.store(minutes: 10, forTrip: "a|b|automobile", now: clock.now)
        #expect(cache.minutes(forTrip: "a|b|automobile") == 10)
        #expect(!cache.isRejected(forTrip: "a|b|automobile"))
    }

    @Test func cache_needsRefresh_onlyAfterTheLifetime() {
        var cache = TravelTimeCache(fileURL: nil)
        #expect(cache.needsRefresh(forTrip: "a|b|automobile", now: clock.now))
        cache.store(minutes: 10, forTrip: "a|b|automobile", now: clock.now)
        #expect(!cache.needsRefresh(forTrip: "a|b|automobile", now: clock.now.addingTimeInterval(TravelTimeCache.lifetime - 1)))
        #expect(cache.needsRefresh(forTrip: "a|b|automobile", now: clock.now.addingTimeInterval(TravelTimeCache.lifetime)))
        // Reading ignores the age.
        #expect(cache.minutes(forTrip: "a|b|automobile") == 10)
    }

    @Test func cache_latestMinutesToDestination_picksTheNewestUsableOne() {
        var cache = TravelTimeCache(fileURL: nil)
        cache.store(minutes: 10, forTrip: "geo:1|text:büro|automobile", now: clock.now)
        cache.store(minutes: 25, forTrip: "text:zuhause|text:büro|automobile", now: clock.now.addingTimeInterval(60))
        cache.store(minutes: 0, forTrip: "text:nah|text:büro|automobile", now: clock.now.addingTimeInterval(120))
        cache.storeRejected(forTrip: "text:ort|text:büro|automobile", now: clock.now.addingTimeInterval(180))
        cache.store(minutes: 45, forTrip: "text:zuhause|text:büro|walking", now: clock.now.addingTimeInterval(240))
        cache.store(minutes: 40, forTrip: "text:zuhause|text:anderes büro|automobile", now: clock.now.addingTimeInterval(300))
        cache.store(latitude: 1, longitude: 2, forPlace: "place|text:büro", now: clock.now.addingTimeInterval(360))
        #expect(cache.latestMinutes(toDestination: "text:büro", transport: .automobile) == 25)
        #expect(cache.latestMinutes(toDestination: "text:büro", transport: .walking) == 45)
        #expect(cache.latestMinutes(toDestination: "text:büro", transport: .transit) == nil)
        #expect(cache.latestMinutes(toDestination: "text:unbekannt", transport: .automobile) == nil)
    }

    @Test func cache_dropsOldestBeyondLimit() {
        var cache = TravelTimeCache(fileURL: nil)
        for index in 0...TravelTimeCache.maximumEntries {
            cache.store(minutes: index, forTrip: "trip-\(index)", now: clock.now.addingTimeInterval(TimeInterval(index)))
        }
        let now = clock.now.addingTimeInterval(1000)
        #expect(cache.entries.count == TravelTimeCache.maximumEntries)
        #expect(cache.minutes(forTrip: "trip-0") == nil)
        #expect(cache.minutes(forTrip: "trip-1") == 1)
        #expect(cache.minutes(forTrip: "trip-\(TravelTimeCache.maximumEntries)") == TravelTimeCache.maximumEntries)
    }

    @Test func cache_roundTripsThroughFile() {
        var cache = TravelTimeCache(fileURL: fileURL)
        cache.store(minutes: 15, forTrip: "a|b|automobile", now: clock.now)
        cache.store(latitude: 52.5, longitude: 13.4, forPlace: "place|text:büro", now: clock.now)
        cache.save()
        let loaded = TravelTimeCache(fileURL: fileURL)
        #expect(loaded.minutes(forTrip: "a|b|automobile") == 15)
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
        // Neither the place nor a time reached the file; only the verdict for the trip did.
        let stored = TravelTimeCache(fileURL: fileURL)
        #expect(stored.entries.values.allSatisfy { $0.rejected == true && $0.minutes == nil && $0.latitude == nil })
        #expect(stored.entries.count == 1)
        // Remembered like other "not found" answers: no second lookup.
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
        let trips = TravelTimeCache(fileURL: fileURL).entries.filter { !$0.key.hasPrefix("place|") }
        #expect(trips.count == 1)
        #expect(trips.values.allSatisfy { $0.rejected == true && $0.minutes == nil })
        // Not asked again.
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
