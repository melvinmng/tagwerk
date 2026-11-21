import Foundation
import Observation
import TagwerkCore

/// What a reminder list editor hands back.
enum ReminderListResult: Equatable {
    /// The entry follows the default of its kind.
    case useDefault
    /// The entry has its own list (possibly empty: no reminders).
    case custom([ReminderOffset])
}

/// Edit state of one reminder list (plan P4, Task 8): either the default of the kind (read-only, grey) or an own list.
@MainActor
@Observable
final class ReminderListModel {
    /// The own list while `isUsingDefault` is false; always sorted and without duplicates.
    private(set) var offsets: [ReminderOffset]
    private(set) var isUsingDefault: Bool
    /// The default list the entry would follow; shown grey and taken as starting point by `customize()`.
    private(set) var defaultOffsets: [ReminderOffset]
    /// An entry without time or an all-day entry: hour and minute distances are not offered, and a list written for a
    /// timed entry loses them.
    private(set) var isAllDay: Bool

    /// `offsets == nil` means the entry follows the default.
    init(offsets: [ReminderOffset]?, defaultOffsets: [ReminderOffset], isAllDay: Bool) {
        self.isAllDay = isAllDay
        self.defaultOffsets = ReminderOffset.normalized(defaultOffsets, isAllDay: isAllDay)
        self.isUsingDefault = offsets == nil
        self.offsets = ReminderOffset.normalized(offsets ?? [], isAllDay: isAllDay)
    }

    /// A list without a default behind it (the default settings themselves).
    convenience init(list: [ReminderOffset], isAllDay: Bool) {
        self.init(offsets: list, defaultOffsets: [], isAllDay: isAllDay)
    }

    /// The list the rows show.
    var displayed: [ReminderOffset] { isUsingDefault ? defaultOffsets : offsets }

    /// Units the picker offers.
    var availableUnits: [ReminderUnit] { ReminderUnit.allCases.filter { !isAllDay || !$0.needsTimeOfDay } }

    var result: ReminderListResult { isUsingDefault ? .useDefault : .custom(offsets) }

    /// Adds a reminder; an own list is started from the default first. A duplicate (also an equal distance) is ignored.
    func add(_ offset: ReminderOffset) {
        if isUsingDefault { customize() }
        offsets = ReminderOffset.normalized(offsets + [offset], isAllDay: isAllDay)
    }

    /// Whether a reminder of this distance is on the list the rows show (60 minutes and 1 hour are one reminder).
    func isSelected(_ offset: ReminderOffset) -> Bool { displayed.contains { $0.isEquivalent(to: offset) } }

    /// Sets the reminder when it is missing and removes it when it is there. While the default applies, the own list starts
    /// from the default first, so a tap changes a copy and never the default itself.
    func toggle(_ offset: ReminderOffset) {
        if isUsingDefault { customize() }
        if let index = offsets.firstIndex(where: { $0.isEquivalent(to: offset) }) {
            offsets.remove(at: index)
        } else {
            offsets = ReminderOffset.normalized(offsets + [offset], isAllDay: isAllDay)
        }
    }

    /// The rows of the selection page: the usual distances and everything that is set.
    var choiceRows: [ReminderOffset] { ReminderChoices.rows(selected: displayed, isAllDay: isAllDay) }

    /// The short form for a row of a form: "Standard · 1 Tag vorher um 18:00 + 1 weitere".
    func rowSummary(subject: ReminderSubject, calendar: Calendar = .tagwerk, locale: Locale = .current) -> String {
        ReminderText.rowSummary(displayed, isDefault: isUsingDefault, subject: subject, isAllDay: isAllDay,
                                locale: locale, calendar: calendar)
    }

    func remove(at index: Int) {
        guard !isUsingDefault, offsets.indices.contains(index) else { return }
        offsets.remove(at: index)
    }

    /// Replaces the own list (a list without a default behind it).
    func setList(_ list: [ReminderOffset]) {
        isUsingDefault = false
        offsets = ReminderOffset.normalized(list, isAllDay: isAllDay)
    }

    /// Goes back to the default; the own list is dropped.
    func useDefault() {
        isUsingDefault = true
        offsets = []
    }

    /// Starts an own list with the default as its first content.
    func customize() {
        guard isUsingDefault else { return }
        isUsingDefault = false
        offsets = defaultOffsets
    }

    /// Adapts the list to a changed entry (the due date got or lost its time, the default of the kind changed).
    func configure(isAllDay: Bool, defaultOffsets: [ReminderOffset]) {
        self.isAllDay = isAllDay
        self.defaultOffsets = ReminderOffset.normalized(defaultOffsets, isAllDay: isAllDay)
        offsets = ReminderOffset.normalized(offsets, isAllDay: isAllDay)
    }
}
