import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

/// The typed meal as the sheet edits it: further nutrients are unknown until typed (decision NU3b, NU4b).
struct MealDraftTests {
    private func typedDraft(kcal: Double = 200) -> MealDraft {
        var draft = MealDraft()
        draft.title = "Brot"
        draft.manualKcal = kcal
        return draft
    }

    @Test func emptyField_savesUnknown() {
        var draft = typedDraft()
        #expect(draft.manualNutrient(.fiber) == nil)
        #expect(draft.value.items.first?.fiber == nil, "nothing typed means unknown, never 0")
        draft.setManualNutrient(.fiber, 6)
        #expect(draft.value.items.first?.fiber == 6)
        // Clearing the field makes it unknown again.
        draft.setManualNutrient(.fiber, nil)
        #expect(draft.value.items.first?.fiber == nil)
    }

    @Test func statedZero_staysZero() {
        var draft = typedDraft()
        draft.setManualNutrient(.sugar, 0)
        #expect(draft.manualNutrient(.sugar) == 0)
        #expect(draft.value.items.first?.sugar == 0, "a typed 0 is a value, not unknown")
    }

    @Test func negativeInput_clampsToZero() {
        var draft = typedDraft()
        draft.setManualNutrient(.salt, -2)
        #expect(draft.manualNutrient(.salt) == 0)
    }

    @Test func nutrientBeforeAnyValue_createsTheItem_andClearingWithoutItemDoesNothing() {
        var draft = MealDraft()
        draft.setManualNutrient(.fiber, nil)
        #expect(draft.items.isEmpty)
        draft.setManualNutrient(.fiber, 3)
        #expect(draft.items.count == 1 && draft.manualNutrient(.fiber) == 3)
    }

    @Test func counter_countsTheKnownVisibleNutrients() {
        var draft = typedDraft()
        let visible: [Nutrient] = [.fiber, .sugar, .salt]
        #expect(draft.knownManualNutrients(in: visible) == 0)
        draft.setManualNutrient(.fiber, 4)
        draft.setManualNutrient(.saturatedFat, 2)
        #expect(draft.knownManualNutrients(in: visible) == 1, "a hidden nutrient does not count")
        draft.setManualNutrient(.sugar, 0)
        #expect(draft.knownManualNutrients(in: visible) == 2)
    }

    @Test func quantityFactor_isFoldedIntoTheNutrientsToo() {
        var draft = MealDraft()
        draft.title = "Müsli"
        var item = MealItem(name: "Müsli", amount: "1", kcalMin: 100, kcal: 100, kcalMax: 100, protein: 4, carbs: 20, fat: 2, fiber: 3)
        item.factor = 2
        draft.items = [item]
        // Shown values include the factor, so what is typed next is a value of the whole item.
        #expect(draft.manualNutrient(.fiber) == 6)
        draft.setManualNutrient(.sugar, 5)
        let saved = draft.value.items[0]
        #expect(saved.factor == 1 && saved.fiber == 6 && saved.sugar == 5 && saved.kcal == 200)
        #expect(draft.value.nutrient(.fiber) == 6)
    }

    @Test func mealsWithoutTheFields_keepTheirUnknownValues() {
        var draft = typedDraft()
        draft.setManualNutrient(.fiber, 2)
        #expect(draft.value.nutrient(.sugar) == nil && draft.value.nutrient(.saturatedFat) == nil && draft.value.nutrient(.salt) == nil)
    }
}
