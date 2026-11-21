import AIKit
import Foundation
import TagwerkCore

/// Asks ChatGPT to revise the arguments of one open action card (plan ki-vorschlaege-anpassen, task B4, AN4a).
///
/// One short request about this card only: the name of the function, the current arguments, the fields the user set by
/// hand and the message. It sends no chat history, no other card and no note text, and it needs a sign-in; the caller
/// checks the consent of the context (notes chats). Nothing is stored and nothing is executed: the answer fills the fields
/// of the sheet, and the card changes only with "Fertig".
///
/// The answer has the schema of the function plus a sentence and a flag. Values that identify something (ids, repository,
/// projects, people, calendar) are never taken from the answer: ChatGPT cannot look them up here, so it must not invent them.
@MainActor
final class CardReviser {
    enum Failure: Error, Equatable {
        case consentMissing, unknownFunction, network, signedOut, usageLimit, invalidAnswer, failed

        var message: String {
            switch self {
            case .consentMissing: String(localized: "Für diese Rückfrage ist deine Einwilligung nötig.")
            case .unknownFunction: String(localized: "Zu diesem Vorschlag gibt es keine Rückfrage.")
            case .network: String(localized: "Keine Verbindung. Ändern von Hand geht weiter.")
            case .signedOut: String(localized: "Die Anmeldung bei ChatGPT ist abgelaufen. Melde dich unter Einstellungen › KI neu an.")
            case .usageLimit: String(localized: "ChatGPT nimmt gerade keine Anfragen an. Versuch es später noch einmal.")
            case .invalidAnswer: String(localized: "Die Antwort passte nicht zum Vorschlag. Es wurde nichts geändert.")
            case .failed: String(localized: "Die Rückfrage ist fehlgeschlagen. Versuch es noch einmal.")
            }
        }
    }

    /// What ChatGPT answered: the arguments after the revision (identifiers restored), one sentence, and whether it changed something.
    struct Answer: Equatable {
        var arguments: Data
        var message: String
        var changed: Bool
    }

    /// Arguments that identify something outside the card; an answer cannot change them. The people of a hand-over
    /// (`add`, `remove` of `assign_task`) and the items a shopping card checks off count as identifiers; the items it adds do not.
    static func lockedKeys(for name: String) -> Set<String> {
        var keys: Set<String> = ["id", "event_id", "task_id", "calendar_id", "repository", "project_ids", "assignees"]
        if name == "assign_task" { keys.formUnion(["add", "remove"]) }
        if name == "update_shopping" { keys.insert("check_off") }
        return keys
    }

    private let responder: any ResponseStreaming
    private let model: @MainActor () async throws -> String
    private let hasConsent: @MainActor () -> Bool
    private let definitions: @MainActor () -> [ToolDefinition]
    private let language: @MainActor () -> VoiceLanguage
    private let now: () -> Date
    private let calendar: Calendar
    private let timeout: Duration

    init(responder: any ResponseStreaming, model: @escaping @MainActor () async throws -> String,
         hasConsent: @escaping @MainActor () -> Bool,
         definitions: @escaping @MainActor () -> [ToolDefinition] = { AppTools.allDefinitions + AppTools.gitHubDefinitions },
         language: @escaping @MainActor () -> VoiceLanguage = { .app }, now: @escaping () -> Date = Date.init,
         calendar: Calendar = .tagwerk, timeout: Duration = .seconds(30)) {
        self.responder = responder
        self.model = model
        self.hasConsent = hasConsent
        self.definitions = definitions
        self.language = language
        self.now = now
        self.calendar = calendar
        self.timeout = timeout
    }

    /// `current`: the arguments as the sheet shows them now. `proposed`: what the model proposed (`nil` for a card the user
    /// did not change); the fields that differ are the ones the user set by hand.
    func revise(name: String, current: Data, proposed: Data?, comment: String) async throws -> Answer {
        // The consent check comes before anything that could reach OpenAI, including the model list.
        guard hasConsent() else { throw Failure.consentMissing }
        guard let definition = definitions().first(where: { $0.name == name }),
              let currentObject = ProposalArguments.decode(current),
              let properties = Self.propertyNames(of: definition) else { throw Failure.unknownFunction }
        let pinned = Self.pinnedKeys(current: currentObject, proposed: proposed.flatMap(ProposalArguments.decode))
        let schema = Self.schema(for: definition)
        let answer: String
        do {
            let slug = try await model()
            let input = InputItem.user(Self.message(name: name, current: current, pinned: pinned, comment: comment))
            let instructions = Self.instructions(language: language(), today: Self.todayText(now(), calendar: calendar))
            answer = try await RecipeRequest.withTimeout(timeout) { [responder] in
                try await RecipeRequest.collect(responder.respond(model: slug, instructions: instructions, input: [input], tools: [],
                                                                  jsonSchema: (name: "card_revision", schema: schema)))
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as Failure {
            throw error
        } catch let error as ChatGPTError {
            switch RecipeRequest.failure(for: error) {
            case .network: throw Failure.network
            case .signedOut: throw Failure.signedOut
            case .usageLimit: throw Failure.usageLimit
            case .failed: throw Failure.failed
            }
        } catch {
            throw Failure.failed
        }
        return try Self.parse(answer, name: name, current: currentObject, properties: properties)
    }

    // MARK: Answer

    /// Checks the answer against the schema of the function and restores the identifiers. An answer that does not fit changes nothing.
    static func parse(_ text: String, name: String, current: [String: Any], properties: Set<String>) throws -> Answer {
        guard let object = ProposalArguments.decode(Data(text.utf8)),
              let arguments = object["arguments"] as? [String: Any],
              let message = object["message"] as? String,
              let changed = object["changed"] as? Bool,
              Set(arguments.keys) == properties else { throw Failure.invalidAnswer }
        var result = arguments
        for key in lockedKeys(for: name) where properties.contains(key) { result[key] = current[key] ?? NSNull() }
        let sentence = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard changed else { return Answer(arguments: ProposalArguments.encode(current), message: sentence, changed: false) }
        return Answer(arguments: ProposalArguments.encode(result), message: sentence, changed: true)
    }

    // MARK: Request

    /// The fields the user set by hand: those whose value differs from what the model proposed.
    static func pinnedKeys(current: [String: Any], proposed: [String: Any]?) -> [String] {
        guard let proposed else { return [] }
        return current.keys.filter { key in
            !NSDictionary(dictionary: [key: current[key] ?? NSNull()]).isEqual(to: [key: proposed[key] ?? NSNull()])
        }.sorted()
    }

    /// The message about one card; no chat history and no other card.
    static func message(name: String, current: Data, pinned: [String], comment: String) -> String {
        let pinnedText = pinned.isEmpty ? "none" : pinned.joined(separator: ", ")
        return """
        Function: \(name)
        Current arguments (JSON): \(String(decoding: current, as: UTF8.self))
        Fields set by the user by hand: \(pinnedText)
        Message from the user: \(comment)
        """
    }

    static func instructions(language: VoiceLanguage, today: String) -> String {
        """
        You adjust one pending proposal of a task and calendar app. You get the name of a function, its current arguments, \
        the fields the user set by hand and a message from the user. Return the complete arguments object for the same function.
        - Change only the values the message asks for. Keep every other value exactly as it is, including null.
        - Fields the user set by hand may only change when the message is about them.
        - Never invent identifiers (ids, repositories, projects, logins, calendar ids, item ids); keep them as they are.
        - You cannot look anything up. If the message needs something you cannot know without looking it up (another calendar, \
        another task, a phone number), return the arguments unchanged, set changed to false and say so in one short sentence.
        - Otherwise set changed to true and describe what you changed in one short sentence.
        - Write message in the language of the user's message; if unsure, in \(language.promptName).
        - Today is \(today).
        """
    }

    private static func todayText(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
        let weekday = calendar.weekdaySymbols[(calendar.component(.weekday, from: date) - 1) % 7]
        return "\(day), a \(weekday)"
    }

    /// `{ arguments: <schema of the function>, message, changed }`, strict like every schema of the app.
    static func schema(for definition: ToolDefinition) -> Data {
        let arguments = (try? JSONSerialization.jsonObject(with: definition.parameters)) ?? [String: Any]()
        let object: [String: Any] = [
            "type": "object", "additionalProperties": false, "required": ["arguments", "changed", "message"],
            "properties": ["arguments": arguments, "message": ["type": "string"], "changed": ["type": "boolean"]],
        ]
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
    }

    static func propertyNames(of definition: ToolDefinition) -> Set<String>? {
        guard let object = ProposalArguments.decode(definition.parameters), let properties = object["properties"] as? [String: Any] else { return nil }
        return Set(properties.keys)
    }

    /// Quick replies below the field of the sheet, in the words of the function.
    static func quickReplies(for name: String) -> [String] {
        switch name {
        case "create_task", "update_task", "reschedule_task", "assign_to_day":
            [String(localized: "Später"), String(localized: "Früher"), String(localized: "Kürzer")]
        case "create_event", "update_event", "create_time_block":
            [String(localized: "Später"), String(localized: "Anderer Tag"), String(localized: "Kürzer")]
        case "set_day_hours", "set_lunch", "plan_period":
            [String(localized: "Später"), String(localized: "Früher"), String(localized: "Anderer Tag")]
        case "update_shopping":
            [String(localized: "Ohne Mengen"), String(localized: "Mengen verdoppeln")]
        case "assign_task":
            [String(localized: "Nur mich"), String(localized: "Niemanden entfernen")]
        case "add_comment":
            [String(localized: "Kürzer"), String(localized: "Freundlicher")]
        default:
            []
        }
    }
}
