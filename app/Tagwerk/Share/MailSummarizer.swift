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
        var lines = ["Betreff: \(subject)"]
        if let senderName, !senderName.isEmpty { lines.append("Von: \(senderName)") }
        lines.append("Text:")
        lines.append(String(body.prefix(MailTaskSuggestion.maximumInputLength)))
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
