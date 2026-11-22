import Foundation
import Testing
@testable import TagwerkCore

struct MarkdownTableTests {
    private static let one = "| A | B |\n|---|---|\n| 1 | 2 |"

    // MARK: Finding blocks

    @Test func blocks_findsTwoTablesWithLineRanges() {
        let text = "Intro\n\n| A | B |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |\n\nZwischen\n\n| X |\n|---|\n| y |\n"
        let blocks = MarkdownTable.blocks(in: text)
        #expect(blocks.count == 2)
        #expect(blocks[0].lines == 3...6)
        #expect(blocks[0].table.header == ["A", "B"])
        #expect(blocks[0].table.rows == [["1", "2"], ["3", "4"]])
        #expect(blocks[1].lines == 10...12)
        #expect(blocks[1].table.header == ["X"])
        #expect(blocks[1].table.rows == [["y"]])
    }

    @Test func blocks_skipsTableInCodeFence() {
        let text = "```\n| A | B |\n|---|---|\n| 1 | 2 |\n```\n\n| C |\n|---|\n| 3 |"
        let blocks = MarkdownTable.blocks(in: text)
        #expect(blocks.count == 1)
        #expect(blocks[0].table.header == ["C"])
        #expect(blocks[0].lines == 7...9)
    }

    @Test func blocks_needsSeparatorLine() {
        #expect(MarkdownTable.blocks(in: "| A | B |\n| 1 | 2 |").isEmpty)
        #expect(MarkdownTable.blocks(in: "Nur | ein | Text").isEmpty)
    }

    @Test func blocks_skipsTablesInsideQuotesAndLists() {
        let text = "> | A |\n> |---|\n> | 1 |\n\n- | B |\n  |---|\n  | 2 |\n\n| C |\n|---|\n| 3 |"
        let blocks = MarkdownTable.blocks(in: text)
        #expect(blocks.count == 1)
        #expect(blocks[0].table.header == ["C"])
    }

    @Test func blocks_tableDirectlyBehindParagraphLine() {
        // The parser reports the range of such a table from the first line of the paragraph; the block starts at its header.
        let blocks = MarkdownTable.blocks(in: "Text davor\n| A | B |\n|---|---|\n| 1 | 2 |")
        #expect(blocks.count == 1)
        #expect(blocks[0].lines == 2...4)
        #expect(blocks[0].table.header == ["A", "B"])
        let longer = MarkdownTable.blocks(in: "Eins\nZwei\nDrei\n| A | B |\n|---|---|")
        #expect(longer.first?.lines == 4...5)
        #expect(longer.first?.table.rows.isEmpty == true)
    }

    @Test func blocks_handlesCRLF() {
        let blocks = MarkdownTable.blocks(in: "Text\r\n\r\n| A | B |\r\n|---|---|\r\n| 1 | 2 |\r\n")
        #expect(blocks.count == 1)
        #expect(blocks[0].lines == 3...5)
        #expect(blocks[0].table.rows == [["1", "2"]])
    }

    // MARK: Parsing

    @Test func parse_alignments() {
        let blocks = MarkdownTable.blocks(in: "| A | B | C | D |\n|:--|:-:|--:|---|\n| 1 | 2 | 3 | 4 |")
        #expect(blocks.first?.table.alignments == [.left, .center, .right, .none])
    }

    @Test func parse_escapedPipeInCell() {
        let table = MarkdownTable.blocks(in: "| A | B |\n|---|---|\n| a \\| b | c |")[0].table
        #expect(table.rows == [["a | b", "c"]])
    }

    @Test func parse_keepsInlineMarkdownOfCells() {
        let table = MarkdownTable.blocks(in: "| **Titel** | [Link](https://example.com) |\n|---|---|\n| `code` | _kursiv_ |")[0].table
        #expect(table.header == ["**Titel**", "[Link](https://example.com)"])
        #expect(table.rows == [["`code`", "_kursiv_"]])
    }

    @Test func parse_tablesWithoutOuterPipesAndShortRows() {
        let table = MarkdownTable.blocks(in: "A | B | C\n--|--|--\n1 | 2\n4 | 5 | 6")[0].table
        #expect(table.header == ["A", "B", "C"])
        #expect(table.rows == [["1", "2", ""], ["4", "5", "6"]])
    }

    // MARK: Writing

    @Test func markdown_padsColumns() {
        var table = MarkdownTable(header: ["Name", "Menge"], alignments: [.none, .right], rows: [["Äpfel", "3"], ["Birnen", "12"]])
        #expect(table.markdown() == "| Name   | Menge |\n| ------ | ----: |\n| Äpfel  |     3 |\n| Birnen |    12 |")
        table.setAlignment(.center, column: 0)
        #expect(table.markdown().components(separatedBy: "\n")[1] == "| :----: | ----: |")
    }

    @Test func markdown_escapesPipeAndFlattensLineBreak() {
        let table = MarkdownTable(header: ["A", "B"], alignments: [.none, .none], rows: [["x|y", "eins\nzwei"]])
        let markdown = table.markdown()
        #expect(markdown.contains("x\\|y"))
        #expect(markdown.contains("eins zwei"))
        #expect(!markdown.contains("eins\nzwei"))
        #expect(markdown.components(separatedBy: "\n").count == 3)
    }

    @Test func roundTrip_parseMarkdownParse_isEqual() {
        let original = MarkdownTable(header: ["Spalte|eins", "**zwei**", ""], alignments: [.left, .center, .right],
                                     rows: [["a | b", "c", "ä"], ["", "", ""], ["`x`", "[l](https://e.com)", "9"]])
        let parsed = MarkdownTable.blocks(in: original.markdown())
        #expect(parsed.count == 1)
        #expect(parsed[0].table == original)
        #expect(MarkdownTable.blocks(in: parsed[0].table.markdown())[0].table == original)
    }

    @Test func empty_isThreeColumnsHeaderAndTwoRows() {
        let table = MarkdownTable.empty
        #expect(table.header.count == 3 && table.rows.count == 2)
        #expect(table.rows.allSatisfy { $0.count == 3 })
        #expect(MarkdownTable.blocks(in: table.markdown()).first?.table == table)
    }

    // MARK: Replacing

    @Test func replacing_touchesOnlyTheBlock() {
        let before = "Titel  \n\n  Absatz mit Leerzeichen \t\n\n"
        let after = "\n\n- [ ] Aufgabe\n```\n| code |\n```\nEnde ohne Umbruch"
        let text = before + Self.one + after
        var table = MarkdownTable.blocks(in: text)[0].table
        table.insertRow(at: 1)
        table.rows[1] = ["neu", "Zeile"]
        let result = MarkdownTable.replacing(blockAt: 0, with: table, in: text)
        #expect(result == before + table.markdown() + after)
        #expect(result.hasPrefix(before) && result.hasSuffix(after))
    }

    @Test func replacing_keepsCRLF() {
        let text = "Text\r\n\r\n| A | B |\r\n|---|---|\r\n| 1 | 2 |\r\n\r\nEnde"
        var table = MarkdownTable.blocks(in: text)[0].table
        table.insertRow(at: 1)
        let result = MarkdownTable.replacing(blockAt: 0, with: table, in: text)
        #expect(result.hasPrefix("Text\r\n\r\n| A "))
        #expect(!result.replacingOccurrences(of: "\r\n", with: "").contains("\n"))
        #expect(result.hasSuffix("\r\n\r\nEnde"))
    }

    @Test func replacing_secondTableLeavesFirstAlone() {
        let text = "| A |\n|---|\n| 1 |\n\n| B |\n|---|\n| 2 |\n"
        var table = MarkdownTable.blocks(in: text)[1].table
        table.header = ["Neu"]
        let result = MarkdownTable.replacing(blockAt: 1, with: table, in: text)
        #expect(result.hasPrefix("| A |\n|---|\n| 1 |\n\n"))
        #expect(MarkdownTable.blocks(in: result).map(\.table.header) == [["A"], ["Neu"]])
        #expect(result.hasSuffix("| 2 |\n") || result.hasSuffix("| 2   |\n") || result.hasSuffix("\n"))
    }

    @Test func replacing_unknownIndexChangesNothing() {
        #expect(MarkdownTable.replacing(blockAt: 3, with: .empty, in: Self.one) == Self.one)
        #expect(MarkdownTable.replacing(blockAt: -1, with: .empty, in: Self.one) == Self.one)
    }

    // MARK: Editing

    @Test func insertColumn_stopsAtEight() {
        var table = MarkdownTable.empty
        for _ in 0..<10 { table.insertColumn(at: 0) }
        #expect(table.header.count == MarkdownTable.maximumColumns)
        #expect(table.alignments.count == MarkdownTable.maximumColumns)
        #expect(table.rows.allSatisfy { $0.count == MarkdownTable.maximumColumns })
    }

    @Test func insertColumn_atIndexKeepsOtherCells() {
        var table = MarkdownTable(header: ["A", "B"], alignments: [.left, .right], rows: [["1", "2"]])
        table.insertColumn(at: 1)
        #expect(table.header == ["A", "", "B"])
        #expect(table.alignments == [.left, .none, .right])
        #expect(table.rows == [["1", "", "2"]])
    }

    @Test func removeColumn_keepsLast() {
        var table = MarkdownTable(header: ["A", "B"], alignments: [.left, .right], rows: [["1", "2"]])
        table.removeColumn(at: 0)
        #expect(table.header == ["B"] && table.alignments == [.right] && table.rows == [["2"]])
        table.removeColumn(at: 0)
        #expect(table.header == ["B"])
    }

    @Test func removeRow_neverRemovesHeader() {
        var table = MarkdownTable(header: ["A"], alignments: [.none], rows: [["1"], ["2"]])
        table.removeRow(at: 0)
        #expect(table.rows == [["2"]])
        table.removeRow(at: 0)
        table.removeRow(at: 0)
        #expect(table.rows.isEmpty)
        #expect(table.header == ["A"])
    }

    @Test func insertRow_addsEmptyRowOfSameWidth() {
        var table = MarkdownTable(header: ["A", "B"], alignments: [.none, .none], rows: [["1", "2"]])
        table.insertRow(at: 0)
        table.insertRow(at: 99)
        #expect(table.rows == [["", ""], ["1", "2"], ["", ""]])
    }

    @Test func moveRow() {
        var table = MarkdownTable(header: ["A"], alignments: [.none], rows: [["1"], ["2"], ["3"]])
        table.moveRow(from: 0, to: 2)
        #expect(table.rows == [["2"], ["3"], ["1"]])
        table.moveRow(from: 2, to: 0)
        #expect(table.rows == [["1"], ["2"], ["3"]])
        table.moveRow(from: 5, to: 0)
        #expect(table.rows == [["1"], ["2"], ["3"]])
    }

    // MARK: Cursor

    @Test func blockIndex_forCursorLine() {
        let text = "Text\n\n| A |\n|---|\n| 1 |\n\nMitte\n\n| B |\n|---|\n| 2 |"
        #expect(MarkdownTable.blockIndex(containingLine: 1, in: text) == nil)
        #expect(MarkdownTable.blockIndex(containingLine: 3, in: text) == 0)
        #expect(MarkdownTable.blockIndex(containingLine: 5, in: text) == 0)
        #expect(MarkdownTable.blockIndex(containingLine: 6, in: text) == nil)
        #expect(MarkdownTable.blockIndex(containingLine: 11, in: text) == 1)
        #expect(MarkdownTable.blockIndex(containingLine: 99, in: text) == nil)
    }

    @Test func index_inLink() {
        #expect(MarkdownTable.index(inLink: "tagwerk-table:0") == 0)
        #expect(MarkdownTable.index(inLink: "TAGWERK-TABLE:12") == 12)
        for url in ["tagwerk-table:", "tagwerk-table:-1", "tagwerk-table:1x", "tagwerk-table:١", "tagwerk-edit:1", "https://example.com", "tagwerk-table:1234567"] {
            #expect(MarkdownTable.index(inLink: url) == nil, "\(url)")
        }
    }
}
