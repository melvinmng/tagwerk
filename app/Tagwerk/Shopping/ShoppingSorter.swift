import AIKit
import Foundation
import TagwerkCore

/// Asks ChatGPT for a better assignment of open shopping items to categories (phase 5 design §5.5).
///
/// Sends only item names and category names, and only after the user's consent and tap. Without consent
/// nothing happens, not even the model list is loaded. The answer is a proposal: nothing is stored before the
/// user applies it, reminders are never written, and a partial or late answer is never used.
@MainActor
final class ShoppingSorter {
    enum Failure: Error, Equatable {
        case consentMissing, network, signedOut, usageLimit, failed

        var message: String {
            switch self {
            case .consentMissing: String(localized: "Zum Sortieren ist deine Einwilligung nötig.")
            case .network: String(localized: "Keine Verbindung. Das Sortieren braucht Internet.")
            case .signedOut: String(localized: "Die Anmeldung bei ChatGPT ist abgelaufen. Melde dich unter Einstellungen › KI neu an.")
            case .usageLimit: String(localized: "ChatGPT nimmt gerade keine Anfragen an. Versuch es später noch einmal.")
            case .failed: String(localized: "Das Sortieren ist fehlgeschlagen. Versuch es noch einmal.")
            }
        }
    }

    static let maxItems = 60
    static let maxNewCategories = 3

    /// What is sent. `categoryNames` ends with the name of the fixed section "Sonstiges".
    struct Request: Equatable {
        var itemNames: [String]
        var categoryNames: [String]
    }

    struct Change: Equatable, Identifiable {
        var itemName: String
        var fromCategory: String
        var toCategory: String
        var id: String { ShoppingName.key(itemName) }
    }

    /// Only the differences to the current state.
    struct Proposal: Equatable {
        var newCategories: [String]
        var changes: [Change]
    }

    /// Name of the fixed section in the app language; it stands for "no category".
    static var otherName: String { String(localized: "Sonstiges") }

    private let responder: any ResponseStreaming
    private let model: @MainActor () async throws -> String
    private let hasConsent: @MainActor () -> Bool
    private let timeout: Duration

    init(responder: any ResponseStreaming, model: @escaping @MainActor () async throws -> String,
         hasConsent: @escaping @MainActor () -> Bool, timeout: Duration = .seconds(30)) {
        self.responder = responder
        self.model = model
        self.hasConsent = hasConsent
        self.timeout = timeout
    }

    // MARK: Request

    /// Open items without an assignment made by hand (the first 60 in list order) and all category names.
    /// Quantities are not part of the request.
    static func request(sections: [ShoppingSection], assignments: [String: ShoppingAssignmentInfo],
                        categories: [ShoppingCategoryInfo]) -> Request {
        var seen = Set<String>()
        var names: [String] = []
        for item in sections.flatMap(\.items) {
            let key = ShoppingName.key(item.name)
            guard assignments[key]?.isManual != true, seen.insert(key).inserted else { continue }
            names.append(item.name)
        }
        let ordered = categories.sorted { $0.sortIndex != $1.sortIndex ? $0.sortIndex < $1.sortIndex : $0.name < $1.name }
        return Request(itemNames: Array(names.prefix(maxItems)), categoryNames: ordered.map(\.name) + [otherName])
    }

    /// Item key → name of the category it is shown under now.
    static func currentCategories(sections: [ShoppingSection], categories: [ShoppingCategoryInfo]) -> [String: String] {
        var result: [String: String] = [:]
        for section in sections {
            let name = section.categoryID.flatMap { id in categories.first { $0.id == id }?.name } ?? otherName
            for item in section.items { result[ShoppingName.key(item.name)] = name }
        }
        return result
    }

    /// `current` maps an item key to its category name (see `currentCategories`).
    func sort(_ request: Request, current: [String: String]) async throws -> Proposal {
        // The consent check comes before anything that could reach OpenAI, including the model list.
        guard hasConsent() else { throw Failure.consentMissing }
        let answer: String
        do {
            let slug = try await model()
            let input = InputItem.user(Self.inputText(request))
            answer = try await RecipeRequest.withTimeout(timeout) { [responder] in
                try await RecipeRequest.collect(responder.respond(model: slug, instructions: Self.instructions, input: [input],
                                                                  tools: [], jsonSchema: (name: "shopping_sort", schema: Self.schema)))
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
        return try Self.validate(Data(answer.utf8), request: request, current: current)
    }

    // MARK: Follow-up (plan ki-vorschlaege-anpassen, task D4)

    /// A second request about the proposal on the sheet: the same item and category names as the first one, the proposal with
    /// the categories the user picked by hand, what the message is about, and the message. Answered in the format of `sort` and
    /// checked the same way against `request` and `current`, so an unknown item or category never gets in. `pinned` are the ids
    /// (`Change.id`) of the changes the user set; `focus` is the id of the change the message is about. Without the current
    /// consent nothing happens, not even the model list.
    func revise(_ request: Request, current: [String: String], proposal: Proposal, pinned: Set<String>, focus: String?,
                comment: String) async throws -> Proposal {
        guard hasConsent() else { throw Failure.consentMissing }
        let answer: String
        do {
            let slug = try await model()
            let input = InputItem.user(Self.revisionText(request, proposal: proposal, pinned: pinned, focus: focus, comment: comment))
            answer = try await RecipeRequest.withTimeout(timeout) { [responder] in
                try await RecipeRequest.collect(responder.respond(model: slug, instructions: Self.instructions + "\n" + Self.revisionInstructions,
                                                                  input: [input], tools: [],
                                                                  jsonSchema: (name: "shopping_sort", schema: Self.schema)))
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
        return try Self.validate(Data(answer.utf8), request: request, current: current)
    }

    /// The message of a follow-up as JSON: the names of the first request, the proposal, the item the message is about and the
    /// message. Quantities, notes and everything else of the list stay on the device.
    static func revisionText(_ request: Request, proposal: Proposal, pinned: Set<String>, focus: String?, comment: String) -> String {
        let entries: [[String: Any]] = proposal.changes.map { ["item": $0.itemName, "category": $0.toCategory, "fixed_by_user": pinned.contains($0.id)] }
        let about = focus.flatMap { id in proposal.changes.first { $0.id == id }?.itemName }
        let object: [String: Any] = ["items": request.itemNames, "categories": request.categoryNames, "proposal": entries,
                                     "new_categories": proposal.newCategories, "about": about as Any? ?? NSNull(), "message": comment]
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    static let revisionInstructions = """
    Jetzt überarbeitest du einen Vorschlag, den du schon gegeben hast. Die Eingabe enthält zusätzlich "proposal" (die Zuordnungen, die \
    sich ändern würden, mit fixed_by_user), "new_categories" (die vorgeschlagenen neuen Kategorien), "about" (der Artikel, um den es \
    geht, oder null) und "message" (die Nachricht der Person).
    - Gib die vollständige Antwort im selben Format zurück. Ändere nur, was die Nachricht verlangt; wiederhole alle anderen \
    Zuordnungen aus "proposal" unverändert.
    - Zuordnungen mit fixed_by_user true hat die Person selbst gewählt: lass sie unverändert, außer die Nachricht betrifft sie.
    - Betrifft die Nachricht einen einzelnen Artikel ("about"), ändere nur diesen.
    - Verwendest du eine neue Kategorie weiter oder legst du eine an, nenne sie in new_categories.
    """

    // MARK: Validation

    private struct Answer: Decodable {
        struct Assignment: Decodable {
            var item: String
            var category: String
        }
        var assignments: [Assignment]
        var new_categories: [String]
    }

    /// Checks the model's answer: unknown items and categories are dropped, the first entry per item counts,
    /// category names are matched without regard to case, at most three valid new categories are kept, and
    /// only differences to `current` remain.
    static func validate(_ answer: Data, request: Request, current: [String: String]) throws -> Proposal {
        guard let decoded = try? JSONDecoder().decode(Answer.self, from: answer) else { throw Failure.failed }
        let other = request.categoryNames.last ?? otherName
        let existing = Array(request.categoryNames.dropLast())
        func normalized(_ name: String) -> String { name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        // Lowercased name → the name as the app writes it.
        var known = Dictionary((existing + [other]).map { (normalized($0), $0) }, uniquingKeysWith: { first, _ in first })
        var accepted: [String] = []
        for candidate in decoded.new_categories where known[normalized(candidate)] == nil {
            guard accepted.count < maxNewCategories,
                  let name = try? ShoppingCategoryRules.validatedName(candidate, existing: existing + accepted, isNew: true)
            else { continue }
            accepted.append(name)
            known[normalized(name)] = name
        }
        let requested = Dictionary(request.itemNames.map { (ShoppingName.key($0), $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        var changes: [Change] = []
        for assignment in decoded.assignments {
            let key = ShoppingName.key(assignment.item)
            guard let itemName = requested[key], seen.insert(key).inserted,
                  let target = known[normalized(assignment.category)] else { continue }
            let source = current[key] ?? other
            guard normalized(source) != normalized(target) else { continue }
            changes.append(Change(itemName: itemName, fromCategory: source, toCategory: target))
        }
        // A new category nothing is moved into would only be an empty section.
        let used = Set(changes.map(\.toCategory))
        return Proposal(newCategories: accepted.filter(used.contains), changes: changes)
    }

    /// Stores an accepted proposal: new categories at the end, one learned assignment per change. A choice the
    /// user made by hand is kept, and no reminder is written.
    static func apply(_ proposal: Proposal, categories: ShoppingCategoryStore, model: ShoppingModel) {
        for name in proposal.newCategories { _ = try? categories.add(name: name) }
        let all = categories.categories()
        let other = otherName.lowercased()
        for change in proposal.changes {
            let target = change.toCategory.lowercased()
            if target == other {
                categories.assign(nameKey: change.id, to: nil, manual: false)
            } else if let category = all.first(where: { $0.name.lowercased() == target }) {
                categories.assign(nameKey: change.id, to: category.id, manual: false)
            }
        }
        model.refreshSections()
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

    /// The user message: item names and category names as JSON, nothing else.
    static func inputText(_ request: Request) -> String {
        let object = ["items": request.itemNames, "categories": request.categoryNames]
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    static let instructions = """
    Du ordnest Artikel einer Einkaufsliste den Kategorien eines Supermarkts zu. Die Eingabe ist JSON mit "items" \
    (Artikelnamen, Deutsch oder Englisch) und "categories" (vorhandene Kategorien; die letzte steht für alles ohne Kategorie).
    - Ordne nur die genannten Artikel ein und gib jeden Artikelnamen unverändert zurück.
    - Bevorzuge die vorhandenen Kategorien und schreibe ihre Namen genau wie in der Eingabe.
    - Schlage höchstens 3 neue Kategorien vor (new_categories, Name höchstens 30 Zeichen), und nur, wenn mehrere \
    Artikel in keine vorhandene Kategorie passen. Benenne oder lösche keine vorhandene Kategorie.
    - Passt ein Artikel nirgends, nimm die letzte Kategorie der Eingabe.
    - Erfinde keine Artikel.
    """

    static let schema = Data("""
    {
      "type": "object",
      "properties": {
        "assignments": {
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "item": { "type": "string" },
              "category": { "type": "string" }
            },
            "required": ["item", "category"],
            "additionalProperties": false
          }
        },
        "new_categories": { "type": "array", "items": { "type": "string" } }
      },
      "required": ["assignments", "new_categories"],
      "additionalProperties": false
    }
    """.utf8)
}
