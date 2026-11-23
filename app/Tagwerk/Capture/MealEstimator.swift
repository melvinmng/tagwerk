import AIKit
import Foundation
import TagwerkCore

/// Estimates a meal with ChatGPT (phase 3 design §6).
///
/// Sends only the meal text and, if given, the photo; never Health values, goals or history. Without consent
/// nothing happens, not even the model list is loaded. A partial or late answer is never used.
@MainActor
final class MealEstimator {
    enum Failure: Error, Equatable {
        case consentMissing, network, signedOut, usageLimit, nothingRecognized, failed

        var message: String {
            switch self {
            case .consentMissing: String(localized: "Für Schätzungen ist deine Einwilligung nötig.")
            case .network: String(localized: "Keine Verbindung. Die Schätzung braucht Internet.")
            case .signedOut: String(localized: "Die Anmeldung bei ChatGPT ist abgelaufen. Melde dich unter Einstellungen › KI neu an.")
            case .usageLimit: String(localized: "ChatGPT nimmt gerade keine Anfragen an. Versuch es später noch einmal oder trag die Werte selbst ein.")
            case .nothingRecognized: String(localized: "Darin war kein Essen zu erkennen. Beschreib die Mahlzeit genauer oder trag die Werte selbst ein.")
            case .failed: String(localized: "Die Schätzung ist fehlgeschlagen. Versuch es noch einmal oder trag die Werte selbst ein.")
            }
        }
    }

    private let responder: any ResponseStreaming
    private let model: @MainActor () async throws -> String
    private let hasConsent: @MainActor () -> Bool
    private let timeout: Duration
    /// The language of the meal title and amounts; both are shown and stored (plan english-app, decision 8).
    private let language: @MainActor () -> VoiceLanguage

    init(responder: any ResponseStreaming, model: @escaping @MainActor () async throws -> String,
         hasConsent: @escaping @MainActor () -> Bool, timeout: Duration = .seconds(30),
         language: @escaping @MainActor () -> VoiceLanguage = { .app }) {
        self.responder = responder
        self.model = model
        self.hasConsent = hasConsent
        self.timeout = timeout
        self.language = language
    }

    func estimate(text: String, jpeg: Data?) async throws -> NormalizedMealEstimate {
        // The consent check comes before anything that could reach OpenAI, including the model list.
        guard hasConsent() else { throw Failure.consentMissing }
        let answer: String
        do {
            let slug = try await model()
            let instructions = Self.instructions(language: language())
            let input: InputItem = jpeg.map { .userImage(text: text, jpeg: $0) } ?? .user(text)
            answer = try await withTimeout { [responder] in
                try await Self.collect(responder.respond(model: slug, instructions: instructions, input: [input],
                                                         tools: [], jsonSchema: (name: "meal_estimate", schema: Self.schema)))
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
        guard let output = try? MealEstimateOutput.decode(Data(answer.utf8)) else { throw Failure.failed }
        guard let estimate = output.normalized() else { throw Failure.nothingRecognized }
        return estimate
    }

    // MARK: Follow-up (plan ki-vorschlaege-anpassen, task D1)

    /// A second request about the estimate on the sheet: the description and the photo the sheet still holds (AN7b), the items
    /// as they are now with the ones the user set by hand, and the message. Answered in the format of `estimate`, so it runs
    /// through the same checks. Never sent: Health values, goals, history and other meals; a meal that was saved earlier counts
    /// as the current meal, so its items go out and no description. Without consent nothing happens, not even the model list.
    func revise(text: String, jpeg: Data?, items: [MealItem], pinned: Set<UUID>, focus: UUID?, comment: String) async throws -> NormalizedMealEstimate {
        guard hasConsent() else { throw Failure.consentMissing }
        let answer: String
        do {
            let slug = try await model()
            let instructions = Self.instructions(language: language()) + "\n" + Self.revisionInstructions
            let message = Self.followUpMessage(text: text, items: items, pinned: pinned, focus: focus, comment: comment)
            let input: InputItem = jpeg.map { .userImage(text: message, jpeg: $0) } ?? .user(message)
            answer = try await withTimeout { [responder] in
                try await Self.collect(responder.respond(model: slug, instructions: instructions, input: [input],
                                                         tools: [], jsonSchema: (name: "meal_estimate", schema: Self.schema)))
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
        guard let output = try? MealEstimateOutput.decode(Data(answer.utf8)) else { throw Failure.failed }
        guard let estimate = output.normalized() else { throw Failure.nothingRecognized }
        return estimate
    }

    /// The message of a follow-up: the description, the items (per portion, with the quantity factor of the stepper and a flag
    /// for the ones the user changed), what the message is about, and the message.
    static func followUpMessage(text: String, items: [MealItem], pinned: Set<UUID>, focus: UUID?, comment: String) -> String {
        let entries: [[String: Any]] = items.map { item in
            ["name": item.name, "amount": item.amount, "kcal_min": item.kcalMin, "kcal": item.kcal, "kcal_max": item.kcalMax,
             "protein_g": item.protein, "carbs_g": item.carbs, "fat_g": item.fat,
             // The further nutrients go along (null while unknown), so a revision returns them unchanged instead of losing them.
             "fiber_g": item.fiber ?? NSNull(), "sugar_g": item.sugar ?? NSNull(),
             "saturated_fat_g": item.saturatedFat ?? NSNull(), "salt_g": item.salt ?? NSNull(),
             "quantity_factor": item.factor, "fixed_by_user": pinned.contains(item.id)]
        }
        let json = (try? JSONSerialization.data(withJSONObject: entries, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? "[]"
        let description = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let about = focus.flatMap { id in items.first { $0.id == id }?.name } ?? "all items"
        return """
        Meal description: \(description.isEmpty ? "(none)" : description)
        Current estimate as JSON: \(json)
        The message is about: \(about)
        Message from the user: \(comment)
        """
    }

    static let revisionInstructions = """
    Jetzt überarbeitest du eine Schätzung, die du schon gegeben hast. Die Eingabe enthält die Beschreibung (und ggf. das Foto), \
    die aktuelle Schätzung als JSON ("quantity_factor" ist der Mengenfaktor des Nutzers; die Werte sind je Portion) und eine Nachricht.
    - Gib die vollständige Schätzung im selben Format zurück. Ändere nur, was die Nachricht verlangt; gib alle anderen Posten \
    unverändert zurück, mit denselben Namen und Werten.
    - Posten mit fixed_by_user true hat die Person selbst eingestellt: lass sie unverändert, außer die Nachricht betrifft sie.
    - Betrifft die Nachricht einen einzelnen Posten ("The message is about"), ändere nur diesen.
    """

    /// The answer of a follow-up put onto the items of the sheet: an item the answer names like an item on the sheet is that item
    /// (it keeps its identity and the quantity factor; it is the very same item when nothing about it changed), every other
    /// answer item is new. With a `focus` that has no namesake, a single unmatched answer item stands for it (the message
    /// renamed it).
    static func align(_ answer: [MealItem], with current: [MealItem], focus: UUID? = nil) -> [MealItem] {
        func key(_ name: String) -> String { name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        var unused = current
        var matches: [UUID?] = answer.map { item in
            guard let index = unused.firstIndex(where: { key($0.name) == key(item.name) }) else { return nil }
            return unused.remove(at: index).id
        }
        if let focus, let target = unused.first(where: { $0.id == focus }) {
            let open = matches.indices.filter { matches[$0] == nil }
            if open.count == 1 { matches[open[0]] = target.id }
        }
        return zip(answer, matches).map { item, id in
            guard let id, let old = current.first(where: { $0.id == id }) else { return item }
            func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.5 }
            if old.name == item.name, old.amount == item.amount, close(old.kcal, item.kcal), close(old.kcalMin, item.kcalMin),
               close(old.kcalMax, item.kcalMax), close(old.protein, item.protein), close(old.carbs, item.carbs), close(old.fat, item.fat) {
                return old
            }
            var merged = item
            merged.id = old.id
            merged.factor = old.factor
            return merged
        }
    }

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

    static func instructions(language: VoiceLanguage) -> String {
        """
        Du schätzt Kalorien und Makronährstoffe einer Mahlzeit für eine Ernährungs-App. Die Eingabe ist eine kurze \
        Beschreibung (Deutsch oder Englisch) und/oder ein Foto der Mahlzeit.
        - Zerlege die Mahlzeit in ihre Bestandteile (Posten) mit einer üblichen Mengenangabe auf \(language.promptName), z. B. \(language == .german ? "„2 Stück“, „1 Teller (300 g)“" : "„2 pieces“, „1 plate (300 g)“").
        - Gib je Posten kcal als wahrscheinlichsten Wert sowie eine ehrliche Spanne (kcal_min, kcal_max) und Eiweiß, \
        Kohlenhydrate und Fett in Gramm an. Die Spanne soll die typische Unsicherheit einer Schätzung abbilden.
        - Gib außerdem Ballaststoffe (fiber_g), Zucker (sugar_g), gesättigte Fettsäuren (saturated_fat_g) und Salz (salt_g, nicht \
        Natrium) in Gramm an. Weißt du einen dieser Werte nicht ausreichend sicher, gib null an; null ist besser als geraten. 0 \
        bedeutet, dass der Posten den Stoff nicht enthält.
        - Mengenangaben in der Beschreibung haben Vorrang vor dem Foto.
        - title: kurzer \(language.promptAdjective) Name der Mahlzeit (höchstens 40 Zeichen).
        - Ist kein Essen oder Getränk zu erkennen, gib eine leere Liste items zurück. Erfinde nichts.
        """
    }

    static let schema = Data("""
    {
      "type": "object",
      "properties": {
        "title": { "type": "string" },
        "items": {
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "name": { "type": "string" },
              "amount": { "type": "string" },
              "kcal_min": { "type": "number" },
              "kcal": { "type": "number" },
              "kcal_max": { "type": "number" },
              "protein_g": { "type": "number" },
              "carbs_g": { "type": "number" },
              "fat_g": { "type": "number" },
              "fiber_g": { "type": ["number", "null"] },
              "sugar_g": { "type": ["number", "null"] },
              "saturated_fat_g": { "type": ["number", "null"] },
              "salt_g": { "type": ["number", "null"] }
            },
            "required": ["name", "amount", "kcal_min", "kcal", "kcal_max", "protein_g", "carbs_g", "fat_g", "fiber_g", "sugar_g",
                         "saturated_fat_g", "salt_g"],
            "additionalProperties": false
          }
        }
      },
      "required": ["title", "items"],
      "additionalProperties": false
    }
    """.utf8)
}
