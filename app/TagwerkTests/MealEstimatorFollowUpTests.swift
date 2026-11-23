import AIKit
import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

/// The follow-up about a meal estimate (plan ki-vorschlaege-anpassen, task D1).
@MainActor
struct MealEstimatorFollowUpTests {
    let responder = FakePlanResponder()
    final class Counter { var value = 0 }

    private func make(consent: Bool = true, counter: Counter = Counter()) -> MealEstimator {
        MealEstimator(responder: responder, model: { counter.value += 1; return "gpt-test" }, hasConsent: { consent },
                      language: { .german })
    }

    private func item(_ name: String, _ amount: String, _ kcal: Double, factor: Double = 1, estimated: Bool = true) -> MealItem {
        MealItem(name: name, amount: amount, factor: factor, kcalMin: kcal - 20, kcal: kcal, kcalMax: kcal + 20, protein: 5, carbs: 10, fat: 2,
                 isEstimated: estimated)
    }

    private func answer(_ names: [(String, Double)]) -> String {
        let items = names.map { #"{"name":"\#($0.0)","amount":"1 Stück","kcal_min":\#($0.1 - 20),"kcal":\#($0.1),"kcal_max":\#($0.1 + 20),"protein_g":5,"carbs_g":10,"fat_g":2,"fiber_g":null,"sugar_g":null,"saturated_fat_g":null,"salt_g":null}"# }
        return #"{"title":"Frühstück","items":[\#(items.joined(separator: ","))]}"#
    }

    private func userText(_ index: Int = 0) -> String {
        responder.calls[index].input.compactMap { item -> String? in
            switch item {
            case .user(let text): text
            case .userImage(let text, _): text
            default: nil
            }
        }.joined(separator: "\n")
    }

    // MARK: Request

    @Test func revise_requiresMealConsent() async {
        let counter = Counter()
        await #expect(throws: MealEstimator.Failure.consentMissing) {
            try await make(consent: false, counter: counter).revise(text: "Brötchen", jpeg: nil, items: [item("Brötchen", "2", 300)],
                                                                    pinned: [], focus: nil, comment: "Mehr")
        }
        #expect(counter.value == 0 && responder.calls.isEmpty)
    }

    @Test func revise_sendsTextPhotoItemsAndComment() async throws {
        responder.enqueue(answer([("Brötchen", 300)]))
        let brötchen = item("Brötchen", "2 Stück", 300, factor: 2)
        let käse = item("Käse", "2 Scheiben", 180)
        let photo = Data([1, 2, 3])

        _ = try await make().revise(text: "2 Brötchen mit Käse", jpeg: photo, items: [brötchen, käse], pinned: [käse.id], focus: nil,
                                    comment: "Kein Käse")

        let call = try #require(responder.calls.first)
        guard case .userImage(let text, let jpeg) = call.input[0] else { Issue.record("expected the photo to go with it"); return }
        #expect(jpeg == photo)
        #expect(text.contains("2 Brötchen mit Käse") && text.contains("Kein Käse"))
        #expect(text.contains(#""name":"Käse""#) && text.contains(#""fixed_by_user":true"#) && text.contains(#""fixed_by_user":false"#))
        #expect(text.contains(#""quantity_factor":2"#) && text.contains("all items"))
    }

    @Test func revise_strictSchema_andInstructionsOfTheFirstRequestPlusRevision() async throws {
        responder.enqueue(answer([("Brötchen", 300)]))
        _ = try await make().revise(text: "Brötchen", jpeg: nil, items: [item("Brötchen", "2", 300)], pinned: [], focus: nil, comment: "Mehr")
        #expect(responder.calls[0].schema == "meal_estimate")
        #expect(responder.schemas[0] == MealEstimator.schema)
        #expect(responder.instructions[0].hasPrefix(MealEstimator.instructions(language: .german)))
        #expect(responder.instructions[0].contains("fixed_by_user"))
    }

    @Test func revise_withoutAUsableAnswer_isNothingRecognized() async {
        responder.enqueue(#"{"title":"","items":[]}"#)
        await #expect(throws: MealEstimator.Failure.nothingRecognized) {
            try await make().revise(text: "x", jpeg: nil, items: [item("Brötchen", "2", 300)], pinned: [], focus: nil, comment: "Mehr")
        }
    }

    @Test func existingMeal_withoutOriginalInput_sendsItemsOnly() async throws {
        responder.enqueue(answer([("Brötchen", 300)]))
        let one = item("Brötchen", "2", 300)
        _ = try await make().revise(text: "", jpeg: nil, items: [one], pinned: [], focus: one.id, comment: "Größer")
        let text = userText()
        #expect(text.contains("Meal description: (none)") && text.contains("The message is about: Brötchen"))
        if case .user = responder.calls[0].input[0] {} else { Issue.record("no photo expected") }
    }

    @Test func followUp_sendsNoGoalsNoHealthNoEarlierMeals() async throws {
        responder.enqueue(answer([("Brötchen", 300)]))
        _ = try await make().revise(text: "Brötchen", jpeg: nil, items: [item("Brötchen", "2", 300)], pinned: [], focus: nil, comment: "Mehr")
        // The request holds exactly four parts: the description, the items, the focus and the message.
        let lines = userText().split(separator: "\n").map { $0.prefix(while: { $0 != ":" }) }
        #expect(lines.map(String.init) == ["Meal description", "Current estimate as JSON", "The message is about", "Message from the user"])
        for word in ["health", "goal", "ziel", "weight", "gewicht"] { #expect(!userText().lowercased().contains(word), "\(word) was sent") }
    }

    // MARK: Putting the answer onto the items

    @Test func align_keepsIdentityAndQuantityFactorOfNamedItems() {
        let old = item("Brötchen", "2 Stück", 300, factor: 2)
        let answer = MealItem(name: "brötchen", amount: "3 Stück", kcalMin: 380, kcal: 450, kcalMax: 520, protein: 15, carbs: 80, fat: 3, isEstimated: true)

        let aligned = MealEstimator.align([answer], with: [old])

        #expect(aligned.count == 1 && aligned[0].id == old.id && aligned[0].factor == 2 && aligned[0].kcal == 450)
    }

    @Test func align_aRepeatedItemIsTheVeryOldItem() {
        let old = item("Brötchen", "2 Stück", 300, factor: 1.5, estimated: false)
        let same = MealItem(name: "Brötchen", amount: "2 Stück", kcalMin: 280, kcal: 300, kcalMax: 320, protein: 5, carbs: 10, fat: 2, isEstimated: true)
        #expect(MealEstimator.align([same], with: [old]) == [old])
    }

    @Test func align_newNamesAreNewItems_andAMissingOneIsGone() {
        let old = [item("Brötchen", "2", 300), item("Käse", "2", 180)]
        let new = item("Butter", "1 Portion", 70)
        let aligned = MealEstimator.align([new], with: old)
        #expect(aligned == [new])
    }

    @Test func align_aRenamedFocusKeepsItsIdentity() {
        let old = [item("Brötchen", "2", 300), item("Käse", "2", 180)]
        let renamed = MealItem(name: "Vollkornbrötchen", amount: "2 Stück", kcalMin: 280, kcal: 300, kcalMax: 320, protein: 5, carbs: 10, fat: 2, isEstimated: true)
        let aligned = MealEstimator.align([renamed, old[1]], with: old, focus: old[0].id)
        #expect(aligned[0].id == old[0].id && aligned[0].name == "Vollkornbrötchen" && aligned[1] == old[1])
    }

    // MARK: With the model of the sheet

    @Test func scopeItem_changesOnlyThatItem_andUndoRestoresTheDraft() async throws {
        let brötchen = item("Brötchen", "2 Stück", 300), käse = item("Käse", "2 Scheiben", 180)
        let model = PreviewFollowUpModel<MealItem>(items: [brötchen, käse])
        model.focus = käse.id
        // The answer would change both items; only the one the message is about may change.
        responder.enqueue(answer([("Brötchen", 400), ("Käse", 90)]))
        let estimator = make()

        await model.send("Weniger Käse", using: { request in
            var focus: UUID?
            if case .one(let id) = request.scope { focus = id }
            let reply = try await estimator.revise(text: "", jpeg: nil, items: request.items, pinned: Set(request.pinned), focus: focus, comment: request.comment)
            return .init(items: MealEstimator.align(reply.items, with: request.items, focus: focus), message: "ok")
        }, failure: { _ in "Fehler" })

        #expect(model.items[0] == brötchen && model.items[1].kcal == 90 && model.items[1].id == käse.id)
        model.undo()
        #expect(model.items == [brötchen, käse])
    }

    @Test func scopeAll_namesFixedItemsInTheRequest_andReportsOverwrittenOnes() async throws {
        let brötchen = item("Brötchen", "2 Stück", 300), käse = item("Käse", "2 Scheiben", 180)
        let model = PreviewFollowUpModel<MealItem>(items: [brötchen, käse])
        var edited = käse
        edited.amount = "1 Scheibe"
        model.edit(edited)
        responder.enqueue(answer([("Brötchen", 300), ("Käse", 180)]))
        let estimator = make()

        await model.send("Alles genauer", using: { request in
            let reply = try await estimator.revise(text: "", jpeg: nil, items: request.items, pinned: Set(request.pinned), focus: nil, comment: request.comment)
            return .init(items: MealEstimator.align(reply.items, with: request.items), message: "ok")
        }, failure: { _ in "Fehler" })

        // The request named the item as fixed; the answer changed it anyway (other amount), so the sheet reports it.
        #expect(model.overwritten == [käse.id] && model.mark(of: käse.id) == .byAssistant)
        #expect(responder.calls.count == 1 && userText().contains(#""fixed_by_user":true"#))
    }

    @Test func newEstimate_stillDiscardsEverything() {
        let model = PreviewFollowUpModel<MealItem>(items: [item("Brötchen", "2", 300)])
        var edited = model.items[0]
        edited.amount = "3"
        model.edit(edited)
        model.replaceItems([item("Apfel", "1", 80)])
        #expect(model.items.map(\.name) == ["Apfel"] && model.mark(of: model.items[0].id) == nil && !model.canUndo)
    }
}
