import Foundation
import GitHubKit
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// A transport that records every request and answers from a script. The tests never touch the network.
fileprivate final class RecordingTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private var answers: [(Int, String)] = []
    var requests: [URLRequest] { lock.withLock { recorded } }

    func enqueue(_ body: String, status: Int = 200) { lock.withLock { answers.append((status, body)) } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (status, body) = lock.withLock { () -> (Int, String) in
            recorded.append(request)
            return answers.isEmpty ? (200, Self.emptySearch) : answers.removeFirst()
        }
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    static let emptySearch = #"{"count":0,"page":1,"page_size":20,"products":[]}"#
    static let oneHit = #"{"count":1,"page":1,"page_size":20,"products":[{"code":"4000000000001","product_name":"Demo Skyr","nutriments":{"energy-kcal_100g":62}}]}"#
    static let product = #"{"status":1,"code":"4000000000001","product":{"product_name":"Demo Skyr","nutriments":{"energy-kcal_100g":62}}}"#
}

/// A transport that fails like a lost connection.
fileprivate struct FailingTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) { throw URLError(.notConnectedToInternet) }
}

@MainActor
struct ProductLookupTests {
    final class Clock { var now = Date(timeIntervalSince1970: 1_000_000) }
    let clock = Clock()
    fileprivate let transport = RecordingTransport()

    func make(consent: Bool = true, contact: String? = "test@example.org", online: Bool = true, version: String = "9.9",
              transport: (any HTTPTransport)? = nil) -> ProductLookup {
        let clock = self.clock
        return ProductLookup(transport: transport ?? self.transport, hasConsent: { consent }, contact: { contact }, isOnline: { online },
                             version: { version }, now: { clock.now })
    }

    // MARK: Nothing goes out

    @Test func lookup_withoutConsent_sendsNothing() async {
        let lookup = make(consent: false)
        await #expect(throws: ProductLookupError.noConsent) { try await lookup.search("skyr", page: 1) }
        await #expect(throws: ProductLookupError.noConsent) { try await lookup.product(barcode: "4000000000001") }
        #expect(transport.requests.isEmpty)
    }

    @Test func lookup_withoutContactAddress_sendsNothing() async {
        for contact in [nil, "", "   ", "not an address", "a@b"] as [String?] {
            let lookup = make(contact: contact)
            await #expect(throws: ProductLookupError.noContact) { try await lookup.search("skyr", page: 1) }
            await #expect(throws: ProductLookupError.noContact) { try await lookup.product(barcode: "4000000000001") }
        }
        #expect(transport.requests.isEmpty)
    }

    @Test func lookup_offline_sendsNothingAndReportsOffline() async {
        let lookup = make(online: false)
        await #expect(throws: ProductLookupError.offline) { try await lookup.search("skyr", page: 1) }
        await #expect(throws: ProductLookupError.offline) { try await lookup.product(barcode: "4000000000001") }
        #expect(transport.requests.isEmpty)
        #expect(ProductLookupError.offline.message == "Keine Verbindung")
    }

    @Test func lookup_gateOrder_consentBeforeContactBeforeOnline() async {
        // Everything is missing: the first gate that stops the call is the one that is reported.
        await #expect(throws: ProductLookupError.noConsent) { try await make(consent: false, contact: nil, online: false).search("skyr", page: 1) }
        await #expect(throws: ProductLookupError.noContact) { try await make(consent: true, contact: nil, online: false).search("skyr", page: 1) }
        await #expect(throws: ProductLookupError.offline) { try await make(consent: true, contact: "a@example.org", online: false).search("skyr", page: 1) }
        #expect(transport.requests.isEmpty)
    }

    @Test func lookup_shortQuery_sendsNothing() async {
        let lookup = make()
        await #expect(throws: ProductLookupError.queryTooShort) { try await lookup.search("sk", page: 1) }
        await #expect(throws: ProductLookupError.queryTooShort) { try await lookup.search("  s  ", page: 1) }
        #expect(transport.requests.isEmpty)
    }

    @Test func lookup_invalidBarcode_sendsNothing() async {
        let lookup = make()
        await #expect(throws: ProductLookupError.invalidBarcode) { try await lookup.product(barcode: "12") }
        #expect(transport.requests.isEmpty)
    }

    // MARK: The request

    @Test func request_hasTheExactUserAgent_andNothingElse() async throws {
        transport.enqueue(RecordingTransport.oneHit)
        let page = try await make(contact: "  test@example.org ", version: "9.9").search("Skyr natur", page: 1)
        #expect(page.candidates.map(\.name) == ["Demo Skyr"])
        let request = try #require(transport.requests.first)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "Tagwerk/9.9 (test@example.org)")
        #expect(request.allHTTPHeaderFields == ["User-Agent": "Tagwerk/9.9 (test@example.org)", "Accept": "application/json"])
        #expect(request.httpShouldHandleCookies == false && request.httpBody == nil && request.httpMethod == "GET")
    }

    @Test func request_hasNoCookiesNoAccountNoDeviceIdentifiers_inTheProductionSession() {
        let configuration = ProductLookup.makeSessionConfiguration()
        #expect(configuration.httpCookieStorage == nil, "no cookie jar")
        #expect(configuration.httpShouldSetCookies == false)
        #expect(configuration.httpCookieAcceptPolicy == .never)
        #expect(configuration.urlCache == nil, "no cache on disk: the hits stay in memory only")
        #expect(configuration.urlCredentialStorage == nil, "no account")
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
        #expect(configuration.httpAdditionalHeaders == nil, "no further headers")
        #expect(configuration.waitsForConnectivity == false, "no request waits in the background for the network")
    }

    @Test func request_productLookup_usesTheProductAddress() async throws {
        transport.enqueue(RecordingTransport.product)
        let product = try await make().product(barcode: " 4000000000001 ")
        #expect(product?.food.kcal == 62)
        #expect(transport.requests.first?.url?.path == "/api/v2/product/4000000000001")
    }

    @Test func product_unknownBarcode_isNil_andServedFromMemoryNextTime() async throws {
        transport.enqueue(#"{"status":0}"#)
        let lookup = make()
        #expect(try await lookup.product(barcode: "4000000000009") == nil)
        #expect(try await lookup.product(barcode: "4000000000009") == nil)
        #expect(transport.requests.count == 1, "the unknown answer is remembered too")
    }

    // MARK: Limits and memory

    @Test func limiter_blocksAboveLimit_andReportsWaitTime() async throws {
        let lookup = make()
        for index in 0..<ProductSearchRules.searchLimit { _ = try await lookup.search("skyr \(index)", page: 1) }
        #expect(transport.requests.count == 10)
        await #expect(throws: ProductLookupError.rateLimited(wait: 60)) { try await lookup.search("skyr extra", page: 1) }
        #expect(transport.requests.count == 10, "the eleventh search is not sent")
        clock.now = clock.now.addingTimeInterval(61)
        _ = try await lookup.search("skyr extra", page: 1)
        #expect(transport.requests.count == 11)
    }

    @Test func limiter_productLookupsHaveTheirOwnLimit() async throws {
        let lookup = make()
        for index in 0..<ProductSearchRules.searchLimit { _ = try await lookup.search("skyr \(index)", page: 1) }
        // The search limit is used up, a product lookup still goes out.
        transport.enqueue(RecordingTransport.product)
        #expect(try await lookup.product(barcode: "4000000000001") != nil)
    }

    @Test func limiter_sameQueryWithinSession_servedFromMemory() async throws {
        let lookup = make()
        transport.enqueue(RecordingTransport.oneHit)
        let first = try await lookup.search("Skyr", page: 1)
        let second = try await lookup.search("  skyr ", page: 1)
        #expect(first == second)
        #expect(transport.requests.count == 1, "the same words in the same session are not sent again")
        // A repeat from memory uses no slot: ten more different searches still fit.
        for index in 0..<9 { _ = try await lookup.search("andere \(index)", page: 1) }
        #expect(transport.requests.count == 10)
        _ = try await lookup.search("SKYR", page: 1)
        #expect(transport.requests.count == 10)
    }

    @Test func memory_isClearedWhenTheSheetCloses() async throws {
        let lookup = make()
        _ = try await lookup.search("skyr", page: 1)
        lookup.clearMemory()
        _ = try await lookup.search("skyr", page: 1)
        #expect(transport.requests.count == 2)
    }

    @Test func nextPage_isARequestOfItsOwn_andCountsAgainstTheLimit() async throws {
        let lookup = make()
        _ = try await lookup.search("skyr", page: 1)
        _ = try await lookup.search("skyr", page: 2)
        #expect(transport.requests.count == 2)
        let page = URLComponents(url: try #require(transport.requests.last?.url), resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "page" }?.value
        #expect(page == "2")
    }

    @Test func blockedCalls_useNoSlot() async throws {
        // Without consent, offline, with a query that is too short: calls that go nowhere must not use up the minute.
        final class Gate { var consent = false; var online = true }
        let gate = Gate()
        let clock = self.clock
        let lookup = ProductLookup(transport: transport, hasConsent: { gate.consent }, contact: { "test@example.org" },
                                   isOnline: { gate.online }, version: { "1" }, now: { clock.now })
        for _ in 0..<12 { _ = try? await lookup.search("skyr", page: 1) }
        gate.consent = true
        gate.online = false
        for _ in 0..<12 { _ = try? await lookup.search("skyr", page: 1) }
        gate.online = true
        for _ in 0..<12 { _ = try? await lookup.search("sk", page: 1) }
        #expect(transport.requests.isEmpty)
        for index in 0..<ProductSearchRules.searchLimit { _ = try await lookup.search("skyr \(index)", page: 1) }
        #expect(transport.requests.count == 10, "all ten slots of the minute were still free")
    }

    // MARK: Failures

    @Test func serverStatus_isMappedWithoutRetry() async {
        transport.enqueue("busy", status: 503)
        let lookup = make()
        await #expect(throws: ProductLookupError.serverBusy) { try await lookup.search("skyr", page: 1) }
        transport.enqueue("denied", status: 403)
        await #expect(throws: ProductLookupError.serverBusy) { try await lookup.search("quark", page: 1) }
        transport.enqueue("nope", status: 404)
        await #expect(throws: ProductLookupError.failed) { try await lookup.search("milch", page: 1) }
        #expect(transport.requests.count == 3, "a failed request is not repeated by itself")
    }

    @Test func unreadableAnswer_isAFailure_andNotRemembered() async {
        transport.enqueue("<html>not json</html>")
        let lookup = make()
        await #expect(throws: ProductLookupError.failed) { try await lookup.search("skyr", page: 1) }
        transport.enqueue(RecordingTransport.oneHit)
        #expect((try? await lookup.search("skyr", page: 1))?.candidates.count == 1)
    }

    @Test func transportError_isAFailure() async {
        let lookup = make(transport: FailingTransport())
        await #expect(throws: ProductLookupError.failed) { try await lookup.search("skyr", page: 1) }
    }
}

// MARK: - Consent and settings

@MainActor
struct FoodLookupSettingsTests {
    let container: ModelContainer
    let settings: AppSettings

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        settings = try AppSettings.current(in: container.mainContext)
    }

    @Test func onlineSearch_isOffByDefault_withoutAnAddress() {
        #expect(!settings.foodLookupConsent)
        #expect(settings.foodLookupContact == nil)
        #expect(!settings.isFoodLookupEnabled)
    }

    @Test func contactAddress_neverPrefilled() {
        let model = FoodLookupConsentModel(settings: settings)
        #expect(model.contact == "", "the sheet starts empty: no address from the device, an account or the app")
        #expect(!model.canAgree && !model.showsInvalidHint)
    }

    @Test func contactAddress_theSheetShowsOnlyWhatTheUserTypedEarlier() {
        settings.foodLookupContact = "mine@example.org"
        #expect(FoodLookupConsentModel(settings: settings).contact == "mine@example.org")
    }

    @Test func contactAddress_invalid_notAccepted() {
        let model = FoodLookupConsentModel(settings: settings)
        model.contact = "not an address"
        #expect(!model.canAgree && model.showsInvalidHint)
        model.agree(settings: settings)
        #expect(!settings.foodLookupConsent && settings.foodLookupContact == nil, "an invalid address does not switch anything on")
        #expect(settings.commitFoodLookupContact("also bad") == .invalid)
        #expect(settings.foodLookupContact == nil)
    }

    @Test func agreeing_storesTheTrimmedAddress_andSwitchesTheSearchOn() {
        let model = FoodLookupConsentModel(settings: settings)
        model.contact = "  me@example.org "
        #expect(model.canAgree)
        model.agree(settings: settings)
        #expect(settings.foodLookupConsent && settings.foodLookupContact == "me@example.org")
        #expect(settings.isFoodLookupEnabled)
    }

    @Test func contactAddress_cleared_switchesLookupOff() {
        settings.agreeToFoodLookup(contact: "me@example.org")
        #expect(settings.isFoodLookupEnabled)
        #expect(settings.commitFoodLookupContact("  ") == .cleared)
        #expect(settings.foodLookupContact == nil)
        #expect(!settings.foodLookupConsent && !settings.isFoodLookupEnabled)
    }

    @Test func contactAddress_changed_keepsTheSearchOn_andInvalidKeepsTheOldOne() {
        settings.agreeToFoodLookup(contact: "me@example.org")
        #expect(settings.commitFoodLookupContact("other@example.org") == .accepted("other@example.org"))
        #expect(settings.foodLookupContact == "other@example.org" && settings.isFoodLookupEnabled)
        #expect(settings.commitFoodLookupContact("broken") == .invalid)
        #expect(settings.foodLookupContact == "other@example.org", "an invalid entry changes nothing")
    }

    @Test func revoking_keepsTheAddress_butStopsEverything() {
        settings.agreeToFoodLookup(contact: "me@example.org")
        settings.foodLookupConsent = false
        #expect(!settings.isFoodLookupEnabled)
        #expect(settings.foodLookupContact == "me@example.org")
    }
}
