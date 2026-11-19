import Foundation

/// Dates as they appear in a Notion export: in property values and in the titles of journal pages.
public enum NotionDate {
    /// Parses a localized date from a property ("November 19, 2026 1:23 PM", "19. November 2026 13:23", "2026-11-19 13:23",
    /// "19.11.2026 13:23"), read in `timeZone`; a date without time is 00:00. Notion writes the creation time in UTC.
    public static func parse(_ text: String, timeZone: TimeZone = TimeZone(identifier: "UTC")!) -> Date? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("@") { value.removeFirst() }
        // "(GMT+1)" style suffixes carry no usable information here.
        if let open = value.firstIndex(of: "("), value.hasSuffix(")") { value = String(value[..<open]) }
        value = value.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }
        for (pattern, localeID) in patterns {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: localeID)
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = timeZone
            formatter.isLenient = false
            formatter.dateFormat = pattern
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    private static let patterns: [(String, String)] = [
        ("MMMM d, yyyy h:mm a", "en_US_POSIX"), ("MMMM d, yyyy HH:mm", "en_US_POSIX"), ("MMMM d, yyyy", "en_US_POSIX"),
        ("MMM d, yyyy h:mm a", "en_US_POSIX"), ("MMM d, yyyy", "en_US_POSIX"),
        ("d. MMMM yyyy HH:mm", "de_DE"), ("d. MMMM yyyy", "de_DE"), ("d. MMM yyyy HH:mm", "de_DE"), ("d. MMM yyyy", "de_DE"),
        ("yyyy-MM-dd HH:mm", "en_US_POSIX"), ("yyyy-MM-dd'T'HH:mm", "en_US_POSIX"), ("yyyy-MM-dd", "en_US_POSIX"),
        ("dd.MM.yyyy HH:mm", "en_US_POSIX"), ("dd.MM.yyyy", "en_US_POSIX"), ("d.M.yyyy HH:mm", "en_US_POSIX"), ("d.M.yyyy", "en_US_POSIX"),
    ]

    /// The day named in a journal title: "16.03.2024" or "Tagebuch mit Gott (2025-12-09)". `nil` when there is none or it is
    /// not a real calendar day (the titles contain typos like "31.04.2024").
    public static func dayInTitle(_ title: String) -> PlanDay? {
        let digits = title.split(whereSeparator: { !$0.isNumber })
        // "DD.MM.YYYY" and "YYYY-MM-DD" both reduce to three digit groups once everything else is a separator.
        guard digits.count >= 3 else { return nil }
        for start in 0...(digits.count - 3) {
            let group = digits[start...(start + 2)].map(String.init)
            let numbers = group.compactMap(Int.init)
            guard numbers.count == 3 else { continue }
            if group[2].count == 4, group[0].count <= 2, group[1].count <= 2, let day = validDay(numbers[2], numbers[1], numbers[0]) { return day }
            if group[0].count == 4, group[1].count <= 2, group[2].count <= 2, let day = validDay(numbers[0], numbers[1], numbers[2]) { return day }
        }
        return nil
    }

    private static func validDay(_ year: Int, _ month: Int, _ day: Int) -> PlanDay? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        guard (1900...2200).contains(year), (1...12).contains(month), (1...31).contains(day),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return parts.year == year && parts.month == month && parts.day == day ? PlanDay(year: year, month: month, day: day) : nil
    }
}
