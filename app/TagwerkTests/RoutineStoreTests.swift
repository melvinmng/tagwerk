import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct RoutineStoreTests {
    let container: ModelContainer
    let store: RoutineStore
    let day = PlanDay(year: 2026, month: 11, day: 18)

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        store = RoutineStore(context: container.mainContext, now: { testNow() })
    }

    private func recordCount() -> Int {
        (try? container.mainContext.fetchCount(FetchDescriptor<RoutineDayRecord>())) ?? -1
    }

    @Test func readingADay_insertsNothing() {
        #expect(store.day(day) == .empty)
        #expect(recordCount() == 0)
    }

    @Test func update_insertsOnTheFirstWrite_andKeepsOneRecordPerDay() {
        store.update(day) { $0.startCompletedAt = testNow() }
        store.update(day) { $0.closeCompletedAt = testNow() }
        #expect(recordCount() == 1)
        #expect(store.day(day).startCompletedAt == testNow() && store.day(day).closeCompletedAt == testNow())
    }

    @Test func update_keepsAtMostThreeGratitudeEntries_andDropsEmptyOnes() {
        store.update(day) { $0.gratitude = ["Kaffee", "", "Sonne", "Ruhe", "Vierte"] }
        #expect(store.day(day).gratitude == ["Kaffee", "Sonne", "Ruhe"])
    }

    @Test func update_storesCheckedItemsAndDismissal() {
        let id = UUID()
        store.update(day) { $0.checkedItemIDs = [id]; $0.startDismissed = true }
        #expect(store.day(day).checkedItemIDs == [id] && store.day(day).startDismissed)
        #expect(store.day(day.adding(days: -1, calendar: testCalendar())) == .empty)
    }

    @Test func saveItem_rejectsTheNinthItem_andTheFifthReminder() {
        for index in 0..<4 {
            #expect(store.saveItem(ChecklistItem(title: "Punkt \(index)", order: index, offsetMinutes: 30 + index * 5)))
        }
        // The fifth reminder is refused, the same point without a reminder is fine.
        #expect(!store.saveItem(ChecklistItem(title: "Fünfter", order: 4, offsetMinutes: 10)))
        #expect(store.saveItem(ChecklistItem(title: "Fünfter", order: 4, offsetMinutes: nil)))
        for index in 5..<8 { #expect(store.saveItem(ChecklistItem(title: "Punkt \(index)", order: index, offsetMinutes: nil))) }
        #expect(store.checklist().count == 8)
        #expect(!store.saveItem(ChecklistItem(title: "Neunter", order: 8, offsetMinutes: nil)))
        #expect(store.checklist().count == 8)
    }

    @Test func saveItem_updatesAnExistingReminderWithoutCountingItTwice() {
        let items = (0..<4).map { ChecklistItem(title: "Punkt \($0)", order: $0, offsetMinutes: 30 + $0 * 5) }
        items.forEach { _ = store.saveItem($0) }
        var changed = items[0]
        changed.offsetMinutes = 120
        #expect(store.saveItem(changed))
        #expect(store.checklist().first?.offsetMinutes == 120)
    }

    @Test func saveItem_cutsTheTitle_andRoundsTheOffsetToFiveMinutes() {
        _ = store.saveItem(ChecklistItem(title: String(repeating: "x", count: 80), order: 0, offsetMinutes: 62))
        let saved = store.checklist()[0]
        #expect(saved.title.count == RoutineSchedule.titleLimit && saved.offsetMinutes == 60)
        _ = store.saveItem(ChecklistItem(title: "Weit", order: 1, offsetMinutes: 999))
        #expect(store.checklist()[1].offsetMinutes == 240)
    }

    @Test func deleteAndReorderItems() {
        let first = ChecklistItem(title: "A", order: 0, offsetMinutes: nil)
        let second = ChecklistItem(title: "B", order: 1, offsetMinutes: nil)
        _ = store.saveItem(first)
        _ = store.saveItem(second)
        store.reorderItems([second.id, first.id])
        #expect(store.checklist().map(\.title) == ["B", "A"])
        store.deleteItem(second.id)
        #expect(store.checklist().map(\.title) == ["A"])
    }

    @Test func adoptSuggestion_createsFiveItems_onlyIntoAnEmptyList() {
        store.adoptSuggestion()
        #expect(store.checklist().map(\.offsetMinutes) == [nil, 90, 60, nil, 30])
        #expect(store.checklist().first?.title == "Helle Lichter ausmachen")
        // The long titles of the original template are stored whole.
        #expect(store.checklist().map(\.title) == RoutineSchedule.suggestedItems.map(\.title))
        store.adoptSuggestion()
        #expect(store.checklist().count == 5)
    }

    private func adoptLegacyList(_ titles: [String] = ["Tagesabschluss öffnen", "Handy weglegen", "Ins Bett"]) -> [ChecklistItem] {
        let items = zip(titles.indices, titles).map { ChecklistItem(title: $1, order: $0, offsetMinutes: [90, 60, 30][$0 % 3]) }
        for item in items { store.saveItem(item) }
        return items
    }

    @Test func replaceLegacySuggestion_replacesTheUntouchedOldList() {
        let old = adoptLegacyList()
        #expect(store.replaceLegacySuggestion())
        let items = store.checklist()
        #expect(items.count == 5)
        #expect(Set(items.map(\.id)).isDisjoint(with: Set(old.map(\.id))))
        #expect(items.map(\.offsetMinutes) == [nil, 90, 60, nil, 30])
    }

    @Test func replaceLegacySuggestion_keepsAnEditedList() {
        let old = adoptLegacyList(["Tagesabschluss öffnen", "Handy weglegen", "Schlafen"])
        #expect(!store.replaceLegacySuggestion())
        #expect(store.checklist().map(\.id) == old.map(\.id))
        #expect(store.checklist().map(\.title) == ["Tagesabschluss öffnen", "Handy weglegen", "Schlafen"])
    }

    @Test func replaceLegacySuggestion_onAnEmptyList_doesNothing() {
        #expect(!store.replaceLegacySuggestion())
        #expect(store.checklist().isEmpty)
    }

    @Test func settingsDefaults() throws {
        let settings = try AppSettings.current(in: container.mainContext)
        #expect(settings.bedtimeMinutes == 1380)
        #expect(settings.eveningRemindersEnabled)
        #expect(!settings.morningReminderEnabled)
        #expect(settings.morningReminderMinutes == 450)
        #expect(settings.showsRoutinesInPlan)
        #expect(!settings.noteSuggestionConsent)
    }

    @Test func noteAssistantConsent_defaultsToFalse() throws {
        let settings = try AppSettings.current(in: container.mainContext)
        #expect(!settings.noteAssistantConsent)
    }

    @Test func schema_containsTheRoutineTypes() {
        let names = Set(ModelContainerFactory.schema.entities.map(\.name))
        #expect(names.isSuperset(of: ["RoutineDayRecord", "EveningChecklistItemRecord"]))
    }

    // MARK: Focus

    private func task(_ title: String) -> TaskItem { makeTask(title, source: .local) }

    @Test func addFocus_allowsAtMostThreePerDay() {
        #expect(store.addFocus(task("A"), on: day))
        #expect(store.addFocus(task("B"), on: day))
        #expect(store.addFocus(task("C"), on: day))
        #expect(!store.addFocus(task("D"), on: day))
        #expect(!store.addFocus(task("A"), on: day))
        #expect(store.focusMarks(on: day).map(\.title) == ["A", "B", "C"])
    }

    @Test func sameTask_canBeFocusOnTwoDays() {
        let next = day.adding(days: 1, calendar: testCalendar())
        #expect(store.addFocus(task("A"), on: day))
        #expect(store.addFocus(task("A"), on: next))
        #expect(store.focusMarks(on: day).count == 1 && store.focusMarks(on: next).count == 1)
    }

    @Test func removeFocus_andSetDone_andTitle() {
        let item = task("Alt")
        store.addFocus(item, on: day)
        store.setFocusDone(taskKey: item.id.key, on: day, at: testNow())
        #expect(store.focusMarks(on: day).first?.doneAt == testNow())
        store.updateFocusTitle(taskKey: item.id.key, on: day, title: "Neu")
        #expect(store.focusMarks(on: day).first?.title == "Neu")
        store.removeFocus(taskKey: item.id.key, on: day)
        #expect(store.focusMarks(on: day).isEmpty)
        // A removed mark frees its place.
        for title in ["A", "B", "C"] { store.addFocus(task(title), on: day) }
        #expect(store.focusMarks(on: day).count == 3)
    }

    @Test func schema_containsFocusMark() {
        #expect(ModelContainerFactory.schema.entities.map(\.name).contains("FocusMarkRecord"))
    }

    @Test func gratitudeDays_skipsEmptyAndWhitespace() {
        store.update(day) { $0.gratitude = ["Kaffee", "Sonne"] }
        store.update(PlanDay(year: 2026, month: 11, day: 19)) { $0.startCompletedAt = testNow() }
        // A record with blank entries only (written by an older version or by hand) is not a day with gratitude.
        let blank = RoutineDayRecord(day: PlanDay(year: 2026, month: 11, day: 20))
        blank.gratitudeData = try? JSONEncoder().encode(["  ", ""])
        container.mainContext.insert(blank)
        try? container.mainContext.save()
        #expect(store.gratitudeDays() == [day: ["Kaffee", "Sonne"]])
    }

    @Test func gratitudeDays_afterClearing_isGone() {
        store.update(day) { $0.gratitude = ["Kaffee"] }
        #expect(store.gratitudeDays().keys.contains(day))
        store.update(day) { $0.gratitude = [] }
        #expect(store.gratitudeDays().isEmpty)
    }
}
