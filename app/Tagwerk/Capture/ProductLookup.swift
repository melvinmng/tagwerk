import Foundation
import GitHubKit
import Network
import Observation
import OSLog
import TagwerkCore

/// Why the online search sent nothing, or what went wrong with a request.
enum ProductLookupError: Error, Equatable {
    /// The user has not agreed.
    case noConsent
    case offline
    /// Fewer than `ProductSearchRules.minimumQueryLength` characters.
    case queryTooShort
    /// The local limit of requests per minute is used up; `wait` is the time until the next one may go out.
    case rateLimited(wait: TimeInterval)
    /// The operator refused the request (HTTP 403): a blocked network address or client, not a busy server.
    case blocked
    /// The operator's request limit is reached (HTTP 429).
    case tooManyRequests
    /// The operator is overloaded or down (HTTP 5xx, also its global limit, 503).
    case serverBusy
    /// A barcode that is not one.
    case invalidBarcode
    /// No answer, an unreadable answer or another error status.
    case failed

    var message: String {
        switch self {
        case .noConsent: String(localized: "Für die Online-Suche ist deine Einwilligung nötig.")
        case .offline: String(localized: "Keine Verbindung")
        case .queryTooShort: String(localized: "Gib mindestens \(ProductSearchRules.minimumQueryLength) Zeichen ein.")
        case .rateLimited(let wait): String(localized: "Bitte kurz warten, noch \(Int(wait)) s. Open Food Facts erlaubt nur wenige Anfragen pro Minute.")
        case .blocked: String(localized: "Open Food Facts hat die Anfrage abgelehnt (Fehler 403). Das betrifft meist die Netzadresse oder die Kennung der App, nicht deine Eingabe. Versuch es später oder in einem anderen Netz noch einmal.")
        case .tooManyRequests: String(localized: "Open Food Facts bekommt von deinem Anschluss gerade zu viele Anfragen. Warte etwa eine Minute und versuch es noch einmal.")
        case .serverBusy: String(localized: "Open Food Facts nimmt gerade keine Anfragen an. Versuch es später noch einmal.")
        case .invalidBarcode: String(localized: "Das ist kein gültiger Strichcode.")
        case .failed: String(localized: "Die Suche hat nicht geklappt. Versuch es noch einmal.")
        }
    }
}

/// The online search in Open Food Facts as the screens use it. Injected, so the screens and their tests run without a network.
@MainActor
protocol ProductLookingUp: AnyObject {
    /// One page of hits for the words; one request on the user's tap, or none when the answer is in memory.
    func search(_ query: String, page: Int) async throws -> ProductPage
    /// The product of a barcode, `nil` when the database does not know it.
    func product(barcode: String) async throws -> ProductCandidate?
    /// Forgets the answers kept in memory (the sheet closed).
    func clearMemory()
}

/// The client of the online search.
///
/// A request goes out only when, in this order: the user agreed (`consent`), the device is online, the answer is not already in
/// memory, and the local limit has a free slot. The contact address is optional; without a valid one the request names the project URL. A call that stops at an earlier step uses no slot and
/// sends nothing. Answers stay in memory only; nothing is written to disk and no search words are logged.
@MainActor
final class ProductLookup: ProductLookingUp {
    private let transport: any HTTPTransport
    private let hasConsent: () -> Bool
    private let contact: () -> String?
    private let isOnline: () -> Bool
    private let version: () -> String
    private let now: () -> Date
    private var searchLimiter = ProductSearchRules.makeSearchLimiter()
    private var productLimiter = ProductSearchRules.makeProductLimiter()
    private var pages: [String: ProductPage] = [:]
    private var products: [String: ProductCandidate?] = [:]
    private let logger = Logger(subsystem: "local.tagwerk", category: "openfoodfacts")

    init(transport: any HTTPTransport, hasConsent: @escaping () -> Bool, contact: @escaping () -> String?,
         isOnline: @escaping () -> Bool, version: @escaping () -> String, now: @escaping () -> Date = { Date() }) {
        self.transport = transport
        self.hasConsent = hasConsent
        self.contact = contact
        self.isOnline = isOnline
        self.version = version
        self.now = now
    }

    func search(_ query: String, page: Int = 1) async throws -> ProductPage {
        let userAgent = try gate()
        let words = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard words.count >= ProductSearchRules.minimumQueryLength else { throw ProductLookupError.queryTooShort }
        let key = "\(max(1, page))|\(SearchText.fold(words))"
        if let cached = pages[key] { return cached }
        if case .wait(let seconds) = searchLimiter.attempt(at: now()) { throw ProductLookupError.rateLimited(wait: seconds) }
        let request = OpenFoodFactsAPI.searchRequest(query: words, page: page, userAgent: userAgent)
        let data = try await send(request)
        guard let result = try? OpenFoodFactsAPI.readSearch(data, page: page) else { throw ProductLookupError.failed }
        pages[key] = result
        return result
    }

    func product(barcode: String) async throws -> ProductCandidate? {
        let userAgent = try gate()
        let code = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let request = OpenFoodFactsAPI.productRequest(barcode: code, userAgent: userAgent) else { throw ProductLookupError.invalidBarcode }
        if let cached = products[code] { return cached }
        if case .wait(let seconds) = productLimiter.attempt(at: now()) { throw ProductLookupError.rateLimited(wait: seconds) }
        let data = try await send(request)
        // `try?` would fold "unknown barcode" (nil) into "unreadable answer"; the two are told apart here.
        let result: ProductCandidate?
        do {
            result = try OpenFoodFactsAPI.readProduct(data)
        } catch {
            throw ProductLookupError.failed
        }
        products[code] = .some(result)
        return result
    }

    func clearMemory() {
        pages = [:]
        products = [:]
    }

    // MARK: Private

    /// Consent and connection; the user agent on success (the contact address when valid, otherwise the project URL).
    private func gate() throws -> String {
        guard hasConsent() else { throw ProductLookupError.noConsent }
        guard isOnline() else { throw ProductLookupError.offline }
        return ProductSearchRules.userAgent(version: version(), contact: contact())
    }

    /// Sends the request. A refusal is told apart by its status and logged as the status alone: no search words, no barcode, no address.
    private func send(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await transport.send(request)
            if let error = Self.error(forStatus: response.statusCode) {
                logger.error("Open Food Facts answered HTTP \(response.statusCode)")
                throw error
            }
            return data
        } catch let error as ProductLookupError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let nsError = error as NSError
            logger.error("Open Food Facts request failed: \(nsError.domain, privacy: .public) \(nsError.code)")
            throw ProductLookupError.failed
        }
    }

    /// The error of an HTTP status; `nil` for a success. 403 (refused), 429 (limit reached) and 5xx (operator down or overloaded)
    /// are different problems with different remedies, so each has its own message.
    static func error(forStatus status: Int) -> ProductLookupError? {
        switch status {
        case 200..<300: nil
        case 403: .blocked
        case 429: .tooManyRequests
        case 500..<600: .serverBusy
        default: .failed
        }
    }

    // MARK: Production transport

    /// The session of the online search: no cookies, no cache on disk, no credentials, no shared state with the rest of the app.
    static func makeSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = OpenFoodFactsAPI.timeout
        configuration.timeoutIntervalForResource = OpenFoodFactsAPI.timeout * 2
        configuration.waitsForConnectivity = false
        configuration.httpAdditionalHeaders = nil
        return configuration
    }

    static func makeTransport() -> any HTTPTransport {
        URLSessionTransport(session: URLSession(configuration: makeSessionConfiguration()))
    }
}

/// Whether the device is online, for the buttons that need the network. Starts as online: until the system has answered, a tap is
/// not blocked, and a request that fails is reported as a failure. The system is only asked once `start()` is called (by the screens
/// that need it), so no watcher runs while nobody looks.
@MainActor
@Observable
final class ConnectivityMonitor {
    private(set) var isOnline = true
    private let isFixed: Bool
    @ObservationIgnored private var monitor: NWPathMonitor?

    /// `fixed` pins the state (tests and the demo mode); otherwise the system path is watched after `start()`.
    init(fixed: Bool? = nil) {
        isFixed = fixed != nil
        if let fixed { isOnline = fixed }
    }

    func start() {
        guard !isFixed, monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "de.tagwerk.connectivity"))
        self.monitor = monitor
    }
}
