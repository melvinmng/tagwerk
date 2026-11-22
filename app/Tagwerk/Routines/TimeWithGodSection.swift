import SwiftUI
import TagwerkCore

/// "Zeit mit Gott" (TB1b, BS6c): the journal and Bible Study in one section with their state, so the routine sheets show
/// what was done without opening anything. The evening wrap-up shows both rows (Bible Study as set in the settings), the
/// morning start only the Bible Study row, and only where the setting offers it there.
struct TimeWithGodSection: View {
    let day: PlanDay
    /// Evening only.
    let showsJournal: Bool
    let showsBibleStudy: Bool
    let onJournal: () -> Void
    let onBibleStudy: () -> Void
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let calendar = environment.routines.calendar
        let entry = environment.notes.journalEntry(dayKey: NoteDayKey.string(day))
        let journal = TimeWithGodText.journalState(entry: entry, isToday: day == environment.routines.eveningDay, calendar: calendar)
        let last = environment.notes.lastSession
        let bible = TimeWithGodText.bibleState(last: last, today: environment.routines.today, calendar: calendar)
        Section {
            if showsJournal {
                row(title: journal == nil ? String(localized: "Tagebuch schreiben") : String(localized: "Tagebuch öffnen"), symbol: "book.closed",
                    detail: journal, isDone: journal != nil, action: onJournal)
            }
            if showsBibleStudy {
                row(title: TimeWithGodText.bibleTitle(last: last), symbol: "book.pages",
                    detail: bible, isDone: false, action: onBibleStudy)
            }
        } header: {
            Text("Zeit mit Gott")
        } footer: {
            Text(showsJournal && showsBibleStudy ? "Beides bleibt auf deinem iPhone und geht nie an ChatGPT."
                                                 : "Bleibt auf deinem iPhone und geht nie an ChatGPT.")
        }
    }

    private func row(title: String, symbol: String, detail: String?, isDone: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Label(title, systemImage: symbol)
                    if let detail { Text(detail).font(.subheadline).foregroundStyle(.secondaryText) }
                }
                Spacer()
                if isDone { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.green).accessibilityHidden(true) }
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .tint(.primary)
    }
}

/// Texts of the section as static functions, so they can be tested.
enum TimeWithGodText {
    /// "Heute geschrieben · 21:40" (a past day: "Geschrieben · 21:40"); `nil` without an entry that holds more than the
    /// unfilled template.
    static func journalState(entry: NoteRecord?, isToday: Bool = true, calendar: Calendar) -> String? {
        guard let entry, !JournalTemplate.isOnlyTemplate(entry.text) else { return nil }
        let time = DateText.time(entry.updatedAt, calendar: calendar)
        return isToday ? String(localized: "Heute geschrieben · \(time)") : String(localized: "Geschrieben · \(time)")
    }

    /// "Bible Study fortsetzen" while the latest session is open, else "Bible Study starten".
    static func bibleTitle(last: BibleStudySessionRecord?) -> String {
        last != nil && last?.completedAt == nil ? String(localized: "Bible Study fortsetzen") : String(localized: "Bible Study starten")
    }

    /// "Zuletzt: Römer 3,21-31 · Dienstag" (until BS2 the passage is the free text that was typed); `nil` without a session.
    static func bibleState(last: BibleStudySessionRecord?, today: PlanDay, calendar: Calendar, locale: Locale = .current) -> String? {
        guard let last, let book = BibleBooks.book(key: last.book) else { return nil }
        let passage = last.passage.isEmpty ? book.name(locale: locale) : book.name(locale: locale) + " " + last.passage
        let when = PlanDay(dayKey: last.dayKey).map { dayText($0, today: today, calendar: calendar, locale: locale) }
        return [String(localized: "Zuletzt: \(passage)"), when].compactMap { $0 }.joined(separator: " · ")
    }

    /// "heute", "gestern", else the weekday within the last six days, else "12.11.".
    private static func dayText(_ day: PlanDay, today: PlanDay, calendar: Calendar, locale: Locale) -> String {
        let distance = calendar.dateComponents([.day], from: day.startDate(in: calendar), to: today.startDate(in: calendar)).day ?? 0
        switch distance {
        case 0: return String(localized: "heute")
        case 1: return String(localized: "gestern")
        case 2...6:
            let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            return day.startDate(in: calendar).formatted(style.weekday(.wide))
        default: return DateText.numericDay(day, calendar: calendar, locale: locale)
        }
    }
}
