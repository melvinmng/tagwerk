import Foundation
import Testing
import TagwerkCore
@testable import RemindersKit

struct ReminderMappingTests {
    let list = ListInfo(id: "studium", title: "Studium", colorHex: "#FF9500", kind: .calDAV)

    @Test func priority_fromEK_mapsAllValues() {
        let expected: [Int: Priority?] = [
            0: nil, 1: .p1, 2: .p2, 3: .p2, 4: .p2, 5: .p3, 6: .p4, 7: .p4, 8: .p4, 9: .p5,
        ]
        for (ek, priority) in expected {
            #expect(ReminderMapping.priority(fromEK: ek) == priority, "EK \(ek)")
        }
    }

    @Test func ekPriority_roundTripOfReminderAppValues() {
        for ek in [0, 1, 5, 9] {
            #expect(ReminderMapping.ekPriority(from: ReminderMapping.priority(fromEK: ek)) == ek)
        }
        #expect(ReminderMapping.ekPriority(from: .p2) == 3)
        #expect(ReminderMapping.ekPriority(from: .p4) == 7)
    }

    @Test func taskItem_mapsDateOnlyDue() {
        let record = ReminderRecord(
            id: "r1", title: "Literaturliste", notes: nil, due: DueDate(year: 2026, month: 11, day: 20),
            ekPriority: 0, isCompleted: false, listID: "studium", lastModified: Date(timeIntervalSince1970: 42)
        )
        let item = ReminderMapping.taskItem(record, list: list)
        #expect(item.id == TaskID(source: .reminders, rawValue: "r1"))
        #expect(item.due == DueDate(year: 2026, month: 11, day: 20))
        #expect(item.due?.hasTime == false)
        #expect(item.priority == nil)
        #expect(item.container == TaskContainer(id: "studium", name: "Studium", colorHex: "#FF9500"))
        #expect(item.version == "42.0")
        #expect(item.editableFields == [.title, .notes, .due, .priority, .container])
    }

    @Test func taskItem_withoutLastModified_hasVersionZero() {
        let record = ReminderRecord(
            id: "r1", title: "x", notes: nil, due: nil, ekPriority: 0,
            isCompleted: false, listID: "studium", lastModified: nil
        )
        #expect(ReminderMapping.taskItem(record, list: list).version == "0")
    }

    @Test func applying_titleOnly_keepsPriorityNotesAndTime() {
        let record = ReminderRecord(
            id: "r1", title: "Alt", notes: "Notiz", due: DueDate(year: 2026, month: 11, day: 20, hour: 14, minute: 30),
            ekPriority: 2, isCompleted: false, listID: "studium", lastModified: nil
        )
        var edit = TaskEdit()
        edit.title = .set("Neu")

        let result = ReminderMapping.applying(edit, to: record)

        #expect(result.title == "Neu")
        #expect(result.ekPriority == 2)
        #expect(result.notes == "Notiz")
        #expect(result.due == DueDate(year: 2026, month: 11, day: 20, hour: 14, minute: 30))
        #expect(result.listID == "studium")
    }

    @Test func applying_allFields() {
        let record = ReminderRecord(
            id: "r1", title: "Alt", notes: "Notiz", due: nil, ekPriority: 0,
            isCompleted: false, listID: "studium", lastModified: nil
        )
        var edit = TaskEdit()
        edit.notes = .set(nil)
        edit.due = .set(DueDate(year: 2026, month: 12, day: 1))
        edit.priority = .set(.p1)
        edit.containerID = .set("privat")
        edit.isCompleted = .set(true)

        let result = ReminderMapping.applying(edit, to: record)

        #expect(result.notes == nil)
        #expect(result.due == DueDate(year: 2026, month: 12, day: 1))
        #expect(result.ekPriority == 1)
        #expect(result.listID == "privat")
        #expect(result.isCompleted)
    }
}

struct CalendarSelectionTests {
    @Test func defaultSelected_excludesSubscriptionAndBirthday() {
        let calendars = [
            ListInfo(id: "work", title: "Arbeit", colorHex: nil, kind: .calDAV),
            ListInfo(id: "home", title: "Privat", colorHex: nil, kind: .local),
            ListInfo(id: "ex", title: "Exchange", colorHex: nil, kind: .exchange),
            ListInfo(id: "holidays", title: "Feiertage", colorHex: nil, kind: .subscription),
            ListInfo(id: "birthdays", title: "Geburtstage", colorHex: nil, kind: .birthday),
        ]
        #expect(CalendarSelection.defaultSelected(calendars) == ["work", "home", "ex"])
    }
}

struct ReminderAlarmTests {
    let old = Date(timeIntervalSince1970: 1_000_000)
    let new = Date(timeIntervalSince1970: 1_086_400)

    @Test func alarmAtOldDue_movesWithDue() {
        #expect(ReminderMapping.movedAlarmDates([old], from: old, to: new) == [new])
    }

    @Test func otherAlarms_stay() {
        let earlier = old.addingTimeInterval(-3600)
        #expect(ReminderMapping.movedAlarmDates([earlier, old], from: old, to: new) == [earlier, new])
    }

    @Test func dateOnlyOldOrNew_leavesAlarms() {
        #expect(ReminderMapping.movedAlarmDates([old], from: nil, to: new) == [old])
        #expect(ReminderMapping.movedAlarmDates([old], from: old, to: nil) == [old])
    }

    @Test func newReminderWithTime_getsAlarmAtDue() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let due = DueDate(year: 2026, month: 11, day: 20, hour: 14, minute: 30)
        #expect(ReminderMapping.alarmDate(for: due, calendar: calendar) == due.startDate(in: calendar))
        #expect(ReminderMapping.alarmDate(for: DueDate(year: 2026, month: 11, day: 20), calendar: calendar) == nil)
        #expect(ReminderMapping.alarmDate(for: nil, calendar: calendar) == nil)
    }
}
