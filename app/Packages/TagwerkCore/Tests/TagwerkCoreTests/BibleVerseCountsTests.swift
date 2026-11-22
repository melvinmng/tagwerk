import CryptoKit
import Foundation
import Testing
@testable import TagwerkCore

/// The verse table (BS1). Every expected number comes from `docs/research/2026-11-20-schlachter-2000-verszahlen.md`
/// (sections "Tabelle" and "Unterschiede zur englischen Zählung"); the English figures are KJV 1769 from the same
/// document. The table is provisional until the Schlachter 2000 is checked against the printed edition.
struct BibleVerseCountsTests {
    // MARK: Structure

    @Test func table_has66Books() {
        #expect(BibleVerseCounts.bookCount == 66)
    }

    @Test func table_totalChapterCountMatchesSource() {
        #expect((1...66).map(BibleVerseCounts.chapterCount(book:)).reduce(0, +) == 1189)
    }

    @Test func table_totalVerseCountMatchesSource() {
        let total = (1...66).flatMap(BibleVerseCounts.versesPerChapter(book:)).reduce(0, +)
        #expect(total == 31_172)
        #expect((1...39).flatMap(BibleVerseCounts.versesPerChapter(book:)).reduce(0, +) == 23_215)
        #expect((40...66).flatMap(BibleVerseCounts.versesPerChapter(book:)).reduce(0, +) == 7_957)
    }

    @Test func table_noChapterIsEmpty() {
        for book in 1...66 {
            let chapters = BibleVerseCounts.versesPerChapter(book: book)
            #expect(!chapters.isEmpty && chapters.allSatisfy { $0 >= 1 }, "book \(book)")
        }
    }

    @Test func table_matchesBibleBooksOrder() {
        #expect(BibleBooks.all.map(\.number) == Array(1...66))
        // Chapters per book in canon order, from the document.
        let chapterCounts = [50, 40, 27, 36, 34, 24, 21, 4, 31, 24, 22, 25, 29, 36, 10, 13, 10, 42, 150, 31, 12, 8, 66, 52, 5, 48,
                             12, 14, 4, 9, 1, 4, 7, 3, 3, 3, 2, 14, 3, 28, 16, 24, 21, 28, 16, 16, 13, 6, 6, 4, 4, 5, 3, 6, 4, 3,
                             1, 13, 5, 5, 3, 5, 1, 1, 1, 22]
        #expect(BibleBooks.all.map { BibleVerseCounts.chapterCount(book: $0.number) } == chapterCounts)
        #expect(BibleBooks.book(matching: "Psalmen").map { BibleVerseCounts.chapterCount(book: $0.number) } == 150)
        #expect(BibleBooks.book(matching: "Römer").map { BibleVerseCounts.chapterCount(book: $0.number) } == 16)
    }

    // MARK: Differences to the English numbering (KJV 1769 in the document)

    @Test func psalms_titleCountsAsAVerse() {
        let psalms = 19
        // German count (title is verse 1 or 1–2) against KJV: Psalm 3 has 9 and 8, 18 has 51 and 50, 51 has 21 and 19, 60 has 14 and 12.
        #expect(BibleVerseCounts.verseCount(book: psalms, chapter: 3) == 9)
        #expect(BibleVerseCounts.verseCount(book: psalms, chapter: 18) == 51)
        #expect(BibleVerseCounts.verseCount(book: psalms, chapter: 51) == 21)
        #expect(BibleVerseCounts.verseCount(book: psalms, chapter: 60) == 14)
        // Psalms without a title keep the count of the English numbering.
        #expect(BibleVerseCounts.verseCount(book: psalms, chapter: 119) == 176)
        #expect(BibleVerseCounts.verseCount(book: psalms, chapter: 150) == 6)
    }

    @Test func joel_chapterCountFollowsGermanNumbering() {
        let joel = 29
        #expect(BibleVerseCounts.chapterCount(book: joel) == 4, "KJV has 3 chapters")
        #expect(BibleVerseCounts.versesPerChapter(book: joel) == [20, 27, 5, 21])
        #expect(BibleVerseCounts.verseCount(book: joel, chapter: 4) == 21, "last chapter")
    }

    @Test func malachi_chapterCountFollowsGermanNumbering() {
        let malachi = 39
        #expect(BibleVerseCounts.chapterCount(book: malachi) == 3, "KJV has 4 chapters")
        #expect(BibleVerseCounts.versesPerChapter(book: malachi) == [14, 17, 24])
        #expect(BibleVerseCounts.verseCount(book: malachi, chapter: 3) == 24, "last chapter")
    }

    @Test func lastChaptersOfSeveralBooks() {
        #expect(BibleVerseCounts.verseCount(book: 45, chapter: 3) == 31)
        #expect(BibleVerseCounts.verseCount(book: 45, chapter: 16) == 27)
        #expect(BibleVerseCounts.verseCount(book: 43, chapter: 21) == 25)
        #expect(BibleVerseCounts.verseCount(book: 66, chapter: 22) == 21)
    }

    // MARK: Rules

    @Test func isValid_rejectsVerseBeyondChapter() {
        #expect(BibleVerseCounts.isValid(book: 45, chapter: 3, verse: 31))
        #expect(BibleVerseCounts.isValid(book: 45, chapter: 3, verse: 1))
        #expect(!BibleVerseCounts.isValid(book: 45, chapter: 3, verse: 32))
        #expect(!BibleVerseCounts.isValid(book: 45, chapter: 3, verse: 0))
        #expect(!BibleVerseCounts.isValid(book: 19, chapter: 51, verse: 22))
        #expect(BibleVerseCounts.isValid(book: 19, chapter: 51, verse: 21))
    }

    @Test func isValid_rejectsChapterBeyondBook() {
        #expect(BibleVerseCounts.isValid(book: 45, chapter: 16, verse: 27))
        #expect(!BibleVerseCounts.isValid(book: 45, chapter: 17, verse: 1))
        #expect(!BibleVerseCounts.isValid(book: 45, chapter: 0, verse: 1))
        #expect(!BibleVerseCounts.isValid(book: 39, chapter: 4, verse: 1), "Maleachi ends at chapter 3")
    }

    @Test func unknownBook_isZero() {
        for book in [0, -1, 67, 1000] {
            #expect(BibleVerseCounts.chapterCount(book: book) == 0)
            #expect(BibleVerseCounts.verseCount(book: book, chapter: 1) == 0)
            #expect(!BibleVerseCounts.isValid(book: book, chapter: 1, verse: 1))
        }
        #expect(BibleVerseCounts.verseCount(book: 45, chapter: 0) == 0)
        #expect(BibleVerseCounts.verseCount(book: 45, chapter: 99) == 0)
    }

    // MARK: File

    @Test func resource_checksumMatchesDocumentation() throws {
        let data = try #require(BibleVerseCounts.resourceData)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #expect(digest == "037874dfabbd3694ad9b3f3384653f1c7c2ac8ec7b876d8f51a1e614b9e37e08")
    }
}
