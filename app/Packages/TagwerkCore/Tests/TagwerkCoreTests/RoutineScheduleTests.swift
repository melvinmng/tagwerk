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

    @Test func eveningNotifications_textAndTime() {
        let handy = item("Handy weglegen", order: 0, offset: 60)
        let result = RoutineSchedule.eveningNotifications(items: [handy], bedtimeMinutes: 1380, enabled: true,
                                                          locale: Locale(identifier: "de_DE"))
        #expect(result.count == 1)
        #expect(result[0].hour == 22 && result[0].minute == 0)
        #expect(result[0].title == "Handy weglegen")
        #expect(result[0].body == "Noch 60 min bis zur Schlafzeit (23:00)")
        #expect(result[0].route == .routineEvening)
        #expect(result[0].id == "tagwerk.routine.evening.\(handy.id.uuidString)")
    }

    @Test func eveningNotifications_atBedtime() {
        let bed = item("Ins Bett", order: 0, offset: 0)
        let result = RoutineSchedule.eveningNotifications(items: [bed], bedtimeMinutes: 1380, enabled: true,
                                                          locale: Locale(identifier: "de_DE"))
        #expect(result[0].body == "Schlafzeit (23:00)")
        #expect(result[0].hour == 23 && result[0].minute == 0)
    }

    @Test func eveningNotifications_english() {
        let handy = item("Phone away", order: 0, offset: 60)
        let result = RoutineSchedule.eveningNotifications(items: [handy], bedtimeMinutes: 1380, enabled: true,
                                                          locale: Locale(identifier: "en_US"))
        #expect(noSpaceVariants(result[0].body) == "60 min until bedtime (11:00 PM)")
        let atBedtime = RoutineSchedule.eveningNotifications(items: [item("Bed", order: 0, offset: 0)], bedtimeMinutes: 1380,
                                                             enabled: true, locale: Locale(identifier: "en_US"))
        #expect(noSpaceVariants(atBedtime[0].body) == "Bedtime (11:00 PM)")
    }

    @Test func eveningNotifications_atMostFour_andNoneWhenDisabledOrWithoutItems() {
        let items = (0..<6).map { item("P\($0)", order: $0, offset: 30 + $0 * 5) }
        let locale = Locale(identifier: "de_DE")
        #expect(RoutineSchedule.eveningNotifications(items: items, bedtimeMinutes: 1380, enabled: true, locale: locale).count == 4)
        #expect(RoutineSchedule.eveningNotifications(items: items, bedtimeMinutes: 1380, enabled: false, locale: locale).isEmpty)
        #expect(RoutineSchedule.eveningNotifications(items: [], bedtimeMinutes: 1380, enabled: true, locale: locale).isEmpty)
        #expect(RoutineSchedule.eveningNotifications(items: [item("Ohne", order: 0, offset: nil)], bedtimeMinutes: 1380,
                                                     enabled: true, locale: locale).isEmpty)
    }

    @Test func eveningNotifications_wrapAroundMidnight() {
        let result = RoutineSchedule.eveningNotifications(items: [item("A", order: 0, offset: 90)], bedtimeMinutes: 30, enabled: true,
                                                          locale: Locale(identifier: "de_DE"))
        #expect(result[0].hour == 23 && result[0].minute == 0)
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
