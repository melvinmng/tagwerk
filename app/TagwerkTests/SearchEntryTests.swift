import Foundation
import RemindersKit
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// A scripted event reader that counts calls and records the calendars asked for.
final class FakeEventSearcher: EventSearching, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [(DateInterval, Set<String>?)] = []
    var events: [CalendarEvent] = []

    var calls: [(DateInterval, Set<String>?)] { lock.withLock { _calls } }

    func events(in interval: DateInterval, calendarIDs: Set<String>?) async -> [CalendarEvent] {
        lock.withLock { _calls.append((interval, calendarIDs)) }
        return events
    }
}

@MainActor
struct SearchEntryTests {
    let store: InMemoryReminderStore
    let searcher = FakeEventSearcher()
    let environment: AppEnvironment

    init() throws {
        store = InMemoryReminderStore(
            lists: [ListInfo(id: "uni", title: "Uni", colorHex: nil, kind: .calDAV)],
            records: [ReminderRecord(id: "task-1", title: "Statistik Übungsblatt", notes: nil, due: nil, ekPriority: 0,
                                     isCompleted: false, listID: "uni", lastModified: nil)])
        environment = try AppEnvironment(modelContainer: ModelContainerFactory.make(inMemory: true),
                                         notificationCenter: FakeNotificationCenter(), health: FakeHealthStore(),
                                         reminderStore: store, eventSearcher: searcher)
        environment.settings.setupCompleted = true
    }

    private func titles(_ model: SearchModel) -> [String] {
        model.results.sections.flatMap(\.rows).compactMap { row in
            switch row {
            case .task(let item, _): item.title
            case .event(let row, _): row.event.title
            case .completed(let group, _): group.latest.item.title
            case .note(let note, _): note.text
            case .shopping(let item, _): item.name
            default: nil
            }
        }
    }

    @Test func openSearchPresentsAFreshModelAndCloseSearchStopsIt() async {
        environment.openSearch()
        #expect(environment.isSearchPresented)
        let model = environment.activeSearch
        #expect(model != nil)
        model?.text = "statistik"
        environment.closeSearch()
        #expect(!environment.isSearchPresented)
        #expect(model?.isClosed == true)
        #expect(model?.results.isEmpty == true)
        environment.openSearch()
        #expect(environment.activeSearch !== model)
        #expect(environment.activeSearch?.text == "")
    }

    @Test func makeSearchModelFiltersLoadedTasksWithoutAnySource() async {
        await environment.taskList.reload()
        let model = environment.makeSearchModel()
        model.text = "statistik"
        #expect(titles(model) == ["Statistik Übungsblatt"])
    }

    @Test func onlineSearchIsOfferedOnlyWithGitHub() async {
        #expect(!environment.isGitHubActive)
        let model = environment.makeSearchModel()
        model.text = "statistik"
        #expect(!model.showsOnlineSearchRow)
    }

    @Test func eventsComeFromTheSearcherWithTheReadableCalendars() async {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var event = CalendarEvent(id: "e1", externalID: nil, calendarID: "cal", title: "Statistik Klausur", start: start,
                                  end: start.addingTimeInterval(3600), isAllDay: false, url: nil, isBusy: true, version: "1")
        event.isRecurring = false
        searcher.events = [event]
        environment.settings.selectedCalendarIDs = ["cal"]
        let model = environment.makeSearchModel()
        model.text = "statistik"
        await model.settle()
        #expect(searcher.calls.count == 1)
        #expect(searcher.calls.first?.1 == environment.planning.readableCalendarIDs())
        #expect(titles(model).contains("Statistik Klausur"))
    }

    @Test func withoutCalendarAccessEventsAreNotAsked() async {
        store.calendarAccessState = .denied
        let model = environment.makeSearchModel()
        model.text = "statistik"
        await model.settle()
        #expect(model.eventState == .noAccess)
        #expect(searcher.calls.isEmpty)
    }

    @Test func plannedTimeBlocksAreNoHits() async {
        let link = TaskLinkURL.make(TaskID(source: .reminders, rawValue: "task-1"))
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let block = CalendarEvent(id: "b", externalID: nil, calendarID: "plan", title: "Statistik lernen", start: start,
                                  end: start.addingTimeInterval(3600), isAllDay: false, url: link, isBusy: true, version: "1")
        searcher.events = [block]
        environment.settings.planCalendarID = "plan"
        let model = environment.makeSearchModel()
        model.text = "statistik"
        await model.settle()
        #expect(!titles(model).contains("Statistik lernen"))
    }

    @Test func makeSearchModelReadsNotesAndOpenShoppingItems() async throws {
        store.listInfos.append(ListInfo(id: "shop", title: "Einkauf", colorHex: nil, kind: .calDAV))
        store.records["milk"] = ReminderRecord(id: "milk", title: "Statistik-Heft", notes: "2 Stück", due: nil, ekPriority: 0,
                                               isCompleted: false, listID: "shop", lastModified: nil)
        environment.settings.shoppingListID = "shop"
        await environment.shopping.reload()
        environment.notes.create(text: "Statistik Ideen")
        await environment.taskList.reload()
        let model = environment.makeSearchModel()
        model.text = "statistik"
        #expect(model.results.sections.map(\.kind).suffix(2) == [.notes, .shopping])
        #expect(titles(model).contains("Statistik Ideen") && titles(model).contains("Statistik-Heft"))
        // The shopping reminder is no task, and the note carries its kind label.
        #expect(titles(model).filter { $0 == "Statistik-Heft" }.count == 1)
    }

    // MARK: Gratitude in the app search (NF5)

    private let gratitudeDay = PlanDay(year: 2026, month: 11, day: 19)

    @Test func gratitudeSearchItems_dayWithoutNote_hasRoutineDay() {
        let calendar = testCalendar()
        let items = AppEnvironment.gratitudeSearchItems(gratitudeDays: [gratitudeDay: ["Kaffee", "Sonne"]], morningNoteDays: [], calendar: calendar)
        #expect(items.count == 1)
        #expect(items[0].routineDay == gratitudeDay && items[0].dayKey == "2026-11-19" && items[0].kindLabel == "Tagesstart")
        #expect(items[0].text == "Dankbar für: Kaffee · Sonne")
        #expect(PlanDay(date: items[0].updatedAt, calendar: calendar) == gratitudeDay)
        // A day with a note has no item of its own: its gratitude is part of the note's text.
        #expect(AppEnvironment.gratitudeSearchItems(gratitudeDays: [gratitudeDay: ["Kaffee"]], morningNoteDays: [gratitudeDay], calendar: calendar).isEmpty)
    }

    @Test func gratitudeSearchItems_idIsStable() {
        let calendar = testCalendar()
        let first = AppEnvironment.gratitudeSearchItems(gratitudeDays: [gratitudeDay: ["Kaffee"]], morningNoteDays: [], calendar: calendar)
        let second = AppEnvironment.gratitudeSearchItems(gratitudeDays: [gratitudeDay: ["Anderes"]], morningNoteDays: [], calendar: calendar)
        #expect(first[0].id == second[0].id)
        #expect(AppEnvironment.gratitudeItemID(for: gratitudeDay) != AppEnvironment.gratitudeItemID(for: PlanDay(year: 2026, month: 11, day: 20)))
    }

    @Test func appSearch_findsGratitudeOfDayWithNote() async throws {
        let note = try #require(environment.notes.create(text: "Abgabe heute", kind: .morning, dayKey: "2026-11-19"))
        environment.routines.setGratitude(["Kaffee mit Jonas"], on: gratitudeDay)
        let model = environment.makeSearchModel()
        model.text = "jonas"
        let rows = model.results.sections.flatMap(\.rows)
        let hit = rows.compactMap { row -> NoteSearchItem? in if case .note(let item, _) = row { return item } else { return nil } }
        #expect(hit.map(\.id) == [note.id])
    }

    @Test func appSearch_findsDayWithGratitudeOnly() async {
        environment.routines.setGratitude(["Ruhiger Morgen"], on: gratitudeDay)
        let model = environment.makeSearchModel()
        model.text = "ruhiger"
        let hit = model.results.sections.flatMap(\.rows).compactMap { row -> NoteSearchItem? in if case .note(let item, _) = row { return item } else { return nil } }
        #expect(hit.map(\.routineDay) == [gratitudeDay])
    }

    @Test func assistantSearchSource_neverContainsGratitude() throws {
        // A morning note is not private, so it reaches the assistant; its gratitude and the days without a note never do.
        environment.notes.create(text: "Abgabe heute", kind: .morning, dayKey: "2026-11-19")
        environment.routines.setGratitude(["Kaffee mit Jonas"], on: gratitudeDay)
        environment.routines.setGratitude(["Ruhiger Morgen"], on: PlanDay(year: 2026, month: 11, day: 18))
        let items = AppEnvironment.assistantSearchNotes(store: environment.notes)
        #expect(items.count == 1 && items[0].routineDay == nil)
        #expect(!items.contains { $0.text.contains("Jonas") || $0.text.contains("Ruhiger") })
    }

    @Test func shoppingSectionNeedsAReadyList() async {
        environment.notes.create(text: "Statistik Ideen")
        let model = environment.makeSearchModel()
        model.text = "statistik"
        #expect(model.results.sections.map(\.kind).contains(.notes))
        #expect(!model.results.sections.map(\.kind).contains(.shopping))
    }

    @Test func checkingOffInTheSearchCompletesTheShoppingReminder() async {
        store.listInfos.append(ListInfo(id: "shop", title: "Einkauf", colorHex: nil, kind: .calDAV))
        store.records["milk"] = ReminderRecord(id: "milk", title: "Hafermilch", notes: nil, due: nil, ekPriority: 0,
                                               isCompleted: false, listID: "shop", lastModified: nil)
        environment.settings.shoppingListID = "shop"
        await environment.shopping.reload()
        let model = environment.makeSearchModel()
        model.text = "hafermilch"
        guard case .shopping(let item, _)? = model.results.sections.first?.rows.first else {
            Issue.record("no shopping row"); return
        }
        await model.checkOff(item)
        #expect(store.records["milk"]?.isCompleted == true)
        #expect(model.results.isEmpty)
    }

    @Test func completedTasksOfTheLastTwelveMonthsAreRead() async {
        let now = Date.now
        store.records["done"] = ReminderRecord(id: "done", title: "Statistik erledigt", notes: nil, due: nil, ekPriority: 0,
                                               isCompleted: true, listID: "uni", lastModified: nil, completedAt: now)
        let model = environment.makeSearchModel()
        model.text = "statistik"
        model.includeCompleted = true
        await model.settle()
        #expect(titles(model).contains("Statistik erledigt"))
        #expect(store.completedIntervals.count == 1)
        let interval = store.completedIntervals[0]
        #expect(interval.end >= now && interval.duration > 360 * 24 * 3600 && interval.duration < 370 * 24 * 3600)
    }

    // MARK: Note hits: "Im Ordner zeigen"

    @Test func showNotes_folder_setsThePathToTheFolder() throws {
        let folderID = UUID()
        environment.showNotes(.folder(folderID))
        #expect(environment.tasksPath == [.notes, .notesFolder(.folder(folderID))])
        #expect(environment.requestedTab == 1)
    }

    @Test func showNotes_standard_opensTheDefaultFolder() {
        environment.tasksPath = [.shopping]
        environment.showNotes(.standard)
        #expect(environment.tasksPath == [.notes, .notesFolder(.standard)])
        #expect(environment.requestedTab == 1)
    }

    @Test func notesScope_isTheFolderOfTheNote() throws {
        let folder = try environment.notes.createFolder(name: "Ideen")
        let note = environment.notes.createBlank(folderID: folder.id)
        #expect(environment.notesScope(ofNote: note.id) == .folder(folder.id))
    }

    @Test func notesScope_noteWithoutFolder_isTheDefaultFolder() {
        let loose = environment.notes.createBlank(folderID: nil)
        #expect(environment.notesScope(ofNote: loose.id) == .standard)
    }

    @Test func notesScope_folderThatIsGone_isTheDefaultFolder() throws {
        // Deleting a folder sends its notes to the trash, so a live note with a missing folder is a leftover (for example
        // from a backup or a sync); `NoteStore` lists it under "Notizen" (`Filter.own`), and so does the jump.
        let note = environment.notes.createBlank(folderID: nil)
        note.folderID = UUID()
        #expect(environment.notes.folder(id: try #require(note.folderID)) == nil)
        #expect(environment.notes.notes(.own).contains { $0.id == note.id })
        #expect(environment.notesScope(ofNote: note.id) == .standard)
    }

    @Test func notesScope_thoughtNote_isItsSystemFolder() throws {
        let thought = try #require(environment.notes.create(text: "Dankbar für den Tag", kind: .evening, dayKey: "2026-11-20"))
        let folderID = try #require(thought.folderID)
        #expect(environment.notesScope(ofNote: thought.id) == .folder(folderID))
    }

    @Test func notesScope_nonFreeNoteWithoutFolder_opensAllNotes() throws {
        // "Notizen" lists the user's own notes only, so such a note would not be found there.
        let study = try #require(environment.notes.create(text: "Römer 8", kind: .bibleStudy, dayKey: "2026-11-20"))
        #expect(study.folderID == nil)
        #expect(!environment.notes.notes(.own).contains { $0.id == study.id })
        #expect(environment.notesScope(ofNote: study.id) == .all)
    }

    @Test func notesScope_deletedNote_opensTheTrash() throws {
        let note = environment.notes.createBlank(folderID: nil)
        environment.notes.trash(note.id)
        #expect(environment.notesScope(ofNote: note.id) == .trash)
    }

    @Test func notesScope_unknownNote_opensAllNotes() {
        #expect(environment.notesScope(ofNote: UUID()) == .all)
    }
}
