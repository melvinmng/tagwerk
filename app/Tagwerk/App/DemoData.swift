#if DEBUG && targetEnvironment(simulator)
import EventKit
import Foundation
import TagwerkCore

/// Simulator-only sample data for manual checks, enabled with the launch argument `-TagwerkDemoData`.
/// It wipes and recreates dedicated calendars and a reminder list (all prefixed "Demo"), so it never
/// touches other data and never runs on a device.
@MainActor
enum DemoData {
    static let launchArgument = "-TagwerkDemoData"
    private static let prefix = "Demo "
    private static let planCalendarTitle = "Demo Tagwerk"

    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains(launchArgument) }

    static func seedIfRequested(_ environment: AppEnvironment) async {
        guard isRequested else { return }
        let store = EKEventStore()
        do {
            guard try await store.requestFullAccessToEvents(), try await store.requestFullAccessToReminders() else {
                print("DemoData: calendar or reminder access denied; grant it with simctl privacy")
                return
            }
            try wipe(store)
            let ids = try seed(store)
            let settings = environment.settings
            settings.setupCompleted = true
            settings.selectedCalendarIDs = nil
            settings.selectedReminderListIDs = [ids.reminderList]
            settings.planCalendarID = ids.planCalendar
            settings.deadlineCalendarIDs = [ids.deadlineCalendar]
            await environment.taskList.reload()
            await environment.planning.reload()
            print("DemoData: sample data created")
        } catch {
            print("DemoData: seeding failed: \(error)")
        }
    }

    private static func wipe(_ store: EKEventStore) throws {
        for calendar in store.calendars(for: .event) + store.calendars(for: .reminder)
        where calendar.title.hasPrefix(prefix) || calendar.title == planCalendarTitle {
            try store.removeCalendar(calendar, commit: false)
        }
        try store.commit()
    }

    private struct SeededIDs {
        let reminderList: String
        let planCalendar: String
        let deadlineCalendar: String
    }

    private static func seed(_ store: EKEventStore) throws -> SeededIDs {
        let calendar = Calendar.tagwerk
        let today = calendar.startOfDay(for: Date())
        func at(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: dayOffset, to: today)!
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        }
        func dayComponents(_ dayOffset: Int) -> DateComponents {
            calendar.dateComponents([.year, .month, .day], from: calendar.date(byAdding: .day, value: dayOffset, to: today)!)
        }

        let source = store.sources.first { $0.sourceType == .local } ?? store.defaultCalendarForNewEvents?.source
        guard let source else { throw TaskWriteError.failed("No calendar source") }

        func makeCalendar(_ title: String, for type: EKEntityType, color: CGColor) throws -> EKCalendar {
            let item = EKCalendar(for: type, eventStore: store)
            item.title = title
            item.cgColor = color
            item.source = type == .reminder ? (store.defaultCalendarForNewReminders()?.source ?? source) : source
            try store.saveCalendar(item, commit: false)
            return item
        }
        let work = try makeCalendar("Demo Termine", for: .event, color: CGColor(srgbRed: 0.2, green: 0.5, blue: 1, alpha: 1))
        let copy = try makeCalendar("Demo Freigabe", for: .event, color: CGColor(srgbRed: 0.6, green: 0.4, blue: 1, alpha: 1))
        let uni = try makeCalendar("Demo Uni", for: .event, color: CGColor(srgbRed: 0.4, green: 0.8, blue: 0.3, alpha: 1))
        let plan = try makeCalendar(planCalendarTitle, for: .event, color: CGColor(srgbRed: 0.18, green: 0.72, blue: 0.63, alpha: 1))
        let list = try makeCalendar("Demo Aufgaben", for: .reminder, color: CGColor(srgbRed: 1, green: 0.3, blue: 0.3, alpha: 1))

        func event(_ title: String, _ calendarItem: EKCalendar, _ start: Date, _ end: Date, allDay: Bool = false) throws {
            let item = EKEvent(eventStore: store)
            item.calendar = calendarItem
            item.title = title
            item.startDate = start
            item.endDate = end
            item.isAllDay = allDay
            try store.save(item, span: .thisEvent, commit: false)
        }
        // The same meeting in two calendars reproduces duplicate rows.
        try event("Seminar", work, at(0, 10), at(0, 12, 30))
        try event("Seminar", copy, at(0, 10), at(0, 12, 30))
        try event("Sprechstunde", work, at(0, 15), at(0, 16))
        try event("Projektwoche", work, at(0, 0), at(1, 0), allDay: true)
        try event("Anmeldung Abschlussarbeit", uni, at(0, 0), at(1, 0), allDay: true)
        try event("Klausur Statistik", uni, at(3, 10), at(3, 12))
        try event("Abgabe Hausarbeit", uni, at(40, 0), at(41, 0), allDay: true)
        try event("Teamtreffen", work, at(1, 9, 30), at(1, 11))

        func reminder(_ title: String, due: Int?, priority: Int = 0, recurrence: EKRecurrenceRule? = nil) throws {
            let item = EKReminder(eventStore: store)
            item.calendar = list
            item.title = title
            item.priority = priority
            item.dueDateComponents = due.map(dayComponents)
            if let recurrence { item.addRecurrenceRule(recurrence) }
            try store.save(item, commit: false)
        }
        try reminder("Training", due: 0, recurrence: EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil))
        try reminder("Karteikarten", due: 0, recurrence: EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil))
        try reminder("Pretest vorbereiten", due: 1, priority: 1)
        try reminder("Bericht überarbeiten", due: -2, priority: 5)
        try reminder("Literatur sichten", due: 0)
        try reminder("Einkaufen", due: nil)
        try store.commit()
        return SeededIDs(reminderList: list.calendarIdentifier, planCalendar: plan.calendarIdentifier,
                         deadlineCalendar: uni.calendarIdentifier)
    }
}
#endif
