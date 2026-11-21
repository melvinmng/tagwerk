import Foundation
import Testing
@testable import TagwerkCore

struct RoutineScheduleTests {
    let calendar = makeCalendar()

    private func item(_ title: String, order: Int, offset: Int?) -> ChecklistItem {
        ChecklistItem(id: UUID(), title: title, order: order, offsetMinutes: offset)
    }

    @Test func anchor_wrapsAroundMidnight() {
        #expect(RoutineSchedule.anchorMinutes(bedtimeMinutes: 1380, offsetMinutes: 90) == 1290)
        #expect(RoutineSchedule.anchorMinutes(bedtimeMinutes: 30, offsetMinutes: 90) == 1380)
        #expect(RoutineSchedule.anchorMinutes(bedtimeMinutes: 1380, offsetMinutes: 0) == 1380)
    }

    @Test func routineDay_beforeFourBelongsToTheDayBefore() {
        #expect(RoutineSchedule.routineDay(at: instant(2026, 11, 19, 3, 59), calendar: calendar) == PlanDay(year: 2026, month: 11, day: 18))
        #expect(RoutineSchedule.routineDay(at: instant(2026, 11, 19, 4, 0), calendar: calendar) == PlanDay(year: 2026, month: 11, day: 19))
        #expect(RoutineSchedule.routineDay(at: instant(2026, 12, 1, 0, 10), calendar: calendar) == PlanDay(year: 2026, month: 11, day: 30))
    }

    @Test func currentRoutine_beforeNoon_isStart() {
        #expect(RoutineSchedule.currentRoutine(at: instant(2026, 11, 19, 4, 0), calendar: calendar) == .routineStart)
        #expect(RoutineSchedule.currentRoutine(at: instant(2026, 11, 19, 11, 59), calendar: calendar) == .routineStart)
    }

    @Test func currentRoutine_fromNoon_isEvening() {
        #expect(RoutineSchedule.currentRoutine(at: instant(2026, 11, 19, 12, 0), calendar: calendar) == .routineEvening)
        #expect(RoutineSchedule.currentRoutine(at: instant(2026, 11, 19, 23, 59), calendar: calendar) == .routineEvening)
    }

    @Test func currentRoutine_at0330_isEvening() {
        // Still the wrap-up of the day before (rule 10).
        let moment = instant(2026, 11, 19, 3, 30)
        #expect(RoutineSchedule.currentRoutine(at: moment, calendar: calendar) == .routineEvening)
        #expect(RoutineSchedule.routineDay(at: moment, calendar: calendar) == PlanDay(year: 2026, month: 11, day: 18))
        #expect(RoutineSchedule.currentRoutine(at: instant(2026, 11, 19, 3, 59), calendar: calendar) == .routineEvening)
    }

    @Test func morningCard_showsFromFourToNoon() {
        #expect(!RoutineSchedule.showsMorningCard(minutesOfDay: 239, completed: false, dismissed: false))
        #expect(RoutineSchedule.showsMorningCard(minutesOfDay: 240, completed: false, dismissed: false))
        #expect(RoutineSchedule.showsMorningCard(minutesOfDay: 719, completed: false, dismissed: false))
        #expect(!RoutineSchedule.showsMorningCard(minutesOfDay: 720, completed: false, dismissed: false))
        #expect(!RoutineSchedule.showsMorningCard(minutesOfDay: 600, completed: true, dismissed: false))
        #expect(!RoutineSchedule.showsMorningCard(minutesOfDay: 600, completed: false, dismissed: true))
    }

    @Test func eveningLine_startsAtTheEarliestAnchor() {
        let offsets = [90, 60, 30]
        #expect(!RoutineSchedule.showsEveningLine(minutesOfDay: 1289, bedtimeMinutes: 1380, offsets: offsets))
        #expect(RoutineSchedule.showsEveningLine(minutesOfDay: 1290, bedtimeMinutes: 1380, offsets: offsets))
        #expect(RoutineSchedule.showsEveningLine(minutesOfDay: 100, bedtimeMinutes: 1380, offsets: offsets))
        #expect(!RoutineSchedule.showsEveningLine(minutesOfDay: 240, bedtimeMinutes: 1380, offsets: offsets))
    }

    @Test func eveningLine_withoutAnchors_startsNinetyMinutesBeforeBedtime() {
        #expect(!RoutineSchedule.showsEveningLine(minutesOfDay: 1289, bedtimeMinutes: 1380, offsets: []))
        #expect(RoutineSchedule.showsEveningLine(minutesOfDay: 1290, bedtimeMinutes: 1380, offsets: []))
    }

    @Test func eveningLine_bedtimeAfterMidnight() {
        #expect(!RoutineSchedule.showsEveningLine(minutesOfDay: 1400, bedtimeMinutes: 60, offsets: [30]))
        #expect(!RoutineSchedule.showsEveningLine(minutesOfDay: 29, bedtimeMinutes: 60, offsets: [30]))
        #expect(RoutineSchedule.showsEveningLine(minutesOfDay: 30, bedtimeMinutes: 60, offsets: [30]))
        #expect(RoutineSchedule.showsEveningLine(minutesOfDay: 239, bedtimeMinutes: 60, offsets: [30]))
    }

    @Test func reminderItems_areTheFirstFourWithAnOffset() {
        let items = [item("A", order: 0, offset: nil), item("B", order: 1, offset: 90), item("C", order: 2, offset: 60),
                     item("D", order: 3, offset: 45), item("E", order: 4, offset: 30), item("F", order: 5, offset: 15)]
        #expect(RoutineSchedule.reminderItems(items).map(\.title) == ["B", "C", "D", "E"])
        // Order, not array position, decides.
        #expect(RoutineSchedule.reminderItems(items.reversed()).map(\.title) == ["B", "C", "D", "E"])
    }

    @Test func checkedCount_ignoresDeletedItems() {
        let first = item("A", order: 0, offset: 30), second = item("B", order: 1, offset: nil)
        var day = RoutineDayValue.empty
        day.checkedItemIDs = [first.id, UUID()]
        #expect(RoutineSchedule.checkedCount(day, items: [first, second]) == 1)
    }

    @Test func suggestedItems_followTheOriginalTemplate() {
        let items = RoutineSchedule.suggestedItems
        #expect(items.count == 5)
        #expect(items.map(\.title) == ["Helle Lichter ausmachen", "Alle Aufgaben bis eine Stunde vorm Schlafen erledigen",
                                       "Eine Stunde vorm Schlafen fertig machen", "Zähne putzen, umziehen, Haus/Wohnung aufräumen",
                                       "Eine halbe Stunde vorm Schlafen ins Bett legen"])
        #expect(items.map(\.offsetMinutes) == [nil, 90, 60, nil, 30])
        let checklist = items.enumerated().map { ChecklistItem(title: $1.title, order: $0, offsetMinutes: $1.offsetMinutes) }
        #expect(RoutineSchedule.reminderItems(checklist).count == 3)
        #expect(items.allSatisfy { $0.title.count <= RoutineSchedule.titleLimit })
    }

    private func legacyList(_ titles: [String], offsets: [Int?] = [90, 60, 30]) -> [ChecklistItem] {
        titles.enumerated().map { ChecklistItem(title: $1, order: $0, offsetMinutes: offsets[$0]) }
    }

    @Test func isLegacySuggestion_exactOldList_isTrue() {
        #expect(RoutineSchedule.isLegacySuggestion(legacyList(["Tagesabschluss öffnen", "Handy weglegen", "Ins Bett"])))
        #expect(RoutineSchedule.isLegacySuggestion(legacyList(["Open evening wrap-up", "Put the phone away", "Go to bed"])))
        // The order of the property decides, not the position in the array.
        #expect(RoutineSchedule.isLegacySuggestion(legacyList(["Tagesabschluss öffnen", "Handy weglegen", "Ins Bett"]).reversed()))
    }

    @Test func isLegacySuggestion_anyChange_isFalse() {
        #expect(!RoutineSchedule.isLegacySuggestion([]))
        #expect(!RoutineSchedule.isLegacySuggestion(legacyList(["Tagesabschluss öffnen", "Handy weglegen", "Schlafen"])))
        #expect(!RoutineSchedule.isLegacySuggestion(legacyList(["Tagesabschluss öffnen", "Handy weglegen", "Ins Bett"], offsets: [90, 60, 45])))
        #expect(!RoutineSchedule.isLegacySuggestion(legacyList(["Handy weglegen", "Tagesabschluss öffnen", "Ins Bett"])))
        #expect(!RoutineSchedule.isLegacySuggestion(legacyList(["Tagesabschluss öffnen", "Handy weglegen", "Ins Bett", "Lesen"],
                                                               offsets: [90, 60, 30, nil])))
        // A list that mixes both languages is not the untouched suggestion.
        #expect(!RoutineSchedule.isLegacySuggestion(legacyList(["Tagesabschluss öffnen", "Put the phone away", "Ins Bett"])))
    }

    @Test func weekPlanningNotification_offByDefault_returnsNil() {
        #expect(RoutineSchedule.weekPlanningNotification(enabled: false, weekday: 1, minutes: 1080, locale: Locale(identifier: "de_DE")) == nil)
    }

    @Test func weekPlanningNotification_carriesWeekdayAndRoute() throws {
        let german = try #require(RoutineSchedule.weekPlanningNotification(enabled: true, weekday: 1, minutes: 1080, locale: Locale(identifier: "de_DE")))
        #expect(german.id == "tagwerk.routine.week" && german.id.hasPrefix(PlannedNotification.routineIdentifierPrefix))
        #expect(german.hour == 18 && german.minute == 0 && german.weekday == 1)
        #expect(german.route == .routineWeek)
        #expect(german.title == "Wochenplanung" && german.body == "5 Minuten für die neue Woche?")
        let english = try #require(RoutineSchedule.weekPlanningNotification(enabled: true, weekday: 7, minutes: 1500, locale: Locale(identifier: "en_US")))
        #expect(english.weekday == 7 && english.hour == 1 && english.minute == 0)
        #expect(english.title == "Weekly planning")
        // Daily reminders carry no weekday.
        #expect(RoutineSchedule.morningNotification(enabled: true, minutes: 450, locale: Locale(identifier: "de_DE"))?.weekday == nil)
    }

    @Test func quietHoursConflict_includesTheWeeklyReminder() {
        let quiet = QuietHours(startMinutes: 1320, endMinutes: 420)
        let conflict = RoutineSchedule.quietHoursConflict(quiet, items: [], bedtimeMinutes: 1380, eveningEnabled: false,
                                                          morningEnabled: false, morningMinutes: 450, weekEnabled: true, weekMinutes: 1380)
        #expect(conflict.week && !conflict.evening && !conflict.morning && !conflict.isEmpty)
        #expect(RoutineSchedule.quietHoursConflict(quiet, items: [], bedtimeMinutes: 1380, eveningEnabled: false, morningEnabled: false,
                                                   morningMinutes: 450, weekEnabled: true, weekMinutes: 1080).isEmpty)
    }

    @Test func gratitude_keepsAtMostThreeNonEmptyEntries() {
        #expect(RoutineDayValue.normalizedGratitude(["  Kaffee ", "", "Sonne", "   ", "Ruhe", "Vierte"]) == ["Kaffee", "Sonne", "Ruhe"])
    }

    // MARK: Evening notifications

    private func noSpaceVariants(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    /// The evening reminders for a first look at 2026-11-20 10:00 unless `now` says otherwise.
    private func evening(_ items: [ChecklistItem], bedtime: Int = 1380, enabled: Bool = true,
                         checked: [PlanDay: Set<UUID>] = [:], now: Date = instant(2026, 11, 20, 10),
                         locale: Locale = Locale(identifier: "de_DE"), days: Int = RoutineSchedule.eveningHorizonDays) -> [DatedRoutineNotification] {
        RoutineSchedule.eveningNotifications(items: items, bedtimeMinutes: bedtime, enabled: enabled, checked: { checked[$0] ?? [] },
                                             now: now, calendar: calendar, locale: locale, days: days)
    }

    private func day(_ notification: DatedRoutineNotification) -> PlanDay {
        PlanDay(year: notification.year, month: notification.month, day: notification.day)
    }

    @Test func eveningNotifications_textAndTime() {
        let handy = item("Handy weglegen", order: 0, offset: 60)
        let result = evening([handy])
        #expect(result.count == 3)
        let first = result[0]
        #expect(day(first) == PlanDay(year: 2026, month: 11, day: 20))
        #expect(first.hour == 22 && first.minute == 0)
        #expect(first.title == "Handy weglegen")
        #expect(first.body == "Noch 60 min bis zur Schlafzeit (23:00)")
        #expect(first.route == .routineEvening)
        #expect(first.id == "tagwerk.routine.evening.\(handy.id.uuidString).2026-11-20")
        #expect(first.id == RoutineSchedule.eveningIdentifier(item: handy.id, day: PlanDay(year: 2026, month: 11, day: 20)))
    }

    @Test func eveningNotifications_atBedtime() {
        let result = evening([item("Ins Bett", order: 0, offset: 0)])
        #expect(result[0].body == "Schlafzeit (23:00)")
        #expect(result[0].hour == 23 && result[0].minute == 0)
    }

    @Test func eveningNotifications_english() {
        let handy = item("Phone away", order: 0, offset: 60)
        let result = evening([handy], locale: Locale(identifier: "en_US"))
        #expect(noSpaceVariants(result[0].body) == "60 min until bedtime (11:00 PM)")
        let atBedtime = evening([item("Bed", order: 0, offset: 0)], locale: Locale(identifier: "en_US"))
        #expect(noSpaceVariants(atBedtime[0].body) == "Bedtime (11:00 PM)")
    }

    @Test func eveningNotifications_planThreeDays() {
        let result = evening([item("A", order: 0, offset: 60)])
        #expect(result.map(day) == [PlanDay(year: 2026, month: 11, day: 20), PlanDay(year: 2026, month: 11, day: 21),
                                    PlanDay(year: 2026, month: 11, day: 22)])
        #expect(RoutineSchedule.eveningHorizonDays == 3)
        #expect(evening([item("A", order: 0, offset: 60)], days: 1).count == 1)
    }

    @Test func eveningNotifications_wrapAroundMidnightOfTheAnchor() {
        // Bedtime 00:30 minus 90 minutes is 23:00 of the routine day itself.
        let result = evening([item("A", order: 0, offset: 90)], bedtime: 30)
        #expect(result[0].hour == 23 && result[0].minute == 0)
        #expect(day(result[0]) == PlanDay(year: 2026, month: 11, day: 20))
    }

    @Test func eveningNotifications_skipCheckedItemOnlyOnItsDay() {
        let first = item("A", order: 0, offset: 60), second = item("B", order: 1, offset: 30)
        let result = evening([first, second], checked: [PlanDay(year: 2026, month: 11, day: 21): [first.id]])
        #expect(result.count == 5)
        #expect(!result.contains { $0.id == RoutineSchedule.eveningIdentifier(item: first.id, day: PlanDay(year: 2026, month: 11, day: 21)) })
        #expect(result.contains { $0.id == RoutineSchedule.eveningIdentifier(item: first.id, day: PlanDay(year: 2026, month: 11, day: 20)) })
        #expect(result.contains { $0.id == RoutineSchedule.eveningIdentifier(item: first.id, day: PlanDay(year: 2026, month: 11, day: 22)) })
        #expect(result.contains { $0.id == RoutineSchedule.eveningIdentifier(item: second.id, day: PlanDay(year: 2026, month: 11, day: 21)) })
    }

    @Test func eveningNotifications_skipPastMoments() {
        let one = item("A", order: 0, offset: 60)
        // 22:30 is after today's 22:00; the window still ends with the routine day 22.
        #expect(evening([one], now: instant(2026, 11, 20, 22, 30)).map(day) ==
                [PlanDay(year: 2026, month: 11, day: 21), PlanDay(year: 2026, month: 11, day: 22)])
        // Exactly at the moment counts as past: the notification would not be after `now`.
        #expect(evening([one], now: instant(2026, 11, 20, 22, 0)).first.map(day) == PlanDay(year: 2026, month: 11, day: 21))
        #expect(evening([one], now: instant(2026, 11, 20, 21, 59)).first.map(day) == PlanDay(year: 2026, month: 11, day: 20))
    }

    @Test func eveningNotifications_afterMidnightBelongToPreviousRoutineDay() {
        // Bedtime 00:30 minus 15 minutes is 00:15, which still belongs to the routine day before (rule 10).
        let point = item("A", order: 0, offset: 15)
        let checkedOn20 = [PlanDay(year: 2026, month: 11, day: 20): Set([point.id])]
        let result = evening([point], bedtime: 30, checked: checkedOn20)
        // Routine day 20 fires on the 21st at 00:15 and is checked: no notification then; the 22nd at 00:15 belongs to day 21.
        #expect(!result.contains { day($0) == PlanDay(year: 2026, month: 11, day: 21) })
        let onThe22nd = result.first { day($0) == PlanDay(year: 2026, month: 11, day: 22) }
        #expect(onThe22nd?.hour == 0 && onThe22nd?.minute == 15)
        #expect(onThe22nd?.id == RoutineSchedule.eveningIdentifier(item: point.id, day: PlanDay(year: 2026, month: 11, day: 21)))
        // Without the check the 21st at 00:15 is planned for routine day 20.
        let unchecked = evening([point], bedtime: 30)
        let onThe21st = unchecked.first { day($0) == PlanDay(year: 2026, month: 11, day: 21) }
        #expect(onThe21st?.id == RoutineSchedule.eveningIdentifier(item: point.id, day: PlanDay(year: 2026, month: 11, day: 20)))
    }

    @Test func eveningNotifications_fourOClockBelongsToItsOwnDay() {
        // Bedtime 04:15 minus 15 minutes is 04:00: not before the boundary, so it fires on the routine day itself.
        let point = item("A", order: 0, offset: 15)
        let now = instant(2026, 11, 19, 12, 0)
        let atBoundary = evening([point], bedtime: 255, now: now)
        #expect(atBoundary[0].id == RoutineSchedule.eveningIdentifier(item: point.id, day: PlanDay(year: 2026, month: 11, day: 20)))
        #expect(day(atBoundary[0]) == PlanDay(year: 2026, month: 11, day: 20))
        #expect(atBoundary[0].hour == 4 && atBoundary[0].minute == 0)
        // 03:59 still belongs to the day before: routine day 19 fires on the 20th.
        let sixteen = item("B", order: 0, offset: 16)
        let before = evening([sixteen], bedtime: 255, now: now)
        #expect(before[0].id == RoutineSchedule.eveningIdentifier(item: sixteen.id, day: PlanDay(year: 2026, month: 11, day: 19)))
        #expect(day(before[0]) == PlanDay(year: 2026, month: 11, day: 20))
        #expect(before[0].hour == 3 && before[0].minute == 59)
    }

    @Test func eveningNotifications_atOneAM_startWithYesterday() {
        // At 01:00 on the 21st the routine day is the 20th; its 01:30 reminder is still ahead.
        let point = item("A", order: 0, offset: 0)
        let now = instant(2026, 11, 21, 1, 0)
        let result = evening([point], bedtime: 90, now: now)
        #expect(result.count == 3)
        #expect(result[0].id == RoutineSchedule.eveningIdentifier(item: point.id, day: PlanDay(year: 2026, month: 11, day: 20)))
        #expect(day(result[0]) == PlanDay(year: 2026, month: 11, day: 21) && result[0].hour == 1 && result[0].minute == 30)
        // Checked on the routine day 20, it stays away although the calendar day is the 21st.
        let checked = evening([point], bedtime: 90, checked: [PlanDay(year: 2026, month: 11, day: 20): [point.id]], now: now)
        #expect(checked.count == 2)
    }

    @Test func eveningNotifications_disabled_isEmpty() {
        #expect(evening([item("A", order: 0, offset: 60)], enabled: false).isEmpty)
        #expect(evening([]).isEmpty)
        #expect(evening([item("Ohne", order: 0, offset: nil)]).isEmpty)
    }

    @Test func eveningNotifications_atMostFourItemsPerDay() {
        let items = (0..<6).map { item("P\($0)", order: $0, offset: 30 + $0 * 5) }
        let result = evening(items)
        #expect(result.count == RoutineSchedule.maximumEveningNotifications)
        #expect(RoutineSchedule.maximumEveningNotifications == 12)
        for offsetDay in 20...22 {
            #expect(result.filter { day($0).day == offsetDay }.count == 4)
        }
        #expect(!result.contains { $0.title == "P4" || $0.title == "P5" })
    }

    @Test func eveningNotifications_idsAreUniqueAndStable() {
        let items = (0..<4).map { item("P\($0)", order: $0, offset: 30 + $0 * 5) }
        let first = evening(items), second = evening(items)
        #expect(first.map(\.id) == second.map(\.id))
        #expect(Set(first.map(\.id)).count == first.count)
        #expect(first.allSatisfy { $0.id.hasPrefix(PlannedNotification.routineIdentifierPrefix + "evening.") })
    }

    @Test func eveningNotifications_areSortedByMoment() {
        let late = item("Late", order: 0, offset: 0), early = item("Early", order: 1, offset: 60)
        let result = evening([late, early])
        #expect(result.prefix(2).map(\.title) == ["Early", "Late"])
    }

    @Test func eveningNotifications_summerTimeDay_keepsClockTime() {
        for (now, expectedDays) in [(instant(2026, 3, 28, 10), [28, 29, 30]), (instant(2026, 10, 24, 10), [24, 25, 26])] {
            let result = evening([item("A", order: 0, offset: 60)], now: now)
            #expect(result.map { $0.day } == expectedDays)
            #expect(result.allSatisfy { $0.hour == 22 && $0.minute == 0 })
        }
    }

    @Test func routineIdentifierPrefix_isUnderTheTagwerkPrefix() {
        #expect(PlannedNotification.routineIdentifierPrefix == "tagwerk.routine.")
        #expect(PlannedNotification.routineIdentifierPrefix.hasPrefix(PlannedNotification.identifierPrefix))
    }

    @Test func morningNotification_textAndTime() throws {
        let notification = try #require(RoutineSchedule.morningNotification(enabled: true, minutes: 450, locale: Locale(identifier: "de_DE")))
        #expect(notification.hour == 7 && notification.minute == 30)
        #expect(notification.title == "Tagesstart" && notification.body == "Ein ruhiger Start in den Tag?")
        #expect(notification.id == "tagwerk.routine.morning" && notification.route == .routineStart)
        let english = try #require(RoutineSchedule.morningNotification(enabled: true, minutes: 450, locale: Locale(identifier: "en_US")))
        #expect(english.title == "Morning start" && english.body == "A calm start to your day?")
    }

    @Test func morningNotification_offByDefault() {
        #expect(RoutineSchedule.morningNotification(enabled: false, minutes: 450, locale: Locale(identifier: "de_DE")) == nil)
    }
}
