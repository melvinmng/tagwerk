#if DEBUG && targetEnvironment(simulator)
import EventKit
import Foundation
import SwiftData
import TagwerkCore

/// Simulator-only sample data for manual checks, enabled with the launch argument `-TagwerkDemoData`.
/// It wipes and recreates dedicated calendars and a reminder list (all prefixed "Demo"), so it never
/// touches other data and never runs on a device.
@MainActor
enum DemoData {
    static let launchArgument = "-TagwerkDemoData"
    private static let prefix = "Demo "
    private static let planCalendarTitle = "Demo Tagwerk"

    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains(launchArgument) || UITestMode.isActive }

    static func seedIfRequested(_ environment: AppEnvironment) async {
        guard isRequested else { return }
        let store = EKEventStore()
        do {
            guard try await store.requestFullAccessToEvents(), try await store.requestFullAccessToReminders() else {
                print("DemoData: calendar or reminder access denied; grant it with simctl privacy")
                return
            }
            try wipe(store)
            let ids = try seed(store, leadTimeMinutes: environment.settings.leadTimeMinutes)
            environment.gateway.discardCachedData()
            let settings = environment.settings
            settings.setupCompleted = true
            settings.selectedCalendarIDs = nil
            settings.selectedReminderListIDs = [ids.reminderList]
            // The UI tests need a shopping list; it is not part of the normal demo data.
            if let shoppingList = ids.shoppingList { settings.shoppingListID = shoppingList }
            settings.planCalendarID = ids.planCalendar
            if DemoTravelEstimator.isRequested {
                settings.homeAddress = "Musterstraße 1, Berlin"
                settings.homeLatitude = 52.52
                settings.homeLongitude = 13.405
            }
            settings.deadlineCalendarIDs = [ids.deadlineCalendar]
            seedRecurringLocalTask(environment)
            await environment.taskList.reload()
            await planSamples(environment)
            await environment.planning.reload()
            try seedIntake(environment)
            await environment.capture.reload()
            seedCompletedTasks(environment)
            seedNotes(environment)
            // Phase 4: the widget reads the demo plan right away.
            environment.writeSnapshot()
            environment.isDemoDataReady = true
            print("DemoData: sample data created")
        } catch {
            print("DemoData: seeding failed: \(error)")
        }
    }

    /// Phase 5: three notes (one pinned, one dictated, one evening thought of yesterday, so the filter shows)
    /// and the built-in shopping categories. There is no demo reminder store: the shopping list shows the
    /// simulator's real reminders once a list is chosen.
    private static func seedNotes(_ environment: AppEnvironment) {
        environment.shoppingCategories.seedIfNeeded()
        let notes = environment.notes
        guard notes.count == 0 else { return }
        let planning = environment.planning
        let yesterday = planning.today.adding(days: -1, calendar: planning.calendar)
        notes.create(text: "Heute lief die Gliederung gut.\nMorgen zuerst die Quellen sichten.", kind: .evening,
                     dayKey: NoteDayKey.string(yesterday))
        notes.create(text: "Geschenkidee für Lea\nKochbuch oder Konzertkarten", wasDictated: true)
        if let pinned = notes.create(text: "Ideen Hausarbeit\nGliederung überarbeiten\nZwei weitere Quellen suchen") {
            notes.setPinned(pinned.id, true)
        }
        // Two folders (one with a subfolder) and a note in "Zuletzt gelöscht".
        if let study = try? notes.createFolder(name: "Studium") {
            notes.create(text: "Literaturliste\nDrei Quellen zur Statistik", folderID: study.id)
            if let thesis = try? notes.createFolder(name: "Hausarbeit", parentID: study.id) {
                notes.create(text: "Gliederung\n1 Einleitung, 2 Methode, 3 Ergebnisse", folderID: thesis.id)
            }
        }
        if let home = try? notes.createFolder(name: "Haushalt") {
            notes.create(text: "Handwerker anrufen\nHeizung entlüften", folderID: home.id)
        }
        // One journal entry for yesterday, with the template filled in.
        let entry = notes.openJournalEntry(dayKey: NoteDayKey.string(yesterday))
        notes.updateText(entry.id, text: """
            Allgemeine Stimmung
            Wie geht es mir im Moment grundsätzlich?
            Ruhig und dankbar.

            Haupterlebnisse des heutigen Tages
            Ein langer Spaziergang am Fluss.

            Tagebuch
            Heute war ein guter Tag. Ich habe mir Zeit zum Nachdenken genommen.
            """)
        // Bible Study: the note of Romans with a completed session yesterday.
        if let romans = BibleBooks.book(number: 45) {
            let started = notes.startSession(book: romans, passage: "3,21-31", dayKey: NoteDayKey.string(yesterday),
                                             dateText: BibleStudyStartSheet.dateText(yesterday))
            notes.updateText(started.note.id, text: started.note.text + "3,24: ohne Verdienst gerecht gemacht, aus seiner Gnade.\n")
            notes.completeSession(started.session.id)
        }
        if let discarded = notes.create(text: "Alte Einkaufsidee\nNicht mehr nötig") {
            notes.trash(discarded.id)
        }
        // A recipe note in the folder "Rezepte" (invented dish), to try the recipe note and "Zutaten auf die Einkaufsliste".
        let soup = RecipeNote(title: "Demo Linsensuppe", servings: 4,
                              ingredients: ["250 g rote Linsen", "1 Zwiebel", "2 Karotten", "1 l Gemüsebrühe", "Salz"],
                              steps: ["Zwiebel und Karotten würfeln und andünsten.", "Linsen und Brühe zugeben und 20 Minuten köcheln."])
        RecipeNoteWriter.save(soup, language: .german, store: notes)
    }

    /// A local task repeating every three days from today, to try ticking off and "Rückgängig" (plan 2026-11-18,
    /// stage 2). Local tasks are not wiped, so it is created only once.
    private static func seedRecurringLocalTask(_ environment: AppEnvironment) {
        let context = environment.modelContainer.mainContext
        let title = "Pflanzen gießen"
        let existing = FetchDescriptor<LocalTask>(predicate: #Predicate { $0.title == title })
        guard ((try? context.fetchCount(existing)) ?? 0) == 0 else { return }
        let today = PlanDay(date: .now, calendar: environment.planning.calendar)
        let task = LocalTask(title: title)
        task.due = DueDate(year: today.year, month: today.month, day: today.day)
        task.recurrence = Recurrence(rule: .daily(interval: 3), start: today, end: nil, count: nil)
        context.insert(task)
        try? context.save()
    }

    /// Two local tasks completed earlier this week, so the weekly review shows "Erledigt".
    private static func seedCompletedTasks(_ environment: AppEnvironment) {
        let context = environment.modelContainer.mainContext
        for (title, daysAgo) in [("Bibliotheksbuch zurückgeben", 1), ("Rechnung ablegen", 2)] {
            let task = LocalTask(title: title)
            task.isCompleted = true
            task.completedAt = Date.now.addingTimeInterval(TimeInterval(-daysAgo * 86_400))
            context.insert(task)
        }
        try? context.save()
    }

    /// Tomorrow: "Pretest vorbereiten" with a 60-minute block at 14:00, a 30-minute block of the recurring
    /// "Training" at 07:00 and "Einkaufen" planned without time.
    private static func planSamples(_ environment: AppEnvironment) async {
        let planning = environment.planning
        let tomorrow = planning.today.adding(days: 1, calendar: planning.calendar)
        let items = environment.taskList.items
        if let pretest = items.first(where: { $0.title == "Pretest vorbereiten" }) {
            let start = tomorrow.startDate(in: planning.calendar).addingTimeInterval(14 * 3600)
            await planning.createBlock(for: pretest, start: start, minutes: 60)
        }
        // A block of the recurring "Training", to try the save question after changing its rule.
        if let training = items.first(where: { $0.title == "Training" }) {
            let start = tomorrow.startDate(in: planning.calendar).addingTimeInterval(7 * 3600)
            await planning.createBlock(for: training, start: start, minutes: 30)
        }
        if let shopping = items.first(where: { $0.title == "Einkaufen" }) {
            await planning.assign(shopping.id, to: tomorrow)
        }
    }

    /// "Erfassen": breakfast (estimated), a typed snack and water today, plus earlier meals for "Zuletzt und häufig".
    private static func seedIntake(_ environment: AppEnvironment) throws {
        let context = environment.modelContainer.mainContext
        try context.delete(model: MealRecord.self)
        try context.delete(model: DrinkRecord.self)
        try context.delete(model: WorkoutRecord.self)
        try context.delete(model: PendingHealthDeletion.self)
        try context.save()
        let calendar = Calendar.tagwerk
        let today = calendar.startOfDay(for: .now)
        func at(_ dayOffset: Int, _ hour: Int, _ minute: Int) -> Date {
            today.addingTimeInterval(TimeInterval(dayOffset * 86_400 + hour * 3600 + minute * 60))
        }
        func estimated(_ name: String, _ amount: String, _ kcal: Double, protein: Double, carbs: Double, fat: Double) -> MealItem {
            MealItem(name: name, amount: amount, kcalMin: (kcal * 0.85).rounded(), kcal: kcal, kcalMax: (kcal * 1.15).rounded(),
                     protein: protein, carbs: carbs, fat: fat, isEstimated: true)
        }
        let intake = environment.intake
        let rolls = [estimated("Brötchen", "2 Stück", 300, protein: 10, carbs: 56, fat: 2),
                     estimated("Käse", "2 Scheiben", 180, protein: 12, carbs: 0, fat: 14)]
        let oats = [estimated("Haferflocken", "60 g", 225, protein: 8, carbs: 36, fat: 4),
                    estimated("Banane", "1 Stück", 105, protein: 1, carbs: 27, fat: 0),
                    estimated("Milch", "200 ml", 130, protein: 7, carbs: 10, fat: 7)]
        let bar = [MealItem(name: "Proteinriegel", amount: "", kcalMin: 210, kcal: 210, kcalMax: 210, protein: 15, carbs: 20, fat: 7)]
        let history: [(Int, Int, Int, MealKind, String, [MealItem], MealOrigin)] = [
            (-1, 7, 30, .breakfast, "Haferflocken mit Banane", oats, .estimated),
            (-2, 7, 45, .breakfast, "Haferflocken mit Banane", oats, .estimated),
            (-3, 8, 0, .breakfast, "Haferflocken mit Banane", oats, .estimated),
            (-2, 10, 30, .snack, "Proteinriegel", bar, .manual),
            (0, 7, 40, .breakfast, "2 Brötchen mit Käse", rolls, .estimated),
            (0, 10, 45, .snack, "Proteinriegel", bar, .manual),
        ]
        for (offset, hour, minute, kind, title, items, origin) in history where at(offset, hour, minute) <= .now {
            intake.addMeal(MealValue(id: UUID(), date: at(offset, hour, minute), kind: kind, title: title, items: items, origin: origin),
                           estimatedAt: origin == .estimated ? at(offset, hour, minute) : nil)
        }
        for (hour, minute, milliliters) in [(8, 0, 250), (9, 10, 500), (11, 30, 250)] where at(0, hour, minute) <= .now {
            intake.addDrink(DrinkValue(id: UUID(), date: at(0, hour, minute), milliliters: milliliters))
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
        /// Only created for the UI tests.
        let shoppingList: String?
    }

    private static func seed(_ store: EKEventStore, leadTimeMinutes: Int) throws -> SeededIDs {
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
        let shoppingList = UITestMode.isActive
            ? try makeCalendar("Demo Einkauf", for: .reminder, color: CGColor(srgbRed: 0.95, green: 0.6, blue: 0.1, alpha: 1))
            : nil

        func event(_ title: String, _ calendarItem: EKCalendar, _ start: Date, _ end: Date, allDay: Bool = false,
                   location: String? = nil) throws {
            let item = EKEvent(eventStore: store)
            item.calendar = calendarItem
            item.title = title
            item.location = location
            item.startDate = start
            item.endDate = end
            item.isAllDay = allDay
            try store.save(item, span: .thisEvent, commit: false)
        }
        // The same meeting in two calendars reproduces duplicate rows.
        try event("Seminar", work, at(0, 10), at(0, 12, 30), location: "Universität, Unter den Linden 6, Berlin")
        try event("Seminar", copy, at(0, 10), at(0, 12, 30))
        try event("Sprechstunde", work, at(0, 15), at(0, 16), location: "Praxis Dr. Muster, Hauptstraße 5, Berlin")
        try event("Projektwoche", work, at(0, 0), at(1, 0), allDay: true)
        try event("Anmeldung Abschlussarbeit", uni, at(0, 0), at(1, 0), allDay: true)
        try event("Klausur Statistik", uni, at(3, 10), at(3, 12))
        try event("Abgabe Hausarbeit", uni, at(40, 0), at(41, 0), allDay: true)
        try event("Teamtreffen", work, at(1, 9, 30), at(1, 11), location: "Zoom")
        // A deadline whose notification fires about two minutes after the start (checks banner and tap).
        let soon = UITestMode.now().addingTimeInterval(TimeInterval((leadTimeMinutes + 3) * 60))
        let soonStart = calendar.date(bySetting: .second, value: 0, of: soon) ?? soon
        try event("Abgabe Kurzbericht", uni, soonStart, soonStart.addingTimeInterval(30 * 60))
        let sport = EKEvent(eventStore: store)
        sport.calendar = work
        sport.title = "Sport"
        sport.startDate = at(1, 17)
        sport.endDate = at(1, 18)
        sport.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil))
        try store.save(sport, span: .futureEvents, commit: false)

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
        // The rules added with the recurrence editor: the n-th weekday of the month and yearly.
        // Days 29 to 31 are a fifth weekday, which Tagwerk does not offer; the day of the month is used then.
        let monthlyDue = at(2, 0)
        let dayOfMonth = calendar.component(.day, from: monthlyDue)
        let weekdayOfMonth = dayOfMonth <= 28
            ? [EKRecurrenceDayOfWeek(EKWeekday(rawValue: calendar.component(.weekday, from: monthlyDue)) ?? .monday,
                                     weekNumber: (dayOfMonth - 1) / 7 + 1)]
            : nil
        try reminder("Nebenkosten ablesen", due: 2, recurrence: EKRecurrenceRule(
            recurrenceWith: .monthly, interval: 1, daysOfTheWeek: weekdayOfMonth,
            daysOfTheMonth: weekdayOfMonth == nil ? [NSNumber(value: dayOfMonth)] : nil, monthsOfTheYear: nil,
            weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: EKRecurrenceEnd(occurrenceCount: 12)))
        try reminder("Versicherung prüfen", due: 5, recurrence: EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil))
        try reminder("Pretest vorbereiten", due: 1, priority: 1)
        try reminder("Bericht überarbeiten", due: -2, priority: 5)
        try reminder("Literatur sichten", due: 0)
        try reminder("Einkaufen", due: nil)
        try store.commit()
        return SeededIDs(reminderList: list.calendarIdentifier, planCalendar: plan.calendarIdentifier,
                         deadlineCalendar: uni.calendarIdentifier, shoppingList: shoppingList?.calendarIdentifier)
    }
}
#endif
