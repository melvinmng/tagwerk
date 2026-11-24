import AIKit
import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

private final class PageFetcher: PageFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var requested: [URL] = []
    var urls: [URL] { lock.withLock { requested } }
    func fetch(_ url: URL) async throws -> Data {
        lock.withLock { requested.append(url) }
        return Data("Pfannkuchen: 2 Eier, 200 g Mehl, 400 ml Milch".utf8)
    }
}

/// Adjusting and following up on the ingredients of a recipe (plan ki-vorschlaege-anpassen, task D2).
@MainActor
struct RecipeFollowUpTests {
    let responder = FakePlanResponder()
    private let fetcher = PageFetcher()
    final class Counter { var models = 0 }
    let counter = Counter()
    let categories = ["Obst & Gemüse", "Kühlregal", "Vorrat & Konserven"]

    private func importer(consent: Bool = true) -> RecipeImporter {
        let counter = self.counter
        return RecipeImporter(responder: responder, model: { counter.models += 1; return "gpt-test" }, hasConsent: { consent }, fetcher: fetcher)
    }

    private func candidate(_ name: String, _ quantity: String? = nil, category: String = "Sonstiges", onList: Bool = false) -> RecipeImporter.Candidate {
        RecipeImporter.Candidate(name: name, quantity: quantity, category: category, alreadyOnList: onList)
    }

    private func result(_ candidates: [RecipeImporter.Candidate], steps: [String] = ["Rühren."]) -> RecipeImporter.Result {
        RecipeImporter.Result(title: "Pfannkuchen", servings: 2, candidates: candidates, steps: steps, language: .german)
    }

    private func answer(_ items: [(String, String?, String)], title: String = "Pfannkuchen", steps: [String] = ["Rühren."]) -> String {
        let object: [String: Any] = ["title": title, "servings": 2, "steps": steps,
                                     "items": items.map { ["name": $0.0, "quantity": $0.1 as Any? ?? NSNull(), "category": $0.2] }]
        return String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    private func sentText(_ index: Int = 0) -> String {
        responder.calls[index].input.map { item -> String in
            switch item {
            case .user(let text): text
            case .userImage(let text, _), .userImages(let text, _): text
            default: ""
            }
        }.joined(separator: "\n")
    }

    private func revise(_ importer: RecipeImporter, _ input: RecipeImporter.Input, current: RecipeImporter.Result, pinned: [String] = [],
                        focus: String? = nil, comment: String = "Ohne Salz") async throws -> RecipeImporter.Result {
        try await importer.revise(input, current: current, pinned: pinned, focus: focus, comment: comment, language: .german,
                                  categoryNames: categories, openItemKeys: [])
    }

    // MARK: Importer

    @Test func revise_requiresRecipeConsent() async {
        await #expect(throws: RecipeImporter.Failure.consentMissing) {
            _ = try await revise(importer(consent: false), .text("Eier"), current: result([candidate("Eier")]))
        }
        #expect(counter.models == 0 && responder.calls.isEmpty)
    }

    @Test func revise_sendsSourceWhileSheetHoldsIt() async throws {
        responder.enqueue(answer([("Eier", "2 Stück", "Kühlregal")]))
        let current = result([candidate("Eier", "2 Stück", category: "Kühlregal"), candidate("Salz", "etwas")])

        _ = try await revise(importer(), .text("Pfannkuchen: 2 Eier und Salz"), current: current, pinned: ["Salz"])

        let text = sentText()
        #expect(text.contains("Pfannkuchen: 2 Eier und Salz") && text.contains("Message from the user: Ohne Salz"))
        #expect(text.contains("Current result as JSON") && text.contains(#""fixed_by_user":true"#) && text.contains(#""fixed_by_user":false"#))
        #expect(responder.calls[0].schema == "recipe_ingredients" && responder.schemas[0] == RecipeImporter.schema)
        #expect(responder.instructions[0].hasPrefix(RecipeImporter.instructions) && responder.instructions[0].contains("fixed_by_user"))
    }

    @Test func revise_photosGoWithTheTailAsOneRequest() async throws {
        responder.enqueue(answer([("Eier", nil, "Kühlregal")]))
        _ = try await revise(importer(), .photos([Data([1]), Data([2])]), current: result([candidate("Eier")]), focus: "Eier")
        guard case .userImages(let text, let jpegs) = responder.calls[0].input[0] else { Issue.record("expected both photos"); return }
        #expect(jpegs.count == 2 && text.contains("The message is about: Eier"))
    }

    @Test func revise_aLinkSendsTheTextReadEarlier_notTheAddress_andLoadsNothing() async throws {
        responder.enqueue(answer([("Eier", nil, "Kühlregal")]))
        let url = URL(string: "https://example.com/pfannkuchen")!
        var current = result([candidate("Eier")])
        current.sourceText = "Pfannkuchen: 2 Eier"
        current.sourceURL = url

        let revised = try await revise(importer(), .link(url), current: current)

        #expect(sentText().contains("Pfannkuchen: 2 Eier") && !sentText().contains("example.com"))
        #expect(fetcher.urls.isEmpty && revised.sourceText == "Pfannkuchen: 2 Eier" && revised.sourceURL == url)
        await #expect(throws: RecipeImporter.Failure.linkUnreadable) {
            _ = try await revise(importer(), .link(url), current: result([candidate("Eier")]))
        }
    }

    @Test func read_ofALink_keepsTheTextForTheFollowUp() async throws {
        responder.enqueue(answer([("Eier", nil, "Kühlregal")]))
        let found = try await importer().read(.link(URL(string: "https://example.com/r")!), language: .german, categoryNames: categories, openItemKeys: [])
        #expect(found.sourceText?.contains("2 Eier") == true && fetcher.urls.count == 1)
    }

    @Test func revise_checksTheAnswerLikeTheFirstReading() async throws {
        responder.enqueue(answer([("Eier", "2", "Unbekannt"), ("", "x", "Kühlregal")]))
        let revised = try await revise(importer(), .text("Eier"), current: result([candidate("Eier")]))
        #expect(revised.candidates.map(\.name) == ["Eier"] && revised.candidates[0].category == "Sonstiges")
    }

    // MARK: Rows

    @Test func row_edit_nameAndCategory_leavesTheAmountAlone() {
        let row = RecipeRow(candidate: RecipeImporter.Candidate(name: "Eier", quantity: "2 Stück",
                                                                line: IngredientLine.parse("2 Eier"), category: "Sonstiges", alreadyOnList: false))
        let edited = row.edited(name: "  Bio-Eier ", category: "Kühlregal")
        #expect(edited.id == row.id && edited.candidate.name == "Bio-Eier" && edited.candidate.category == "Kühlregal")
        // The sheet has no amount: the amount and its structured form (which scaling works on) stay as they were.
        #expect(edited.candidate.quantity == "2 Stück" && edited.candidate.line == row.candidate.line)
        // A blank name changes nothing.
        #expect(row.edited(name: " ", category: "Sonstiges") == row)
    }

    @Test func row_edit_ofARowWithASecondName_changesTheListName() {
        var candidate = candidate("Eggs", "2")
        candidate.shoppingName = "Eier"
        candidate.shoppingUnit = "Stück"
        let edited = RecipeRow(candidate: candidate).edited(name: "Bio-Eier", category: "Sonstiges")
        #expect(edited.candidate.listName == "Bio-Eier" && edited.candidate.name == "Eggs" && edited.candidate.shoppingUnit == "Stück")
        #expect(edited.candidate.quantity == "2")
    }

    @Test func row_edit_categoryFromOwnListOnly() {
        #expect(RecipeRowEditor.choices(["A", "B"], current: "B") == ["A", "B"])
        // A category the list does not know stays selectable, so the picker shows what the row has.
        #expect(RecipeRowEditor.choices(["A", "B"], current: "Alt") == ["A", "B", "Alt"])
    }

    // MARK: Draft

    private func draft(_ candidates: [RecipeImporter.Candidate], reviser: RecipeReviser? = { current, _, _, _ in current }) -> RecipeDraftModel {
        RecipeDraftModel(result: result(candidates), reviser: reviser)
    }

    @Test func draft_startsWithTheIngredientsOnTheListUnchecked() {
        let model = draft([candidate("Eier"), candidate("Mehl", onList: true)])
        #expect(model.selectedCandidates.map(\.name) == ["Eier"])
        model.toggle(model.rows[1].id)
        #expect(model.selectedCandidates.map(\.name) == ["Eier", "Mehl"])
    }

    @Test func revise_scopeRow_changesOnlyThatRow() async {
        var seen: (pinned: [String], focus: String?)?
        let model = draft([candidate("Eier", "2"), candidate("Mehl", "200 g")]) { current, pinned, focus, _ in
            seen = (pinned, focus)
            var answer = current
            answer.candidates = [self.candidate("Eier", "4"), self.candidate("Mehl", "500 g"), self.candidate("Zucker")]
            return answer
        }
        model.followUp.focus = model.rows[0].id

        await model.send("Doppelt")

        #expect(model.candidates.map(\.quantity) == ["4", "200 g"] && model.rows.count == 2)
        #expect(seen?.focus == "Eier" && seen?.pinned == [])
        #expect(model.followUp.mark(of: model.rows[0].id) == .byAssistant && model.followUp.mark(of: model.rows[1].id) == nil)
    }

    @Test func revise_scopeAll_addsRows_keepsDeselectedRowsDeselected_andNamesEditedRows() async {
        var pinnedSeen: [String] = []
        let model = draft([candidate("Eier", "2"), candidate("Mehl", "200 g"), candidate("Salz", "etwas")]) { current, pinned, _, _ in
            pinnedSeen = pinned
            var answer = current
            answer.candidates = [self.candidate("Bio-Eier", "12"), self.candidate("Mehl", "200 g"), self.candidate("Zucker", "1 EL", onList: true)]
            answer.title = "Pfannkuchen süß"
            answer.steps = ["Rühren.", "Braten."]
            return answer
        }
        model.toggle(model.rows[1].id)       // Mehl unchecked
        model.edit(model.rows[0].edited(name: "Bio-Eier", category: "Sonstiges"))

        await model.send("Süß machen")

        // "Bio-Eier" was set by hand and is named in the request; the answer changed its amount anyway, so the row is reported.
        #expect(pinnedSeen == ["Bio-Eier"])
        #expect(model.candidates.map(\.listName) == ["Bio-Eier", "Mehl", "Zucker"] && model.candidates[0].quantity == "12")
        #expect(!model.isSelected(model.rows[1].id))
        // The new row that is on the list already starts unchecked, like in the first reading.
        #expect(!model.isSelected(model.rows[2].id))
        #expect(model.result.title == "Pfannkuchen süß" && model.result.steps.count == 2)
        #expect(model.followUp.overwritten == [model.rows[0].id])
        model.undo()
        #expect(model.candidates.map(\.listName) == ["Bio-Eier", "Mehl", "Salz"] && model.result.title == "Pfannkuchen" && model.result.steps == ["Rühren."])
    }

    @Test func revise_failure_keepsTheRows() async {
        let model = draft([candidate("Eier")]) { _, _, _, _ in throw RecipeImporter.Failure.network }
        await model.send("Mehr")
        #expect(model.followUp.state == .failed(RecipeImporter.Failure.network.message) && model.candidates.map(\.name) == ["Eier"])
    }

    @Test func draft_withoutAReviser_orForARecipeReadOnTheDevice_offersNoFollowUp() {
        #expect(!draft([candidate("Eier")], reviser: nil).hasFollowUp)
        var local = result([candidate("Eier")])
        local.readLocally = true
        #expect(!RecipeDraftModel(result: local, reviser: { current, _, _, _ in current }).hasFollowUp)
    }

    @Test func editedRow_keepsMarkThroughServingsScaling() {
        let model = draft([RecipeImporter.Candidate(name: "Eier", quantity: "2", line: IngredientLine.parse("2 Eier"), category: "Sonstiges", alreadyOnList: false)])
        model.edit(model.rows[0].edited(name: "Bio-Eier", category: "Sonstiges"))
        let scaled = RecipeResultView.scaled(candidates: model.candidates, base: 2, target: 4, locale: Locale(identifier: "de_DE"))
        // Scaling is a view of the rows: the identity and the mark stay with the row, and the amount of the recipe still scales.
        #expect(model.followUp.mark(of: model.rows[0].id) == .byUser && scaled.count == 1)
        #expect(scaled[0].line?.amount != model.candidates[0].line?.amount)
    }

    @Test func apply_usesEditedCandidates_andNoteSave_usesTheSameRevisedResult() {
        let model = draft([candidate("Eier", "2", category: "Sonstiges"), candidate("Mehl", "200 g")])
        model.edit(model.rows[0].edited(name: "Bio-Eier", category: "Kühlregal"))
        model.toggle(model.rows[1].id)

        #expect(model.selectedCandidates.map(\.listName) == ["Bio-Eier"] && model.selectedCandidates[0].category == "Kühlregal")
        let note = RecipeNoteWriter.recipeNote(from: model.current, title: "Pfannkuchen", servings: 2)
        let lines = model.candidates.map { RecipeNoteWriter.ingredientLine(for: $0, locale: Locale(identifier: "de_DE")) }
        #expect(lines.contains { $0.contains("Bio-Eier") } && String(describing: note).contains("Bio-Eier"))
    }

    @Test func align_aRenamedFocusKeepsItsRow() {
        let rows = [RecipeRow(candidate: candidate("Eier")), RecipeRow(candidate: candidate("Mehl"))]
        let aligned = RecipeDraftModel.align([candidate("Bio-Eier"), candidate("Mehl")], with: rows, focus: rows[0].id)
        #expect(aligned[0].id == rows[0].id && aligned[0].candidate.name == "Bio-Eier" && aligned[1] == rows[1])
    }
}
