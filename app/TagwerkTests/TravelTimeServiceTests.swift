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

    private func service(fileURL: URL? = nil) -> TravelTimeService {
        let clock = self.clock
        return TravelTimeService(estimator: estimator, cacheURL: fileURL, now: { clock.now })
    }

    private func leg(_ id: String = "e1", from: String = "Zuhause, Berlin", to: String = "Büro, Berlin") -> TravelLeg {
        TravelLeg(eventID: id, origin: .home, from: TravelPlace(text: from), to: TravelPlace(text: to),
                  arrival: clock.now.addingTimeInterval(3600))
    }

    @Test func cachedValue_isReturnedWithoutRequest() async {
        var cache = TravelTimeCache(fileURL: fileURL)
        let known = leg()
        cache.store(minutes: 20, forTrip: TravelTimeCache.tripKey(from: known.from, to: known.to, transport: .automobile), now: clock.now)
        cache.save()
        let service = service(fileURL: fileURL)
        #expect(service.cachedMinutes(for: [known], transport: .automobile) == ["e1": 20])
        #expect(await service.fetchMissing(legs: [known], transport: .automobile) == false)
        #expect(estimator.tripCalls.isEmpty)
        #expect(service.revision == 0)
    }

    @Test func missingValue_isFetchedOnce() async {
        let service = service()
        let trip = leg()
        #expect(service.cachedMinutes(for: [trip], transport: .automobile).isEmpty)
        #expect(await service.fetchMissing(legs: [trip], transport: .automobile))
        #expect(service.cachedMinutes(for: [trip], transport: .automobile) == ["e1": 25])
        #expect(service.revision == 1)
        // The second call finds the value in the cache: no request, no new value, no reload.
        #expect(await service.fetchMissing(legs: [trip], transport: .automobile) == false)
        #expect(estimator.tripCalls.count == 1)
        #expect(service.revision == 1)
    }

    @Test func sameTripOfTwoEvents_isFetchedOnce() async {
        let service = service()
        #expect(await service.fetchMissing(legs: [leg("e1"), leg("e2")], transport: .automobile))
        #expect(estimator.tripCalls.count == 1)
        #expect(service.cachedMinutes(for: [leg("e1"), leg("e2")], transport: .automobile) == ["e1": 25, "e2": 25])
    }

    @Test func failedRequest_isNotCachedAndNotRetriedInSameSession() async {
        estimator.failingTexts = ["Büro, Berlin"]
        let service = service(fileURL: fileURL)
        let trip = leg()
        #expect(await service.fetchMissing(legs: [trip], transport: .automobile) == false)
        #expect(service.cachedMinutes(for: [trip], transport: .automobile).isEmpty)
        let callsAfterFirst = estimator.tripCalls.count + estimator.geocodeCalls.count
        #expect(await service.fetchMissing(legs: [trip], transport: .automobile) == false)
        #expect(estimator.tripCalls.count + estimator.geocodeCalls.count == callsAfterFirst)
        #expect(service.revision == 0)
        // A new session (network is back) tries again.
        estimator.failingTexts = []
        let nextSession = self.service(fileURL: fileURL)
        #expect(await nextSession.fetchMissing(legs: [trip], transport: .automobile))
        #expect(nextSession.cachedMinutes(for: [trip], transport: .automobile) == ["e1": 25])
    }

    @Test func expiredEntry_isFetchedAgain() async {
        let service = service()
        let trip = leg()
        _ = await service.fetchMissing(legs: [trip], transport: .automobile)
        clock.now = clock.now.addingTimeInterval(13 * 86_400)
        #expect(service.cachedMinutes(for: [trip], transport: .automobile) == ["e1": 25])
        clock.now = clock.now.addingTimeInterval(2 * 86_400)
        #expect(service.cachedMinutes(for: [trip], transport: .automobile).isEmpty)
        estimator.minutes = 30
        #expect(await service.fetchMissing(legs: [trip], transport: .automobile))
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
        _ = await service.fetchMissing(legs: [trip], transport: .automobile)
        #expect(service.cachedMinutes(for: [trip], transport: .walking).isEmpty)
        estimator.minutes = 45
        #expect(await service.fetchMissing(legs: [trip], transport: .walking))
        #expect(service.cachedMinutes(for: [trip], transport: .walking) == ["e1": 45])
        #expect(service.cachedMinutes(for: [trip], transport: .automobile) == ["e1": 25])
    }

    @Test func placesWithoutCoordinates_areLookedUpOnceAndKept() async {
        let service = service()
        #expect(await service.fetchMissing(legs: [leg("e1", to: "Büro, Berlin")], transport: .automobile))
        // Home was looked up once for the first trip; the second trip reuses it.
        #expect(await service.fetchMissing(legs: [leg("e2", to: "Kunde, Potsdam")], transport: .automobile))
        #expect(estimator.geocodeCalls.filter { $0 == "Zuhause, Berlin" }.count == 1)
        #expect(estimator.geocodeCalls.sorted() == ["Büro, Berlin", "Kunde, Potsdam", "Zuhause, Berlin"])
    }

    @Test func placesWithCoordinates_areNotLookedUp() async {
        let service = service()
        let located = TravelLeg(eventID: "e1", origin: .home, from: TravelPlace(text: "A", latitude: 52.5, longitude: 13.4),
                                to: TravelPlace(text: "B", latitude: 52.6, longitude: 13.5), arrival: clock.now.addingTimeInterval(60))
        #expect(await service.fetchMissing(legs: [located], transport: .transit))
        #expect(estimator.geocodeCalls.isEmpty)
    }

    @Test func fetch_isLimitedPerRun() async {
        let service = service()
        let legs = (0..<25).map { leg("e\($0)", to: "Ort \($0)") }
        #expect(await service.fetchMissing(legs: legs, transport: .automobile))
        #expect(estimator.tripCalls.count == TravelTimeService.requestsPerRun)
        // The next run continues with the rest.
        #expect(await service.fetchMissing(legs: legs, transport: .automobile))
        #expect(estimator.tripCalls.count == 25)
    }
}
