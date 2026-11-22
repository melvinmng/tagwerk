import Foundation
import Testing
@testable import TagwerkCore

/// Passages as numbers and the next verse to read (BS2). Book bounds come from `BibleVerseCounts`, never from fixed numbers.
struct BiblePassageTests {
    private let romans = 45
    private func ref(_ chapter: Int, _ verse: Int) -> BibleReference { BibleReference(chapter: chapter, verse: verse) }

    // MARK: Parsing

    @Test func parse_singleChapterRange() {
        #expect(BiblePassage.parse("3,21-31") == BiblePassage(start: ref(3, 21), end: ref(3, 31)))
    }

    @Test func parse_acrossChapters() {
        #expect(BiblePassage.parse("3,21–4,9") == BiblePassage(start: ref(3, 21), end: ref(4, 9)))
        #expect(BiblePassage.parse("3,21-4,9") == BiblePassage(start: ref(3, 21), end: ref(4, 9)))
    }

    @Test func parse_startOnly() {
        #expect(BiblePassage.parse("3,21") == BiblePassage(start: ref(3, 21), end: nil))
        #expect(BiblePassage.parse("3,21–") == BiblePassage(start: ref(3, 21), end: nil))
    }

    @Test func parse_withSpacesAndHyphen() {
        #expect(BiblePassage.parse("3, 21 - 31") == BiblePassage(start: ref(3, 21), end: ref(3, 31)))
        #expect(BiblePassage.parse("  3,21 – 4, 9\n") == BiblePassage(start: ref(3, 21), end: ref(4, 9)))
    }

    @Test func parse_garbage_isNil() {
        for text in ["", "  ", "Kap. 3", "3, 21 bis Ende", "abc", "3", "3,0", "0,5", "3,x", "3:21-31", "3,21-31-40",
                     "3,31-21", "3,21-4", "3,21-3,5", "3,1234", "-5", ",5"] {
            #expect(BiblePassage.parse(text) == nil, "\(text) should stay free text")
        }
    }

    @Test func text_roundTrips() {
        let range = BiblePassage(start: ref(3, 21), end: ref(3, 31))
        let across = BiblePassage(start: ref(3, 21), end: ref(4, 9))
        let open = BiblePassage(start: ref(3, 21))
        #expect(range.text() == "3,21–31" && across.text() == "3,21–4,9" && open.text() == "3,21–")
        #expect(BiblePassage.parse(range.text()) == range && BiblePassage.parse(across.text()) == across)
        #expect(BiblePassage.parse(open.text()) == open)
    }

    @Test func text_endsWhereItStarts_isOneVerse() {
        #expect(BiblePassage(start: ref(3, 21), end: ref(3, 21)).text() == "3,21")
    }

    @Test func text_openEnd() {
        #expect(BiblePassage(start: ref(3, 21), end: nil).text() == "3,21–")
    }

    // MARK: Validity against the table

    @Test func isValid_checksStartAndEndAgainstTheBook() {
        let last = BibleVerseCounts.verseCount(book: romans, chapter: 3)
        #expect(BiblePassage(start: ref(3, 1), end: ref(3, last)).isValid(in: romans))
        #expect(BiblePassage(start: ref(3, 1)).isValid(in: romans))
        #expect(!BiblePassage(start: ref(3, 1), end: ref(3, last + 1)).isValid(in: romans))
        #expect(!BiblePassage(start: ref(3, last + 1)).isValid(in: romans))
        #expect(!BiblePassage(start: ref(BibleVerseCounts.chapterCount(book: romans) + 1, 1)).isValid(in: romans))
        #expect(!BiblePassage(start: ref(3, 5), end: ref(3, 4)).isValid(in: romans), "an end before the start is not a passage")
        #expect(!BiblePassage(start: ref(1, 1)).isValid(in: 0))
    }

    // MARK: Next verse

    @Test func next_withinChapter() {
        #expect(BibleProgress.next(after: ref(3, 20), book: romans) == .start(ref(3, 21)))
    }

    @Test func next_chapterEnd_goesToNextChapter() {
        let last = BibleVerseCounts.verseCount(book: romans, chapter: 3)
        #expect(BibleProgress.next(after: ref(3, last), book: romans) == .start(ref(4, 1)))
        #expect(BibleProgress.next(after: ref(3, last - 1), book: romans) == .start(ref(3, last)))
    }

    @Test func next_bookEnd_isFinished() {
        let lastChapter = BibleVerseCounts.chapterCount(book: romans)
        let lastVerse = BibleVerseCounts.verseCount(book: romans, chapter: lastChapter)
        let end = ref(lastChapter, lastVerse)
        #expect(BibleProgress.next(after: end, book: romans) == .bookFinished(last: end))
    }

    @Test func next_endOutsideTable_countsAsTheNearestVerseInside() {
        let lastChapter = BibleVerseCounts.chapterCount(book: romans)
        let lastVerse = BibleVerseCounts.verseCount(book: romans, chapter: lastChapter)
        #expect(BibleProgress.next(after: ref(lastChapter + 3, 1), book: romans) == .bookFinished(last: ref(lastChapter, lastVerse)))
        #expect(BibleProgress.next(after: ref(3, 999), book: romans) == .start(ref(4, 1)))
        #expect(BibleProgress.next(after: ref(0, 0), book: romans) == .start(ref(1, 2)))
    }

    @Test func next_unknownBook_startsAtTheBeginning() {
        #expect(BibleProgress.next(after: ref(2, 3), book: 0) == .start(ref(1, 1)))
        #expect(BibleProgress.next(after: ref(2, 3), book: 67) == .start(ref(1, 1)))
    }

    // MARK: Suggestion

    @Test func suggestion_firstSession_isOneOne() {
        #expect(BibleProgress.suggestion(lastStart: nil, lastEnd: nil, book: romans) == .start(ref(1, 1)))
    }

    @Test func suggestion_afterTheEndOfTheLastSession() {
        #expect(BibleProgress.suggestion(lastStart: ref(3, 1), lastEnd: ref(3, 20), book: romans) == .start(ref(3, 21)))
        #expect(BibleProgress.suggestion(lastStart: nil, lastEnd: ref(3, 20), book: romans) == .start(ref(3, 21)))
    }

    @Test func suggestion_openSession_continuesAtItsStart() {
        #expect(BibleProgress.suggestion(lastStart: ref(3, 21), lastEnd: nil, book: romans) == .start(ref(3, 21)))
    }

    @Test func suggestion_startOutsideTable_isOneOne() {
        #expect(BibleProgress.suggestion(lastStart: ref(99, 1), lastEnd: nil, book: romans) == .start(ref(1, 1)))
    }

    @Test func suggestion_bookFinished() {
        let lastChapter = BibleVerseCounts.chapterCount(book: romans)
        let lastVerse = BibleVerseCounts.verseCount(book: romans, chapter: lastChapter)
        let end = ref(lastChapter, lastVerse)
        #expect(BibleProgress.suggestion(lastStart: ref(lastChapter, 1), lastEnd: end, book: romans) == .bookFinished(last: end))
    }

    // MARK: Default end

    @Test func defaultEnd_isChapterEnd() {
        let last = BibleVerseCounts.verseCount(book: romans, chapter: 3)
        #expect(BibleProgress.defaultEnd(start: ref(3, 21), chosenEnd: nil, book: romans) == ref(3, last))
    }

    @Test func defaultEnd_chosenEndWins() {
        #expect(BibleProgress.defaultEnd(start: ref(3, 21), chosenEnd: ref(4, 9), book: romans) == ref(4, 9))
    }

    @Test func defaultEnd_chosenEndBeforeStart_isIgnored() {
        let last = BibleVerseCounts.verseCount(book: romans, chapter: 3)
        #expect(BibleProgress.defaultEnd(start: ref(3, 21), chosenEnd: ref(3, 5), book: romans) == ref(3, last))
    }

    @Test func defaultEnd_unknownChapter_endsWhereItStarts() {
        #expect(BibleProgress.defaultEnd(start: ref(99, 4), chosenEnd: nil, book: romans) == ref(99, 4))
    }

    // MARK: Session heading in the note

    @Test func replacingSessionHeading_completesTheLineOfTheStart() {
        let text = "Römer\n\n\n18.11.2026 · 1,1–\n\nGedanken\n\n19.11.2026 · 3,21–\n\nBeobachtung\n"
        let result = BibleStudyTemplate.replacingSessionHeading(in: text, dateText: "19.11.2026", oldPassage: "3,21–", newPassage: "3,21–26")
        #expect(result == "Römer\n\n\n18.11.2026 · 1,1–\n\nGedanken\n\n19.11.2026 · 3,21–26\n\nBeobachtung\n")
    }

    @Test func replacingSessionHeading_takesTheLastMatchingLine() {
        let text = "Römer\n\n19.11.2026 · 3,21–\n\nA\n\n19.11.2026 · 3,21–\n\nB\n"
        let result = BibleStudyTemplate.replacingSessionHeading(in: text, dateText: "19.11.2026", oldPassage: "3,21–", newPassage: "3,21–31")
        #expect(result == "Römer\n\n19.11.2026 · 3,21–\n\nA\n\n19.11.2026 · 3,21–31\n\nB\n")
    }

    @Test func replacingSessionHeading_withoutPassage_matchesTheBareDate() {
        let text = "Römer\n\n19.11.2026\n\nB\n"
        let result = BibleStudyTemplate.replacingSessionHeading(in: text, dateText: "19.11.2026", oldPassage: "", newPassage: "3,21–31")
        #expect(result == "Römer\n\n19.11.2026 · 3,21–31\n\nB\n")
    }

    @Test func replacingSessionHeading_changedLine_leavesTheTextAlone() {
        let text = "Römer\n\n19.11.2026 · Römer 3 gelesen\n\nB\n"
        #expect(BibleStudyTemplate.replacingSessionHeading(in: text, dateText: "19.11.2026", oldPassage: "3,21–", newPassage: "3,21–31") == text)
        // A line that only starts like the heading is not the heading.
        let longer = "Römer\n\n19.11.2026 · 3,21–31 und mehr\n"
        #expect(BibleStudyTemplate.replacingSessionHeading(in: longer, dateText: "19.11.2026", oldPassage: "3,21–31", newPassage: "3,21–4,9") == longer)
    }

    @Test func dateText_isAFixedDayFormat() {
        #expect(BibleStudyTemplate.dateText(PlanDay(year: 2026, month: 11, day: 9)) == "09.11.2026")
        #expect(BibleStudyTemplate.dateText(PlanDay(year: 2027, month: 1, day: 31)) == "31.01.2027")
    }
}
