import Foundation
import Testing
@testable import TagwerkCore

struct BibleBooksTests {
    @Test func canonHas66BooksInOrder() {
        #expect(BibleBooks.all.count == 66)
        #expect(BibleBooks.all.map(\.number) == Array(1...66))
        #expect(BibleBooks.all.first?.german == "1. Mose" && BibleBooks.all.last?.german == "Offenbarung")
        #expect(BibleBooks.all.filter(\.isOldTestament).count == 39)
        #expect(Set(BibleBooks.all.map(\.german)).count == 66 && Set(BibleBooks.all.map(\.english)).count == 66)
    }

    @Test func matching_exactNamesAndSpellings() {
        #expect(BibleBooks.book(matching: "Römer")?.english == "Romans")
        #expect(BibleBooks.book(matching: "Roemer")?.german == "Römer")
        #expect(BibleBooks.book(matching: "römer ")?.german == "Römer")
        #expect(BibleBooks.book(matching: "1. Korinther")?.number == 46)
        #expect(BibleBooks.book(matching: "1.Korinther")?.number == 46)
        #expect(BibleBooks.book(matching: "1 Kor")?.number == 46)
        #expect(BibleBooks.book(matching: "2 corinthians")?.number == 47)
        #expect(BibleBooks.book(matching: "Matthäus")?.number == 40)
        #expect(BibleBooks.book(matching: "Hebraer")?.german == "Hebräer")
    }

    @Test func matching_abbreviationsBeatPrefixes() {
        #expect(BibleBooks.book(matching: "Phil")?.german == "Philipper")
        #expect(BibleBooks.book(matching: "Phlm")?.german == "Philemon")
        #expect(BibleBooks.book(matching: "Joh")?.german == "Johannes")
        #expect(BibleBooks.book(matching: "1 Joh")?.german == "1. Johannes")
        #expect(BibleBooks.book(matching: "Offenb")?.german == "Offenbarung")
    }

    @Test func matching_ambiguousOrUnknownIsNil() {
        #expect(BibleBooks.book(matching: "Jo") == nil)
        #expect(BibleBooks.book(matching: "Jon")?.german == "Jona")
        #expect(BibleBooks.book(matching: "") == nil)
        #expect(BibleBooks.book(matching: "Kochbuch") == nil)
        #expect(BibleBooks.book(matching: "1 K") == nil)
    }

    @Test func keyRoundTrip() {
        #expect(BibleBooks.book(key: "45")?.german == "Römer")
        #expect(BibleBooks.book(key: "x") == nil && BibleBooks.book(number: 67) == nil)
        #expect(BibleBooks.all[44].key == "45")
    }

    @Test func nameFollowsTheLocale() throws {
        let romans = try #require(BibleBooks.book(number: 45))
        #expect(romans.name(locale: Locale(identifier: "de_DE")) == "Römer")
        #expect(romans.name(locale: Locale(identifier: "en_US")) == "Romans")
    }
}

struct BibleStudyTemplateTests {
    private let german = Locale(identifier: "de_DE")

    @Test func bookNoteStartsWithTheNameAndHasThreeSections() throws {
        let romans = try #require(BibleBooks.book(number: 45))
        let text = BibleStudyTemplate.text(book: romans, locale: german)
        #expect(text.hasPrefix("Römer\n"))
        #expect(text.contains("Generelle Gedanken") && text.contains("Action Items") && text.hasSuffix("Notizen\n\n"))
        #expect(NoteText.title(text) == "Römer")
    }

    @Test func appendingSession_addsADatedSectionAtTheEnd() {
        let result = BibleStudyTemplate.appendingSession(to: "Römer\n\nNotizen\n\n3,23: Gnade\n\n", dateText: "19.11.2026", passage: " 3,21-31 ")
        #expect(result == "Römer\n\nNotizen\n\n3,23: Gnade\n\n19.11.2026 · 3,21-31\n\n")
        #expect(BibleStudyTemplate.appendingSession(to: "A", dateText: "19.11.2026", passage: "") == "A\n\n19.11.2026\n\n")
    }
}
