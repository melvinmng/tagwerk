import AIKit
import Foundation
import TagwerkCore

/// Asks ChatGPT for a task title, a short summary and a due date for one mail (plan P6, #166).
///
/// Sends the subject, the sender's name (never the address) and the text, cut to `MailTaskSuggestion.maximumInputLength`
/// characters. Attachments, the message ID, the recipients and the link back to the mail are never part of the request.
/// Without consent nothing happens, not even the model list is loaded. Nothing is logged or stored in the chat history.
@MainActor
final class MailSummarizer {
    enum Failure: Error, Equatable {
        case consentMissing, network, signedOut, usageLimit, notRecognized, timeout, failed

        var message: String {
            switch self {
            case .consentMissing: String(localized: "Für die Zusammenfassung ist deine Einwilligung nötig.")
            case .network: String(localized: "Keine Verbindung. Die Zusammenfassung braucht Internet.")
            case .signedOut: String(localized: "Die Anmeldung bei ChatGPT ist abgelaufen. Melde dich unter Einstellungen › KI neu an.")
            case .usageLimit: String(localized: "ChatGPT nimmt gerade keine Anfragen an. Versuch es später noch einmal oder trag die Aufgabe selbst ein.")
            case .notRecognized: String(localized: "Aus dieser Mail ließ sich keine Aufgabe ableiten. Trag die Aufgabe selbst ein.")
            case .timeout: String(localized: "ChatGPT hat zu lange gebraucht. Versuch es noch einmal oder trag die Aufgabe selbst ein.")
            case .failed: String(localized: "Die Zusammenfassung ist fehlgeschlagen. Versuch es noch einmal oder trag die Aufgabe selbst ein.")
            }
        }
    }

    private let responder: any ResponseStreaming
    private let model: @MainActor () async throws -> String
    private let hasConsent: @MainActor () -> Bool
    private let timeout: Duration
    private let language: @MainActor () -> VoiceLanguage
    private let calendar: @MainActor () -> Calendar
    private let now: @MainActor () -> Date

    init(responder: any ResponseStreaming, model: @escaping @MainActor () async throws -> String,
         hasConsent: @escaping @MainActor () -> Bool, timeout: Duration = .seconds(30),
         language: @escaping @MainActor () -> VoiceLanguage = { .app },
         calendar: @escaping @MainActor () -> Calendar = { .tagwerk }, now: @escaping @MainActor () -> Date = { .now }) {
        self.responder = responder
        self.model = model
        self.hasConsent = hasConsent
        self.timeout = timeout
        self.language = language
        self.calendar = calendar
        self.now = now
    }

    /// The text of the one request: subject, sender name and the cut text. Nothing else.
    nonisolated static func input(subject: String, senderName: String?, body: String) -> String {
        let redact = MailTaskSuggestion.redactingAddresses
        var lines = ["Betreff: \(redact(subject))"]
        if let senderName, !senderName.isEmpty { lines.append("Von: \(redact(senderName))") }
        lines.append("Text:")
        // Addresses go before the cut, so the limit counts what is sent.
        lines.append(String(redact(body).prefix(MailTaskSuggestion.maximumInputLength)))
        return lines.joined(separator: "\n")
    }

    func summarize(subject: String, senderName: String?, body: String) async throws -> MailTaskSuggestion.Normalized {
        // The consent check comes before anything that could reach OpenAI, including the model list.
        guard hasConsent() else { throw Failure.consentMissing }
        let answer: String
        do {
            let slug = try await model()
            let instructions = MailTaskSuggestion.instructions(language: language(), today: now(), calendar: calendar())
            let input: InputItem = .user(Self.input(subject: subject, senderName: senderName, body: body))
            answer = try await withTimeout { [responder] in
                try await Self.collect(responder.respond(model: slug, instructions: instructions, input: [input], tools: [],
                                                         jsonSchema: (name: "mail_task", schema: MailTaskSuggestion.schema)))
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
        guard let suggestion = try? MailTaskSuggestion.decode(Data(answer.utf8)),
              let normalized = suggestion.normalized(now: now(), calendar: calendar()) else { throw Failure.notRecognized }
        return normalized
    }

    // MARK: Follow-up (plan ki-vorschlaege-anpassen, task E1)

    /// A second request about the proposal on the sheet: the same subject, sender name and text as the first one (cut and
    /// without addresses), the task as it is now with the fields the user set by hand, and the message. Answered in the format
    /// of `summarize` and checked the same way. The address of the sender is never sent, and addresses in what the user typed
    /// or wrote are replaced like those in the mail. Without consent nothing happens, not even the model list.
    func revise(subject: String, senderName: String?, body: String, current: MailTaskSuggestion.Normalized, fixed: [String],
                comment: String) async throws -> MailTaskSuggestion.Normalized {
        guard hasConsent() else { throw Failure.consentMissing }
        let answer: String
        do {
            let slug = try await model()
            let instructions = MailTaskSuggestion.instructions(language: language(), today: now(), calendar: calendar()) + "\n" + Self.revisionInstructions
            let input: InputItem = .user(Self.input(subject: subject, senderName: senderName, body: body)
                                         + Self.followUpText(current: current, fixed: fixed, comment: comment, calendar: calendar()))
            answer = try await withTimeout { [responder] in
                try await Self.collect(responder.respond(model: slug, instructions: instructions, input: [input], tools: [],
                                                         jsonSchema: (name: "mail_task", schema: MailTaskSuggestion.schema)))
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
        guard let suggestion = try? MailTaskSuggestion.decode(Data(answer.utf8)),
              let normalized = suggestion.normalized(now: now(), calendar: calendar()) else { throw Failure.notRecognized }
        return normalized
    }

    /// What follows the mail in a follow-up: the current task as JSON, the fields the user set, and the message.
    nonisolated static func followUpText(current: MailTaskSuggestion.Normalized, fixed: [String], comment: String, calendar: Calendar) -> String {
        let redact = MailTaskSuggestion.redactingAddresses
        var due: Any = NSNull()
        if let value = current.due {
            let day = String(format: "%04d-%02d-%02d", value.year, value.month, value.day)
            due = value.hour.map { day + String(format: "T%02d:%02d", $0, value.minute ?? 0) } ?? day
        }
        let object: [String: Any] = ["title": redact(current.title), "summary": redact(current.summary), "due": due]
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return """


        Current task as JSON: \(String(decoding: data, as: UTF8.self))
        Fields the user set by hand: \(fixed.isEmpty ? "none" : fixed.joined(separator: ", "))
        Message from the user: \(redact(comment))
        """
    }

    static let revisionInstructions = """
    Jetzt überarbeitest du den Vorschlag, den du schon gegeben hast. Die Eingabe enthält die Mail wie zuvor, dazu die aktuelle Aufgabe \
    als JSON, die Felder, die die Person selbst eingestellt hat, und ihre Nachricht.
    - Gib die vollständige Aufgabe im selben Format zurück (title, summary, due). Ändere nur, was die Nachricht verlangt; die anderen \
    Felder gibst du unverändert zurück.
    - Felder, die die Person selbst eingestellt hat, lässt du unverändert, außer die Nachricht betrifft sie.
    """

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
        do {
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
        } catch is TimedOut {
            throw Failure.timeout
        }
    }
}
