import AIKit
import Foundation
import TagwerkCore

/// Translates a recipe note with one request to ChatGPT. The note is cut into lines by `RecipeTranslationPlan`: headings,
/// labels, blank lines, attachment references and addresses stay on the device, only the translatable part of each other
/// line is sent. The answer is a proposal that is checked line by line before anyone sees it; a partial, late or deviating
/// answer is never used.
///
/// Follows `RecipeImporter`: nothing is sent without the user's consent and tap. The caller makes sure the note is not
/// private. Attachments (the files) are never sent; the note text, the reference names included, is.
@MainActor
final class RecipeTranslator {
    enum Failure: Error, Equatable {
        case consentMissing, network, signedOut, usageLimit, failed
        /// More lines or characters than `RecipeTranslationPlan` allows.
        case tooLong
        /// The note has no section "Zutaten".
        case notARecipe
        /// The answer does not fit the note (lines, attachments, links, amounts or structure).
        case mismatch

        /// Texts for the user; none of them holds a part of the note.
        var message: String {
            switch self {
            case .consentMissing: String(localized: "Zum Übersetzen ist deine Einwilligung nötig.")
            case .network: String(localized: "Keine Verbindung. Das Übersetzen braucht Internet.")
            case .signedOut: String(localized: "Die Anmeldung bei ChatGPT ist abgelaufen. Melde dich unter Einstellungen › KI neu an.")
            case .usageLimit: String(localized: "ChatGPT nimmt gerade keine Anfragen an. Versuch es später noch einmal.")
            case .failed: String(localized: "Die Notiz ließ sich nicht übersetzen. Versuch es noch einmal.")
            case .tooLong: String(localized: "Die Notiz ist zu lang zum Übersetzen.")
            case .notARecipe: String(localized: "Die Notiz hat keinen Abschnitt „Zutaten“.")
            case .mismatch: String(localized: "Die Übersetzung passt nicht zur Notiz. Versuch es noch einmal.")
            }
        }
    }

    private let responder: any ResponseStreaming
    private let model: @MainActor () async throws -> String
    private let hasConsent: @MainActor () -> Bool
    private let timeout: Duration

    init(responder: any ResponseStreaming, model: @escaping @MainActor () async throws -> String,
         hasConsent: @escaping @MainActor () -> Bool, timeout: Duration = .seconds(45)) {
        self.responder = responder
        self.model = model
        self.hasConsent = hasConsent
        self.timeout = timeout
    }

    /// The note text in `language`, with the same structure as `text` (see `RecipeTranslationPlan.assembled`).
    func translate(_ text: String, to language: VoiceLanguage) async throws -> String {
        // A note that is no recipe is refused before the consent check: nothing is sent either way.
        guard RecipeNote.parse(text) != nil else { throw Failure.notARecipe }
        guard hasConsent() else { throw Failure.consentMissing }
        let plan = RecipeTranslationPlan(markdown: text)
        guard plan.isWithinLimits else { throw Failure.tooLong }
        let message = InputItem.user(Self.inputText(for: plan, language: language))
        let answer: String
        do {
            let slug = try await model()
            answer = try await RecipeRequest.withTimeout(timeout) { [responder] in
                try await RecipeRequest.collect(responder.respond(model: slug, instructions: Self.instructions, input: [message], tools: [],
                                                                  jsonSchema: (name: "recipe_translation", schema: Self.schema)))
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ChatGPTError {
            throw Self.failure(for: error)
        } catch {
            throw Failure.failed
        }
        return try Self.checked(Data(answer.utf8), plan: plan, language: language)
    }

    // MARK: Checking

    private struct Answer: Decodable {
        struct Line: Decodable {
            var i: Int
            var text: String
        }
        var lines: [Line]
    }

    /// Decodes the answer and puts it into the note. An answer that does not decode is `failed`; one that decodes but does
    /// not fit (a line twice, a missing line, a changed amount, …) is `mismatch`.
    static func checked(_ answer: Data, plan: RecipeTranslationPlan, language: VoiceLanguage) throws -> String {
        guard let decoded = try? JSONDecoder().decode(Answer.self, from: answer) else { throw Failure.failed }
        var translations: [Int: String] = [:]
        for line in decoded.lines {
            // Each index may appear once.
            guard translations.updateValue(line.text, forKey: line.i) == nil else { throw Failure.mismatch }
        }
        do {
            return try plan.assembled(translations: translations, language: language)
        } catch {
            throw Failure.mismatch
        }
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

    /// The user message: the target language and the lines to translate as JSON, `{"target":"Deutsch","lines":[{"i":3,"text":"…"}]}`.
    static func inputText(for plan: RecipeTranslationPlan, language: VoiceLanguage) -> String {
        let lines = plan.request.map { ["i": $0.index, "text": $0.text] as [String: Any] }
        let object: [String: Any] = ["target": RecipeLanguage.promptName(language), "lines": lines]
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    static let instructions = """
    You translate the lines of a recipe. The input is JSON with "target" (the language to translate into) and "lines", a list \
    of objects with an index "i" and a "text". Return every line translated into the target language, with the same index.
    - Translate each line on its own. Return exactly the indices you received, each once. Never merge, split, summarize, \
    reorder or leave out a line, and never add one.
    - Keep every number exactly as written: amounts, fractions (½, 1/2), times, temperatures and counts. Do not convert units \
    or recalculate amounts. You may replace a unit by the usual abbreviation of the target language ("tbsp" becomes "EL" in \
    German, "EL" becomes "tbsp" in English).
    - Keep Markdown links, web addresses and "attachment:" references exactly as written, character by character. Translate \
    only the visible link text.
    - Keep proper names, brand names and the names of dishes that are usually not translated.
    - Return the text of the line only: no list marker, no heading marks, no numbering, no line breaks and no comments.
    """

    static let schema = Data("""
    {
      "type": "object",
      "properties": {
        "lines": {
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
      "required": ["lines"],
      "additionalProperties": false
    }
    """.utf8)
}
