import Foundation
import Testing
@testable import TagwerkCore

struct ShoppingInputParserTests {
    @Test func key_lowercasesTrimsCollapsesAndFolds() {
        #expect(ShoppingName.key("  Grüner   Tee ") == "gruner tee")
        #expect(ShoppingName.key("Crème fraîche") == "creme fraiche")
        #expect(ShoppingName.key("Banane") != ShoppingName.key("Bananen"))  // no singular/plural folding
        #expect(ShoppingName.key("MILCH\n") == "milch")
    }

    @Test func parse_splitsOnCommaSemicolonNewlineAndUnd() {
        #expect(ShoppingInputParser.parse("Kaffee, Reis; Eier\nSalz und Pfeffer and milk").map(\.name)
                == ["Kaffee", "Reis", "Eier", "Salz", "Pfeffer", "Milk"])
        #expect(ShoppingInputParser.parse("Butter UND Käse").map(\.name) == ["Butter", "Käse"])
    }

    @Test func parse_doesNotSplitInsideWords() {
        #expect(ShoppingInputParser.parse("Mundwasser, Sandwich").map(\.name) == ["Mundwasser", "Sandwich"])
        #expect(ShoppingInputParser.parse("Rund um Käse").map(\.name) == ["Rund um Käse"])
    }

    @Test func parse_quantities() {
        #expect(ShoppingInputParser.parse("2 Zwiebeln") == [ParsedItem(name: "Zwiebeln", quantity: "2")])
        #expect(ShoppingInputParser.parse("500 g Hackfleisch") == [ParsedItem(name: "Hackfleisch", quantity: "500 g")])
        #expect(ShoppingInputParser.parse("zwei Packungen Hafermilch") == [ParsedItem(name: "Hafermilch", quantity: "2 Packungen")])
        #expect(ShoppingInputParser.parse("three cans tomatoes") == [ParsedItem(name: "Tomatoes", quantity: "3 cans")])
        #expect(ShoppingInputParser.parse("eine Gurke") == [ParsedItem(name: "Gurke", quantity: "1")])
        #expect(ShoppingInputParser.parse("Zwölf Eier") == [ParsedItem(name: "Eier", quantity: "12")])
        #expect(ShoppingInputParser.parse("1 KG  rote Zwiebeln") == [ParsedItem(name: "Rote Zwiebeln", quantity: "1 KG")])
    }

    @Test func parse_unitWithoutNumber_staysInTheName() {
        #expect(ShoppingInputParser.parse("Packung Nudeln") == [ParsedItem(name: "Packung Nudeln", quantity: nil)])
    }

    @Test func parse_capitalizesFirstLetterOnly_andCutsAt80() {
        #expect(ShoppingInputParser.parse("grüner tee").first?.name == "Grüner tee")
        #expect(ShoppingInputParser.parse(String(repeating: "a", count: 100)).first?.name.count == 80)
    }

    @Test func parse_separatorsOnly_isEmpty() {
        #expect(ShoppingInputParser.parse(" , ; und \n ").isEmpty)
        #expect(ShoppingInputParser.parse("").isEmpty)
        #expect(ShoppingInputParser.parse("und").isEmpty)
    }

    @Test func parse_quantityWithoutName_isName() {
        #expect(ShoppingInputParser.parse("2") == [ParsedItem(name: "2", quantity: nil)])
        #expect(ShoppingInputParser.parse("500 g") == [ParsedItem(name: "500 g", quantity: nil)])
    }

    @Test func parseAll_keepsTwentyAndCountsTheRest() {
        let result = ShoppingInputParser.parseAll((1...23).map { "Artikel\($0)" }.joined(separator: ","))
        #expect(result.items.count == 20 && result.droppedCount == 3)
        #expect(ShoppingInputParser.parseAll("Kaffee").droppedCount == 0)
    }

    @Test func quantityFromNotes_firstLineAndLongFlag() {
        #expect(ShoppingItem.quantity(fromNotes: nil) == (nil, false))
        #expect(ShoppingItem.quantity(fromNotes: "  \n") == (nil, false))
        #expect(ShoppingItem.quantity(fromNotes: " 2 Packungen \n") == ("2 Packungen", false))
        #expect(ShoppingItem.quantity(fromNotes: "2\nnur die mit Schraubverschluss") == ("2", true))
        #expect(ShoppingItem.quantity(fromNotes: "\nnur Bio") == (nil, true))
    }
}
