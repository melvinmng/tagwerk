import Foundation
import Testing
@testable import Tagwerk

/// EK1b and EK2a: the bulk actions of the shopping list menu name how many items they touch, and the confirmations use the
/// same words ("entfernen" for completed items, "leeren" for everything).
@MainActor
struct ShoppingBulkActionTextTests {
    @Test func removeCompletedTitle_carriesCount() {
        #expect(ShoppingListView.removeCompletedTitle(count: 5) == "Erledigte entfernen (5)")
        #expect(ShoppingListView.removeCompletedTitle(count: 1) == "Erledigte entfernen (1)")
    }

    @Test func removeCompletedTitle_withoutCompletedItems_hasNoCount() {
        // A "(0)" would read like a promise; the entry is greyed out instead.
        #expect(ShoppingListView.removeCompletedTitle(count: 0) == "Erledigte entfernen")
    }

    @Test func clearListTitle_carriesCountAndEllipsis() {
        #expect(ShoppingListView.clearListTitle(count: 17) == "Liste leeren (17) …")
    }

    @Test func clearListTitle_withoutItems_hasNoCount() {
        #expect(ShoppingListView.clearListTitle(count: 0) == "Liste leeren …")
    }

    @Test func confirmations_useTheWordsOfTheMenu() {
        #expect(ShoppingListView.removeCompletedQuestion(count: 5) == "5 erledigte Artikel entfernen?")
        #expect(ShoppingListView.clearListQuestion(count: 17) == "Gesamte Liste leeren? 17 Artikel werden gelöscht.")
        #expect(ShoppingListView.remindersNotice == "Sie verschwinden auch aus Apple Erinnerungen.")
    }

    @Test func removeCompletedCount_usesTheLargerOfTheTwoSources() {
        // The section "Erledigt" holds the last seven days; the total also counts older items. Right after a check-off the
        // total can lag behind the section, so the larger number counts.
        #expect(ShoppingListView.completedCount(total: 3, shown: 5) == 5)
        #expect(ShoppingListView.completedCount(total: 9, shown: 5) == 9)
        #expect(ShoppingListView.completedCount(total: 0, shown: 0) == 0)
    }
}
