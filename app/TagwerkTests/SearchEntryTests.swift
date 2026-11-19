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
}
