import Foundation
import Testing
@testable import TagwerkCore

struct WidgetSnapshotTests {
    let calendar = makeCalendar()
    var today: PlanDay { PlanDay(year: 2026, month: 11, day: 18) }

    private func event(_ title: String, _ startHour: Int, _ endHour: Int, day: Int = 18, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(id: title, externalID: nil, calendarID: "cal", title: title,
                      start: instant(2026, 11, day, startHour, 0, in: calendar),
                      end: instant(2026, 11, day, endHour, 0, in: calendar),
                      isAllDay: allDay, url: nil, isBusy: true, version: "1")
    }

    private func intake(kcal: Double = 1240) -> SnapshotIntake {
        SnapshotIntake(kcal: kcal, hasEstimate: true, goalKcal: 2300, waterMilliliters: 1200, goalWaterMilliliters: 2000)
    }

    private func make(today events: [CalendarEvent] = [], blocks: [CalendarEvent] = [], tomorrow: [CalendarEvent] = [],
                      intake: SnapshotIntake? = nil, habits: SnapshotHabits? = nil, showsNutrition: Bool = true) -> WidgetSnapshot {
        WidgetSnapshot.make(
            createdAt: instant(2026, 11, 18, 8, 0, in: calendar),
            days: [
                SnapshotDayInput(day: today, events: events, blocks: blocks, deadlines: [], colorHex: { _ in "#FF0000" }),
                SnapshotDayInput(day: today.adding(days: 1, calendar: calendar), events: tomorrow, blocks: [], deadlines: [],
                                 colorHex: { _ in nil }),
            ],
            todayIntake: intake, todayHabits: habits, showsNutrition: showsNutrition, calendar: calendar)
    }

    // MARK: Encoding

    @Test func snapshot_roundTripsJSON() throws {
        let snapshot = make(today: [event("Vorlesung", 9, 10)], intake: intake())
        let data = try snapshot.encoded()
        let decoded = try #require(WidgetSnapshot.decode(data))
        #expect(decoded == snapshot)
    }

    @Test func snapshot_unknownVersion_decodesAsNil() throws {
        var snapshot = make()
        snapshot.schemaVersion = 99
        #expect(WidgetSnapshot.decode(try snapshot.encoded()) == nil)
        #expect(WidgetSnapshot.decode(Data("nonsense".utf8)) == nil)
    }

    // MARK: Builder

    @Test func builder_ordersAllDayFirst_limits12() {
        var events = (0..<14).map { event("E\($0)", 8 + $0 % 10, 9 + $0 % 10) }
        events.append(event("Feiertag", 0, 0, allDay: true))
        let snapshot = make(today: events)
        let entries = snapshot.days[0].entries
        #expect(entries.count == WidgetSnapshot.maximumEntriesPerDay + 1)
        #expect(snapshot.days[0].eventCount == 15)
        #expect(entries.first?.title == "Feiertag")
        #expect(entries.first?.isAllDay == true)
        let timed = entries.dropFirst().map(\.start)
        #expect(timed == timed.sorted())
    }

    @Test func builder_allDayEntries_doNotPushOutTimedOnes() {
        let allDay = (0..<5).map { event("Ganztägig \($0)", 0, 0, allDay: true) }
        let timed = (0..<12).map { event("T\($0)", 8 + $0, 9 + $0) }
        let entries = make(today: allDay + timed).days[0].entries
        #expect(entries.filter(\.isAllDay).count == WidgetSnapshot.maximumAllDayEntriesPerDay)
        #expect(entries.filter { !$0.isAllDay }.count == 12)
    }

    @Test func builder_marksBlocks_andCountsDeadlines() {
        let deadline = ImportantDeadline(id: "d", title: "Abgabe", day: today, time: instant(2026, 11, 18, 14, 0, in: calendar),
                                         kind: .priorityOne, taskID: nil, eventID: nil)
        let snapshot = WidgetSnapshot.make(
            createdAt: .now,
            days: [SnapshotDayInput(day: today, events: [event("Termin", 9, 10)], blocks: [event("Block", 11, 12)],
                                    deadlines: [deadline], colorHex: { _ in nil })],
            todayIntake: nil, showsNutrition: true, calendar: calendar)
        let kinds = snapshot.days[0].entries.map(\.kind)
        #expect(kinds == [.event, .block, .deadline])
        #expect(snapshot.days[0].deadlineCount == 1)
    }

    @Test func builder_withoutNutrition_hasNoIntake() {
        let snapshot = make(intake: intake(), showsNutrition: false)
        #expect(snapshot.days.allSatisfy { $0.intake == nil })
    }

    @Test func builder_withoutNutrition_hasNoSteps() {
        let withSteps = SnapshotIntake(kcal: 0, hasEstimate: false, goalKcal: 2300, waterMilliliters: 0, goalWaterMilliliters: 2000,
                                       steps: 6412, goalSteps: 8000)
        #expect(make(intake: withSteps).days[0].intake?.steps == 6412)
        #expect(make(intake: withSteps, showsNutrition: false).days.allSatisfy { $0.intake == nil })
    }

    @Test func snapshot_fileWithoutSteps_stillDecodes() throws {
        // A file written before steps existed: same schema version, no step fields.
        let json = """
        {"createdAt":1795000000,"days":[{"day":{"day":18,"month":11,"year":2026},"deadlineCount":0,"entries":[],
        "intake":{"goalKcal":2300,"goalWaterMilliliters":2000,"hasEstimate":true,"kcal":1240,"waterMilliliters":1200}}],
        "schemaVersion":1}
        """
        let snapshot = try #require(WidgetSnapshot.decode(Data(json.utf8)))
        let intake = try #require(snapshot.days.first?.intake)
        #expect(intake.kcal == 1240)
        #expect(intake.steps == nil)
        #expect(intake.goalSteps == nil)
    }

    @Test func snapshot_oldFileWithoutCredit_decodes_andCountsTheBaseGoalAlone() throws {
        let json = """
        {"createdAt":1795000000,"days":[{"day":{"day":18,"month":11,"year":2026},"deadlineCount":0,"entries":[],
        "intake":{"goalKcal":2300,"goalWaterMilliliters":2000,"hasEstimate":true,"kcal":1240,"waterMilliliters":1200}}],
        "schemaVersion":1}
        """
        let snapshot = try #require(WidgetSnapshot.decode(Data(json.utf8)))
        let intake = try #require(snapshot.days.first?.intake)
        #expect(intake.creditedKcal == nil && intake.budgetKcal == 2300)
    }

    @Test func snapshot_credit_raisesTheBudget_andSurvivesEncoding() throws {
        let intake = SnapshotIntake(kcal: 1240, hasEstimate: true, goalKcal: 2300, waterMilliliters: 1200, goalWaterMilliliters: 2000,
                                    creditedKcal: 260)
        #expect(intake.budgetKcal == 2560)
        let decoded = try JSONDecoder().decode(SnapshotIntake.self, from: JSONEncoder().encode(intake))
        #expect(decoded == intake)
    }

    @Test func builder_intakeOnlyToday() {
        let snapshot = make(intake: intake())
        #expect(snapshot.days[0].intake != nil)
        #expect(snapshot.days[1].intake == nil)
    }

    // MARK: Reading

    @Test func upcoming_includesRunning_skipsEnded() {
        let snapshot = make(today: [event("Früh", 8, 9), event("Läuft", 10, 12), event("Später", 13, 14)])
        let upcoming = snapshot.upcoming(at: instant(2026, 11, 18, 11, 0, in: calendar), calendar: calendar, limit: 3)
        #expect(upcoming.entries.map(\.title) == ["Läuft", "Später"])
        #expect(upcoming.isTomorrow == false)
    }

    @Test func upcoming_emptyToday_returnsTomorrowFirst() {
        let snapshot = make(today: [event("Früh", 8, 9)], tomorrow: [event("Vorlesung", 9, 10, day: 19)])
        let upcoming = snapshot.upcoming(at: instant(2026, 11, 18, 20, 0, in: calendar), calendar: calendar, limit: 3)
        #expect(upcoming.entries.map(\.title) == ["Vorlesung"])
        #expect(upcoming.isTomorrow)
    }

    @Test func upcoming_ignoresAllDay() {
        let snapshot = make(today: [event("Feiertag", 0, 0, allDay: true)])
        let upcoming = snapshot.upcoming(at: instant(2026, 11, 18, 9, 0, in: calendar), calendar: calendar, limit: 3)
        #expect(upcoming.entries.isEmpty)
    }

    @Test func upcoming_afterMidnight_usesNextDayAsToday() {
        let snapshot = make(today: [event("Heute", 9, 10)], tomorrow: [event("Morgen", 9, 10, day: 19)])
        let upcoming = snapshot.upcoming(at: instant(2026, 11, 19, 7, 0, in: calendar), calendar: calendar, limit: 3)
        #expect(upcoming.entries.map(\.title) == ["Morgen"])
        #expect(upcoming.isTomorrow == false)
    }

    @Test func timelineDates_startsEndsAndMidnight_max30() {
        let snapshot = make(today: [event("A", 9, 10), event("B", 13, 14)])
        let now = instant(2026, 11, 18, 8, 0, in: calendar)
        let dates = snapshot.timelineDates(from: now, calendar: calendar)
        #expect(dates.first == now)
        #expect(dates.contains(instant(2026, 11, 18, 9, 0, in: calendar)))
        #expect(dates.contains(instant(2026, 11, 18, 10, 0, in: calendar)))
        #expect(dates.contains(instant(2026, 11, 18, 14, 0, in: calendar)))
        #expect(dates.contains(instant(2026, 11, 19, 0, 0, in: calendar)))
        #expect(dates == dates.sorted())
        let many = make(today: (0..<40).map { event("E\($0)", 8 + $0 % 14, 9 + $0 % 14) })
        #expect(many.timelineDates(from: now, calendar: calendar).count <= WidgetSnapshot.maximumTimelineEntries)
    }

    @Test func isStale_whenTodayNotInDays() {
        let snapshot = make()
        #expect(snapshot.isStale(at: instant(2026, 11, 19, 23, 0, in: calendar), calendar: calendar) == false)
        #expect(snapshot.isStale(at: instant(2026, 11, 20, 0, 1, in: calendar), calendar: calendar))
    }

    @Test func builder_deadlineCalendarEvent_onlyOnce() {
        let exam = event("Klausur", 10, 12)
        let deadline = ImportantDeadline(id: "event:Klausur", title: "Klausur", day: today, time: exam.start,
                                         kind: .deadlineCalendar, taskID: nil, eventID: exam.id)
        let snapshot = WidgetSnapshot.make(
            createdAt: .now,
            days: [SnapshotDayInput(day: today, events: [exam], blocks: [], deadlines: [deadline], colorHex: { _ in nil })],
            todayIntake: nil, showsNutrition: true, calendar: calendar)
        #expect(snapshot.days[0].entries.map(\.kind) == [.deadline])
        #expect(snapshot.days[0].deadlineCount == 1)
    }

    @Test func markedEventCountsAndShowsAsDeadlineRow() {
        let exam = event("Klausur Statistik", 10, 12)
        let tutorial = event("Tutorium", 14, 15)
        let deadlines = importantDeadlines(tasks: [], events: [exam, tutorial], deadlineCalendarIDs: [], markedEventIDs: [exam.id],
                                           in: today...today, calendar: calendar)
        let snapshot = WidgetSnapshot.make(
            createdAt: .now,
            days: [SnapshotDayInput(day: today, events: [exam, tutorial], blocks: [], deadlines: deadlines, colorHex: { _ in nil })],
            todayIntake: nil, showsNutrition: true, calendar: calendar)
        #expect(snapshot.days[0].entries.map(\.kind) == [.deadline, .event])
        #expect(snapshot.days[0].deadlineCount == 1)
    }

    @Test func builder_eventAcrossMidnight_uniqueIDsPerDay() {
        let night = CalendarEvent(id: "night", externalID: nil, calendarID: "cal", title: "Nachtschicht",
                                  start: instant(2026, 11, 18, 22, 0, in: calendar), end: instant(2026, 11, 19, 6, 0, in: calendar),
                                  isAllDay: false, url: nil, isBusy: true, version: "1")
        let snapshot = make(today: [night], tomorrow: [night])
        #expect(snapshot.days[0].entries[0].id != snapshot.days[1].entries[0].id)
    }

    @Test func replacingToday_keepsPlan() {
        let snapshot = make(today: [event("Vorlesung", 9, 10)])
        let updated = snapshot.replacingToday(intake: intake(kcal: 500), habits: nil, on: today, createdAt: instant(2026, 11, 18, 9, 0, in: calendar))
        #expect(updated.days[0].entries == snapshot.days[0].entries)
        #expect(updated.days[0].intake?.kcal == 500)
        let later = updated.replacingToday(intake: intake(kcal: 1), habits: nil, on: today.adding(days: 1, calendar: calendar), createdAt: .now)
        #expect(later.days[0].intake == nil)
        #expect(later.days[1].intake?.kcal == 1)
    }

    @Test func replacingToday_missingDay_staysStale() {
        let snapshot = make(today: [event("Vorlesung", 9, 10)], intake: intake())
        let thursday = today.adding(days: 3, calendar: calendar)
        let updated = snapshot.replacingToday(intake: intake(), habits: nil, on: thursday, createdAt: .now)
        #expect(updated.isStale(at: thursday.startDate(in: calendar).addingTimeInterval(3600), calendar: calendar))
        #expect(updated.days.allSatisfy { $0.intake == nil })
    }

    @Test func todayIntake_afterMidnight_isNil() {
        let snapshot = make(intake: intake())
        #expect(snapshot.intake(at: instant(2026, 11, 18, 23, 0, in: calendar), calendar: calendar) != nil)
        #expect(snapshot.intake(at: instant(2026, 11, 19, 0, 30, in: calendar), calendar: calendar) == nil)
    }

    @Test func deadlineCount_followsTheDay() {
        let deadline = ImportantDeadline(id: "d", title: "Abgabe", day: today, time: nil, kind: .priorityOne, taskID: nil, eventID: nil)
        let snapshot = WidgetSnapshot.make(
            createdAt: .now,
            days: [SnapshotDayInput(day: today, events: [], blocks: [], deadlines: [deadline], colorHex: { _ in nil })],
            todayIntake: nil, showsNutrition: true, calendar: calendar)
        #expect(snapshot.deadlineCount(at: instant(2026, 11, 18, 9, 0, in: calendar), calendar: calendar) == 1)
        #expect(snapshot.deadlineCount(at: instant(2026, 11, 19, 9, 0, in: calendar), calendar: calendar) == 0)
    }

    @Test func overviewText_countsAndNext() {
        let deadline = ImportantDeadline(id: "d", title: "Abgabe", day: today, time: nil, kind: .priorityOne, taskID: nil, eventID: nil)
        let snapshot = WidgetSnapshot.make(
            createdAt: .now,
            days: [SnapshotDayInput(day: today, events: [event("Vorlesung", 9, 10), event("Sport", 17, 18)],
                                    blocks: [event("Issue #12 Login", 10, 12)], deadlines: [deadline], colorHex: { _ in nil })],
            todayIntake: intake(), showsNutrition: true, calendar: calendar)
        let text = snapshot.overviewText(at: instant(2026, 11, 18, 9, 30, in: calendar), calendar: calendar)
        #expect(text == "Heute: 2 Termine, 1 Block, 1 Deadline. Als Nächstes 09:00 Vorlesung.")
        #expect(!text.contains("kcal"))
    }

    @Test func overviewText_nothingLeftToday() {
        let snapshot = make(today: [event("Vorlesung", 9, 10)])
        #expect(snapshot.overviewText(at: instant(2026, 11, 18, 20, 0, in: calendar), calendar: calendar)
            == "Heute: 1 Termin. Davon steht nichts mehr an.")
    }

    @Test func overviewText_emptyDay() {
        let snapshot = make()
        #expect(snapshot.overviewText(at: instant(2026, 11, 18, 9, 0, in: calendar), calendar: calendar)
            == "Heute steht nichts an.")
    }

    // MARK: Habits (phase 7)

    @Test func habits_belongToTodayOnly() {
        let snapshot = make(habits: SnapshotHabits(done: 3, total: 5))
        #expect(snapshot.days[0].habits == SnapshotHabits(done: 3, total: 5))
        #expect(snapshot.days[1].habits == nil)
        #expect(snapshot.habits(at: instant(2026, 11, 18, 9, 0, in: calendar), calendar: calendar) == SnapshotHabits(done: 3, total: 5))
        #expect(snapshot.habits(at: instant(2026, 11, 19, 0, 30, in: calendar), calendar: calendar) == nil)
    }

    @Test func habits_stayWhenNutritionIsHidden() {
        let snapshot = make(intake: intake(), habits: SnapshotHabits(done: 1, total: 2), showsNutrition: false)
        #expect(snapshot.days[0].intake == nil)
        #expect(snapshot.days[0].habits == SnapshotHabits(done: 1, total: 2))
    }

    @Test func oldFileWithoutHabits_decodes() throws {
        let snapshot = make(today: [event("Vorlesung", 9, 10)], intake: intake())
        var json = try #require(JSONSerialization.jsonObject(with: snapshot.encoded()) as? [String: Any])
        var days = try #require(json["days"] as? [[String: Any]])
        days = days.map { var copy = $0; copy.removeValue(forKey: "habits"); return copy }
        json["days"] = days
        let decoded = try #require(WidgetSnapshot.decode(JSONSerialization.data(withJSONObject: json)))
        #expect(decoded.days[0].habits == nil && decoded.schemaVersion == 1)
    }

    @Test func replacingToday_replacesIntakeAndHabits_keepsEntries() {
        let snapshot = make(today: [event("Vorlesung", 9, 10)], intake: intake(kcal: 100), habits: SnapshotHabits(done: 0, total: 2))
        let updated = snapshot.replacingToday(intake: intake(kcal: 500), habits: SnapshotHabits(done: 1, total: 2), on: today,
                                              createdAt: instant(2026, 11, 18, 9, 0, in: calendar))
        #expect(updated.days[0].entries == snapshot.days[0].entries)
        #expect(updated.days[0].intake?.kcal == 500 && updated.days[0].habits == SnapshotHabits(done: 1, total: 2))
        let later = updated.replacingToday(intake: nil, habits: SnapshotHabits(done: 2, total: 2),
                                           on: today.adding(days: 1, calendar: calendar), createdAt: .now)
        #expect(later.days[0].habits == nil && later.days[1].habits == SnapshotHabits(done: 2, total: 2))
    }

    @Test func snapshot_containsNoHabitNames() throws {
        let snapshot = make(habits: SnapshotHabits(done: 1, total: 2))
        let text = String(decoding: try snapshot.encoded(), as: UTF8.self)
        #expect(!text.contains("Lesen 20 min"))
        #expect(text.contains("\"habits\":{\"done\":1,\"total\":2}"))
    }
}
