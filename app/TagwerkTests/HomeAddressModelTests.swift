import Foundation
import Testing
@testable import Tagwerk

@MainActor
struct HomeAddressModelTests {
    let settings = AppSettings()
    let suggester = FakeAddressSuggester()
    private let musterstrasse = AddressSuggestion(id: "1", title: "Musterstraße 1", subtitle: "10115 Berlin")
    private let musterweg = AddressSuggestion(id: "2", title: "Musterweg 1", subtitle: "80331 München")

    private final class Counter { var reloads = 0 }
    private let counter = Counter()

    private func model(lookUp: @escaping (String) async throws -> PlaceLookup = { _ in throw TravelTimeError.addressNotFound })
        -> HomeAddressModel {
        let counter = self.counter
        return HomeAddressModel(settings: settings, suggester: suggester, lookUp: lookUp,
                                reload: { counter.reloads += 1 }, debounce: .milliseconds(10))
    }

    @Test func typing_showsSuggestions_afterTheDebounce() async {
        suggester.answers = ["Muster": [musterstrasse, musterweg]]
        let model = model()
        model.query = "Muster"
        await model.queryChanged()
        #expect(model.suggestions == [musterstrasse, musterweg])
        #expect(model.status == .idle)
        #expect(suggester.calls == ["Muster"])
    }

    @Test func shortQuery_asksNothing() async {
        suggester.answers = ["Mu": [musterstrasse]]
        let model = model()
        model.query = "Mu"
        await model.queryChanged()
        #expect(model.suggestions.isEmpty)
        #expect(suggester.calls.isEmpty)
        // Spaces do not count.
        model.query = "  M  "
        await model.queryChanged()
        #expect(suggester.calls.isEmpty)
    }

    @Test func choose_storesAddressAndCoordinates_andReloadsThePlan() async {
        suggester.places["1"] = PlaceLookup(latitude: 52.52, longitude: 13.405, description: "Musterstraße 1, 10115 Berlin, Deutschland")
        suggester.answers = ["Muster": [musterstrasse]]
        let model = model()
        model.query = "Muster"
        await model.queryChanged()
        await model.choose(musterstrasse)
        #expect(settings.homeAddress == "Musterstraße 1, 10115 Berlin")
        #expect(settings.homeLatitude == 52.52)
        #expect(settings.homeLongitude == 13.405)
        #expect(model.status == .saved("Musterstraße 1, 10115 Berlin, Deutschland"))
        #expect(model.suggestions.isEmpty)
        #expect(model.query == "Musterstraße 1, 10115 Berlin")
        #expect(counter.reloads == 1)
        // The query now equals the stored address: the field's change does not start a new search.
        let calls = suggester.calls.count
        await model.queryChanged()
        #expect(suggester.calls.count == calls)
    }

    @Test func choose_whenItCannotBeResolved_keepsTheOldHome() async {
        settings.homeAddress = "Alt 1, Berlin"
        settings.homeLatitude = 52.0
        settings.homeLongitude = 13.0
        suggester.failsToResolve = true
        let model = model()
        await model.choose(musterstrasse)
        #expect(model.status == .failed)
        #expect(settings.homeAddress == "Alt 1, Berlin")
        #expect(counter.reloads == 0)
    }

    @Test func clear_removesTheHome() async {
        settings.homeAddress = "Musterstraße 1, Berlin"
        settings.homeLatitude = 52.52
        settings.homeLongitude = 13.405
        let model = model()
        #expect(model.status == .saved("Musterstraße 1, Berlin"))
        await model.clear()
        #expect(settings.homeAddress == nil)
        #expect(settings.homeLatitude == nil)
        #expect(settings.homeLongitude == nil)
        #expect(model.query.isEmpty)
        #expect(model.status == .idle)
        #expect(counter.reloads == 1)
    }

    @Test func noSuggestions_offersTheTypedCheck() async {
        let model = model(lookUp: { text in
            PlaceLookup(latitude: 48.1, longitude: 11.5, description: "\(text), Deutschland")
        })
        model.query = "Unbekannte Gasse 7"
        await model.queryChanged()
        #expect(model.status == .noSuggestions)
        // "Adresse trotzdem prüfen": the path of before the suggestions.
        await model.checkTypedAddress()
        #expect(settings.homeAddress == "Unbekannte Gasse 7")
        #expect(settings.homeLatitude == 48.1)
        #expect(model.status == .saved("Unbekannte Gasse 7, Deutschland"))
        #expect(counter.reloads == 1)
    }

    @Test func typedCheck_notFound_storesNothing() async {
        let model = model()
        model.query = "Nirgendwo 1"
        await model.checkTypedAddress()
        #expect(model.status == .failed)
        #expect(settings.homeAddress == nil)
    }

    @Test(.timeLimit(.minutes(1))) func staleAnswer_isDropped() async {
        suggester.answers = ["Mus": [musterweg], "Muster": [musterstrasse]]
        // The first request answers after the second one.
        let firstGate = Gate()
        suggester.gates = ["Mus": firstGate]
        let model = model()
        model.query = "Mus"
        let first = Task { await model.queryChanged() }
        // The debounce of the first request has passed and it waits for its answer.
        await firstGate.waitUntilEntered()
        model.query = "Muster"
        await model.queryChanged()
        firstGate.open()
        await first.value
        #expect(model.suggestions == [musterstrasse])
        #expect(suggester.calls == ["Mus", "Muster"])
    }
}
