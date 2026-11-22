import AIKit
import Foundation
import TagwerkCore

/// Asks ChatGPT to translate the names of the open shopping items into the language of the list ("Artikel übersetzen").
///
/// Follows `ShoppingSorter` and the recipe translation: nothing is sent without the user's consent and tap (not even the model
/// list), the answer is a proposal that is checked before anyone sees it, and a partial or late answer is never used. What goes
/// to ChatGPT is the name of each open item once and the name of the target language; quantities, notes, categories, completed
/// items and reminder identifiers stay on the device. Nothing is written here.
@MainActor
final class ShoppingTranslator {
    enum Failure: Error, Equatable {
        case consentMissing, network, signedOut, usageLimit, failed
        /// The answer does not belong to the request (missing, extra or repeated index).
        case mismatch

        /// A German text for the notice line; it never contains item names.
        var message: String {
            switch self {
            case .consentMissing: String(localized: "Zum Übersetzen ist deine Einwilligung nötig.")
            case .network: String(localized: "Keine Verbindung. Das Übersetzen braucht Internet.")
            case .signedOut: String(localized: "Die Anmeldung bei ChatGPT ist abgelaufen. Melde dich unter Einstellungen › KI neu an.")
            case .usageLimit: String(localized: "ChatGPT nimmt gerade keine Anfragen an. Versuch es später noch einmal.")
            case .failed: String(localized: "Das Übersetzen ist fehlgeschlagen. Versuch es noch einmal.")
            case .mismatch: String(localized: "Die Übersetzung passt nicht zur Liste. Versuch es noch einmal.")
            }
        }
    }

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

    /// One request for all names of `plan`. The consent check comes first, before the model list is loaded. Returns only the
    /// checked changes; a plan without names sends nothing.
    func translate(_ plan: ShoppingTranslationPlan, to language: VoiceLanguage) async throws -> [ShoppingTranslationPlan.Change] {
        guard hasConsent() else { throw Failure.consentMissing }
        guard !plan.entries.isEmpty else { return [] }
        let answer: String
        do {
            let slug = try await model()
            let input = InputItem.user(Self.inputText(plan, language: language))
            answer = try await RecipeRequest.withTimeout(timeout) { [responder] in
                try await RecipeRequest.collect(responder.respond(model: slug, instructions: Self.instructions, input: [input], tools: [],
                                                                  jsonSchema: (name: "shopping_translation", schema: Self.schema)))
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ChatGPTError {
            // A cancelled request can end its stream first; that is a cancellation, not a failure.
            if Task.isCancelled { throw CancellationError() }
            throw Self.failure(for: error)
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw Failure.failed
        }
        guard let decoded = try? JSONDecoder().decode(Answer.self, from: Data(answer.utf8)) else { throw Failure.failed }
        do {
            return try plan.changes(translations: decoded.items.map { (index: $0.i, text: $0.text) })
        } catch {
            throw Failure.mismatch
        }
    }

    /// A second request about the proposal on the sheet (plan ki-vorschlaege-anpassen, task D5): the same names as the first
    /// request, the names as they are now with the ones the user typed, what the message is about, and the message. Answered in
    /// the format of `translate` and checked by the same plan, so quantities stay and every index is answered once. `pinned` are
    /// item ids of the rows the user set, `focus` is the item id of the row the message is about. Without the consent of the sort
    /// feature nothing happens, not even the model list.
    func revise(_ plan: ShoppingTranslationPlan, to language: VoiceLanguage, current: [ShoppingTranslationPlan.Change], pinned: Set<String>,
                focus: String?, comment: String) async throws -> [ShoppingTranslationPlan.Change] {
        guard hasConsent() else { throw Failure.consentMissing }
        guard !plan.entries.isEmpty else { return [] }
        let answer: String
        do {
            let slug = try await model()
            let input = InputItem.user(Self.revisionText(plan, language: language, current: current, pinned: pinned, focus: focus, comment: comment))
            answer = try await RecipeRequest.withTimeout(timeout) { [responder] in
                try await RecipeRequest.collect(responder.respond(model: slug, instructions: Self.instructions + "\n" + Self.revisionInstructions,
                                                                  input: [input], tools: [],
                                                                  jsonSchema: (name: "shopping_translation", schema: Self.schema)))
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ChatGPTError {
            if Task.isCancelled { throw CancellationError() }
            throw Self.failure(for: error)
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw Failure.failed
        }
        guard let decoded = try? JSONDecoder().decode(Answer.self, from: Data(answer.utf8)) else { throw Failure.failed }
        do {
            return try plan.changes(translations: decoded.items.map { (index: $0.i, text: $0.text) })
        } catch {
            throw Failure.mismatch
        }
    }

    /// The message of a follow-up as JSON: the target, the names of the first request, the names as they are now (an item
    /// without a change keeps its name), which of them the user set, the index the message is about, and the message.
    static func revisionText(_ plan: ShoppingTranslationPlan, language: VoiceLanguage, current: [ShoppingTranslationPlan.Change],
                             pinned: Set<String>, focus: String?, comment: String) -> String {
        var now: [[String: Any]] = []
        var about: Any = NSNull()
        for entry in plan.entries {
            let change = current.first { entry.itemIDs.contains($0.itemID) }
            now.append(["i": entry.index, "text": change?.newName ?? entry.name,
                        "fixed_by_user": entry.itemIDs.contains { pinned.contains($0) }])
            if let focus, entry.itemIDs.contains(focus) { about = entry.index }
        }
        let object: [String: Any] = ["target": RecipeLanguage.promptName(language),
                                     "items": plan.request.map { ["i": $0.index, "text": $0.text] as [String: Any] },
                                     "current": now, "about": about, "message": comment]
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    static let revisionInstructions = """
    The user now writes about your translation. The input also holds "current" (the names as they are now, each with fixed_by_user), \
    "about" (the index the message is about, or null) and "message" (the message of the user).
    - Return all indices of "items" again, each once, in the same format. Change only what the message asks for; return every other \
    name exactly as it is in "current".
    - A name with fixed_by_user true was typed by the user: return it unchanged unless the message is about it.
    - If "about" is set, change only that item.
    """

    private struct Answer: Decodable {
        struct Entry: Decodable {
            var i: Int
            var text: String
        }
        var items: [Entry]
    }

    private static func failure(for error: ChatGPTError) -> Failure {
        switch RecipeRequest.failure(for: error) {
        case .network: .network
        case .signedOut: .signedOut
        case .usageLimit: .usageLimit
        case .failed: .failed
        }
    }

    // MARK: Prompt

    /// The user message: the target language and the names with their indices as JSON, nothing else.
    static func inputText(_ plan: ShoppingTranslationPlan, language: VoiceLanguage) -> String {
        let object: [String: Any] = ["target": RecipeLanguage.promptName(language),
                                     "items": plan.request.map { ["i": $0.index, "text": $0.text] as [String: Any] }]
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    static let instructions = """
    You translate the names of items on a shopping list. The input is JSON with "target" (the language to translate into) and \
    "items" (each with an index "i" and a name "text").
    - Translate every item on its own and return it with the same index. Return every index exactly once.
    - If a name is already in the target language, or it is a brand name or a proper name, return it unchanged.
    - Keep numbers exactly as they are. Add nothing: no amount, no explanation, no extra words.
    - Keep the singular or plural of the name and the capitalisation of its first letter.
    - Use the short name that shops use, not a literal translation.
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
              "i": { "type": "integer" },
              "text": { "type": "string" }
            },
            "required": ["i", "text"],
            "additionalProperties": false
          }
        }
      },
      "required": ["items"],
      "additionalProperties": false
    }
    """.utf8)
}
