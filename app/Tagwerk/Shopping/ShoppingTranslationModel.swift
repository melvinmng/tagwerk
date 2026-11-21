import Foundation
import Observation
import TagwerkCore

/// The state behind "Artikel übersetzen" on the shopping page: the card that appears after the language of the list changed,
/// the request to ChatGPT, the preview, the renaming and its undo. The views stay thin; nothing here sends or writes before
/// the user taps (the view has checked sign-in and consent).
@MainActor
@Observable
final class ShoppingTranslationModel {
    /// The card above the input field.
    struct Offer: Equatable {
        var language: VoiceLanguage
        var openCount: Int
        /// The text of the last failure; it replaces the card's text until the next try.
        var message: String?
    }

    /// The proposal of one request, identifiable for the preview sheet.
    struct Preview: Equatable, Identifiable {
        let id: UUID
        var changes: [ShoppingTranslationPlan.Change]
        /// Open items that did not fit into the request.
        var leftOut: Int
    }

    /// The card; `nil` hides it.
    private(set) var offer: Offer?
    private(set) var isTranslating = false
    var preview: Preview?
    /// Items renamed by the last "Übernehmen"; not empty while the capsule shows.
    private(set) var undo: [ShoppingModel.Renamed] = []
    /// A line for the notice above the input field, set by `translate()` and `apply(_:)`; the view takes and clears it.
    var notice: String?

    @ObservationIgnored private let shopping: ShoppingModel
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let translator: ShoppingTranslator
    /// Identifies the running request, so a cancelled one cannot show or clear anything.
    @ObservationIgnored private var requestID: UUID?
    @ObservationIgnored private var request: Task<[ShoppingTranslationPlan.Change], Error>?
    /// `shoppingItemsLanguage` before the last "Übernehmen", for "Rückgängig".
    @ObservationIgnored private var languageBeforeApply: String?

    init(shopping: ShoppingModel, settings: AppSettings, translator: ShoppingTranslator) {
        self.shopping = shopping
        self.settings = settings
        self.translator = translator
    }

    /// The language the list is in now.
    private var currentLanguage: VoiceLanguage { settings.contentLanguages.shoppingLanguage() }

    // MARK: Card

    /// Called after every reload of the list and when a language setting changes. Reads the list only once it is loaded: a list
    /// that is not there yet is not an empty one.
    func refreshOffer() {
        guard shopping.state == .ready else {
            offer = nil
            return
        }
        let current = currentLanguage
        switch ShoppingTranslationOffer.step(current: current, settled: settings.shoppingItemsLanguage, openItemCount: shopping.openItems.count) {
        case .adopt(let language):
            settings.shoppingItemsLanguage = language.rawValue
            offer = nil
        case .offer(let language):
            let message = offer?.language == language ? offer?.message : nil
            offer = Offer(language: language, openCount: shopping.openItems.count, message: message)
        case .none:
            offer = nil
        }
    }

    /// "So lassen": the language counts as settled; the card comes back at the next change of the language.
    func keepAsIs() {
        settings.shoppingItemsLanguage = currentLanguage.rawValue
        offer = nil
    }

    // MARK: Request

    /// Card and menu entry. One request with the names of the open items; shows the preview, or a line when nothing changes.
    func translate() async {
        guard !isTranslating else { return }
        let language = currentLanguage
        let plan = ShoppingTranslationPlan(openItems: shopping.openItems)
        let id = UUID()
        requestID = id
        isTranslating = true
        let translator = translator
        let task = Task { try await translator.translate(plan, to: language) }
        request = task
        defer {
            if requestID == id {
                isTranslating = false
                request = nil
            }
        }
        do {
            let changes = try await task.value
            // A cancelled request must not show a late answer.
            guard requestID == id, !Task.isCancelled else { return }
            if changes.isEmpty {
                settings.shoppingItemsLanguage = language.rawValue
                offer = nil
                notice = Self.alreadyTranslatedLine(language)
            } else {
                preview = Preview(id: UUID(), changes: changes, leftOut: plan.leftOut)
            }
        } catch let failure as ShoppingTranslator.Failure {
            guard requestID == id else { return }
            fail(failure.message, language: language)
        } catch {
            // Cancelled by the user or by leaving the page: nothing to report.
        }
    }

    /// Cancels the request; a late answer is dropped.
    func cancel() {
        request?.cancel()
        request = nil
        requestID = nil
        isTranslating = false
    }

    private func fail(_ message: String, language: VoiceLanguage) {
        if let current = offer {
            offer = Offer(language: current.language, openCount: current.openCount, message: message)
        } else {
            notice = message
        }
    }

    /// The name of a language in the German texts of this feature: "Englisch", "Deutsch".
    static func languageName(_ language: VoiceLanguage) -> String {
        language == .english ? String(localized: "Englisch") : String(localized: "Deutsch")
    }

    /// "Alle Artikel sind schon auf Englisch."
    static func alreadyTranslatedLine(_ language: VoiceLanguage) -> String {
        language == .english ? String(localized: "Alle Artikel sind schon auf Englisch.") : String(localized: "Alle Artikel sind schon auf Deutsch.")
    }

    // MARK: Preview

    /// The changes "Übernehmen" writes: the rows still checked; a blocked change is never part of it.
    static func selection(_ changes: [ShoppingTranslationPlan.Change], deselected: Set<String>) -> [ShoppingTranslationPlan.Change] {
        changes.filter { $0.blocked == nil && !deselected.contains($0.id) }
    }

    /// "Verwerfen": nothing changes, the card stays.
    func discard() { preview = nil }

    /// Writes the chosen titles, settles the language (also after a partial success) and prepares the undo. Returns the line for
    /// the notice when something was skipped or failed, `nil` when all went well.
    func apply(_ selected: [ShoppingTranslationPlan.Change]) async -> String? {
        let language = currentLanguage
        let chosen = selected.filter { $0.blocked == nil }
        preview = nil
        guard !chosen.isEmpty else { return nil }
        let before = settings.shoppingItemsLanguage
        let report = await shopping.rename(chosen)
        if !report.renamed.isEmpty {
            languageBeforeApply = before
            settings.shoppingItemsLanguage = language.rawValue
            undo = report.renamed
        }
        refreshOffer()
        return Self.reportLine(report, total: chosen.count)
    }

    /// "5 von 6 Artikeln übersetzt. 1 Artikel wurde inzwischen geändert und bleibt." or the first write error; `nil` when every
    /// chosen item was renamed.
    static func reportLine(_ report: ShoppingModel.RenameReport, total: Int) -> String? {
        guard report.skipped > 0 || report.failed > 0 else { return nil }
        var parts = [String(localized: "\(report.renamed.count) von \(total) Artikeln übersetzt.")]
        if report.skipped > 0 {
            parts.append(report.skipped == 1 ? String(localized: "1 Artikel wurde inzwischen geändert und bleibt.")
                                             : String(localized: "\(report.skipped) Artikel wurden inzwischen geändert und bleiben."))
        }
        if report.failed > 0 { parts.append(report.errorMessage ?? String(localized: "Ein Artikel ließ sich nicht schreiben.")) }
        return parts.joined(separator: " ")
    }

    // MARK: Undo

    /// "Rückgängig": the old titles come back where the item is unchanged; the language returns to what it was.
    func undoLast() async {
        let renamed = undo
        undo = []
        guard !renamed.isEmpty else { return }
        await shopping.undoRename(renamed)
        settings.shoppingItemsLanguage = languageBeforeApply
        languageBeforeApply = nil
        refreshOffer()
    }

    /// The capsule ran out: the rename stays.
    func capsuleExpired() { undo = [] }
}
