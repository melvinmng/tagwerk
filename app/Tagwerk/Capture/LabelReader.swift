import AIKit
import Foundation
import TagwerkCore

/// Reads the nutrition table of a package from a photo with ChatGPT (decision LM3b).
///
/// Follows `MealEstimator`: the same consent (the estimate of meals, because only a photo goes out and no Health values, goals or
/// earlier entries), one request on a tap, a strict answer format, and no partial or late answer. The reading is only a proposal:
/// it fills the edit sheet of a food, and nothing is saved until the user has compared it with the package and confirmed.
@MainActor
final class LabelReader {
    enum Failure: Error, Equatable {
        case consentMissing, network, signedOut, usageLimit, nothingRecognized, failed

        var message: String {
            switch self {
            case .consentMissing: String(localized: "Zum Lesen des Etiketts ist deine Einwilligung nötig.")
            case .network: String(localized: "Keine Verbindung. Das Lesen des Etiketts braucht Internet.")
            case .signedOut: String(localized: "Die Anmeldung bei ChatGPT ist abgelaufen. Melde dich unter Einstellungen › KI neu an.")
            case .usageLimit: String(localized: "ChatGPT nimmt gerade keine Anfragen an. Versuch es später noch einmal oder trag die Werte selbst ein.")
            case .nothingRecognized: String(localized: "Auf dem Foto war keine Nährwerttabelle zu erkennen. Versuch es mit einem schärferen Foto oder trag die Werte selbst ein.")
            case .failed: String(localized: "Das Etikett ließ sich nicht lesen. Versuch es noch einmal oder trag die Werte selbst ein.")
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

    /// Reads the table of the photo. Without consent nothing happens, not even the model list.
    func read(jpeg: Data) async throws -> NutritionLabelReading {
        guard hasConsent() else { throw Failure.consentMissing }
        let answer: String
        do {
            let slug = try await model()
            let limit = timeout
            answer = try await RecipeRequest.withTimeout(limit) { [responder] in
                try await RecipeRequest.collect(responder.respond(model: slug, instructions: Self.instructions,
                                                                  input: [.userImage(text: Self.request, jpeg: jpeg)], tools: [],
                                                                  jsonSchema: (name: "nutrition_label", schema: Self.schema)))
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
        guard let output = try? NutritionLabelOutput.decode(Data(answer.utf8)) else { throw Failure.failed }
        guard let reading = output.normalized() else { throw Failure.nothingRecognized }
        return reading
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

    /// The text that goes with the photo; the instructions carry the rules.
    static let request = "Read the nutrition table on this package."

    static let instructions = """
    Du liest die Nährwerttabelle auf der Verpackung eines Lebensmittels für eine Ernährungs-App. Die Eingabe ist ein Foto.
    - Lies nur ab, was dort steht. Rechne nichts um und schätze nichts. Steht ein Wert nicht in der Tabelle, gib null an; null ist \
    besser als geraten. 0 bedeutet, dass die Tabelle 0 angibt.
    - basis: worauf sich die Werte beziehen. per_100g für „je 100 g“, per_100ml für „je 100 ml“, per_serving, wenn die Tabelle nur \
    Werte je Portion oder je Stück nennt. Nennt sie beides, nimm je 100 g oder je 100 ml.
    - serving_grams: das Gewicht einer Portion oder eines Stücks in Gramm, wenn die Verpackung es nennt, sonst null.
    - kcal: Energie in Kilokalorien. Steht nur Kilojoule da, gib kj an und lass kcal null.
    - protein_g, carbs_g, fat_g, fiber_g, sugar_g, saturated_fat_g in Gramm je Bezugsmenge. salt_g ist Salz, nicht Natrium; steht nur \
    Natrium da, gib null an.
    - product_name: der Produktname, wenn er auf dem Foto lesbar ist, sonst null.
    - Ist keine Nährwerttabelle zu erkennen, setze table_found auf false und alle Werte auf null. Erfinde nichts.
    """

    static let schema = Data("""
    {
      "type": "object",
      "properties": {
        "table_found": { "type": "boolean" },
        "product_name": { "type": ["string", "null"] },
        "basis": { "type": "string", "enum": ["per_100g", "per_100ml", "per_serving"] },
        "serving_grams": { "type": ["number", "null"] },
        "kcal": { "type": ["number", "null"] },
        "kj": { "type": ["number", "null"] },
        "protein_g": { "type": ["number", "null"] },
        "carbs_g": { "type": ["number", "null"] },
        "fat_g": { "type": ["number", "null"] },
        "fiber_g": { "type": ["number", "null"] },
        "sugar_g": { "type": ["number", "null"] },
        "saturated_fat_g": { "type": ["number", "null"] },
        "salt_g": { "type": ["number", "null"] }
      },
      "required": ["table_found", "product_name", "basis", "serving_grams", "kcal", "kj", "protein_g", "carbs_g", "fat_g", "fiber_g",
                   "sugar_g", "saturated_fat_g", "salt_g"],
      "additionalProperties": false
    }
    """.utf8)
}
