import AIKit
import Foundation
import TagwerkCore

/// Reads a recipe with ChatGPT: its title, servings, ingredients and steps. The ingredients can go onto the shopping list
/// ("Rezept hinzufügen"), the whole recipe can be saved as a recipe note. Both paths share this one reading step.
///
/// Follows `ShoppingSorter`: nothing is sent or fetched without the user's consent and tap, the answer is a proposal that is
/// checked before anyone sees it, and a partial or late answer is never used. What goes to ChatGPT is the recipe text, or
/// the photo or photos, and the names of the shopping categories. For a link only the text that was read from the page is sent, never
/// the address. The list, quantities already on it, tasks, notes and Health data stay on the device.
@MainActor
final class RecipeImporter {
    /// Where the recipe comes from.
    enum Input: Equatable {
        case text(String)
        /// The photos of one recipe (a recipe spread over several pages), in reading order, each already scaled down
        /// (`ImageDownscaler.jpeg`). They go to ChatGPT in one request and make one recipe; limits in `RecipePhotos`.
        case photos([Data])
        case link(URL)
        /// A note of the user and its text. A structured recipe note (`RecipeNote`) is read on the device, anything else is
        /// treated like pasted text. The caller makes sure the note is not private.
        case note(UUID, text: String)
    }

    enum Failure: Error, Equatable {
        case consentMissing, network, signedOut, usageLimit, failed
        /// The page could not be loaded: not a web address, no answer, an error status or no text.
        case linkUnreadable
        /// The answer holds no ingredient.
        case nothingFound
        /// More photos than `RecipePhotos.maximumCount`, or together too large to send.
        case photosTooLarge

        var message: String {
            switch self {
            case .consentMissing: String(localized: "Zum Lesen von Rezepten ist deine Einwilligung nötig.")
            case .network: String(localized: "Keine Verbindung. Das Lesen eines Rezepts braucht Internet.")
            case .signedOut: String(localized: "Die Anmeldung bei ChatGPT ist abgelaufen. Melde dich unter Einstellungen › KI neu an.")
            case .usageLimit: String(localized: "ChatGPT nimmt gerade keine Anfragen an. Versuch es später noch einmal.")
            case .failed: String(localized: "Das Rezept ließ sich nicht lesen. Versuch es noch einmal.")
            case .linkUnreadable: String(localized: "Die Seite ließ sich nicht laden. Prüfe den Link oder füge den Rezepttext ein.")
            case .nothingFound: String(localized: "In dem Rezept wurden keine Zutaten gefunden.")
            case .photosTooLarge: String(localized: "Die Fotos sind zu viele oder zu groß. Nimm höchstens \(RecipePhotos.maximumCount) Fotos.")
            }
        }
    }

    /// What reading a recipe gives: the recipe itself and the ingredients as a proposal for the shopping list.
    struct Result: Equatable {
        var title: String
        /// The servings the amounts are written for; `nil` when the recipe names none.
        var servings: Int?
        var candidates: [Candidate]
        var steps: [String]
        /// The page of a link import; there is none for text, photo and notes.
        var sourceURL: URL?
        /// The language the recipe was created in.
        var language: VoiceLanguage
        /// Read on the device from a structured recipe note: nothing was sent to ChatGPT.
        var readLocally = false
    }

    /// One ingredient of the proposal.
    struct Candidate: Equatable, Identifiable {
        var name: String
        /// The amount as text ("500 g", "nach Geschmack"), for the list's notes.
        var quantity: String?
        /// The amount and unit as numbers, when there are some; this is what scaling works on.
        var line: IngredientLine? = nil
        /// A category name of the list, or "Sonstiges".
        var category: String
        /// An open item of that name is on the list already; the result sheet leaves it unselected.
        var alreadyOnList: Bool
        var id: String { ShoppingName.key(name) }
    }

    static let maxItems = 40
    static let maxQuantityLength = 40
    static let maxSteps = 20
    static let maxStepLength = 300
    static let maxTitleLength = 120
    static let servingsRange = 1...50

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

    /// Reads the recipe and returns it with its checked ingredients. The title, ingredients and steps are written in
    /// `language`, translated when the recipe has another one. `categoryNames` are the names of the list's categories without
    /// "Sonstiges" (empty when the recipe is only saved); `openItemKeys` are the `ShoppingName.key`s of the open items.
    ///
    /// A structured recipe note is read on the device, without ChatGPT and without the consent; `localClassifier` gives the
    /// category name of an ingredient key from the user's own assignments and the dictionary, or `nil` for "Sonstiges".
    func read(_ input: Input, language: VoiceLanguage, categoryNames: [String], openItemKeys: Set<String>,
              localClassifier: (String) -> String? = { _ in nil }) async throws -> Result {
        var input = input
        let names = categoryNames + [ShoppingSorter.otherName]
        if case .note(_, let text) = input {
            if let note = RecipeNote.parse(text) {
                return try Self.result(for: note, language: language, categoryNames: names, openItemKeys: openItemKeys,
                                       classifier: localClassifier)
            }
            input = .text(text)
        }
        // The consent check comes before anything that could reach the network, the page of a link included.
        guard hasConsent() else { throw Failure.consentMissing }
        let message: InputItem
        var sourceURL: URL?
        switch input {
        case .text(let text), .note(_, let text):
            let recipe = RecipeText.limited(text.trimmingCharacters(in: .whitespacesAndNewlines))
            guard !recipe.isEmpty else { throw Failure.nothingFound }
            message = .user(Self.inputText(recipe: recipe, categories: names, language: language))
        case .photos(let jpegs):
            guard !jpegs.isEmpty else { throw Failure.nothingFound }
            guard RecipePhotos.isSendable(byteCounts: jpegs.map(\.count)) else { throw Failure.photosTooLarge }
            message = Self.photoMessage(jpegs, categories: names, language: language)
        case .link(let url):
            message = .user(Self.inputText(recipe: try await pageText(of: url), categories: names, language: language))
            sourceURL = url
        }
        let answer: String
        do {
            let slug = try await model()
            answer = try await RecipeRequest.withTimeout(timeout) { [responder] in
                try await RecipeRequest.collect(responder.respond(model: slug, instructions: Self.instructions, input: [message], tools: [],
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
        return try Self.validate(Data(answer.utf8), categoryNames: names, openItemKeys: openItemKeys, language: language, sourceURL: sourceURL)
    }

    /// A structured recipe note as a result, read on the device.
    static func result(for note: RecipeNote, language: VoiceLanguage, categoryNames: [String], openItemKeys: Set<String>,
                       classifier: (String) -> String?) throws -> Result {
        let other = categoryNames.last ?? ShoppingSorter.otherName
        let known = Set(categoryNames)
        var candidates: [Candidate] = []
        var indexByKey: [String: Int] = [:]
        for raw in note.ingredients {
            let line = IngredientLine.parse(raw)
            let name = String((line.name.isEmpty ? raw : line.name).prefix(ShoppingInputParser.maxNameLength))
            let key = ShoppingName.key(name)
            guard !key.isEmpty else { continue }
            let quantity = Self.quantityText(of: line, locale: language.locale)
            let structured = line.amount == nil ? nil : line
            if let index = indexByKey[key] {
                if candidates[index].quantity == nil {
                    candidates[index].quantity = quantity
                    candidates[index].line = structured
                }
                continue
            }
            let category = classifier(key).flatMap { known.contains($0) ? $0 : nil } ?? other
            indexByKey[key] = candidates.count
            candidates.append(Candidate(name: name, quantity: quantity, line: structured, category: category,
                                        alreadyOnList: openItemKeys.contains(key)))
        }
        guard !candidates.isEmpty else { throw Failure.nothingFound }
        return Result(title: String(note.title.prefix(maxTitleLength)),
                      servings: note.servings.flatMap { servingsRange.contains($0) ? $0 : nil },
                      candidates: Array(candidates.prefix(maxItems)), steps: checked(steps: note.steps), sourceURL: note.sourceURL,
                      language: language, readLocally: true)
    }

    /// "500 g" or "1 Dose (400 ml)"; `nil` for a line without an amount.
    static func quantityText(of line: IngredientLine, locale: Locale) -> String? {
        var text = line.quantityText(locale: locale)
        guard !text.isEmpty else { return nil }
        if let note = line.note { text += " (\(note))" }
        return String(text.prefix(maxQuantityLength))
    }

    private static func checked(steps: [String]) -> [String] {
        Array(steps.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxStepLength)) }
            .filter { !$0.isEmpty }.prefix(maxSteps))
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

    /// The address from the link field: trimmed, and "https://" is put in front of an address typed without a scheme
    /// ("example.com/rezept"). Anything else that does not parse stays as it is and is refused later.
    static func url(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        return URL(string: trimmed.contains(":") ? trimmed : "https://" + trimmed)
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
            var amount: Double?
            var unit: String?
            var category: String
        }
        var title: String?
        var servings: Double?
        var steps: [String]?
        var items: [Entry]
    }

    /// Checks the answer: empty names go, an unknown category becomes "Sonstiges", entries of the same name are merged
    /// (the first quantity wins, a later one fills a gap), an item that is open on the list is marked, and at most
    /// `maxItems` remain. The servings count only between 1 and 50, the steps are cut to 20 of 300 characters. No new
    /// category is ever created. `categoryNames` ends with "Sonstiges".
    static func validate(_ answer: Data, categoryNames: [String], openItemKeys: Set<String>, language: VoiceLanguage = .german,
                         sourceURL: URL? = nil) throws -> Result {
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
            var quantity = entry.quantity.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxQuantityLength)) }
                .flatMap { $0.isEmpty ? nil : $0 }
            var line: IngredientLine?
            if let amount = entry.amount, amount >= 0.01, amount < 100_000,
               let value = Decimal(string: String(amount), locale: Locale(identifier: "en_US_POSIX")) {
                let unit = entry.unit.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(15)) }
                    .flatMap { $0.isEmpty ? nil : $0 }
                let structured = IngredientLine(amount: value, unit: unit, name: name)
                line = structured
                quantity = Self.quantityText(of: structured, locale: language.locale)
            }
            if let index = indexByKey[key] {
                if candidates[index].quantity == nil {
                    candidates[index].quantity = quantity
                    candidates[index].line = line
                }
                continue
            }
            let category = known[entry.category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] ?? other
            indexByKey[key] = candidates.count
            candidates.append(Candidate(name: name, quantity: quantity, line: line, category: category,
                                        alreadyOnList: openItemKeys.contains(key)))
        }
        guard !candidates.isEmpty else { throw Failure.nothingFound }
        let servings = decoded.servings.flatMap { Int(exactly: $0.rounded()) }.flatMap { servingsRange.contains($0) ? $0 : nil }
        let title = String((decoded.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxTitleLength))
        return Result(title: title, servings: servings, candidates: Array(candidates.prefix(maxItems)),
                      steps: checked(steps: decoded.steps ?? []), sourceURL: sourceURL, language: language)
    }

    /// The category name of an ingredient key from the user's own assignments and the bundled dictionary, for reading a
    /// recipe note on the device; `nil` stands for "Sonstiges".
    static func localClassifier(assignments: [String: ShoppingAssignmentInfo], categories: [ShoppingCategoryInfo],
                                dictionary: ShoppingDictionary = .bundled) -> (String) -> String? {
        { key in
            ShoppingClassifier.categoryID(forKey: key, assignments: assignments, categories: categories, dictionary: dictionary)
                .flatMap { id in categories.first { $0.id == id }?.name }
        }
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
        switch RecipeRequest.failure(for: error) {
        case .network: .network
        case .signedOut: .signedOut
        case .usageLimit: .usageLimit
        case .failed: .failed
        }
    }

    // MARK: Prompt

    /// The user message: the recipe text (or a note that the photo is the recipe), and the category names and the language
    /// of the result as JSON.
    static func inputText(recipe: String?, categories: [String], language: VoiceLanguage, photoCount: Int = 1) -> String {
        let object: [String: Any] = ["categories": categories, "language": RecipeLanguage.promptName(language)]
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        let json = String(decoding: data, as: UTF8.self)
        guard let recipe else {
            let lead = photoCount > 1
                ? "The \(photoCount) photos are the pages of one recipe, in reading order. Read all of them together as one recipe."
                : "The photo shows the recipe."
            return "\(lead)\n\nCategories and language as JSON:\n\(json)"
        }
        return "Recipe:\n\(recipe)\n\nCategories and language as JSON:\n\(json)"
    }

    /// The request message for photos: one message with the text and one image per photo, so ChatGPT reads one recipe.
    static func photoMessage(_ jpegs: [Data], categories: [String], language: VoiceLanguage) -> InputItem {
        let text = inputText(recipe: nil, categories: categories, language: language, photoCount: jpegs.count)
        return jpegs.count == 1 ? .userImage(text: text, jpeg: jpegs[0]) : .userImages(text: text, jpegs: jpegs)
    }

    static let instructions = """
    Du liest ein Rezept und gibst es strukturiert zurück: Titel, Portionen, Zutaten und Zubereitungsschritte. Die Eingabe ist \
    der Rezepttext oder ein Foto des Rezepts (mehrere Fotos sind die Seiten eines einzigen Rezepts: lies sie zusammen und gib \
    ein Rezept zurück), dazu JSON mit "categories" (die Kategorien der Einkaufsliste; die letzte steht \
    für alles ohne Kategorie) und "language" (die Sprache des Ergebnisses).
    - Schreibe title, name, unit, quantity und steps in der Sprache aus "language". Übersetze, wenn das Rezept eine andere \
    Sprache hat. Übersetze keine Eigennamen.
    - title ist der Name des Rezepts. servings ist die Portionszahl aus dem Rezept, null wenn keine genannt ist; rate sie nicht.
    - Gib jede Zutat einmal zurück, mit einem kurzen Namen ohne Menge ("Zwiebel", nicht "2 mittelgroße Zwiebeln").
    - Schreibe die Menge als Zahl in amount und die Einheit in unit ("500" und "g", "2" und "Dose"; unit ist null bei Stückzahlen \
    wie 2 Eiern). Ist die Menge ein Bruch, schreibe die Dezimalzahl. Nennt das Rezept keine Zahl, sind amount und unit null; \
    steht dann ein Text wie "nach Geschmack" da, schreibe ihn in quantity, sonst ist quantity null.
    - steps sind die Zubereitungsschritte in Kurzform, höchstens 20. Ohne Schritte im Rezept ist steps leer.
    - Wähle für category genau einen Namen aus der Liste der Eingabe, nimm die letzte Kategorie, wenn keine passt. \
    Erfinde keine Kategorie.
    - Gib keine Zutaten zurück, die nicht im Rezept stehen. Lass Wasser, Salz und Pfeffer nur weg, wenn das Rezept sie nicht \
    ausdrücklich als Zutat nennt, und ignoriere Werbung und Kommentare.
    - Gib höchstens 40 Zutaten zurück.
    """

    static let schema = Data("""
    {
      "type": "object",
      "properties": {
        "title": { "type": ["string", "null"] },
        "servings": { "type": ["integer", "null"] },
        "steps": { "type": "array", "items": { "type": "string" } },
        "items": {
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "name": { "type": "string" },
              "amount": { "type": ["number", "null"] },
              "unit": { "type": ["string", "null"] },
              "quantity": { "type": ["string", "null"] },
              "category": { "type": "string" }
            },
            "required": ["name", "amount", "unit", "quantity", "category"],
            "additionalProperties": false
          }
        }
      },
      "required": ["title", "servings", "steps", "items"],
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
