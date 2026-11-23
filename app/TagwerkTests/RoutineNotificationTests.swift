import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct RoutineNotificationTests {
    let container: ModelContainer
    let settings: AppSettings
    let store: RoutineStore
    let center = FakeNotificationCenter()

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        settings = try AppSettings.current(in: container.mainContext)
        store = RoutineStore(context: container.mainContext)
    }

    /// The clock of the scheduler; Wednesday 2026-11-18 10:00 in Berlin unless a test moves it.
    final class Clock { var now = testNow() }
    let clock = Clock()
    let calendar = testCalendar()
    let today = PlanDay(year: 2026, month: 11, day: 18)

    private func makeScheduler() -> RoutineNotificationScheduler {
        let clock = self.clock
        return RoutineNotificationScheduler(center: center, store: store, settings: settings, now: { clock.now }, calendar: calendar,
                                            locale: { Locale(identifier: "de_DE") })
    }

    /// The four points of the suggestion that remind (60, 90, 60 and 30 minutes before bedtime).
    private func reminderItems() -> [ChecklistItem] { RoutineSchedule.reminderItems(store.checklist()) }

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func eveningID(_ item: ChecklistItem, day: Int) -> String {
        RoutineSchedule.eveningIdentifier(item: item.id, day: PlanDay(year: 2026, month: 11, day: day))
    }

    @Test func reschedule_replacesAllRoutineRequests() async {
        store.adoptSuggestion()
        center.seed("tagwerk.routine.evening.OLD", fireDate: nil)
        await makeScheduler().reschedule()
        #expect(!center.pendingIDs.contains("tagwerk.routine.evening.OLD"))
        #expect(center.pendingIDs.count == 12 && center.pendingIDs.allSatisfy { $0.hasPrefix("tagwerk.routine.evening.") })
        #expect(center.addedRepeating.isEmpty)
    }

    @Test func reschedule_addsDatedEveningRemindersForThreeDays() async {
        store.adoptSuggestion()
        await makeScheduler().reschedule()
        let titles = ["Alle Aufgaben bis eine Stunde vorm Schlafen erledigen", "Helle Lichter ausmachen",
                      "Eine Stunde vorm Schlafen fertig machen", "Eine halbe Stunde vorm Schlafen ins Bett legen"]
        // Offsets 90, 60, 60 and 30 before 23:00 give 21:30, 22:00, 22:00 and 22:30 on each of the three days; the two points at
        // 22:00 are two requests.
        #expect(center.addedDated.count == 12)
        #expect(center.addedDated.map(\.title) == Array(repeating: titles, count: 3).flatMap { $0 })
        #expect(center.addedDated.map(\.day) == [18, 18, 18, 18, 19, 19, 19, 19, 20, 20, 20, 20])
        #expect(center.addedDated.prefix(4).map { "\($0.hour):\($0.minute)" } == ["21:30", "22:0", "22:0", "22:30"])
        #expect(Set(center.addedDated.map(\.id)).count == 12)
    }

    @Test func reschedule_removesOldRepeatingEveningRequests() async {
        store.adoptSuggestion()
        let item = reminderItems()[0]
        // What the earlier version left behind: no date in the identifier.
        center.seed("tagwerk.routine.evening.\(item.id.uuidString)", fireDate: nil)
        await makeScheduler().reschedule()
        #expect(!center.pendingIDs.contains("tagwerk.routine.evening.\(item.id.uuidString)"))
        #expect(center.pendingIDs.contains(eveningID(item, day: 18)))
    }

    @Test func reschedule_keepsMorningAndWeekRepeating() async {
        store.adoptSuggestion()
        settings.morningReminderEnabled = true
        settings.weekPlanningReminderEnabled = true
        await makeScheduler().reschedule()
        #expect(center.addedRepeating.map(\.id).sorted() == ["tagwerk.routine.morning", "tagwerk.routine.week"])
        #expect(center.addedDated.count == 12)
        #expect(center.pendingIDs.count == 14)
    }

    @Test func reschedule_skipsCheckedItemsOnTheirDayOnly() async {
        store.adoptSuggestion()
        let item = reminderItems()[1]
        store.update(today) { $0.checkedItemIDs.insert(item.id) }
        await makeScheduler().reschedule()
        #expect(!center.pendingIDs.contains(eveningID(item, day: 18)))
        #expect(center.pendingIDs.contains(eveningID(item, day: 19)) && center.pendingIDs.contains(eveningID(item, day: 20)))
        #expect(center.pendingIDs.count == 11)
    }

    @Test func reschedule_twoItemsAtTheSameMinute_bothPending() async {
        store.adoptSuggestion()
        await makeScheduler().reschedule()
        let atTen = center.addedDated.filter { $0.day == 18 && $0.hour == 22 && $0.minute == 0 }
        #expect(atTen.count == 2 && center.pendingIDs.isSuperset(of: atTen.map(\.id)))
    }

    @Test func reschedule_openItemsRemindAfterTheWrapUpWasCompleted() async {
        store.adoptSuggestion()
        store.update(today) { $0.closeCompletedAt = testNow() }
        await makeScheduler().reschedule()
        #expect(center.pendingIDs.count == 12)
    }

    @Test func reschedule_keepsDeadlineRequests() async {
        store.adoptSuggestion()
        center.seed("tagwerk.task.local:1", fireDate: testNow().addingTimeInterval(3600))
        await makeScheduler().reschedule()
        #expect(center.pendingIDs.contains("tagwerk.task.local:1"))
    }

    @Test func reschedule_withoutPermission_addsNothing() async {
        store.adoptSuggestion()
        center.status = .denied
        center.seed("tagwerk.routine.evening.OLD", fireDate: nil)
        await makeScheduler().reschedule()
        #expect(center.addedRepeating.isEmpty && center.addedDated.isEmpty)
        // Without permission nothing can stay pending either.
        #expect(!center.pendingIDs.contains("tagwerk.routine.evening.OLD"))
    }

    @Test func reschedule_whenSwitchedOff_removesTheRequests() async {
        store.adoptSuggestion()
        let scheduler = makeScheduler()
        await scheduler.reschedule()
        settings.eveningRemindersEnabled = false
        await scheduler.reschedule()
        #expect(center.pendingIDs.isEmpty)
    }

    @Test func reschedule_followsTheBedtime() async {
        store.adoptSuggestion()
        settings.bedtimeMinutes = 1320
        await makeScheduler().reschedule()
        let first = center.addedDated.first
        #expect(first?.hour == 20 && first?.minute == 30)
    }

    @Test func reschedule_neverExceedsFourteen() async {
        store.adoptSuggestion()
        store.saveItem(ChecklistItem(title: "Vierter", order: 5, offsetMinutes: 15))
        // A fifth reminder point is refused by the store; the limit of the plan holds on top of it.
        #expect(!store.saveItem(ChecklistItem(title: "Fünfter", order: 6, offsetMinutes: 10)))
        settings.morningReminderEnabled = true
        settings.weekPlanningReminderEnabled = true
        await makeScheduler().reschedule()
        let routineIDs = center.pendingIDs.filter { $0.hasPrefix("tagwerk.routine.") }
        // Four points on three days, plus the morning start and the weekly planning.
        #expect(routineIDs.count == 14)
        #expect(routineIDs.count <= RoutineSchedule.maximumRoutineNotifications)
        #expect(routineIDs.count <= NotificationBudget.routines)
        #expect(center.addedDated.count == RoutineSchedule.maximumEveningNotifications)
        let week = center.addedRepeating.first { $0.id == "tagwerk.routine.week" }
        #expect(week?.weekday == 1 && week?.hour == 18 && week?.route == .routineWeek)
    }

    @Test func reschedule_weekReminderOffByDefault() async {
        store.adoptSuggestion()
        await makeScheduler().reschedule()
        #expect(!center.pendingIDs.contains("tagwerk.routine.week"))
    }

    @Test func reschedule_addsTheMorningRequest_whenEnabled() async {
        store.adoptSuggestion()
        store.saveItem(ChecklistItem(title: "Vierter", order: 3, offsetMinutes: 15))
        settings.morningReminderEnabled = true
        await makeScheduler().reschedule()
        #expect(center.pendingIDs.contains("tagwerk.routine.morning"))
        #expect(center.pendingIDs.count == 13)
        #expect(center.addedRepeating.first { $0.id == "tagwerk.routine.morning" }?.route == .routineStart)
    }

    @Test func reschedule_morningStaysOffByDefault() async {
        await makeScheduler().reschedule()
        #expect(!center.pendingIDs.contains("tagwerk.routine.morning"))
    }

    @Test func reschedule_morningFollowsItsTime() async {
        settings.morningReminderEnabled = true
        settings.morningReminderMinutes = 8 * 60
        await makeScheduler().reschedule()
        #expect(center.addedRepeating.first?.hour == 8 && center.addedRepeating.first?.minute == 0)
    }

    // MARK: Checking a point

    @Test func itemChecked_removesOnlyThatDaysRequest() async {
        store.adoptSuggestion()
        let items = reminderItems()
        let scheduler = makeScheduler()
        await scheduler.reschedule()
        await scheduler.itemChecked(items[0].id, on: today)
        #expect(!center.pendingIDs.contains(eveningID(items[0], day: 18)))
        #expect(center.pendingIDs.contains(eveningID(items[0], day: 19)) && center.pendingIDs.contains(eveningID(items[0], day: 20)))
        #expect(center.pendingIDs.contains(eveningID(items[1], day: 18)))
        #expect(center.pendingIDs.count == 11)
    }

    @Test func uncheck_readdsWhenStillAhead() async {
        store.adoptSuggestion()
        let item = reminderItems()[0]
        let scheduler = makeScheduler()
        store.update(today) { $0.checkedItemIDs.insert(item.id) }
        await scheduler.reschedule()
        #expect(!center.pendingIDs.contains(eveningID(item, day: 18)))
        store.update(today) { $0.checkedItemIDs.remove(item.id) }
        await scheduler.reschedule()
        #expect(center.pendingIDs.contains(eveningID(item, day: 18)))
        #expect(center.pendingIDs.count == 12)
    }

    @Test func uncheck_afterItsTime_addsNothing() async {
        store.adoptSuggestion()
        let item = reminderItems()[1]
        let scheduler = makeScheduler()
        store.update(today) { $0.checkedItemIDs.insert(item.id) }
        await scheduler.reschedule()
        // 21:30 is over at 21:45; unchecking brings nothing back for tonight.
        clock.now = at(18, 21, 45)
        store.update(today) { $0.checkedItemIDs.remove(item.id) }
        await scheduler.reschedule()
        #expect(!center.pendingIDs.contains(eveningID(item, day: 18)))
        #expect(center.pendingIDs.contains(eveningID(item, day: 19)))
    }

    @Test func denied_addsNothing() async {
        store.adoptSuggestion()
        center.status = .denied
        let scheduler = makeScheduler()
        await scheduler.reschedule()
        await scheduler.itemChecked(reminderItems()[0].id, on: today)
        #expect(center.addedDated.isEmpty && center.addedRepeating.isEmpty && center.pendingIDs.isEmpty)
    }

    @Test func reschedule_afterMidnight_startsWithTheRoutineDayBefore() async {
        store.adoptSuggestion()
        settings.bedtimeMinutes = 30
        let late = reminderItems()[3]    // 30 minutes before 00:30 is 00:00 on the calendar day after the routine day
        clock.now = at(19, 0, 0).addingTimeInterval(-60)  // 23:59 on the 18th: routine day 18, its 00:00 reminder is ahead
        await makeScheduler().reschedule()
        #expect(center.pendingIDs.contains(eveningID(late, day: 18)))
        let first = center.addedDated.first { $0.id == eveningID(late, day: 18) }
        #expect(first?.day == 19 && first?.hour == 0 && first?.minute == 0)
        // At 01:00 the same moment is over, the next routine days stay.
        clock.now = at(19, 1, 0)
        await makeScheduler().reschedule()
        #expect(!center.pendingIDs.contains(eveningID(late, day: 18)))
        #expect(center.pendingIDs.contains(eveningID(late, day: 19)) && center.pendingIDs.contains(eveningID(late, day: 20)))
    }

    // MARK: Bible Study (BS7)

    /// The scheduler with the Bible Study sessions of a note store behind it, the way the app wires it.
    private func makeScheduler(notes: NoteStore) -> RoutineNotificationScheduler {
        let clock = self.clock
        return RoutineNotificationScheduler(
            center: center, store: store, settings: settings, now: { clock.now }, calendar: calendar, locale: { Locale(identifier: "de_DE") },
            bibleStudyCompletedDays: { notes.completedSessionDays(in: $0) },
            bibleStudyNextPassage: { showsPassage, locale in
                let continuation = notes.reminderContinuation()
                return BibleStudyReminders.nextPassageText(bookName: continuation?.book.name(locale: locale), next: continuation?.next,
                                                           showsPassage: showsPassage, locale: locale)
            })
    }

    private func bibleID(_ day: Int) -> String { BibleStudyReminders.identifier(day: PlanDay(year: 2026, month: 11, day: day)) }

    /// A reminder at 20:30 on every day: today (still ahead at 10:00) and the next two days.
    private func enableBibleStudy(showsPassage: Bool = true) {
        settings.bibleStudyReminderEnabled = true
        settings.bibleStudyReminderTimes = [BibleStudyReminderTime(minutes: 20 * 60 + 30, weekdays: Set(1...7))]
        settings.bibleStudyReminderShowsPassage = showsPassage
    }

    /// A completed session of Römer 3,1–26 on a day in the past.
    @discardableResult
    private func finishedSession(in notes: NoteStore, dayKey: String) -> BibleStudySessionRecord {
        let romans = BibleBooks.book(number: 45)!
        let started = notes.startSession(book: romans, passage: BiblePassage(start: BibleReference(chapter: 3, verse: 1),
                                                                              end: BibleReference(chapter: 3, verse: 26)),
                                         dayKey: dayKey, dateText: dayKey, locale: Locale(identifier: "de_DE"))
        notes.completeSession(started.session.id)
        return started.session
    }

    @Test func reschedule_addsBibleStudyReminders() async {
        enableBibleStudy()
        let notes = NoteStore(context: container.mainContext, now: { [clock] in clock.now })
        finishedSession(in: notes, dayKey: "2026-11-17")
        await makeScheduler(notes: notes).reschedule()
        let bible = center.addedDated.filter { $0.id.hasPrefix("tagwerk.routine.bible.") }
        #expect(bible.map(\.id) == [bibleID(18), bibleID(19), bibleID(20)])
        #expect(bible.allSatisfy { $0.hour == 20 && $0.minute == 30 && $0.route == .bibleStudyStart })
        #expect(bible.first?.body == "Zeit für Bible Study. Weiter in Römer ab 3,27.")
        #expect(bible.first?.categoryIdentifier == BibleStudyReminders.categoryIdentifier)
    }

    @Test func reschedule_withoutThePassageSwitch_namesNoVerse() async {
        enableBibleStudy(showsPassage: false)
        let notes = NoteStore(context: container.mainContext, now: { [clock] in clock.now })
        finishedSession(in: notes, dayKey: "2026-11-17")
        await makeScheduler(notes: notes).reschedule()
        #expect(center.addedDated.first { $0.id == bibleID(18) }?.body == "Zeit für Bible Study.")
    }

    @Test func reschedule_neverExceedsSeventeen() async {
        store.adoptSuggestion()
        settings.morningReminderEnabled = true
        settings.weekPlanningReminderEnabled = true
        enableBibleStudy()
        let notes = NoteStore(context: container.mainContext, now: { [clock] in clock.now })
        await makeScheduler(notes: notes).reschedule()
        // 12 evening points, the morning start and the weekly planning, and the three days of Bible Study.
        #expect(center.pendingIDs.count == RoutineSchedule.maximumRoutineNotifications)
        #expect(center.pendingIDs.count == 17)
        #expect(center.pendingIDs.filter { $0.hasPrefix("tagwerk.routine.bible.") }.count == 3)
    }

    @Test func completeSession_removesTodaysReminderAndReplans() async {
        enableBibleStudy()
        let notes = NoteStore(context: container.mainContext, now: { [clock] in clock.now })
        let scheduler = makeScheduler(notes: notes)
        await scheduler.reschedule()
        #expect(center.pendingIDs.contains(bibleID(18)))
        // A session of today is completed: the reminder of today goes, the next days name the verse after it.
        finishedSession(in: notes, dayKey: "2026-11-18")
        await scheduler.reschedule()
        #expect(!center.pendingIDs.contains(bibleID(18)))
        #expect(center.pendingIDs.contains(bibleID(19)) && center.pendingIDs.contains(bibleID(20)))
        #expect(center.addedDated.last { $0.id == bibleID(19) }?.body == "Zeit für Bible Study. Weiter in Römer ab 3,27.")
    }

    @Test func skippedDay_isLeftOut() async {
        enableBibleStudy()
        settings.bibleStudySkippedDayKey = "2026-11-18"
        let notes = NoteStore(context: container.mainContext, now: { [clock] in clock.now })
        await makeScheduler(notes: notes).reschedule()
        #expect(!center.pendingIDs.contains(bibleID(18)) && center.pendingIDs.contains(bibleID(19)))
    }

    @Test func skipFromYesterday_doesNotAffectToday() async {
        enableBibleStudy()
        settings.bibleStudySkippedDayKey = "2026-11-17"
        let notes = NoteStore(context: container.mainContext, now: { [clock] in clock.now })
        await makeScheduler(notes: notes).reschedule()
        #expect(center.pendingIDs.contains(bibleID(18)))
    }

    @Test func removeBibleStudyReminder_dropsOnlyThatDay() async {
        enableBibleStudy()
        let notes = NoteStore(context: container.mainContext, now: { [clock] in clock.now })
        let scheduler = makeScheduler(notes: notes)
        await scheduler.reschedule()
        await scheduler.removeBibleStudyReminder(on: PlanDay(year: 2026, month: 11, day: 18))
        #expect(!center.pendingIDs.contains(bibleID(18)) && center.pendingIDs.contains(bibleID(19)))
    }

    @Test func freeTextSession_namesNoVerse() async {
        enableBibleStudy()
        let notes = NoteStore(context: container.mainContext, now: { [clock] in clock.now })
        let started = notes.startSession(book: BibleBooks.book(number: 45)!, passage: nil, freeText: "Kap. 3", dayKey: "2026-11-17",
                                         dateText: "17.11.2026", locale: Locale(identifier: "de_DE"))
        notes.completeSession(started.session.id)
        await makeScheduler(notes: notes).reschedule()
        #expect(center.addedDated.first { $0.id == bibleID(18) }?.body == "Zeit für Bible Study.")
    }
}
