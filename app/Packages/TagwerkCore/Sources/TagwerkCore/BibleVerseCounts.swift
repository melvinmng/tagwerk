import Foundation

/// Chapter and verse counts in the numbering of German Bibles. One number per chapter.
///
/// The target edition is the Schlachter 2000, but the table is **provisional**: it follows the German (Luther-tradition)
/// numbering and has not been verified against the Schlachter 2000. The sources, the known open points (4. Mose, Apostel-
/// geschichte 19) and the check against the printed edition are in
/// `docs/research/2026-11-20-schlachter-2000-verszahlen.md`. The table holds numbers only, no Bible text.
public enum BibleVerseCounts {
    /// The edition the table is meant for. See the type documentation: the numbers are not yet verified for it.
    public static let edition = "Schlachter 2000"

    /// Number of chapters of a book (`BibleBook.number`, 1…66); 0 for an unknown book.
    public static func chapterCount(book: Int) -> Int {
        versesPerChapter(book: book).count
    }

    /// Number of verses of a chapter; 0 for an unknown book or chapter.
    public static func verseCount(book: Int, chapter: Int) -> Int {
        let chapters = versesPerChapter(book: book)
        guard chapter >= 1, chapter <= chapters.count else { return 0 }
        return chapters[chapter - 1]
    }

    public static func isValid(book: Int, chapter: Int, verse: Int) -> Bool {
        verse >= 1 && verse <= verseCount(book: book, chapter: chapter)
    }

    /// The verse counts of all chapters of a book, in chapter order; empty for an unknown book.
    static func versesPerChapter(book: Int) -> [Int] {
        guard book >= 1, book <= table.count else { return [] }
        return table[book - 1]
    }

    /// Number of books in the table; 66 when the resource is intact.
    static var bookCount: Int { table.count }

    /// The resource file as shipped; its SHA-256 is recorded in the documentation.
    static var resourceData: Data? { resourceURL.flatMap { try? Data(contentsOf: $0) } }

    private static var resourceURL: URL? {
        Bundle.module.url(forResource: "schlachter2000-verses", withExtension: "json")
    }

    /// Resource layout: `{ "edition": "...", "books": [[verses of chapter 1, verses of chapter 2, …], …] }`, one entry
    /// per book in canon order. Read once.
    private static let table: [[Int]] = {
        struct File: Decodable { var books: [[Int]] }
        guard let data = resourceData, let file = try? JSONDecoder().decode(File.self, from: data) else { return [] }
        return file.books
    }()
}
