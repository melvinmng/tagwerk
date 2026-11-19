import Foundation

/// One file of an unpacked Notion export (format "Markdown & CSV"): the file name without folders and its text.
public struct NotionExportFile: Sendable, Equatable {
    public let name: String
    public let content: String

    public init(name: String, content: String) {
        self.name = name
        self.content = content
    }
}

/// A page of the export: its title, the properties (from the database CSV and from the property lines of the page)
/// and the text below them.
public struct NotionPage: Sendable, Equatable {
    /// The 32-digit hexadecimal id at the end of the file name; `nil` when the name has none.
    public let notionID: String?
    public let title: String
    public let properties: [String: String]
    public let body: String

    public init(notionID: String?, title: String, properties: [String: String], body: String) {
        self.notionID = notionID
        self.title = title
        self.properties = properties
        self.body = body
    }

    /// The first property whose name contains one of `needles` (compared without case and accents).
    public func property(containing needles: [String]) -> String? {
        for (key, value) in properties.sorted(by: { $0.key < $1.key }) {
            let folded = SearchText.fold(key)
            if needles.contains(where: { folded.contains($0) }) { return value }
        }
        return nil
    }
}

/// A journal entry read from the export, ready to be stored for its day.
public struct NotionJournalEntry: Sendable, Equatable, Identifiable {
    /// The Notion page id, or a stable stand-in made of the title when the file name has no id.
    public let id: String
    public let title: String
    public let day: PlanDay
    public let createdAt: Date?
    public let text: String

    public var dayKey: String { NoteDayKey.string(day) }

    public init(id: String, title: String, day: PlanDay, createdAt: Date?, text: String) {
        self.id = id
        self.title = title
        self.day = day
        self.createdAt = createdAt
        self.text = text
    }
}

/// A page that could not be placed on a day and is therefore not imported.
public struct NotionSkippedPage: Sendable, Equatable {
    public let title: String

    public init(title: String) { self.title = title }
}

public struct NotionJournalPlan: Sendable, Equatable {
    /// Sorted by day, then by creation time.
    public let entries: [NotionJournalEntry]
    public let skipped: [NotionSkippedPage]
    /// Pages of the export that belong to the journal, whether they could be placed or not.
    public var foundCount: Int { entries.count + skipped.count }
    public init(entries: [NotionJournalEntry], skipped: [NotionSkippedPage]) {
        self.entries = entries
        self.skipped = skipped
    }

    public var firstDay: PlanDay? { entries.first?.day }
    public var lastDay: PlanDay? { entries.last?.day }
}

/// A note of the export for the Bible Study folder: one note per book.
public struct NotionBibleNote: Sendable, Equatable, Identifiable {
    public let id: String
    /// The title of the page as written in Notion, usually the name of the book.
    public let title: String
    public let text: String

    public init(id: String, title: String, text: String) {
        self.id = id
        self.title = title
        self.text = text
    }
}

/// Reads an unpacked Notion export. Pure: it gets the text of the files and returns what it found; choosing the folder and
/// reading the files is the app's job. It is tolerant on purpose, because the layout was derived from the documentation of
/// the export and has to be adjustable to real exports.
public enum NotionExportParser {
    /// Which pages of the notes database a function looks for, by the value of the "Resource / FACH" relation.
    public static let journalResourceNeedle = "tagebuch mit gott"
    public static let bibleResourceNeedle = "bible stud"

    // MARK: Pages

    /// All pages of the export: every `.md` file, with the properties of its row in a database CSV merged in. A property of
    /// the page file wins over the CSV.
    public static func pages(in files: [NotionExportFile]) -> [NotionPage] {
        var rowsByTitle: [String: [[String: String]]] = [:]
        for file in files where file.name.lowercased().hasSuffix(".csv") {
            let records = NotionCSV.records(file.content)
            guard let titleKey = titleColumn(of: records) else { continue }
            for record in records {
                guard let title = record[titleKey], !title.isEmpty else { continue }
                rowsByTitle[normalizedTitle(title), default: []].append(record)
            }
        }
        var used: [String: Int] = [:]
        var pages: [NotionPage] = []
        for file in files where file.name.lowercased().hasSuffix(".md") {
            let (nameTitle, notionID) = splitFileName(file.name)
            let (heading, fileProperties, body) = splitPage(file.content)
            let title = heading ?? nameTitle
            var properties: [String: String] = [:]
            let key = normalizedTitle(title)
            if let rows = rowsByTitle[key] {
                // Pages with the same title take the rows in order.
                let index = used[key, default: 0]
                used[key] = index + 1
                if index < rows.count { properties = rows[index] }
            }
            properties.merge(fileProperties) { _, fromFile in fromFile }
            pages.append(NotionPage(notionID: notionID, title: title, properties: properties, body: body))
        }
        return pages
    }

    /// Name and id from "Titel 0123…ef.md".
    static func splitFileName(_ name: String) -> (title: String, notionID: String?) {
        var stem = name
        if let dot = stem.lastIndex(of: "."), stem[stem.index(after: dot)...].count <= 4 { stem = String(stem[..<dot]) }
        let parts = stem.split(separator: " ")
        if let last = parts.last, last.count == 32, last.allSatisfy(\.isHexDigit) {
            return (parts.dropLast().joined(separator: " "), String(last).lowercased())
        }
        return (stem, nil)
    }

    /// The `# Title` line, the `Key: value` lines directly below it and the rest of the page.
    static func splitPage(_ content: String) -> (title: String?, properties: [String: String], body: String) {
        var lines = content.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        if lines.first?.hasPrefix("\u{FEFF}") == true { lines[0] = String(lines[0].dropFirst()) }
        var title: String?
        if let first = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
           lines[first].hasPrefix("# ") {
            title = String(lines[first].dropFirst(2)).trimmingCharacters(in: .whitespaces)
            lines.removeSubrange(0...first)
        }
        while lines.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeFirst() }
        var properties: [String: String] = [:]
        var consumed = 0
        for line in lines {
            guard let split = line.range(of: ": "), !line.hasPrefix("#"), line.distance(from: line.startIndex, to: split.lowerBound) <= 80,
                  !line.hasPrefix("- "), !line.hasPrefix("> ") else { break }
            let key = String(line[..<split.lowerBound]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { break }
            properties[key] = String(line[split.upperBound...]).trimmingCharacters(in: .whitespaces)
            consumed += 1
        }
        let body = lines.dropFirst(consumed).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (title, properties, body)
    }

    private static func titleColumn(of records: [[String: String]]) -> String? {
        guard let keys = records.first?.keys else { return nil }
        let names = ["name", "title", "titel"]
        return keys.first { names.contains(SearchText.fold($0).trimmingCharacters(in: .whitespaces)) }
    }

    static func normalizedTitle(_ title: String) -> String {
        SearchText.fold(title.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: Journal

    /// The pages related to "Tagebuch mit Gott", each placed on a day. `calendar` decides the day of a creation time, so
    /// pass the calendar of the device (the evening rule: before 04:00 counts for the day before).
    public static func journalPlan(in files: [NotionExportFile], calendar: Calendar, locale: Locale = Locale(identifier: "de_DE")) -> NotionJournalPlan {
        var entries: [NotionJournalEntry] = []
        var skipped: [NotionSkippedPage] = []
        for page in pages(in: files) where isRelated(page, needle: journalResourceNeedle) {
            let createdAt = page.property(containing: ["created time", "created", "erstellt"]).flatMap { NotionDate.parse($0) }
            guard let day = journalDay(title: page.title, createdAt: createdAt, calendar: calendar) else {
                skipped.append(NotionSkippedPage(title: page.title))
                continue
            }
            let text = NotionMarkdown.plainText(page.body, sections: journalSections(locale: locale))
            entries.append(NotionJournalEntry(id: page.notionID ?? "title:" + normalizedTitle(page.title), title: page.title,
                                              day: day, createdAt: createdAt, text: text))
        }
        entries.sort { ($0.day, $0.createdAt ?? .distantPast) < ($1.day, $1.createdAt ?? .distantPast) }
        return NotionJournalPlan(entries: entries, skipped: skipped)
    }

    /// The headings of the journal in the notes: Notion's (uppercase) section names mapped onto the template headings.
    static func journalSections(locale: Locale) -> [NotionMarkdown.Section] {
        [NotionMarkdown.Section(needle: "stimmung", heading: JournalTemplate.heading(.mood, locale: locale)),
         NotionMarkdown.Section(needle: "haupterlebnis", heading: JournalTemplate.heading(.events, locale: locale)),
         NotionMarkdown.Section(needle: "tagebuch", heading: JournalTemplate.heading(.journal, locale: locale))]
    }

    static func isRelated(_ page: NotionPage, needle: String) -> Bool {
        guard let resource = page.property(containing: ["resource", "fach"]) else { return false }
        return SearchText.fold(resource).contains(needle)
    }

    /// The day of an entry. The title carries the day ("16.03.2024" or "Tagebuch mit Gott (2025-12-09)") but can hold typos,
    /// so it is checked against the creation time: if both name days no more than one day apart, the title wins; otherwise
    /// the creation time decides. Without a usable day the entry has none.
    public static func journalDay(title: String, createdAt: Date?, calendar: Calendar) -> PlanDay? {
        let titleDay = NotionDate.dayInTitle(title)
        let createdDay = createdAt.map { RoutineSchedule.routineDay(at: $0, calendar: calendar) }
        switch (titleDay, createdDay) {
        case let (titleDay?, createdDay?):
            let apart = calendar.dateComponents([.day], from: titleDay.startDate(in: calendar), to: createdDay.startDate(in: calendar)).day ?? 0
            return abs(apart) <= 1 ? titleDay : createdDay
        case let (titleDay?, nil): return titleDay
        case let (nil, createdDay?): return createdDay
        case (nil, nil): return nil
        }
    }

    // MARK: Bible Study

    /// The pages related to "Bible Studies": one note per book, the title is the book.
    public static func bibleStudyNotes(in files: [NotionExportFile], sections: [NotionMarkdown.Section]) -> [NotionBibleNote] {
        pages(in: files).filter { isRelated($0, needle: bibleResourceNeedle) }.map { page in
            NotionBibleNote(id: page.notionID ?? "title:" + normalizedTitle(page.title), title: page.title,
                            text: NotionMarkdown.plainText(page.body, sections: sections))
        }
    }
}

/// How many entries an import would create, append or skip.
public struct NotionImportPreview: Sendable, Equatable {
    public var newCount = 0
    /// The day already has an entry; the imported text goes below a separator.
    public var conflictCount = 0
    public var alreadyImportedCount = 0

    public init(newCount: Int = 0, conflictCount: Int = 0, alreadyImportedCount: Int = 0) {
        self.newCount = newCount
        self.conflictCount = conflictCount
        self.alreadyImportedCount = alreadyImportedCount
    }
}

public enum NotionImportPlanner {
    /// Sorts the entries into new ones, conflicts with an existing entry of the same day (or with an earlier entry of the same
    /// import) and entries that an earlier import already stored (`importedIDs`).
    public static func preview(entries: [NotionJournalEntry], existingDayKeys: Set<String>, importedIDs: Set<String>) -> NotionImportPreview {
        var preview = NotionImportPreview()
        var taken = existingDayKeys
        for entry in entries {
            if importedIDs.contains(entry.id) {
                preview.alreadyImportedCount += 1
            } else if taken.contains(entry.dayKey) {
                preview.conflictCount += 1
            } else {
                preview.newCount += 1
                taken.insert(entry.dayKey)
            }
        }
        return preview
    }

    /// The same for Bible Study notes: a page for a book that has a note (`existingBookKeys`) is a conflict (its text is
    /// appended), a second page for a book in the same import too. Pages whose title is not a book are listed as unmatched.
    public static func biblePreview(pages: [NotionBibleNote], existingBookKeys: Set<String>, importedIDs: Set<String>)
        -> (preview: NotionImportPreview, unmatched: [String]) {
        var preview = NotionImportPreview()
        var unmatched: [String] = []
        var taken = existingBookKeys
        for page in pages {
            if importedIDs.contains(page.id) {
                preview.alreadyImportedCount += 1
            } else if let book = BibleBooks.book(matching: page.title) {
                if taken.contains(book.key) {
                    preview.conflictCount += 1
                } else {
                    preview.newCount += 1
                    taken.insert(book.key)
                }
            } else {
                unmatched.append(page.title)
            }
        }
        return (preview, unmatched)
    }

    /// The separator line under which imported text is appended to an existing entry.
    public static func separator(locale: Locale) -> String {
        Localized.string("Aus Notion importiert", in: VoiceLanguage.from(locale: locale), bundle: .module)
    }

    /// An entry's text with the imported text below the separator; nothing is overwritten.
    public static func appending(_ imported: String, to existing: String, locale: Locale) -> String {
        let base = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        let block = "———\n" + separator(locale: locale) + "\n\n" + imported.trimmingCharacters(in: .whitespacesAndNewlines)
        return base.isEmpty ? imported : base + "\n\n" + block
    }

    /// The ids in a stored marker ("id1 id2").
    public static func markerIDs(_ marker: String?) -> Set<String> {
        Set((marker ?? "").split(separator: " ").map(String.init))
    }
}
