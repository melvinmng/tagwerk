import Foundation
import Testing
@testable import TagwerkCore

struct ShoppingClassifierTests {
    let dict = ShoppingDictionary(entries: ["chilled": ["milch", "eier"], "bakery": ["brot", "baguette"],
                                            "produce": ["banane", "bananen"], "pantry": ["kokosmilch"]])
    let chilled = ShoppingCategoryInfo(id: UUID(), name: "Kühlregal", sortIndex: 2, builtinKey: "chilled")
    let bakery = ShoppingCategoryInfo(id: UUID(), name: "Brot & Backwaren", sortIndex: 0, builtinKey: "bakery")
    let household = ShoppingCategoryInfo(id: UUID(), name: "Haushalt", sortIndex: 5, builtinKey: nil)

    private func classify(_ key: String, assignments: [String: ShoppingAssignmentInfo]) -> UUID? {
        ShoppingClassifier.categoryID(forKey: key, assignments: assignments, categories: [chilled, household],
                                      dictionary: dict)
    }

    @Test func dictionary_wholeKeyWordAndSuffix() {
        #expect(dict.builtinKey(forKey: "milch") == "chilled")
        #expect(dict.builtinKey(forKey: "frische bananen") == "produce")
        #expect(dict.builtinKey(forKey: "hafermilch") == "chilled")
        #expect(dict.builtinKey(forKey: "vollkornbrot") == "bakery")
        #expect(dict.builtinKey(forKey: "kokosmilch") == "pantry")
        #expect(dict.builtinKey(forKey: "sonnenmilch") == "chilled")
        #expect(dict.builtinKey(forKey: "schrauben") == nil)
        #expect(dict.builtinKey(forKey: "") == nil)
    }

    @Test func dictionary_suffixNeedsFourCharacters() {
        #expect(ShoppingDictionary(entries: ["produce": ["ei"]]).builtinKey(forKey: "brei") == nil)
        #expect(ShoppingDictionary(entries: ["produce": ["ei"]]).builtinKey(forKey: "ei") == "produce")
    }

    @Test func dictionary_longestMatchWins_acrossWordAndSuffix() {
        let dict = ShoppingDictionary(entries: ["drinks": ["saft"], "produce": ["orangen"]])
        #expect(dict.builtinKey(forKey: "orangen saft") == "produce")
    }

    @Test func classify_learnedBeatsDictionary_dictionaryBeatsOther() {
        #expect(classify("milch", assignments: ["milch": .init(categoryID: household.id, isManual: true)]) == household.id)
        #expect(classify("milch", assignments: [:]) == chilled.id)
        #expect(classify("schrauben", assignments: [:]) == nil)
    }

    @Test func classify_assignmentToDeletedCategory_fallsBackToDictionary() {
        #expect(classify("milch", assignments: ["milch": .init(categoryID: UUID(), isManual: true)]) == chilled.id)
    }

    @Test func classify_manualOther_beatsDictionary() {
        #expect(classify("milch", assignments: ["milch": .init(categoryID: nil, isManual: true)]) == nil)
    }

    @Test func classify_suggestedOther_alsoBeatsDictionary() {
        #expect(classify("milch", assignments: ["milch": .init(categoryID: nil, isManual: false)]) == nil)
    }

    @Test func classify_builtinCategoryDeleted_goesToOther() {
        #expect(ShoppingClassifier.categoryID(forKey: "milch", assignments: [:], categories: [household], dictionary: dict) == nil)
    }

    @Test func sections_orderBySortIndex_otherLast_emptyOmitted_itemsByCreationThenTitle() {
        let t1 = Date(timeIntervalSince1970: 100), t2 = Date(timeIntervalSince1970: 200)
        let items = [
            ShoppingItem(id: "1", name: "Milch", createdAt: t2),
            ShoppingItem(id: "2", name: "Eier", createdAt: t1),
            ShoppingItem(id: "3", name: "Brot"),
            ShoppingItem(id: "4", name: "Baguette"),
            ShoppingItem(id: "5", name: "Schrauben"),
        ]
        let sections = ShoppingSections.make(open: items, assignments: [:], categories: [chilled, bakery, household],
                                             dictionary: dict)
        #expect(sections.map(\.categoryID) == [bakery.id, chilled.id, nil])
        #expect(sections[0].items.map(\.name) == ["Baguette", "Brot"])
        #expect(sections[1].items.map(\.name) == ["Eier", "Milch"])
        #expect(sections[2].id == "other")
    }

    @Test func sections_datedItemsComeBeforeUndated() {
        let items = [ShoppingItem(id: "1", name: "Alt"), ShoppingItem(id: "2", name: "Neu", createdAt: Date(timeIntervalSince1970: 5))]
        let sections = ShoppingSections.make(open: items, assignments: [:], categories: [], dictionary: dict)
        #expect(sections.first?.items.map(\.name) == ["Neu", "Alt"])
    }

    @Test func categoryName_rules() throws {
        #expect(try ShoppingCategoryRules.validatedName("  Tierbedarf ", existing: [], isNew: true) == "Tierbedarf")
        #expect(throws: ShoppingCategoryRules.NameError.empty) { try ShoppingCategoryRules.validatedName("   ", existing: [], isNew: true) }
        #expect(throws: ShoppingCategoryRules.NameError.tooLong) {
            try ShoppingCategoryRules.validatedName(String(repeating: "a", count: 31), existing: [], isNew: true)
        }
        #expect(throws: ShoppingCategoryRules.NameError.duplicate) {
            try ShoppingCategoryRules.validatedName("kühlregal", existing: ["Kühlregal"], isNew: true)
        }
        #expect(throws: ShoppingCategoryRules.NameError.reserved) { try ShoppingCategoryRules.validatedName("sonstiges", existing: [], isNew: true) }
        #expect(throws: ShoppingCategoryRules.NameError.reserved) { try ShoppingCategoryRules.validatedName("Other", existing: [], isNew: true) }
        #expect(throws: ShoppingCategoryRules.NameError.limitReached) {
            try ShoppingCategoryRules.validatedName("Neu", existing: (1...30).map { "K\($0)" }, isNew: true)
        }
        #expect(try ShoppingCategoryRules.validatedName("Neu", existing: (1...29).map { "K\($0)" }, isNew: false) == "Neu")
    }

    @Test func bundledDictionary_isConsistent() {
        let entries = ShoppingDictionary.bundledEntries
        #expect(Set(entries.keys) == Set(ShoppingBuiltinCategory.allCases.map(\.rawValue)))
        let all = entries.values.flatMap { $0 }
        #expect(all.count == Set(all).count)
        #expect(all.filter { $0 != ShoppingName.key($0) } == [])
        #expect((400...600).contains(all.count))
        let expected = ["Spülmittel": "household", "Milch": "chilled", "Brot": "bakery", "Bananen": "produce", "Banane": "produce",
                        "Eier": "chilled", "Hackfleisch": "meat", "Reis": "pantry", "Zwiebeln": "produce",
                        "milk": "chilled", "bread": "bakery", "Zahnpasta": "care", "Mundwasser": "care"]
        for (name, key) in expected {
            #expect(ShoppingDictionary.bundled.builtinKey(forKey: ShoppingName.key(name)) == key, "\(name)")
        }
        #expect(ShoppingDictionary.bundled.builtinKey(forKey: ShoppingName.key("Kaffee")) != nil)
        #expect(ShoppingDictionary.bundled.builtinKey(forKey: ShoppingName.key("Sojasauce")) == nil)
    }

    @Test func builtinNames_germanInTests() {
        #expect(ShoppingBuiltinCategory.produce.localizedName == "Obst & Gemüse")
        #expect(ShoppingBuiltinCategory.allCases.map(\.rawValue)
                == ["produce", "bakery", "chilled", "meat", "frozen", "pantry", "snacks", "drinks", "household", "care"])
        #expect(ShoppingBuiltinCategory.otherName == "Sonstiges")
    }
}
