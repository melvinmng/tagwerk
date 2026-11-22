import Foundation
import Observation
import TagwerkCore

/// Edit state of the default reminders (plan P4, Task 11): ten lists, one per kind with and without a time of day.
@MainActor
@Observable
final class ReminderDefaultsModel {
    /// One list of the settings page.
    struct Slot: Hashable, Identifiable {
        let kind: ReminderKind
        let isAllDay: Bool
        var id: String { "\(kind.rawValue)-\(isAllDay)" }
    }

    /// The lists in the order of the page: events, Apple reminders, GitHub issues, local tasks, deadlines; each with a time of day first.
    static let slots: [Slot] = ReminderKind.allCases.flatMap { [Slot(kind: $0, isAllDay: false), Slot(kind: $0, isAllDay: true)] }

    private(set) var lists: [Slot: ReminderListModel]

    init(defaults: ReminderDefaults) {
        lists = Dictionary(uniqueKeysWithValues: Self.slots.map { slot in
            (slot, ReminderListModel(list: defaults.offsets(for: slot.kind, isAllDay: slot.isAllDay), isAllDay: slot.isAllDay))
        })
    }

    func list(_ slot: Slot) -> ReminderListModel {
        lists[slot] ?? ReminderListModel(list: [], isAllDay: slot.isAllDay)
    }

    /// The defaults the lists describe now.
    var defaults: ReminderDefaults {
        var result = ReminderDefaults()
        for slot in Self.slots { result.set(list(slot).offsets, for: slot.kind, isAllDay: slot.isAllDay) }
        return result
    }

    /// The name of a kind on the overview page.
    static func kindTitle(_ kind: ReminderKind) -> String {
        switch kind {
        case .event: String(localized: "Kalendertermine")
        case .appleReminder: String(localized: "Apple Erinnerungen")
        case .githubIssue: String(localized: "GitHub-Issues")
        case .localTask: String(localized: "Lokale Aufgaben")
        case .deadline: String(localized: "Deadline-Termine")
        }
    }

    /// The name of a list on the page of its kind. Events and deadlines say "Ganztägig", the others "Ohne Uhrzeit".
    static func slotTitle(_ slot: Slot) -> String {
        guard slot.isAllDay else { return String(localized: "Mit Uhrzeit") }
        switch slot.kind {
        case .event, .deadline: return String(localized: "Ganztägig")
        case .appleReminder, .githubIssue, .localTask: return String(localized: "Ohne Uhrzeit")
        }
    }

    /// The short form of a list, worded for what the kind counts from.
    func rowSummary(for slot: Slot, locale: Locale = .current, calendar: Calendar = .tagwerk) -> String {
        ReminderText.summary(list(slot).offsets, subject: slot.kind.subject, isAllDay: slot.isAllDay, locale: locale, calendar: calendar)
    }
}
