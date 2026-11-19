import Foundation
import Testing
@testable import TagwerkCore

/// The names Siri may speak for the shopping shortcut: own history first, then common terms.
struct ShoppingSuggestionsTests {
    private func date(_ day: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(day) * 86_400) }

    private func entry(_ name: String, _ day: Int?) -> ShoppingHistoryEntry {
        ShoppingHistoryEntry(name: name, date: day.map(date))
    }

    @Test func ownNamesComeFirst_thenCommonTerms() {
        let result = ShoppingSuggestions.articles(history: [entry("Hafermilch", 1)], commonTerms: ["Milch", "Brot"], limit: 10)
        #expect(result == ["Hafermilch", "Milch", "Brot"])
    }

    @Test func ownNames_orderedByFrequencyThenRecency() {
        let history = [entry("Eier", 1), entry("Brot", 5), entry("Eier", 2), entry("Quark", 9), entry("Käse", 3)]
        let result = ShoppingSuggestions.articles(history: history, commonTerms: [], limit: 10)
        // Eier twice; the others once, newest first.
        #expect(result == ["Eier", "Quark", "Brot", "Käse"])
    }

    @Test func ownNames_equalCountAndDate_orderedByName() {
        let history = [entry("Zimt", 4), entry("Anis", 4), entry("Mehl", nil), entry("Reis", nil)]
        #expect(ShoppingSuggestions.articles(history: history, commonTerms: [], limit: 10) == ["Anis", "Zimt", "Mehl", "Reis"])
    }

    @Test func dedupe_ignoresCaseAndDiacritics_keepsNewestSpelling() {
        let history = [entry("äpfel", 1), entry("Äpfel", 7), entry("APFEL", 3), entry("Milch", 2)]
        let result = ShoppingSuggestions.articles(history: history, commonTerms: [], limit: 10)
        #expect(result == ["Äpfel", "Milch"])
    }

    @Test func commonTerms_alreadyOwned_areSkipped_andDeduped() {
        let result = ShoppingSuggestions.articles(history: [entry("milch", 1)], commonTerms: ["Milch", "Käse", "KASE", "Brot"],
                                                  limit: 10)
        #expect(result == ["milch", "Käse", "Brot"])
    }

    @Test func blankNames_areIgnored() {
        let result = ShoppingSuggestions.articles(history: [entry("  ", 1), entry("", 2), entry(" Brot ", 3)],
                                                  commonTerms: [" ", "Käse"], limit: 10)
        #expect(result == ["Brot", "Käse"])
    }

    @Test func limit_cutsTheTail_ownNamesSurviveFirst() {
        let history = (0..<5).map { entry("Eigen\($0)", $0) }
        let result = ShoppingSuggestions.articles(history: history, commonTerms: ["A", "B", "C"], limit: 7)
        #expect(result.count == 7)
        #expect(result.prefix(5).allSatisfy { $0.hasPrefix("Eigen") })
        #expect(result.suffix(2) == ["A", "B"])
    }

    @Test func limit_defaultIs150() {
        let history = (0..<400).map { entry("Artikel \($0)", $0) }
        #expect(ShoppingSuggestions.articles(history: history, commonTerms: ["Milch"]).count == 150)
        #expect(ShoppingSuggestions.defaultLimit == 150)
    }

    @Test func emptyInput_givesNothing() {
        #expect(ShoppingSuggestions.articles(history: [], commonTerms: [], limit: 10).isEmpty)
        #expect(ShoppingSuggestions.articles(history: [entry("Brot", 1)], commonTerms: [], limit: 0).isEmpty)
    }

    // MARK: Common terms

    @Test func commonTerms_everyTermIsInTheOfflineDictionary() {
        let entries = ShoppingDictionary.bundledEntries
        let terms = Set(entries.values.flatMap { $0 })
        for term in ShoppingSuggestions.commonTerms(preferEnglish: false) + ShoppingSuggestions.commonTerms(preferEnglish: true) {
            #expect(terms.contains(ShoppingName.key(term)), "\(term) is not a dictionary term")
        }
    }

    @Test func commonTerms_languageDecidesWhichListComesFirst_andNoDuplicates() {
        let german = ShoppingSuggestions.commonTerms(preferEnglish: false)
        let english = ShoppingSuggestions.commonTerms(preferEnglish: true)
        #expect(german.first == "Milch" && english.first == "Milk")
        #expect(german.contains("Milk") && english.contains("Milch"))
        for list in [german, english] {
            let keys = list.map(ShoppingName.key)
            #expect(Set(keys).count == keys.count)
        }
    }

    @Test func commonTerms_haveProperSpelling() {
        let german = ShoppingSuggestions.commonTerms(preferEnglish: false)
        #expect(german.contains("Käse") && german.contains("Äpfel") && german.contains("Öl"))
        #expect(german.allSatisfy { $0.first?.isUppercase == true })
    }
}
