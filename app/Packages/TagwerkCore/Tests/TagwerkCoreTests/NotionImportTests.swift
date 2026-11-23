import Foundation
import Testing
@testable import TagwerkCore

/// All texts here are invented; no real diary content is used.
enum NotionFixtures {
    static let id1 = "0123456789abcdef0123456789abcdef"
    static let id2 = "fedcba9876543210fedcba9876543210"
    static let id3 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    static let id4 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    static let id5 = "cccccccccccccccccccccccccccccccc"

    static let resource = "📓 Mein Tagebuch mit Gott (https://www.notion.so/Mein-Tagebuch-mit-Gott-1111)"
    static let otherResource = "📚 Rezepte (https://www.notion.so/Rezepte-2222)"

    static func page(title: String, resource: String? = resource, created: String? = nil, body: String) -> String {
        var text = "# \(title)\n\n"
        if let resource { text += "🗄️ Resource / FACH: \(resource)\n" }
        if let created { text += "Created time: \(created)\n" }
        text += "Art der Notiz: Normale Notiz\n\n" + body
        return text
    }

    static let body = """
    ## ALLGEMEINE STIMMUNG

    > Wie geht es mir im Moment grundsätzlich?

    Ruhig und dankbar.

    ## HAUPTERLEBNISSE DES HEUTIGEN TAGES

    - Spaziergang am Fluss
    - **Gespräch** mit [Anna](Anna%20abc.md)

    ## TAGEBUCH:

    Heute war ein guter Tag.
    Zweite Zeile.
    """

    static func files(extra: [NotionExportFile] = []) -> [NotionExportFile] {
        [NotionExportFile(name: "Test 16.03.2024 \(id1).md",
                          content: page(title: "16.03.2024", created: "March 16, 2024 9:12 PM", body: body)),
         // Typo in the title: "05.05." instead of "05.04."; the creation time decides.
         NotionExportFile(name: "05.05.2024 \(id2).md",
                          content: page(title: "05.05.2024", created: "April 5, 2024 7:30 PM", body: "## TAGEBUCH:\n\nTypo-Tag.")),
         // Created 23:20 UTC is 00:20 the next day in Berlin, which still counts for the day before.
         NotionExportFile(name: "Tagebuch mit Gott (2025-12-09) \(id3).md",
                          content: page(title: "Tagebuch mit Gott (2025-12-09)", created: "December 9, 2025 11:20 PM", body: "## TAGEBUCH:\n\nWinter.")),
         NotionExportFile(name: "Rezept \(id4).md", content: page(title: "Kuchen", resource: otherResource, created: "May 1, 2024 8:00 AM", body: "Mehl.")),
         NotionExportFile(name: "Ohne Datum \(id5).md", content: page(title: "Ohne Datum", body: "Kein Datum."))] + extra
    }
}

struct NotionCSVTests {
    @Test func parsesQuotesNewlinesAndBOM() {
        let text = "\u{FEFF}Name,Notiz,Datum\r\n\"A, B\",\"Zeile 1\nZeile 2 mit \"\"Zitat\"\"\",x\r\nC,,y\r\n\r\n"
        let rows = NotionCSV.rows(text)
        #expect(rows.count == 3)
        #expect(rows[0] == ["Name", "Notiz", "Datum"])
        #expect(rows[1] == ["A, B", "Zeile 1\nZeile 2 mit \"Zitat\"", "x"])
        #expect(rows[2] == ["C", "", "y"])
    }

    @Test func recordsUseHeaderNames() {
        let records = NotionCSV.records("Name,Created time\nTitel,\"March 1, 2024 9:00 AM\"\n")
        #expect(records == [["Name": "Titel", "Created time": "March 1, 2024 9:00 AM"]])
    }

    @Test func lastRowWithoutNewlineIsKept() {
        #expect(NotionCSV.rows("a,b\nc,d") == [["a", "b"], ["c", "d"]])
    }
}

struct NotionDateTests {
    private var utc: TimeZone { TimeZone(identifier: "UTC")! }

    @Test func parsesLocalizedValues() throws {
        let calendar = makeCalendar("UTC")
        let expected = instant(2026, 11, 19, 13, 23, in: calendar)
        for text in ["November 19, 2026 1:23 PM", "@November 19, 2026 1:23 PM", "19. November 2026 13:23", "2026-11-19 13:23",
                     "19.11.2026 13:23", "November 19, 2026 1:23 PM (GMT+1)"] {
            #expect(NotionDate.parse(text) == expected, "\(text)")
        }
        #expect(NotionDate.parse("November 19, 2026") == instant(2026, 11, 19, in: calendar))
        #expect(NotionDate.parse("irgendwann") == nil)
        #expect(NotionDate.parse("") == nil)
    }

    @Test func dayInTitle_bothFormatsAndTypos() {
        #expect(NotionDate.dayInTitle("16.03.2024") == PlanDay(year: 2024, month: 3, day: 16))
        #expect(NotionDate.dayInTitle("Tagebuch mit Gott (2025-12-09)") == PlanDay(year: 2025, month: 12, day: 9))
        #expect(NotionDate.dayInTitle("5.4.2024") == PlanDay(year: 2024, month: 4, day: 5))
        #expect(NotionDate.dayInTitle("31.04.2024") == nil)
        #expect(NotionDate.dayInTitle("Ohne Datum") == nil)
        #expect(NotionDate.dayInTitle("12 34") == nil)
    }
}

struct NotionExportParserTests {
    private let calendar = makeCalendar()
    private var german: Locale { Locale(identifier: "de_DE") }

    @Test func fileNameSplitsIntoTitleAndID() {
        let parts = NotionExportParser.splitFileName("Römer \(NotionFixtures.id1).md")
        #expect(parts.title == "Römer" && parts.notionID == NotionFixtures.id1)
        #expect(NotionExportParser.splitFileName("Ohne ID.md").notionID == nil)
    }

    @Test func pageSplitsTitlePropertiesAndBody() {
        let page = NotionExportParser.splitPage(NotionFixtures.page(title: "16.03.2024", created: "March 16, 2024 9:12 PM", body: "## TAGEBUCH:\n\nText"))
        #expect(page.title == "16.03.2024")
        #expect(page.properties["Created time"] == "March 16, 2024 9:12 PM")
        #expect(page.properties["Art der Notiz"] == "Normale Notiz")
        #expect(page.body == "## TAGEBUCH:\n\nText")
    }

    @Test func journalPlan_filtersByResourceAndPlacesDays() {
        let plan = NotionExportParser.journalPlan(in: NotionFixtures.files(), calendar: calendar, locale: german)
        #expect(plan.entries.map(\.dayKey) == ["2024-03-16", "2024-04-05", "2025-12-09"])
        #expect(plan.skipped.map(\.title) == ["Ohne Datum"])
        #expect(plan.foundCount == 4)
        #expect(plan.firstDay == PlanDay(year: 2024, month: 3, day: 16) && plan.lastDay == PlanDay(year: 2025, month: 12, day: 9))
        #expect(plan.entries.map(\.id) == [NotionFixtures.id1, NotionFixtures.id2, NotionFixtures.id3])
    }

    @Test func journalPlan_convertsBodyToTemplateSections() throws {
        let plan = NotionExportParser.journalPlan(in: NotionFixtures.files(), calendar: calendar, locale: german)
        let text = try #require(plan.entries.first).text
        #expect(text.hasPrefix("Allgemeine Stimmung\n\nWie geht es mir im Moment grundsätzlich?\n\nRuhig und dankbar."))
        #expect(text.contains("Haupterlebnisse des heutigen Tages\n\n- Spaziergang am Fluss\n- Gespräch mit Anna"))
        #expect(text.hasSuffix("Tagebuch\n\nHeute war ein guter Tag.\nZweite Zeile."))
        #expect(!text.contains("#") && !text.contains("**") && !text.contains("](") && !text.contains("Resource"))
    }

    @Test func journalDay_titleWinsWithinOneDay_createdTimeOtherwise() {
        let created = NotionDate.parse("March 16, 2024 9:12 PM")
        #expect(NotionExportParser.journalDay(title: "16.03.2024", createdAt: created, calendar: calendar) == PlanDay(year: 2024, month: 3, day: 16))
        // One day apart: the title wins.
        #expect(NotionExportParser.journalDay(title: "15.03.2024", createdAt: created, calendar: calendar) == PlanDay(year: 2024, month: 3, day: 15))
        // Typo in the month, wrong year: the creation time wins.
        #expect(NotionExportParser.journalDay(title: "16.05.2024", createdAt: created, calendar: calendar) == PlanDay(year: 2024, month: 3, day: 16))
        #expect(NotionExportParser.journalDay(title: "16.03.2023", createdAt: created, calendar: calendar) == PlanDay(year: 2024, month: 3, day: 16))
        #expect(NotionExportParser.journalDay(title: "16.03.2024", createdAt: nil, calendar: calendar) == PlanDay(year: 2024, month: 3, day: 16))
        #expect(NotionExportParser.journalDay(title: "Ohne", createdAt: created, calendar: calendar) == PlanDay(year: 2024, month: 3, day: 16))
        #expect(NotionExportParser.journalDay(title: "Ohne", createdAt: nil, calendar: calendar) == nil)
    }

    @Test func journalDay_createdTimeBeforeFourCountsForTheDayBefore() {
        // 22:30 UTC is 00:30 the next day in Berlin during summer time, which still counts for the day before.
        let created = NotionDate.parse("June 10, 2024 10:30 PM")
        #expect(NotionExportParser.journalDay(title: "Ohne", createdAt: created, calendar: calendar) == PlanDay(year: 2024, month: 6, day: 10))
        let later = NotionDate.parse("June 11, 2024 2:30 AM")
        #expect(NotionExportParser.journalDay(title: "Ohne", createdAt: later, calendar: calendar) == PlanDay(year: 2024, month: 6, day: 11))
    }

    @Test func csvRowSuppliesPropertiesForPagesWithoutThem() {
        let csv = "\u{FEFF}Name,\"🗄️ Resource / FACH\",Created time\n\"16.03.2024\",\"\(NotionFixtures.resource)\",\"March 16, 2024 9:12 PM\"\n"
        let files = [NotionExportFile(name: "Notizen Datenbank \(NotionFixtures.id4)_all.csv", content: csv),
                     NotionExportFile(name: "16.03.2024 \(NotionFixtures.id1).md", content: "# 16.03.2024\n\n## TAGEBUCH:\n\nNur Text.")]
        let plan = NotionExportParser.journalPlan(in: files, calendar: calendar, locale: german)
        #expect(plan.entries.map(\.dayKey) == ["2024-03-16"])
        #expect(plan.entries.first?.text == "Tagebuch\n\nNur Text.")
    }

    @Test func noFilesOrNoJournalPages_giveAnEmptyPlan() {
        #expect(NotionExportParser.journalPlan(in: [], calendar: calendar).foundCount == 0)
        let others = [NotionExportFile(name: "Rezept \(NotionFixtures.id4).md", content: NotionFixtures.page(title: "Kuchen", resource: NotionFixtures.otherResource, body: "x"))]
        #expect(NotionExportParser.journalPlan(in: others, calendar: calendar).foundCount == 0)
    }

    @Test func bibleStudyNotes_oneNotePerBook() {
        let resource = "📖 Bible Studies (https://www.notion.so/Bible-Studies-3333)"
        let files = [NotionExportFile(name: "Römer \(NotionFixtures.id1).md",
                                      content: NotionFixtures.page(title: "Römer", resource: resource, body: "## GENERELLE GEDANKEN\n\nGnade.\n\n## NOTIZEN:\n\n3,23: alle haben gesündigt")),
                     NotionExportFile(name: "Rezept \(NotionFixtures.id4).md", content: NotionFixtures.page(title: "Kuchen", resource: NotionFixtures.otherResource, body: "x"))]
        let sections = [NotionMarkdown.Section(needle: "generelle", heading: "Generelle Gedanken"), NotionMarkdown.Section(needle: "notizen", heading: "Notizen")]
        let notes = NotionExportParser.bibleStudyNotes(in: files, sections: sections)
        #expect(notes.map(\.title) == ["Römer"])
        #expect(notes.first?.text == "Generelle Gedanken\n\nGnade.\n\nNotizen\n\n3,23: alle haben gesündigt")
    }
}

struct NotionImportPlannerTests {
    private func entry(_ id: String, _ key: String) -> NotionJournalEntry {
        NotionJournalEntry(id: id, title: key, day: NoteDayKey.day(key)!, createdAt: nil, text: "t")
    }

    @Test func preview_countsNewConflictsAndRepeats() {
        let entries = [entry("a", "2024-03-16"), entry("b", "2024-03-17"), entry("c", "2024-03-17"), entry("d", "2024-03-18")]
        let preview = NotionImportPlanner.preview(entries: entries, existingDayKeys: ["2024-03-16"], importedIDs: ["d"])
        // a: day taken (conflict), b: new, c: same day as b (conflict), d: already imported.
        #expect(preview == NotionImportPreview(newCount: 1, conflictCount: 2, alreadyImportedCount: 1))
    }

    private func entry(_ id: String, _ key: String, text: String) -> NotionJournalEntry {
        NotionJournalEntry(id: id, title: key, day: NoteDayKey.day(key)!, createdAt: nil, text: text)
    }

    @Test func conflicts_listNewestFirstAndMatchThePreviewCount() {
        let entries = [entry("a", "2024-03-16", text: "Notion A"), entry("b", "2024-03-17", text: "Notion B"),
                       entry("c", "2024-03-17", text: "Notion C"), entry("d", "2024-03-18", text: "Notion D")]
        let existing = ["2024-03-16": "Tagwerk A"]
        let conflicts = NotionImportPlanner.conflicts(entries: entries, existingTexts: existing, importedIDs: ["d"])
        // a: day taken by the entry in Tagwerk, c: day taken by b of the same import, d: already imported.
        #expect(conflicts.map(\.id) == ["c", "a"])
        #expect(conflicts.map(\.day) == [NoteDayKey.day("2024-03-17")!, NoteDayKey.day("2024-03-16")!])
        #expect(conflicts.first?.existingExcerpt == "Notion B" && conflicts.first?.importedExcerpt == "Notion C")
        #expect(conflicts.last?.existingExcerpt == "Tagwerk A" && conflicts.last?.importedExcerpt == "Notion A")
        let preview = NotionImportPlanner.preview(entries: entries, existingDayKeys: Set(existing.keys), importedIDs: ["d"])
        #expect(conflicts.count == preview.conflictCount)
    }

    @Test func excerpt_skipsTemplateLinesAndIsCutAtFortyCharacters() {
        let text = "Allgemeine Stimmung\nWie geht es mir im Moment grundsätzlich?\n\n  Müde,   aber ruhig.\nZweite Zeile"
        #expect(NotionImportPlanner.excerpt(text) == "Müde, aber ruhig.")
        let long = String(repeating: "abcdefghij", count: 6)
        #expect(NotionImportPlanner.excerpt(long) == String(long.prefix(40)) + "…")
        let exact = String(repeating: "x", count: 40)
        #expect(NotionImportPlanner.excerpt(exact) == exact)
        #expect(NotionImportPlanner.excerpt("Allgemeine Stimmung\n\n") == "")
    }

    @Test func appending_putsImportedTextBelowASeparator() {
        let german = Locale(identifier: "de_DE")
        let result = NotionImportPlanner.appending("Alt", to: "Heute geschrieben", locale: german)
        #expect(result == "Heute geschrieben\n\n———\nAus Notion importiert\n\nAlt")
        #expect(NotionImportPlanner.appending("Alt", to: "  ", locale: german) == "Alt")
    }

    @Test func markerIDs_splitOnSpaces() {
        #expect(NotionImportPlanner.markerIDs("a b") == ["a", "b"])
        #expect(NotionImportPlanner.markerIDs(nil).isEmpty)
    }
}

struct JournalTemplateTests {
    private let german = Locale(identifier: "de_DE")
    private let english = Locale(identifier: "en_US")

    @Test func text_hasThreeSectionsInTheLanguage() {
        let text = JournalTemplate.text(locale: german)
        #expect(text.hasPrefix("Allgemeine Stimmung\nWie geht es mir im Moment grundsätzlich?\n"))
        #expect(text.contains("Haupterlebnisse des heutigen Tages") && text.contains("Tagebuch"))
        #expect(JournalTemplate.text(locale: english).contains("General mood"))
    }

    @Test func isOnlyTemplate_recognizesUntouchedEntries() {
        #expect(JournalTemplate.isOnlyTemplate(JournalTemplate.text(locale: german)))
        #expect(JournalTemplate.isOnlyTemplate(JournalTemplate.text(locale: english)))
        #expect(JournalTemplate.isOnlyTemplate(""))
        #expect(JournalTemplate.isOnlyTemplate("  \n tagebuch: \n"))
        #expect(!JournalTemplate.isOnlyTemplate(JournalTemplate.text(locale: german) + "Heute war gut."))
        #expect(!JournalTemplate.isOnlyTemplate("Allgemeine Stimmung\nMüde."))
    }

    @Test func contentLines_dropTemplateLines() {
        let text = JournalTemplate.text(locale: german).replacingOccurrences(of: "Tagebuch\n", with: "Tagebuch\nHeute war gut.\n")
        #expect(JournalTemplate.contentLines(text) == ["Heute war gut."])
    }
}
