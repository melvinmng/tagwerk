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
            case .consentMissing: "Für Schätzungen ist deine Einwilligung nötig."
            case .network: "Keine Verbindung. Die Schätzung braucht Internet."
            case .signedOut: "Die Anmeldung bei ChatGPT ist abgelaufen. Melde dich unter Einstellungen › KI neu an."
            case .usageLimit: "ChatGPT nimmt gerade keine Anfragen an. Versuch es später noch einmal oder trag die Werte selbst ein."
            case .nothingRecognized: "Darin war kein Essen zu erkennen. Beschreib die Mahlzeit genauer oder trag die Werte selbst ein."
            case .failed: "Die Schätzung ist fehlgeschlagen. Versuch es noch einmal oder trag die Werte selbst ein."
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

    func estimate(text: String, jpeg: Data?) async throws -> NormalizedMealEstimate {
        // The consent check comes before anything that could reach OpenAI, including the model list.
        guard hasConsent() else { throw Failure.consentMissing }
        let answer: String
        do {
            let slug = try await model()
            let input: InputItem = jpeg.map { .userImage(text: text, jpeg: $0) } ?? .user(text)
            answer = try await withTimeout { [responder] in
                try await Self.collect(responder.respond(model: slug, instructions: Self.instructions, input: [input],
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

    static let instructions = """
    Du schätzt Kalorien und Makronährstoffe einer Mahlzeit für eine Ernährungs-App. Die Eingabe ist eine kurze \
    deutsche Beschreibung und/oder ein Foto der Mahlzeit.
    - Zerlege die Mahlzeit in ihre Bestandteile (Posten) mit einer üblichen Mengenangabe auf Deutsch, z. B. „2 Stück“, \
    „1 Teller (300 g)“.
    - Gib je Posten kcal als wahrscheinlichsten Wert sowie eine ehrliche Spanne (kcal_min, kcal_max) und Eiweiß, \
    Kohlenhydrate und Fett in Gramm an. Die Spanne soll die typische Unsicherheit einer Schätzung abbilden.
    - Mengenangaben in der Beschreibung haben Vorrang vor dem Foto.
    - title: kurzer deutscher Name der Mahlzeit (höchstens 40 Zeichen).
    - Ist kein Essen oder Getränk zu erkennen, gib eine leere Liste items zurück. Erfinde nichts.
    """

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
              "fat_g": { "type": "number" }
            },
            "required": ["name", "amount", "kcal_min", "kcal", "kcal_max", "protein_g", "carbs_g", "fat_g"],
            "additionalProperties": false
          }
        }
      },
      "required": ["title", "items"],
      "additionalProperties": false
    }
    """.utf8)
}
