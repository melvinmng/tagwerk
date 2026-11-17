import Foundation
import SwiftData
import TagwerkCore

/// The day a task is planned to be worked on (Tagwerk only; never written to the source).
/// Schema rule: later attributes must be optional or have a default value.
@Model
final class DayAssignment {
    @Attribute(.unique) var taskKey: String
    var year: Int
    var month: Int
    var day: Int
    var order: Int
    var createdAt: Date

    init(taskKey: String, day: PlanDay, order: Int = 0, createdAt: Date = .now) {
        self.taskKey = taskKey
        self.year = day.year
        self.month = day.month
        self.day = day.day
        self.order = order
        self.createdAt = createdAt
    }

    var planDay: PlanDay {
        get { PlanDay(year: year, month: month, day: day) }
        set { year = newValue.year; month = newValue.month; day = newValue.day }
    }
}

/// Working hours that differ from the weekday schedule on one date.
@Model
final class DayOverrideRecord {
    @Attribute(.unique) var dayKey: String
    var year: Int
    var month: Int
    var day: Int
    var isOff: Bool
    var startMinutes: Int?
    var endMinutes: Int?

    init(day: PlanDay, override: DayOverride) {
        self.dayKey = Self.key(day)
        self.year = day.year
        self.month = day.month
        self.day = day.day
        self.isOff = false
        apply(override)
    }

    static func key(_ day: PlanDay) -> String { String(format: "%04d-%02d-%02d", day.year, day.month, day.day) }

    var planDay: PlanDay { PlanDay(year: year, month: month, day: day) }

    var value: DayOverride {
        if isOff { return .off }
        return .hours(WorkHours(startMinutes: startMinutes ?? 0, endMinutes: endMinutes ?? 0))
    }

    func apply(_ override: DayOverride) {
        switch override {
        case .off:
            isOff = true
            startMinutes = nil
            endMinutes = nil
        case .hours(let hours):
            isOff = false
            startMinutes = hours.startMinutes
            endMinutes = hours.endMinutes
        }
    }
}

/// Local effort of a reminder (EventKit has no such field).
@Model
final class ReminderEstimateRecord {
    @Attribute(.unique) var reminderID: String
    var minutes: Int

    init(reminderID: String, minutes: Int) {
        self.reminderID = reminderID
        self.minutes = minutes
    }
}
