import AIKit
import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// Journal entries and Bible Study notes never go to ChatGPT, the assistant's tools or the widget. These tests
/// guard every place that sends or shares note content.
@MainActor
struct PrivateNotesTests {
    @Test func everyPrivateKind_isCoveredByThePredicate() {
        let privateKinds = NoteKind.allCases.filter(\.isPrivate)
        #expect(privateKinds.contains(.journal) && privateKinds.contains(.bibleStudy))
        #expect(!NoteKind.free.isPrivate && !NoteKind.morning.isPrivate && !NoteKind.evening.isPrivate)
    }

    @Test func assistantTools_haveNoAccessToNotesOfAnyKind() {
        let names = AppTools.allDefinitions.map(\.name)
        for forbidden in ["note", "journal", "tagebuch", "bible", "diary"] {
            #expect(!names.contains { $0.localizedCaseInsensitiveContains(forbidden) }, "tool name contains \(forbidden)")
        }
        // The note suggestions may only call these tools, and none of them reads or writes notes.
        for name in NoteSuggestionRules.allowedTools { #expect(!name.localizedCaseInsensitiveContains("note")) }
    }

    @Test func assistantSearch_hasNoSourceForNotes() {
        // The assistant's `search` tool reads events and tasks only. It is built from these sources, so a note cannot reach it.
        let sources = SearchToolSources(events: { _ in nil }, calendarNames: { [:] }, completedTasks: { [] })
        let labels = Mirror(reflecting: sources).children.compactMap(\.label)
        #expect(labels.sorted() == ["calendarNames", "completedTasks", "events"])
    }

    @Test func widgetSnapshot_hasNoFieldForNoteText() {
        let entry = SnapshotEntry(id: "e", title: "Termin", start: .now, end: .now, kind: .event, colorHex: nil, isAllDay: false)
        let day = SnapshotDay(day: PlanDay(year: 2026, month: 11, day: 19), entries: [entry], deadlineCount: 0, intake: nil)
        let labels = (Array(Mirror(reflecting: entry).children) + Array(Mirror(reflecting: day).children)).compactMap(\.label)
        #expect(!labels.contains { $0.localizedCaseInsensitiveContains("note") || $0.localizedCaseInsensitiveContains("journal") })
    }

    @Test func suggestions_neverSendAPrivateNote_evenWithConsent() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let notes = NoteStore(context: container.mainContext)
        let settings = try AppSettings.current(in: container.mainContext)
        _ = settings
        let responder = NoteSuggestionResponder()
        let tools = NoteSuggestionTools()
        final class Counter { var models = 0 }
        let counter = Counter()
        let calendar = testCalendar()
        let local = FakeTaskProvider(source: .local, tasks: [])
        let taskList = TaskListModel(providers: [local], now: { testNow() }, calendar: calendar)
        let planStore = PlanStore(context: container.mainContext)
        let calendarStore = FakeCalendarStore()
        let blocks = BlockPlanner(store: calendarStore, planStore: planStore, links: EventLinkStore(context: container.mainContext),
                                  settings: settings, calendar: calendar)
        let planning = PlanningModel(taskList: taskList, calendarStore: calendarStore, reminderStore: FakeAccessStore(), planStore: planStore,
                                     efforts: RecurringEffortStore(context: container.mainContext), blocks: blocks, settings: settings,
                                     marks: EventMarkStore(context: container.mainContext), now: { testNow() }, calendar: calendar)
        let model = NoteSuggestionModel(responder: responder, model: { counter.models += 1; return "gpt-test" }, tools: tools,
                                        describer: ActionCardDescriber(planning: planning), notes: notes, hasConsent: { true },
                                        context: { NoteSuggestionContext(json: "[]", taskIDs: [], eventIDs: [], blockEventIDs: []) })
        let entry = notes.openJournalEntry(dayKey: "2026-11-19", locale: Locale(identifier: "de_DE"))
        // Whatever kind the caller names, the stored kind of the note decides as well.
        await model.fetch(noteID: entry.id, text: "Erfundener Text", kind: .journal)
        await model.fetch(noteID: entry.id, text: "Erfundener Text", kind: .evening)
        let study = notes.openBibleNote(book: BibleBooks.book(number: 45)!, locale: Locale(identifier: "de_DE"))
        await model.fetch(noteID: study.id, text: "Erfundener Text", kind: .free)
        // The dream log never goes to ChatGPT either.
        let dream = try #require(notes.create(text: "Erfundener Traum", kind: .dream, dayKey: "2026-11-19"))
        await model.fetch(noteID: dream.id, text: "Erfundener Traum", kind: .dream)
        await model.fetch(noteID: dream.id, text: "Erfundener Traum", kind: .evening)
        #expect(responder.calls == 0 && counter.models == 0)
        #expect(model.phase == .idle)
    }
}
