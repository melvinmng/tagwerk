import Foundation
import FoundationModels

@Generable
struct MealEstimate {
    @Guide(description: "Einzelne Lebensmittel mit geschätzten Kilokalorien")
    var items: [MealItem]
    @Guide(description: "Summe der Kilokalorien")
    var totalKcal: Int
}

@Generable
struct MealItem {
    var name: String
    var kcal: Int
}

/// Checks Apple's on-device language model: availability, German support and one guided generation.
struct AppleModelProbe: Probe {
    let name = "Apple lokales Modell"

    static func describe(_ availability: SystemLanguageModel.Availability) -> String {
        switch availability {
        case .available:
            return "verfügbar"
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Apple Intelligence ist ausgeschaltet (Einstellungen → Apple Intelligence & Siri)"
        case .unavailable(.modelNotReady):
            return "Modell lädt noch herunter, später erneut versuchen"
        case .unavailable(.deviceNotEligible):
            return "Gerät unterstützt Apple Intelligence nicht"
        case .unavailable(let other):
            return "nicht verfügbar: \(other)"
        }
    }

    func run() async -> ProbeResult {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            return ProbeResult(name: name, ok: false, detail: Self.describe(model.availability))
        }
        let germanSupported = model.supportedLanguages.contains { $0.languageCode?.identifier == "de" }
        do {
            let session = LanguageModelSession(instructions: "Du schätzt Nährwerte von Mahlzeiten realistisch.")
            let started = Date()
            let response = try await session.respond(to: "2 Brötchen mit Käse", generating: MealEstimate.self)
            let seconds = Date().timeIntervalSince(started)
            let meal = response.content
            let items = meal.items.map { "\($0.name) \($0.kcal) kcal" }.joined(separator: ", ")
            return ProbeResult(
                name: name, ok: true,
                detail: "Deutsch: \(germanSupported ? "ja" : "nein"); \(items) = \(meal.totalKcal) kcal (\(String(format: "%.1f", seconds)) s)"
            )
        } catch {
            return ProbeResult(name: name, ok: false, detail: "Deutsch: \(germanSupported ? "ja" : "nein"); Fehler: \(error.localizedDescription)")
        }
    }
}
