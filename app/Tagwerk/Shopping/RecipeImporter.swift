import AIKit
import Foundation
import TagwerkCore

/// Reads the ingredients of a recipe with ChatGPT so they can go onto the shopping list ("Rezept hinzufügen").
///
/// Follows `ShoppingSorter`: nothing is sent or fetched without the user's consent and tap, the answer is a proposal that is
/// checked before anyone sees it, and a partial or late answer is never used. What goes to ChatGPT is the recipe text, or
/// the photo, and the names of the shopping categories. For a link only the text that was read from the page is sent, never
/// the address. The list, quantities already on it, tasks, notes and Health data stay on the device.
@MainActor
final class RecipeImporter {
    /// Where the recipe comes from.
    enum Input: Equatable {
        case text(String)
        /// A photo, already scaled down (`ImageDownscaler.jpeg`).
        case photo(jpeg: Data)
        case link(URL)
    }

    enum Failure: Error, Equatable {
        case consentMissing, network, signedOut, usageLimit, failed
        /// The page could not be loaded: not a web address, no answer, an error status or no text.
        case linkUnreadable
        /// The answer holds no ingredient.
        case nothingFound

        var message: String {
            switch self {
            case .consentMissing: String(localized: "Zum Lesen von Rezepten ist deine Einwilligung nötig.")
            case .network: String(localized: "Keine Verbindung. Das Lesen eines Rezepts braucht Internet.")
            case .signedOut: String(localized: "Die Anmeldung bei ChatGPT ist abgelaufen. Melde dich unter Einstellungen › KI neu an.")
            case .usageLimit: String(localized: "ChatGPT nimmt gerade keine Anfragen an. Versuch es später noch einmal.")
            case .failed: String(localized: "Das Rezept ließ sich nicht lesen. Versuch es noch einmal.")
            case .linkUnreadable: String(localized: "Die Seite ließ sich nicht laden. Prüfe den Link oder füge den Rezepttext ein.")
            case .nothingFound: String(localized: "In dem Rezept wurden keine Zutaten gefunden.")
            }
        }
    }

    /// One ingredient of the proposal.
    struct Candidate: Equatable, Identifiable {
        var name: String
        var quantity: String?
        /// A category name of the list, or "Sonstiges".
        var category: String
        /// An open item of that name is on the list already; the result sheet leaves it unselected.
        var alreadyOnList: Bool
        var id: String { ShoppingName.key(name) }
    }

    static let maxItems = 40
    static let maxQuantityLength = 40

    private let responder: any ResponseStreaming
    private let model: @MainActor () async throws -> String
    private let hasConsent: @MainActor () -> Bool
    private let fetcher: any PageFetching
    private let timeout: Duration

    init(responder: any ResponseStreaming, model: @escaping @MainActor () async throws -> String,
         hasConsent: @escaping @MainActor () -> Bool, fetcher: any PageFetching = URLSessionPageFetcher(),
         timeout: Duration = .seconds(45)) {
        self.responder = responder
        self.model = model
        self.hasConsent = hasConsent
        self.fetcher = fetcher
        self.timeout = timeout
    }

    // MARK: Reading

    /// Reads the recipe and returns the checked ingredients. `categoryNames` are the names of the list's categories without
    /// "Sonstiges"; `openItemKeys` are the `ShoppingName.key`s of the open items.
    func read(_ input: Input, categoryNames: [String], openItemKeys: Set<String>) async throws -> [Candidate] {
        // The consent check comes before anything that could reach the network, the page of a link included.
        guard hasConsent() else { throw Failure.consentMissing }
        let names = categoryNames + [ShoppingSorter.otherName]
        let message: InputItem
        switch input {
        case .text(let text):
            let recipe = RecipeText.limited(text.trimmingCharacters(in: .whitespacesAndNewlines))
            guard !recipe.isEmpty else { throw Failure.nothingFound }
            message = .user(Self.inputText(recipe: recipe, categories: names))
        case .photo(let jpeg):
            message = .userImage(text: Self.inputText(recipe: nil, categories: names), jpeg: jpeg)
        case .link(let url):
            message = .user(Self.inputText(recipe: try await pageText(of: url), categories: names))
        }
        let answer: String
        do {
            let slug = try await model()
            answer = try await withTimeout { [responder] in
                try await Self.collect(responder.respond(model: slug, instructions: Self.instructions, input: [message], tools: [],
                                                         jsonSchema: (name: "recipe_ingredients", schema: Self.schema)))
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as Failure {
            throw error
        } catch let error as ChatGPTError {
            throw Self.failure(for: error)
        } catch {
            throw Failure.failed
        }
        return try Self.validate(Data(answer.utf8), categoryNames: names, openItemKeys: openItemKeys)
    }

    /// The text of the page behind a link: the ingredient list of its structured data, otherwise its visible text.
    private func pageText(of url: URL) async throws -> String {
        guard Self.isWebLink(url) else { throw Failure.linkUnreadable }
        let data: Data
        do {
            data = try await fetcher.fetch(url)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Failure.linkUnreadable
        }
        let html = String(decoding: data, as: UTF8.self)
        let text = RecipeText.ingredients(fromHTML: html).map { $0.joined(separator: "\n") } ?? RecipeText.plainText(fromHTML: html)
        let limited = RecipeText.limited(text)
        guard !limited.isEmpty else { throw Failure.linkUnreadable }
        return limited
    }

    /// Only http and https links are loaded.
    static func isWebLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        return url.host()?.isEmpty == false
    }

    // MARK: Validation

    private struct Answer: Decodable {
        struct Entry: Decodable {
            var name: String
            var quantity: String?
            var category: String
        }
        var items: [Entry]
    }

    /// Checks the answer: empty names go, an unknown category becomes "Sonstiges", entries of the same name are merged
    /// (the first quantity wins, a later one fills a gap), an item that is open on the list is marked, and at most
    /// `maxItems` remain. No new category is ever created. `categoryNames` ends with "Sonstiges".
    static func validate(_ answer: Data, categoryNames: [String], openItemKeys: Set<String>) throws -> [Candidate] {
        guard let decoded = try? JSONDecoder().decode(Answer.self, from: answer) else { throw Failure.failed }
        let other = categoryNames.last ?? ShoppingSorter.otherName
        let known = Dictionary(categoryNames.map { ($0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), $0) },
                               uniquingKeysWith: { first, _ in first })
        var candidates: [Candidate] = []
        var indexByKey: [String: Int] = [:]
        for entry in decoded.items {
            let name = String(entry.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(ShoppingInputParser.maxNameLength))
            let key = ShoppingName.key(name)
            guard !key.isEmpty else { continue }
            let quantity = entry.quantity.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxQuantityLength)) }
                .flatMap { $0.isEmpty ? nil : $0 }
            if let index = indexByKey[key] {
                if candidates[index].quantity == nil { candidates[index].quantity = quantity }
                continue
            }
            let category = known[entry.category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] ?? other
            indexByKey[key] = candidates.count
            candidates.append(Candidate(name: name, quantity: quantity, category: category, alreadyOnList: openItemKeys.contains(key)))
        }
        guard !candidates.isEmpty else { throw Failure.nothingFound }
        return Array(candidates.prefix(maxItems))
    }

    // MARK: Applying

    /// Puts the selected ingredients on the list and remembers each one's category as an automatic assignment, so a choice
    /// the user makes later by hand takes precedence. Returns what the list reported.
    @discardableResult
    static func apply(_ selected: [Candidate], model: ShoppingModel, categories: ShoppingCategoryStore) async -> ShoppingModel.AddReport {
        let report = await model.add(selected.map { ParsedItem(name: $0.name, quantity: $0.quantity) })
        let all = categories.categories()
        let other = ShoppingSorter.otherName.lowercased()
        let failed = Set(report.failed.map(ShoppingName.key))
        for candidate in selected where !failed.contains(candidate.id) {
            let target = candidate.category.lowercased()
            if target == other {
                categories.assign(nameKey: candidate.id, to: nil, manual: false)
            } else if let category = all.first(where: { $0.name.lowercased() == target }) {
                categories.assign(nameKey: candidate.id, to: category.id, manual: false)
            }
        }
        model.refreshSections()
        return report
    }

    // MARK: Transport

    private static func failure(for error: ChatGPTError) -> Failure {
        switch error {
        case .network: .network
        case .notSignedIn, .invalidUser: .signedOut
        case .usageLimit: .usageLimit
        case .server, .incomplete: .failed
        }
    }

    /// Text of a completed answer; a stream that ends without `completed` is an error.
    nonisolated private static func collect(_ stream: AsyncThrowingStream<StreamEvent, Error>) async throws -> String {
        var text = ""
        var completed = false
        for try await event in stream {
            switch event {
            case .textDelta(let delta): text += delta
            case .completed: completed = true
            case .functionCall: break
            }
        }
        guard completed else { throw ChatGPTError.incomplete }
        return text
    }

    private struct TimedOut: Error {}

    private func withTimeout(_ operation: @escaping @Sendable () async throws -> String) async throws -> String {
        let limit = timeout
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: limit)
                throw TimedOut()
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw TimedOut() }
            return first
        }
    }

    // MARK: Prompt

    /// The user message: the recipe text (or a note that the photo is the recipe) and the category names as JSON.
    static func inputText(recipe: String?, categories: [String]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: ["categories": categories], options: [.sortedKeys])) ?? Data()
        let json = String(decoding: data, as: UTF8.self)
        guard let recipe else { return "The photo shows the recipe.\n\nCategories as JSON:\n\(json)" }
        return "Recipe:\n\(recipe)\n\nCategories as JSON:\n\(json)"
    }

    static let instructions = """
    Du liest ein Rezept und gibst die Zutaten als Einkaufsliste zurück. Die Eingabe ist der Rezepttext oder ein Foto des \
    Rezepts, dazu JSON mit "categories" (die Kategorien der Einkaufsliste; die letzte steht für alles ohne Kategorie).
    - Gib jede Zutat einmal zurück, mit einem kurzen Namen ohne Menge ("Zwiebel", nicht "2 mittelgroße Zwiebeln").
    - Schreibe die Menge in quantity ("500 g", "2 Dosen"), oder null, wenn das Rezept keine nennt.
    - Behalte die Sprache des Rezepts bei.
    - Wähle für category genau einen Namen aus der Liste der Eingabe, nimm die letzte Kategorie, wenn keine passt. \
    Erfinde keine Kategorie.
    - Gib keine Zutaten zurück, die nicht im Rezept stehen. Lass Wasser, Salz und Pfeffer nur weg, wenn das Rezept sie nicht \
    ausdrücklich als Zutat nennt, und ignoriere Zubereitungsschritte, Werbung und Kommentare.
    - Gib höchstens 40 Zutaten zurück.
    """

    static let schema = Data("""
    {
      "type": "object",
      "properties": {
        "items": {
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "name": { "type": "string" },
              "quantity": { "type": ["string", "null"] },
              "category": { "type": "string" }
            },
            "required": ["name", "quantity", "category"],
            "additionalProperties": false
          }
        }
      },
      "required": ["items"],
      "additionalProperties": false
    }
    """.utf8)
}

// MARK: Loading a page

/// Loads a web page for the recipe import. A protocol so tests need no network.
protocol PageFetching: Sendable {
    /// The first bytes of the page. Throws for any failure; the caller reports "link unreadable".
    func fetch(_ url: URL) async throws -> Data
}

/// Loads with a URL session of its own: no cookies, no cache, 15 seconds, at most 2 MB, only a successful answer.
struct URLSessionPageFetcher: PageFetching {
    static let timeout: TimeInterval = 15
    static let maximumBytes = 2 * 1024 * 1024

    func fetch(_ url: URL) async throws -> Data {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Self.timeout
        configuration.timeoutIntervalForResource = Self.timeout
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Self.timeout)
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count >= Self.maximumBytes { break }
        }
        return data
    }
}
