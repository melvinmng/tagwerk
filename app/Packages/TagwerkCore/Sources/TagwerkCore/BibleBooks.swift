import Foundation

/// A book of the Bible with its German name (as Notion spells it, "1. Korinther") and its English name.
public struct BibleBook: Sendable, Hashable, Identifiable {
    /// Position in the canon, 1 (Genesis) to 66 (Revelation); also the stable key stored with notes and sessions.
    public let number: Int
    public let german: String
    public let english: String
    /// Further spellings and abbreviations that identify the book exactly ("1 Kor", "Röm").
    let aliases: [String]

    public var id: Int { number }
    public var key: String { String(number) }
    public var isOldTestament: Bool { number <= 39 }

    /// The name in the language of `locale`.
    public func name(locale: Locale) -> String {
        VoiceLanguage.from(locale: locale) == .german ? german : english
    }
}

/// The 66 books and the recognition of how a book is written.
public enum BibleBooks {
    public static let all: [BibleBook] = {
        let rows: [(String, String, [String])] = [
            ("1. Mose", "Genesis", ["Gen", "1Mo", "1Mose"]), ("2. Mose", "Exodus", ["Ex", "2Mo"]), ("3. Mose", "Leviticus", ["Lev", "3Mo"]),
            ("4. Mose", "Numbers", ["Num", "4Mo"]), ("5. Mose", "Deuteronomy", ["Dtn", "Deut", "5Mo"]),
            ("Josua", "Joshua", ["Jos"]), ("Richter", "Judges", ["Ri", "Judg"]), ("Rut", "Ruth", []),
            ("1. Samuel", "1 Samuel", ["1Sam"]), ("2. Samuel", "2 Samuel", ["2Sam"]),
            ("1. Könige", "1 Kings", ["1Kön", "1Kg"]), ("2. Könige", "2 Kings", ["2Kön", "2Kg"]),
            ("1. Chronik", "1 Chronicles", ["1Chr"]), ("2. Chronik", "2 Chronicles", ["2Chr"]),
            ("Esra", "Ezra", []), ("Nehemia", "Nehemiah", ["Neh"]), ("Ester", "Esther", ["Est"]), ("Hiob", "Job", ["Ijob"]),
            ("Psalmen", "Psalms", ["Psalm", "Ps"]), ("Sprüche", "Proverbs", ["Spr", "Prov"]), ("Prediger", "Ecclesiastes", ["Pred", "Koh", "Kohelet"]),
            ("Hohelied", "Song of Solomon", ["Hld", "Hoheslied", "Song of Songs"]),
            ("Jesaja", "Isaiah", ["Jes", "Isa"]), ("Jeremia", "Jeremiah", ["Jer"]), ("Klagelieder", "Lamentations", ["Klgl", "Lam"]),
            ("Hesekiel", "Ezekiel", ["Hes", "Ez", "Ezechiel", "Ezek"]), ("Daniel", "Daniel", ["Dan"]),
            ("Hosea", "Hosea", ["Hos"]), ("Joel", "Joel", []), ("Amos", "Amos", []), ("Obadja", "Obadiah", ["Obd", "Ob"]),
            ("Jona", "Jonah", []), ("Micha", "Micah", ["Mi"]), ("Nahum", "Nahum", ["Nah"]), ("Habakuk", "Habakkuk", ["Hab"]),
            ("Zefanja", "Zephaniah", ["Zef", "Zeph"]), ("Haggai", "Haggai", ["Hag"]), ("Sacharja", "Zechariah", ["Sach", "Zech"]),
            ("Maleachi", "Malachi", ["Mal"]),
            ("Matthäus", "Matthew", ["Mt", "Matt"]), ("Markus", "Mark", ["Mk"]), ("Lukas", "Luke", ["Lk"]), ("Johannes", "John", ["Joh"]),
            ("Apostelgeschichte", "Acts", ["Apg"]), ("Römer", "Romans", ["Röm", "Rom"]),
            ("1. Korinther", "1 Corinthians", ["1Kor", "1Cor"]), ("2. Korinther", "2 Corinthians", ["2Kor", "2Cor"]),
            ("Galater", "Galatians", ["Gal"]), ("Epheser", "Ephesians", ["Eph"]), ("Philipper", "Philippians", ["Phil"]),
            ("Kolosser", "Colossians", ["Kol", "Col"]), ("1. Thessalonicher", "1 Thessalonians", ["1Thess", "1Thes"]),
            ("2. Thessalonicher", "2 Thessalonians", ["2Thess", "2Thes"]), ("1. Timotheus", "1 Timothy", ["1Tim"]),
            ("2. Timotheus", "2 Timothy", ["2Tim"]), ("Titus", "Titus", ["Tit"]), ("Philemon", "Philemon", ["Phlm", "Phm"]),
            ("Hebräer", "Hebrews", ["Hebr", "Heb"]), ("Jakobus", "James", ["Jak", "Jas"]),
            ("1. Petrus", "1 Peter", ["1Petr", "1Pet"]), ("2. Petrus", "2 Peter", ["2Petr", "2Pet"]),
            ("1. Johannes", "1 John", ["1Joh"]), ("2. Johannes", "2 John", ["2Joh"]), ("3. Johannes", "3 John", ["3Joh"]),
            ("Judas", "Jude", ["Jud"]), ("Offenbarung", "Revelation", ["Offb", "Apokalypse", "Rev"]),
        ]
        return rows.enumerated().map { BibleBook(number: $0.offset + 1, german: $0.element.0, english: $0.element.1, aliases: $0.element.2) }
    }()

    public static func book(number: Int) -> BibleBook? {
        all.first { $0.number == number }
    }

    public static func book(key: String) -> BibleBook? {
        Int(key).flatMap(book(number:))
    }

    /// Recognizes a book from how it is written: the German or English name, a known abbreviation ("1 Kor", "Röm"), a
    /// spelling without umlauts or dots ("Roemer", "1.Korinther") or an unambiguous start of the name ("Offenb"). `nil`
    /// when nothing matches or the start fits several books ("Jo").
    public static func book(matching text: String) -> BibleBook? {
        let wanted = normalize(text)
        guard !wanted.isEmpty else { return nil }
        if let exact = all.first(where: { names(of: $0).contains(wanted) }) { return exact }
        // A start of a name needs three characters, so "1 K" or "Jo" never guess.
        guard wanted.count >= 3 else { return nil }
        let candidates = all.filter { book in
            [normalize(book.german), normalize(book.english)].contains { $0.hasPrefix(wanted) }
        }
        return candidates.count == 1 ? candidates[0] : nil
    }

    /// The books that match what is typed into the search field of the book list (BS2b): the typed text is part of the
    /// German or English name, or the start of an abbreviation ("Offb", "1 Kor"). Spelling is folded as in `book(matching:)`.
    /// Empty text returns every book. The result keeps the order of the canon.
    public static func search(_ text: String) -> [BibleBook] {
        let wanted = normalize(text)
        guard !wanted.isEmpty else { return all }
        return all.filter { book in
            [book.german, book.english].contains { normalize($0).contains(wanted) }
                || book.aliases.contains { normalize($0).hasPrefix(wanted) }
        }
    }

    private static func names(of book: BibleBook) -> Set<String> {
        Set(([book.german, book.english] + book.aliases).map(normalize))
    }

    /// Folded, without spaces, dots and punctuation; "oe", "ae" and "ue" spellings equal the umlaut letters after folding.
    static func normalize(_ text: String) -> String {
        var folded = SearchText.fold(text).filter { $0.isLetter || $0.isNumber }
        for pair in ["ae": "a", "oe": "o", "ue": "u"] { folded = folded.replacingOccurrences(of: pair.key, with: pair.value) }
        return folded
    }
}

/// The text of a book's note and of a session section.
public enum BibleStudyTemplate {
    public enum Section: CaseIterable, Sendable {
        case thoughts, actionItems, notes
    }

    public static func heading(_ section: Section, locale: Locale) -> String {
        func text(_ key: String.LocalizationValue) -> String { Localized.string(key, in: VoiceLanguage.from(locale: locale), bundle: .module) }
        switch section {
        case .thoughts: return text("Generelle Gedanken")
        case .actionItems: return text("Action Items")
        case .notes: return text("Notizen")
        }
    }

    /// The Notion section names mapped onto the headings, for the import.
    public static func importSections(locale: Locale) -> [NotionMarkdown.Section] {
        [NotionMarkdown.Section(needle: "generelle", heading: heading(.thoughts, locale: locale)),
         NotionMarkdown.Section(needle: "action", heading: heading(.actionItems, locale: locale)),
         NotionMarkdown.Section(needle: "notizen", heading: heading(.notes, locale: locale))]
    }

    /// The note of a new book: its name as the title, then the three sections.
    public static func text(book: BibleBook, locale: Locale) -> String {
        ([book.name(locale: locale)] + Section.allCases.map { heading($0, locale: locale) })
            .joined(separator: "\n\n\n") + "\n\n"
    }

    /// A new dated section at the end of the note ("19.11.2026 · 3,21-31"). The "Notizen" section is the last one, so the
    /// section starts below the last observations.
    public static func appendingSession(to text: String, dateText: String, passage: String) -> String {
        let base = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return base + "\n\n" + sessionHeading(dateText: dateText, passage: passage) + "\n\n"
    }

    /// Completes the heading of a session section (BV2b) once the end is known: the line written at the start,
    /// "19.11.2026 · 3,21–", becomes "19.11.2026 · 3,21–26". Only a line that is still exactly the heading of the start is
    /// replaced (the last one when two sessions of a day wrote the same heading); a heading the reader has edited leaves the
    /// text unchanged.
    public static func replacingSessionHeading(in text: String, dateText: String, oldPassage: String, newPassage: String) -> String {
        let oldHeading = sessionHeading(dateText: dateText, passage: oldPassage)
        var lines = text.components(separatedBy: "\n")
        guard let index = lines.lastIndex(of: oldHeading) else { return text }
        lines[index] = sessionHeading(dateText: dateText, passage: newPassage)
        return lines.joined(separator: "\n")
    }

    /// "19.11.2026", fixed so the section titles of a note read alike whatever the language was when they were written.
    public static func dateText(_ day: PlanDay) -> String {
        String(format: "%02d.%02d.%04d", day.day, day.month, day.year)
    }

    /// The title line of a session section: the date, then the passage when there is one.
    private static func sessionHeading(dateText: String, passage: String) -> String {
        let trimmedPassage = passage.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedPassage.isEmpty ? dateText : dateText + " · " + trimmedPassage
    }
}
