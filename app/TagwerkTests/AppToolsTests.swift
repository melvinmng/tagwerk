import AIKit
import Foundation
import GitHubKit
import RemindersKit
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct AppToolsTests {
    let container: ModelContainer
    let settings: AppSettings
    let calendarStore = FakeCalendarStore()
    let local: FakeTaskProvider
    let taskList: TaskListModel
    let planStore: PlanStore
    let blocks: BlockPlanner
    let store: SuggestionStore
    let responder = FakePlanResponder()
    let calendar = testCalendar()
    let today = PlanDay(year: 2026, month: 11, day: 18)

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        settings = try AppSettings.current(in: container.mainContext)
        settings.planCalendarID = "plan"
        local = FakeTaskProvider(source: .local, tasks: [
            makeTask("Fahrrad", source: .local, due: DueDate(year: 2026, month: 11, day: 18)),
            makeTask("Abgabe", source: .local, due: DueDate(year: 2026, month: 11, day: 20)),
        ])
        taskList = TaskListModel(providers: [local], now: testNow, calendar: calendar)
        planStore = PlanStore(context: container.mainContext)
        blocks = BlockPlanner(store: calendarStore, planStore: planStore, links: EventLinkStore(context: container.mainContext),
                              settings: settings, calendar: calendar)
        store = SuggestionStore(context: container.mainContext)
    }

    private func make() async -> (AppTools, PlanningModel) {
        await taskList.reload()
        let planning = PlanningModel(taskList: taskList, calendarStore: calendarStore, reminderStore: FakeAccessStore(),
                                     planStore: planStore, efforts: RecurringEffortStore(context: container.mainContext),
                                     blocks: blocks, settings: settings, marks: EventMarkStore(context: container.mainContext),
                                     suggestions: store, now: testNow, calendar: calendar)
        await planning.reload()
        let planner = AIPlanner(responder: responder, model: { "gpt-test" }, planning: planning, store: store)
        let calendarStore = self.calendarStore
        let tools = AppTools(taskList: taskList, planning: planning, planner: planner,
                             events: { interval in calendarStore.events(in: interval, calendarIDs: nil) })
        return (tools, planning)
    }

    private func run(_ tools: AppTools, _ name: String, _ arguments: String) async -> [String: Any] {
        let output = await tools.run(ToolCall(id: "c1", name: name, arguments: Data(arguments.utf8)))
        return (try? JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any]) ?? ["raw": output]
    }

    @Test func definitions_areStrict_andKindsSplitReadWrite() async throws {
        let (tools, _) = await make()
        for definition in tools.definitions {
            let schema = try #require(try JSONSerialization.jsonObject(with: definition.parameters) as? [String: Any])
            let properties = try #require(schema["properties"] as? [String: Any])
            #expect(schema["additionalProperties"] as? Bool == false, "\(definition.name)")
            #expect(Set(schema["required"] as? [String] ?? []) == Set(properties.keys), "\(definition.name)")
            #expect(definition.strict)
        }
        #expect(tools.kind(of: "list_tasks") == .read)
        #expect(tools.kind(of: "get_task") == .read)
        #expect(tools.kind(of: "list_events") == .read)
        #expect(tools.kind(of: "list_calendars") == .read)
        for name in ["create_event", "update_event", "delete_event", "create_task", "update_task", "reschedule_task", "complete_task", "assign_to_day", "create_time_block",
                     "link_event_to_task", "set_day_hours", "set_lunch", "mark_events_free", "plan_period", "add_comment"] {
            #expect(tools.kind(of: name) == .write, "\(name)")
        }
    }

    // MARK: search

    private func makeSearch(events: [CalendarEvent] = [], completed: [CompletedTask] = [], access: Bool = true) async -> AppTools {
        calendarStore.storedEvents = events
        await taskList.reload()
        let planning = PlanningModel(taskList: taskList, calendarStore: calendarStore, reminderStore: FakeAccessStore(),
                                     planStore: planStore, efforts: RecurringEffortStore(context: container.mainContext),
                                     blocks: blocks, settings: settings, marks: EventMarkStore(context: container.mainContext),
                                     suggestions: store, now: testNow, calendar: calendar)
        await planning.reload()
        let calendarStore = self.calendarStore
        let sources = SearchToolSources(
            events: { interval in access ? calendarStore.events(in: interval, calendarIDs: nil) : nil },
            calendarNames: { ["cal": "Uni"] },
            completedTasks: { completed })
        return AppTools(taskList: taskList, planning: planning, planner: nil,
                        events: { interval in calendarStore.events(in: interval, calendarIDs: nil) }, search: sources)
    }

    private func searchEvent(_ title: String, id: String? = nil, on day: DateComponents, recurring: Bool = false,
                             notes: String? = nil, location: String? = nil) -> CalendarEvent {
        let start = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 9))!
        var event = CalendarEvent(id: id ?? title, externalID: nil, calendarID: "cal", title: title, start: start,
                                  end: start.addingTimeInterval(3600), isAllDay: false, url: nil, isBusy: true, version: "1")
        event.isRecurring = recurring
        event.notes = notes
        event.location = location
        return event
    }

    private func searchArguments(_ query: String, kind: String = "all", completed: Bool = false, from: String? = nil, to: String? = nil) -> String {
        func quoted(_ value: String?) -> String { value.map { "\"\($0)\"" } ?? "null" }
        return #"{"query":"\#(query)","kind":"\#(kind)","include_completed":\#(completed),"from":\#(quoted(from)),"to":\#(quoted(to))}"#
    }

    @Test func search_isAReadToolWithStrictSchema() async throws {
        let tools = await makeSearch()
        #expect(tools.kind(of: "search") == .read)
        let definition = try #require(tools.definitions.first { $0.name == "search" })
        let schema = try #require(try JSONSerialization.jsonObject(with: definition.parameters) as? [String: Any])
        #expect(Set(schema["required"] as? [String] ?? []) == ["query", "kind", "include_completed", "from", "to"])
        #expect(definition.strict)
        #expect(definition.description.hasPrefix("Searches calendar events and tasks by text"))
    }

    @Test func search_findsEventsAndTasksInDefaultWindow() async throws {
        local.tasks.append(makeTask("Statistik Übungsblatt", source: .local))
        let tools = await makeSearch(events: [searchEvent("Klausur Statistik", on: DateComponents(year: 2027, month: 2, day: 10))])
        let result = await run(tools, "search", searchArguments("statistik"))
        #expect((result["events"] as? [[String: Any]])?.first?["title"] as? String == "Klausur Statistik")
        #expect((result["tasks"] as? [[String: Any]])?.first?["matchedIn"] as? [String] == ["title"])
        #expect((result["events"] as? [[String: Any]])?.first?["matchedIn"] as? [String] == ["title"])
        #expect(result["eventCount"] as? Int == 1)
        #expect(result["taskCount"] as? Int == 1)
        #expect((result["searched"] as? [String: String]) == ["from": "2026-05-18", "to": "2027-11-17"])
    }

    @Test func search_neverReturnsNoteText() async throws {
        var task = makeTask("Lernen", source: .local)
        task.notes = "Zugangscode Blau-77 geheim"
        local.tasks.append(task)
        let tools = await makeSearch(events: [searchEvent("Besprechung", on: DateComponents(year: 2026, month: 12, day: 1),
                                                          notes: "Raum 12 geheim")])
        let output = await tools.run(ToolCall(id: "c", name: "search", arguments: Data(searchArguments("geheim").utf8)))
        #expect(!output.contains("Raum 12") && !output.contains("Zugangscode") && !output.contains("Blau-77"))
        let result = try #require(try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
        #expect((result["events"] as? [[String: Any]])?.first?["matchedIn"] as? [String] == ["notes"])
        #expect((result["tasks"] as? [[String: Any]])?.first?["matchedIn"] as? [String] == ["notes"])
        #expect(result["eventCount"] as? Int == 1 && result["taskCount"] as? Int == 1)
    }

    @Test func search_seriesCarriesMoreOccurrences() async throws {
        let base = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 9))!
        let events = (0..<10).map { index -> CalendarEvent in
            var event = searchEvent("Statistik Vorlesung", id: "abc|\(1_795_000_000 + index * 604_800)",
                                    on: DateComponents(year: 2026, month: 11, day: 20), recurring: true)
            event.start = calendar.date(byAdding: .day, value: index * 7, to: base)!
            event.end = event.start.addingTimeInterval(3600)
            return event
        }
        let tools = await makeSearch(events: events)
        let result = await run(tools, "search", searchArguments("statistik", kind: "events"))
        let listed = try #require(result["events"] as? [[String: Any]])
        #expect(listed.count == 1)
        #expect(listed.first?["moreOccurrences"] as? Int == 9)
        #expect(listed.first?["recurring"] as? Bool == true)
    }

    @Test func search_completedOnlyOnRequest() async throws {
        var item = makeTask("Statistik Übung", source: .reminders)
        item.isCompleted = true
        let done = CompletedTask(item: item, completedAt: calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 8)))
        let tools = await makeSearch(completed: [done])
        let without = await run(tools, "search", searchArguments("statistik", kind: "tasks"))
        #expect((without["tasks"] as? [[String: Any]])?.isEmpty == true)
        let with = await run(tools, "search", searchArguments("statistik", kind: "tasks", completed: true))
        let task = try #require((with["tasks"] as? [[String: Any]])?.first)
        #expect(task["completed"] as? Bool == true)
        #expect((task["completedAt"] as? String)?.hasPrefix("2026-11-12") == true)
    }

    @Test func search_capsAtTwentyAndReportsTotals() async throws {
        local.tasks += (1...30).map { makeTask("Treffer \($0)", source: .local) }
        let tools = await makeSearch()
        let result = await run(tools, "search", searchArguments("treffer", kind: "tasks"))
        #expect((result["tasks"] as? [[String: Any]])?.count == 20)
        #expect(result["taskCount"] as? Int == 30)
    }

    @Test func search_kindLimitsTheAnswer() async throws {
        local.tasks.append(makeTask("Statistik lernen", source: .local))
        let tools = await makeSearch(events: [searchEvent("Statistik Klausur", on: DateComponents(year: 2026, month: 12, day: 3))])
        let events = await run(tools, "search", searchArguments("statistik", kind: "events"))
        #expect((events["tasks"] as? [[String: Any]])?.isEmpty == true && events["taskCount"] as? Int == 0)
        #expect(events["eventCount"] as? Int == 1)
        let tasks = await run(tools, "search", searchArguments("statistik", kind: "tasks"))
        #expect((tasks["events"] as? [[String: Any]])?.isEmpty == true && tasks["eventCount"] as? Int == 0)
        #expect(tasks["taskCount"] as? Int == 1)
    }

    @Test func search_upcomingEventsComeBeforePastOnes() async throws {
        let tools = await makeSearch(events: [searchEvent("Statistik alt", on: DateComponents(year: 2026, month: 10, day: 1)),
                                              searchEvent("Statistik neu", on: DateComponents(year: 2026, month: 12, day: 1))])
        let result = await run(tools, "search", searchArguments("statistik", kind: "events"))
        #expect((result["events"] as? [[String: Any]])?.map { $0["title"] as? String } == ["Statistik neu", "Statistik alt"])
    }

    @Test func search_rejectsBadArguments() async throws {
        let tools = await makeSearch()
        func error(_ arguments: String) async -> String? { await run(tools, "search", arguments)["error"] as? String }
        #expect(await error(searchArguments("a")) == "Der Suchtext braucht mindestens zwei Zeichen.")
        #expect(await error(searchArguments("ab", from: "2027-01-01", to: "2026-01-01")) == "Der Zeitraum ist ungültig.")
        #expect(await error(searchArguments("ab", from: "2020-01-01", to: "2026-01-01")) == "Der Zeitraum darf höchstens vier Jahre umfassen.")
        // Only "to", and earlier than the default start.
        #expect(await error(searchArguments("ab", to: "2026-01-01")) == "Der Zeitraum ist ungültig.")
        #expect(await error(searchArguments("ab", from: "kein-datum")) == "Das Datum from ist ungültig.")
    }

    @Test func search_acceptsAnExplicitPeriod() async throws {
        let tools = await makeSearch(events: [searchEvent("Statistik 2024", on: DateComponents(year: 2024, month: 5, day: 6))])
        let result = await run(tools, "search", searchArguments("statistik", kind: "events", from: "2024-01-01", to: "2024-12-31"))
        #expect(result["eventCount"] as? Int == 1)
        #expect((result["searched"] as? [String: String]) == ["from": "2024-01-01", "to": "2024-12-31"])
    }

    @Test func search_withoutCalendarAccessStillAnswersTasks() async throws {
        local.tasks.append(makeTask("Statistik lernen", source: .local))
        let tools = await makeSearch(access: false)
        let result = await run(tools, "search", searchArguments("statistik"))
        #expect((result["events"] as? [[String: Any]])?.isEmpty == true)
        #expect(result["taskCount"] as? Int == 1)
        #expect(result["calendarAccess"] as? Bool == false)
    }

    @Test func search_withoutSourcesReportsItself() async throws {
        let (tools, _) = await make()
        let result = await run(tools, "search", searchArguments("statistik"))
        #expect(result["error"] as? String == "Die Suche ist nicht verfügbar.")
    }

    @Test func listEvents_outputIsUnchangedAfterExtraction() async throws {
        let (tools, _) = await make()
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 9))!
        var event = CalendarEvent(id: "e1", externalID: nil, calendarID: "plan", title: "Seminar", start: start,
                                  end: start.addingTimeInterval(3600), isAllDay: false, url: nil, isBusy: true, version: "1")
        event.location = "Raum 3"
        calendarStore.storedEvents = [event]
        let result = await run(tools, "list_events", #"{"from":"2026-11-19","to":"2026-11-19"}"#)
        let listed = try #require((result["events"] as? [[String: Any]])?.first)
        #expect(Set(listed.keys) == ["id", "title", "allDay", "busy", "calendarId", "editable", "recurring", "calendar", "location", "start", "end"])
        #expect(listed["location"] as? String == "Raum 3")
    }

    @Test func listTasks_returnsCompactJSON() async throws {
        let (tools, _) = await make()
        let result = await run(tools, "list_tasks", #"{"filter":"all"}"#)
        let tasks = try #require(result["tasks"] as? [[String: Any]])
        #expect(tasks.map { $0["id"] as? String } == ["local:Fahrrad", "local:Abgabe"])
        #expect(tasks.first?["due"] as? String == "2026-11-18")
        #expect(tasks.first?["notes"] == nil)
    }

    @Test func listTasks_today_filtersDueToday() async throws {
        let (tools, _) = await make()
        let result = await run(tools, "list_tasks", #"{"filter":"today"}"#)
        #expect((result["tasks"] as? [[String: Any]])?.map { $0["title"] as? String } == ["Fahrrad"])
    }

    @Test func createTask_isWriteKind_andCreatesLocalTask() async throws {
        let (tools, _) = await make()
        #expect(tools.kind(of: "create_task") == .write)
        let result = await run(tools, "create_task",
                               #"{"title":"Neu","due":"2026-11-19","priority":"P2","minutes":30,"notes":null,"source":"local","repository":null,"project_ids":null,"assignees":null}"#)
        #expect(result["ok"] as? Bool == true)
        let created = try #require(local.tasks.first { $0.title == "Neu" })
        #expect(created.due == DueDate(year: 2026, month: 11, day: 19))
        #expect(created.priority == .p2)
        #expect(taskList.items.contains { $0.title == "Neu" })
        #expect(result["id"] as? String == created.id.key)
    }

    @Test func rescheduleAndComplete_updateTheTask() async throws {
        let (tools, _) = await make()
        _ = await run(tools, "reschedule_task", #"{"id":"local:Fahrrad","due":"2026-11-25"}"#)
        #expect(local.tasks.first { $0.title == "Fahrrad" }?.due == DueDate(year: 2026, month: 11, day: 25))
        let completed = await run(tools, "complete_task", #"{"id":"local:Fahrrad"}"#)
        #expect(completed["ok"] as? Bool == true)
        #expect(!taskList.items.contains { $0.title == "Fahrrad" })
    }

    @Test func unknownTask_returnsErrorOutput() async throws {
        let (tools, _) = await make()
        let result = await run(tools, "complete_task", #"{"id":"local:Gibtsnicht"}"#)
        #expect(result["error"] as? String == "Diese Aufgabe gibt es nicht.")
        let unknownTool = await run(tools, "delete_everything", "{}")
        #expect(unknownTool["error"] != nil)
        let badArguments = await run(tools, "complete_task", "kein JSON")
        #expect(badArguments["error"] != nil)
    }

    @Test func writeError_isReportedAsOutput() async throws {
        local.applyError = .failed("Die Quelle ist offline.")
        let (tools, _) = await make()
        let result = await run(tools, "reschedule_task", #"{"id":"local:Fahrrad","due":"2026-11-25"}"#)
        #expect(result["error"] as? String == "Die Quelle ist offline.")
    }

    @Test func setDayHours_writesOverride() async throws {
        let (tools, planning) = await make()
        _ = await run(tools, "set_day_hours", #"{"day":"2026-11-18","start":"09:00","end":"20:00","off":false}"#)
        #expect(planStore.override(on: today) == .hours(WorkHours(startMinutes: 540, endMinutes: 1200)))
        _ = await run(tools, "set_day_hours", #"{"day":"2026-11-19","start":null,"end":null,"off":true}"#)
        #expect(planStore.override(on: PlanDay(year: 2026, month: 11, day: 19)) == .off)
        #expect(planning.days.first?.capacity.availableMinutes ?? 0 > 480)
    }

    @Test func setLunch_movesBreakOfThatDay() async throws {
        let (tools, planning) = await make()
        _ = await run(tools, "set_lunch", #"{"day":"2026-11-18","start":"13:00","minutes":30}"#)
        #expect(planning.lunch(on: today) == 780..<810)
    }

    @Test func markEventsFree_series_asksSpanInArguments() async throws {
        calendarStore.storedEvents = [CalendarEvent(id: "e1", externalID: nil, calendarID: "work", title: "Jour fixe",
                                                    start: testNow(), end: testNow().addingTimeInterval(3600),
                                                    isAllDay: false, url: nil, isBusy: true, version: "1")]
        let (tools, _) = await make()
        let definition = try #require(tools.definitions.first { $0.name == "mark_events_free" })
        let schema = try #require(try JSONSerialization.jsonObject(with: definition.parameters) as? [String: Any])
        #expect((schema["required"] as? [String])?.contains("series") == true)
        let result = await run(tools, "mark_events_free", #"{"event_ids":["e1"],"free":true,"series":false}"#)
        #expect(result["ok"] as? Bool == true)
        #expect(result["count"] as? Int == 1)
    }

    @Test func assignAndBlock_planTheTask() async throws {
        let (tools, _) = await make()
        _ = await run(tools, "assign_to_day", #"{"id":"local:Abgabe","day":"2026-11-19"}"#)
        #expect(planStore.assignment(for: TaskID(source: .local, rawValue: "Abgabe")) == PlanDay(year: 2026, month: 11, day: 19))
        let block = await run(tools, "create_time_block", #"{"id":"local:Fahrrad","day":"2026-11-18","start":"15:00","minutes":45}"#)
        #expect(block["ok"] as? Bool == true)
        #expect(calendarStore.storedEvents.contains { $0.calendarID == "plan" })
    }

    @Test func planPeriod_returnsSummaryWithCounts() async throws {
        responder.enqueue(#"{"blocks":[{"taskId":"local:Fahrrad","start":"14:00","minutes":60,"reason":"r"}],"unscheduled":[{"taskId":"local:Abgabe","reason":"voll"}],"risks":[],"estimates":[]}"#)
        planStore.assign(TaskID(source: .local, rawValue: "Abgabe"), to: today)
        let (tools, _) = await make()
        let result = await run(tools, "plan_period", #"{"scope":"day","day":"2026-11-18"}"#)
        #expect(result["ok"] as? Bool == true)
        #expect(result["suggestions"] as? Int == 1)
        #expect(result["unscheduled"] as? Int == 1)
    }

    @Test func addComment_unsupportedSource_returnsError() async throws {
        let (tools, _) = await make()
        let result = await run(tools, "add_comment", #"{"id":"local:Fahrrad","body":"Hallo"}"#)
        #expect(result["error"] as? String == "Kommentare gibt es nur bei GitHub-Issues.")
    }

    // MARK: Events (issue #118)

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func addWorkCalendar() {
        calendarStore.calendars.append(ListInfo(id: "work", title: "Arbeit", colorHex: nil, kind: .calDAV))
    }

    @Test func createEvent_goesToPlanCalendarByDefault() async throws {
        let (tools, _) = await make()
        let result = await run(tools, "create_event", #"{"title":"Zahnarzt","start":"2026-11-19T10:00","end":"2026-11-19T11:00","all_day":false,"calendar_id":null,"location":"Praxis","notes":null}"#)
        #expect(result["ok"] as? Bool == true, "\(result)")
        let event = try #require(calendarStore.storedEvents.first)
        #expect(event.calendarID == "plan")
        #expect(event.title == "Zahnarzt")
        #expect(event.start == date(19, 10))
        #expect(event.end == date(19, 11))
        #expect(event.location == "Praxis")
        #expect(result["id"] as? String == event.id)
    }

    @Test func createEvent_inNamedCalendar_andRefusesUnknown() async throws {
        addWorkCalendar()
        let (tools, _) = await make()
        let result = await run(tools, "create_event", #"{"title":"Review","start":"2026-11-19T14:00","end":"2026-11-19T15:00","all_day":false,"calendar_id":"work","location":null,"notes":null}"#)
        #expect(result["ok"] as? Bool == true)
        #expect(calendarStore.storedEvents.first?.calendarID == "work")
        let unknown = await run(tools, "create_event", #"{"title":"X","start":"2026-11-19T14:00","end":"2026-11-19T15:00","all_day":false,"calendar_id":"birthdays","location":null,"notes":null}"#)
        #expect(unknown["error"] != nil)
        #expect(calendarStore.storedEvents.count == 1)
    }

    @Test func createEvent_allDay_spansInclusiveDays() async throws {
        let (tools, _) = await make()
        let result = await run(tools, "create_event", #"{"title":"Urlaub","start":"2026-11-23","end":"2026-11-27","all_day":true,"calendar_id":null,"location":null,"notes":null}"#)
        #expect(result["ok"] as? Bool == true, "\(result)")
        let event = try #require(calendarStore.storedEvents.first)
        #expect(event.isAllDay)
        #expect(event.start == date(23, 0))
        #expect(event.end == date(28, 0))
    }

    @Test func createEvent_refusesEndBeforeStart() async throws {
        let (tools, _) = await make()
        let result = await run(tools, "create_event", #"{"title":"X","start":"2026-11-19T11:00","end":"2026-11-19T10:00","all_day":false,"calendar_id":null,"location":null,"notes":null}"#)
        #expect(result["error"] != nil)
        #expect(calendarStore.storedEvents.isEmpty)
    }

    @Test func updateEvent_changesGivenFieldsOnly() async throws {
        addWorkCalendar()
        let (tools, _) = await make()
        _ = await run(tools, "create_event", #"{"title":"Zahnarzt","start":"2026-11-19T10:00","end":"2026-11-19T11:00","all_day":false,"calendar_id":null,"location":"Praxis","notes":"Karte"}"#)
        let id = try #require(calendarStore.storedEvents.first?.id)
        let result = await run(tools, "update_event", #"{"event_id":"\#(id)","title":null,"start":"2026-11-19T15:00","end":"2026-11-19T16:30","all_day":null,"calendar_id":"work","location":null,"notes":null,"series":false}"#)
        #expect(result["ok"] as? Bool == true, "\(result)")
        let event = try #require(calendarStore.storedEvents.first)
        #expect(event.title == "Zahnarzt")
        #expect(event.start == date(19, 15))
        #expect(event.end == date(19, 16, 30))
        #expect(event.location == "Praxis")
        #expect(event.notes == "Karte")
        #expect(event.calendarID == "work")
    }

    @Test func updateEvent_startOnly_keepsDuration() async throws {
        let (tools, _) = await make()
        _ = await run(tools, "create_event", #"{"title":"Zahnarzt","start":"2026-11-19T10:00","end":"2026-11-19T11:00","all_day":false,"calendar_id":null,"location":null,"notes":null}"#)
        let id = try #require(calendarStore.storedEvents.first?.id)
        _ = await run(tools, "update_event", #"{"event_id":"\#(id)","title":"Zahnarzt Kontrolle","start":"2026-11-20T08:30","end":null,"all_day":null,"calendar_id":null,"location":null,"notes":null,"series":false}"#)
        let event = try #require(calendarStore.storedEvents.first)
        #expect(event.title == "Zahnarzt Kontrolle")
        #expect(event.start == date(20, 8, 30))
        #expect(event.end == date(20, 9, 30))
    }

    @Test func deleteEvent_removesIt_andReportsMissing() async throws {
        let (tools, _) = await make()
        _ = await run(tools, "create_event", #"{"title":"Zahnarzt","start":"2026-11-19T10:00","end":"2026-11-19T11:00","all_day":false,"calendar_id":null,"location":null,"notes":null}"#)
        let id = try #require(calendarStore.storedEvents.first?.id)
        let result = await run(tools, "delete_event", #"{"event_id":"\#(id)","series":false}"#)
        #expect(result["ok"] as? Bool == true)
        #expect(calendarStore.storedEvents.isEmpty)
        let again = await run(tools, "delete_event", #"{"event_id":"\#(id)","series":false}"#)
        #expect(again["error"] != nil)
    }

    @Test func listCalendars_marksPlanAndWritable() async throws {
        addWorkCalendar()
        let (tools, _) = await make()
        let result = await run(tools, "list_calendars", "{}")
        let calendars = try #require(result["calendars"] as? [[String: Any]])
        #expect(calendars.map { $0["id"] as? String } == ["plan", "work"])
        #expect(calendars.first?["default"] as? Bool == true)
        #expect(calendars.last?["default"] as? Bool == false)
        #expect(calendars.allSatisfy { $0["writable"] as? Bool == true })
    }

    @Test func listEvents_showsCalendarAndEditability() async throws {
        let (tools, _) = await make()
        _ = await run(tools, "create_event", #"{"title":"Zahnarzt","start":"2026-11-19T10:00","end":"2026-11-19T11:00","all_day":false,"calendar_id":null,"location":"Praxis","notes":null}"#)
        let result = await run(tools, "list_events", #"{"from":"2026-11-19","to":"2026-11-19"}"#)
        let event = try #require((result["events"] as? [[String: Any]])?.first)
        #expect(event["calendar"] as? String == "Tagwerk")
        #expect(event["calendarId"] as? String == "plan")
        #expect(event["location"] as? String == "Praxis")
        #expect(event["editable"] as? Bool == true)
        #expect(event["recurring"] as? Bool == false)
        #expect(event["deadline"] == nil)
    }

    @Test func listEventsNamesDeadline() async throws {
        let (tools, planning) = await make()
        _ = await run(tools, "create_event", #"{"title":"Klausur Statistik","start":"2026-11-19T10:00","end":"2026-11-19T12:00","all_day":false,"calendar_id":null,"location":null,"notes":null}"#)
        let exam = try #require(calendarStore.storedEvents.first { $0.title == "Klausur Statistik" })
        await planning.markDeadline(exam, series: false)
        let result = await run(tools, "list_events", #"{"from":"2026-11-19","to":"2026-11-19"}"#)
        let event = try #require((result["events"] as? [[String: Any]])?.first)
        #expect(event["deadline"] as? Bool == true)
    }
}

@MainActor
struct LinkSuggestionTests {
    @Test func suggestLink_isWriteKind_andLinksOnConfirm() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let settings = try AppSettings.current(in: container.mainContext)
        let calendarStore = FakeCalendarStore()
        calendarStore.storedEvents = [CalendarEvent(id: "e1", externalID: nil, calendarID: "work", title: "Login fixen",
                                                    start: testNow(), end: testNow().addingTimeInterval(3600), isAllDay: false,
                                                    url: nil, isBusy: true, version: "1")]
        let local = FakeTaskProvider(source: .local, tasks: [makeTask("Login", source: .local)])
        let taskList = TaskListModel(providers: [local], now: testNow, calendar: testCalendar())
        await taskList.reload()
        let planStore = PlanStore(context: container.mainContext)
        let links = EventLinkStore(context: container.mainContext)
        let blocks = BlockPlanner(store: calendarStore, planStore: planStore, links: links, settings: settings, calendar: testCalendar())
        let planning = PlanningModel(taskList: taskList, calendarStore: calendarStore, reminderStore: FakeAccessStore(),
                                     planStore: planStore, efforts: RecurringEffortStore(context: container.mainContext),
                                     blocks: blocks, settings: settings, marks: EventMarkStore(context: container.mainContext),
                                     now: testNow, calendar: testCalendar())
        let tools = AppTools(taskList: taskList, planning: planning, planner: nil, events: { _ in calendarStore.storedEvents })
        #expect(tools.kind(of: "link_event_to_task") == .write)
        // Before confirmation nothing is linked; running the call is what the confirmation does.
        #expect(links.manualLinks().isEmpty)
        _ = await tools.run(ToolCall(id: "c", name: "link_event_to_task", arguments: Data(#"{"event_id":"e1","task_id":"local:Login"}"#.utf8)))
        #expect(links.manualLinks()["e1"] == TaskID(source: .local, rawValue: "Login"))
    }

    @Test func contextMenu_hasAIEntries_onlyWhenSignedIn() {
        #expect(TaskContextMenu.showsAIEntries(isSignedIn: true))
        #expect(!TaskContextMenu.showsAIEntries(isSignedIn: false))
    }

    @Test func contextMenu_offersFocusStart_forOpenTasksOfEverySource() {
        for source in TaskSource.allCases {
            var item = makeTask("Aufgabe", source: source)
            #expect(TaskContextMenu.showsFocusStart(for: item))
            item.isCompleted = true
            #expect(!TaskContextMenu.showsFocusStart(for: item))
        }
    }

}

@MainActor
struct AppToolsGitHubTests {
    let container: ModelContainer
    let settings: AppSettings
    let calendarStore = FakeCalendarStore()
    let local = FakeTaskProvider(source: .local)
    let github = FakeTaskProvider(source: .github)
    let directory = FakeGitHubDirectory.single()
    let taskList: TaskListModel
    let calendar = testCalendar()

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        settings = try AppSettings.current(in: container.mainContext)
        github.viewerLogin = "octo"
        taskList = TaskListModel(providers: [local, github], now: testNow, calendar: calendar)
    }

    private func make(signedIn: Bool = true) async -> AppTools {
        await makeWithPlanning(signedIn: signedIn).tools
    }

    /// The tools together with the planning model and its stores, for tests that look at blocks and planned days.
    private func makeWithPlanning(signedIn: Bool = true) async
        -> (tools: AppTools, planning: PlanningModel, blocks: BlockPlanner, planStore: PlanStore) {
        await taskList.reload()
        settings.planCalendarID = "plan"
        let planStore = PlanStore(context: container.mainContext)
        let blocks = BlockPlanner(store: calendarStore, planStore: planStore, links: EventLinkStore(context: container.mainContext),
                                  settings: settings, calendar: calendar)
        let planning = PlanningModel(taskList: taskList, calendarStore: calendarStore, reminderStore: FakeAccessStore(),
                                     planStore: planStore, efforts: RecurringEffortStore(context: container.mainContext),
                                     blocks: blocks, settings: settings, marks: EventMarkStore(context: container.mainContext),
                                     now: testNow, calendar: calendar)
        // Like AppEnvironment: a hand-over deletes the planned day and the future blocks.
        taskList.onHandedOver = { id in await planning.didHandOver(id) }
        let directory = self.directory
        let tools = AppTools(taskList: taskList, planning: planning, planner: nil, events: { _ in [] },
                             gitHub: { signedIn ? directory : nil })
        return (tools, planning, blocks, planStore)
    }

    private func run(_ tools: AppTools, _ name: String, _ arguments: String) async -> [String: Any] {
        let output = await tools.run(ToolCall(id: "c1", name: name, arguments: Data(arguments.utf8)))
        return (try? JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any]) ?? ["raw": output]
    }

    /// Arguments of a create_task call for a GitHub issue; the three GitHub fields default to null.
    private func issue(repository: String? = nil, projects: [String]? = nil, assignees: [String]? = nil,
                       source: String = "github") -> String {
        func json(_ value: Any?) -> String {
            guard let value else { return "null" }
            return String(decoding: try! JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]), as: UTF8.self)
        }
        return #"{"title":"Export","due":null,"priority":null,"minutes":null,"notes":null,"source":"\#(source)","#
            + #""repository":\#(json(repository)),"project_ids":\#(json(projects)),"assignees":\#(json(assignees))}"#
    }

    private func addSecondRepository() {
        let projects = directory.storedCatalog?.projects ?? []
        directory.storedCatalog = GitHubCatalog(repositories: ["beispiel/app", "beispiel/web"], projects: projects,
                                                fetchedAt: Date(timeIntervalSince1970: 0))
    }

    @Test func definitions_includeGitHubToolsOnlyWhenSignedIn() async {
        let signedOut = await make(signedIn: false)
        #expect(!signedOut.definitions.contains { $0.name == "list_github_targets" || $0.name == "list_assignees" })
        let signedIn = await make()
        let names = Set(signedIn.definitions.map(\.name))
        #expect(names.isSuperset(of: ["list_github_targets", "list_assignees"]))
        #expect(signedIn.kind(of: "list_github_targets") == .read)
        #expect(signedIn.kind(of: "list_assignees") == .read)
        #expect(signedIn.kind(of: "create_task") == .write)
    }

    @Test func gitHubDefinitions_areStrict() throws {
        for definition in AppTools.gitHubDefinitions {
            let schema = try #require(try JSONSerialization.jsonObject(with: definition.parameters) as? [String: Any])
            let properties = try #require(schema["properties"] as? [String: Any])
            #expect(schema["additionalProperties"] as? Bool == false)
            #expect(Set(schema["required"] as? [String] ?? []) == Set(properties.keys))
            #expect(definition.strict)
        }
    }

    @Test func createTaskSchema_requiresTheThreeNullableGitHubFields() throws {
        let definition = try #require(AppTools.allDefinitions.first { $0.name == "create_task" })
        let schema = try #require(try JSONSerialization.jsonObject(with: definition.parameters) as? [String: Any])
        let required = Set(schema["required"] as? [String] ?? [])
        let properties = try #require(schema["properties"] as? [String: [String: Any]])
        for field in ["repository", "project_ids", "assignees"] {
            #expect(required.contains(field), "\(field)")
            #expect((properties[field]?["type"] as? [String])?.contains("null") == true, "\(field)")
        }
    }

    @Test func listGitHubTargets_returnsRepositoriesWithLinkedProjects() async throws {
        let result = await run(await make(), "list_github_targets", "{}")
        let repositories = try #require(result["repositories"] as? [[String: Any]])
        #expect(repositories.count == 1)
        #expect(repositories[0]["name"] as? String == "beispiel/app")
        #expect(repositories[0]["linked_project_ids"] as? [String] == ["PVT_1"])
        let projects = try #require(result["projects"] as? [[String: String]])
        #expect(projects == [["id": "PVT_1", "title": "App"]])
    }

    @Test func listGitHubTargets_capsAtThirtyRepositories() async throws {
        directory.storedCatalog = GitHubCatalog(repositories: (1...40).map { "beispiel/repo-\($0)" }, projects: [],
                                                fetchedAt: Date(timeIntervalSince1970: 0))
        let result = await run(await make(), "list_github_targets", "{}")
        let repositories = try #require(result["repositories"] as? [[String: Any]])
        #expect(repositories.count == 30)
        #expect(repositories.first?["name"] as? String == "beispiel/repo-1")
    }

    @Test func listAssignees_returnsMeAndOthers() async {
        let result = await run(await make(), "list_assignees", #"{"repository":"beispiel/app"}"#)
        #expect(result["repository"] as? String == "beispiel/app")
        #expect(result["me"] as? String == "octo")
        #expect(result["assignees"] as? [String] == ["jonas-k", "lea-m"])
    }

    @Test func listAssignees_unknownRepository_returnsError() async {
        let result = await run(await make(), "list_assignees", #"{"repository":"fremd/repo"}"#)
        #expect(result["error"] != nil)
        #expect(directory.assignableRequests.isEmpty)
    }

    @Test func listAssignees_notLoadable_returnsError() async {
        directory.assignable = [:]
        let result = await run(await make(), "list_assignees", #"{"repository":"beispiel/app"}"#)
        #expect(result["error"] as? String == "Personen konnten nicht geladen werden")
    }

    @Test func createIssue_withoutAssignees_goesToMe() async {
        let result = await run(await make(), "create_task", issue(repository: "beispiel/app", projects: ["PVT_1"]))
        #expect(result["ok"] as? Bool == true)
        #expect(result["listed"] as? Bool == true)
        #expect(result["number"] as? Int == 151)
        #expect(result["assignees"] as? [String] == ["octo"])
        #expect(result["id"] != nil && result["task"] != nil)
        #expect(result["not_assigned"] == nil)
        #expect(github.createdDrafts.last?.containerID == "beispiel/app")
        #expect(github.createdDrafts.last?.subContainerIDs == ["PVT_1"])
        #expect(github.createdDrafts.last?.assignees == nil)
        #expect(directory.assignableRequests.isEmpty)
        #expect(taskList.items.contains { $0.id.source == .github })
    }

    @Test func createIssue_nullTargets_resolveToTheOnlyRepositoryAndLinkedProjects() async {
        let result = await run(await make(), "create_task", issue())
        #expect(result["ok"] as? Bool == true)
        #expect(github.createdDrafts.last?.containerID == "beispiel/app")
        #expect(github.createdDrafts.last?.subContainerIDs == ["PVT_1"])
    }

    @Test func createIssue_emptyProjectList_meansNoProject_notTheLinkedDefault() async {
        github.requiresPlacementToBeListed = true
        let result = await run(await make(), "create_task", issue(repository: "beispiel/app", projects: []))
        #expect(result["ok"] as? Bool == true)
        #expect(github.createdDrafts.last?.subContainerIDs == [])
        #expect(result["listed"] as? Bool == false)
        #expect(result["number"] as? Int == 151)
        #expect(result["url"] as? String == "https://github.com/beispiel/app/issues/151")
        #expect(result["id"] == nil && result["task"] == nil)
        // The assistant reports the issue in its answer; no capsule on top.
        #expect(taskList.lastHandedOver == nil)
    }

    @Test func createIssue_missingProjectList_stillUsesTheLinkedProjects() async {
        _ = await run(await make(), "create_task", issue(repository: "beispiel/app", projects: nil))
        #expect(github.createdDrafts.last?.subContainerIDs == ["PVT_1"])
    }

    @Test func createIssue_twoRepositoriesWithoutName_returnsError() async {
        addSecondRepository()
        let result = await run(await make(), "create_task", issue())
        #expect(result["error"] as? String == "Bitte ein Repository nennen.")
        #expect(github.createdDrafts.isEmpty)
    }

    @Test func createIssue_unknownRepositoryOrProject_returnsError() async {
        let tools = await make()
        #expect((await run(tools, "create_task", issue(repository: "fremd/repo")))["error"] != nil)
        #expect((await run(tools, "create_task", issue(repository: "beispiel/app", projects: ["PVT_9"])))["error"] != nil)
        #expect(github.createdDrafts.isEmpty)
    }

    @Test func createIssue_forOther_usesGitHubSpelling_andReportsNotListed() async {
        let result = await run(await make(), "create_task", issue(repository: "beispiel/app", projects: ["PVT_1"], assignees: ["LEA-M"]))
        #expect(github.createdDrafts.last?.assignees == ["lea-m"])
        #expect(result["ok"] as? Bool == true)
        #expect(result["number"] as? Int == 151)
        #expect(result["url"] as? String == "https://github.com/beispiel/app/issues/151")
        #expect(result["assignees"] as? [String] == ["lea-m"])
        #expect(result["listed"] as? Bool == false)
        #expect(result["id"] == nil && result["task"] == nil)
        #expect(taskList.lastHandedOver == nil)
        #expect(!taskList.items.contains { $0.id.source == .github })
        #expect(directory.assignableRequests == ["beispiel/app"])
    }

    @Test func createIssue_forNoOne_sendsEmptyList() async {
        let result = await run(await make(), "create_task", issue(assignees: []))
        #expect(github.createdDrafts.last?.assignees == [])
        #expect(result["listed"] as? Bool == false)
        #expect(directory.assignableRequests.isEmpty)
    }

    @Test func createIssue_unknownLogin_createsNothing() async throws {
        let result = await run(await make(), "create_task", issue(assignees: ["ghost"]))
        let message = try #require(result["error"] as? String)
        #expect(message == "ghost ist in beispiel/app nicht zuweisbar.")
        #expect(github.createdDrafts.isEmpty)
    }

    @Test func createIssue_assignableNotLoadable_createsNothing() async {
        directory.assignable = [:]
        let result = await run(await make(), "create_task", issue(assignees: ["lea-m"]))
        #expect(result["error"] as? String == "Personen konnten nicht geladen werden")
        #expect(github.createdDrafts.isEmpty)
    }

    @Test func createIssue_droppedAssignee_reportsNotAssigned() async {
        github.droppedAssignees = ["lea-m"]
        let result = await run(await make(), "create_task", issue(assignees: ["octo", "lea-m"]))
        #expect(result["ok"] as? Bool == true)
        #expect(result["not_assigned"] as? [String] == ["lea-m"])
        #expect(result["assignees"] as? [String] == ["octo"])
        #expect(result["listed"] as? Bool == true)
        #expect(taskList.lastError == nil)
    }

    @Test func createIssue_moreThanTen_returnsError() async {
        let result = await run(await make(), "create_task", issue(assignees: (1...11).map { "user-\($0)" }))
        #expect(result["error"] as? String == "Höchstens 10 Personen je Issue.")
        #expect(github.createdDrafts.isEmpty)
        #expect(directory.assignableRequests.isEmpty)
    }

    @Test func createLocalTask_withGitHubFields_returnsError() async {
        let result = await run(await make(), "create_task", issue(assignees: ["lea-m"], source: "local"))
        #expect(result["error"] != nil)
        #expect(local.createdDrafts.isEmpty)
    }

    @Test func createLocalTask_withNullGitHubFields_works() async {
        let result = await run(await make(), "create_task", issue(source: "local"))
        #expect(result["ok"] as? Bool == true)
        #expect(local.createdDrafts.count == 1)
    }

    @Test func gitHubTarget_noLinkedProjects_fallsBackToOnlyProject_orAsks() {
        let unlinked = ProjectInfo(id: "PVT_1", number: 1, title: "App", fields: [], repositories: [])
        let other = ProjectInfo(id: "PVT_2", number: 2, title: "Web", fields: [], repositories: [])
        let one = GitHubCatalog(repositories: ["beispiel/app"], projects: [unlinked], fetchedAt: .distantPast)
        let two = GitHubCatalog(repositories: ["beispiel/app"], projects: [unlinked, other], fetchedAt: .distantPast)
        #expect(AppTools.gitHubTarget(repository: nil, projectIDs: nil, catalog: one)
            == .success(AppTools.GitHubTarget(repository: "beispiel/app", projectIDs: ["PVT_1"])))
        #expect(AppTools.gitHubTarget(repository: nil, projectIDs: nil, catalog: two) == .failure(.projectMissing))
        #expect(AppTools.gitHubTarget(repository: "Beispiel/App", projectIDs: ["PVT_2"], catalog: two)
            == .success(AppTools.GitHubTarget(repository: "beispiel/app", projectIDs: ["PVT_2"])))
        #expect(AppTools.gitHubTarget(repository: "fremd/repo", projectIDs: nil, catalog: two) == .failure(.repositoryUnknown))
        #expect(AppTools.gitHubTarget(repository: nil, projectIDs: ["PVT_9"], catalog: two) == .failure(.projectUnknown))
        let none = GitHubCatalog(repositories: [], projects: [], fetchedAt: .distantPast)
        #expect(AppTools.gitHubTarget(repository: nil, projectIDs: nil, catalog: none) == .failure(.repositoryMissing))
        // An explicitly empty list is a choice, not a gap: even two unlinked projects do not ask.
        #expect(AppTools.gitHubTarget(repository: nil, projectIDs: [], catalog: two)
            == .success(AppTools.GitHubTarget(repository: "beispiel/app", projectIDs: [])))
    }
}

// MARK: assign_task (issue #173, decision 1)

extension AppToolsGitHubTests {
    private func issue(_ number: Int, assignees: [String]) -> TaskItem {
        TaskItem(id: TaskID(source: .github, rawValue: "ISSUE_\(number)"), title: "Export \(number)", notes: nil, due: nil,
                 priority: nil, estimateMinutes: nil, isCompleted: false,
                 container: TaskContainer(id: "beispiel/app", name: "beispiel/app", colorHex: nil),
                 url: URL(string: "https://github.com/beispiel/app/issues/\(number)"), version: "1",
                 editableFields: [.title, .notes, .due, .priority, .assignees], assignees: assignees)
    }

    private func assignArguments(_ task: TaskItem, add: [String] = [], remove: [String] = []) -> String {
        func json(_ values: [String]) -> String {
            String(decoding: try! JSONSerialization.data(withJSONObject: values), as: UTF8.self)
        }
        return #"{"id":"\#(task.id.key)","add":\#(json(add)),"remove":\#(json(remove))}"#
    }

    private func at(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    // MARK: Plan

    @Test func assignmentPlan_addAndRemove_keepsOrderAndSpelling() throws {
        let plan = try AppTools.assignmentPlan(current: ["Octo", "Lea-M"], add: ["jonas-k"], remove: ["lea-m"], me: "octo").get()
        #expect(plan.change == AssigneeChange(add: ["jonas-k"], remove: ["Lea-M"]))
        #expect(plan.before == ["Octo", "Lea-M"])
        #expect(plan.after == ["Octo", "jonas-k"])
        #expect(!plan.handsOver)
    }

    @Test func assignmentPlan_removingUnassigned_fails() {
        #expect(AppTools.assignmentPlan(current: ["octo"], add: [], remove: ["ghost", "lea-m"], me: "octo")
            == .failure(.notAssigned(["ghost", "lea-m"])))
    }

    @Test func assignmentPlan_sameLoginInBoth_fails() {
        #expect(AppTools.assignmentPlan(current: ["octo", "lea-m"], add: ["Lea-M"], remove: ["lea-m"], me: "octo")
            == .failure(.conflicting(["Lea-M"])))
    }

    @Test func assignmentPlan_moreThanTen_fails() {
        let current = (1...9).map { "user-\($0)" }
        #expect(AppTools.assignmentPlan(current: current, add: ["a-1", "a-2"], remove: [], me: nil) == .failure(.tooMany))
        // Exactly ten is allowed.
        #expect((try? AppTools.assignmentPlan(current: current, add: ["a-1"], remove: [], me: nil).get())?.after.count == 10)
    }

    @Test func assignmentPlan_emptyChange_fails() {
        #expect(AppTools.assignmentPlan(current: ["octo"], add: [], remove: [], me: "octo") == .failure(.nothingToChange))
        // Adding someone who is assigned already changes nothing.
        #expect(AppTools.assignmentPlan(current: ["octo"], add: ["OCTO"], remove: [], me: "octo") == .failure(.nothingToChange))
    }

    @Test func assignmentPlan_ignoresCaseOfOwnLogin() throws {
        let plan = try AppTools.assignmentPlan(current: ["Octo", "lea-m"], add: [], remove: ["OCTO"], me: "octo").get()
        #expect(plan.change == AssigneeChange(remove: ["Octo"]))
        #expect(plan.handsOver)
        let giveBack = try AppTools.assignmentPlan(current: ["lea-m"], add: ["OCTO"], remove: [], me: "octo").get()
        #expect(giveBack.change == AssigneeChange(add: ["octo"]))
        #expect(!giveBack.handsOver)
    }

    // MARK: Execution

    @Test func assignTask_addsValidatedPerson() async throws {
        let task = issue(212, assignees: ["octo"])
        github.tasks = [task]
        let result = await run(await make(), "assign_task", assignArguments(task, add: ["Lea-M"]))
        #expect(result["ok"] as? Bool == true)
        #expect(result["assignees"] as? [String] == ["octo", "lea-m"])
        #expect(result["handed_over"] as? Bool == false)
        #expect(result["deleted_blocks"] as? Int == 0)
        #expect(result["not_assigned"] == nil)
        let applied = try #require(github.appliedEdits.last)
        guard case .set(let change) = applied.edit.assignees else { Issue.record("assignees not set"); return }
        #expect(change == AssigneeChange(add: ["lea-m"]))
        #expect(applied.edit.title.isUnchanged)
        #expect(directory.assignableRequests == ["beispiel/app"])
        #expect(taskList.items.contains { $0.id == task.id })
    }

    @Test func assignTask_ownLoginNeedsNoAssignableList() async {
        let task = issue(212, assignees: ["lea-m"])
        github.tasks = [task]
        directory.assignable = [:]
        let result = await run(await make(), "assign_task", assignArguments(task, add: ["OCTO"]))
        #expect(result["ok"] as? Bool == true)
        #expect(directory.assignableRequests.isEmpty)
    }

    @Test func assignTask_unknownLogin_writesNothing() async {
        let task = issue(212, assignees: ["octo"])
        github.tasks = [task]
        let result = await run(await make(), "assign_task", assignArguments(task, add: ["ghost"]))
        #expect(result["error"] as? String == "ghost ist in beispiel/app nicht zuweisbar.")
        #expect(github.appliedEdits.isEmpty)
    }

    @Test func assignTask_assignableListFails_writesNothing() async {
        let task = issue(212, assignees: ["octo"])
        github.tasks = [task]
        directory.assignable = [:]
        let result = await run(await make(), "assign_task", assignArguments(task, add: ["lea-m"]))
        #expect(result["error"] as? String == "Personen konnten nicht geladen werden")
        #expect(github.appliedEdits.isEmpty)
    }

    @Test func assignTask_removingUnassignedPerson_writesNothing() async {
        let task = issue(212, assignees: ["octo"])
        github.tasks = [task]
        let result = await run(await make(), "assign_task", assignArguments(task, remove: ["lea-m"]))
        #expect(result["error"] != nil)
        #expect(github.appliedEdits.isEmpty)
    }

    @Test func assignTask_handOver_deletesOnlyFutureBlocks() async throws {
        let task = issue(212, assignees: ["octo", "lea-m"])
        github.tasks = [task]
        let (tools, planning, blocks, planStore) = await makeWithPlanning()
        // testNow is 2026-11-18 10:00: one block lies in the past, two start later.
        let past = try blocks.createBlock(for: task, start: at(17, 9), minutes: 60)
        _ = try blocks.createBlock(for: task, start: at(18, 14), minutes: 60)
        _ = try blocks.createBlock(for: task, start: at(19, 9), minutes: 60)
        #expect(planning.futureBlockCount(for: task.id) == 2)

        let result = await run(tools, "assign_task", assignArguments(task, remove: ["octo"]))

        #expect(result["ok"] as? Bool == true)
        #expect(result["handed_over"] as? Bool == true)
        #expect(result["deleted_blocks"] as? Int == 2)
        #expect(result["assignees"] as? [String] == ["lea-m"])
        #expect(result["number"] as? Int == 212)
        #expect(result["url"] as? String == "https://github.com/beispiel/app/issues/212")
        #expect(!taskList.items.contains { $0.id == task.id })
        #expect(calendarStore.storedEvents.map(\.id) == [past.id])
        #expect(planStore.assignment(for: task.id) == nil)
    }

    @Test func assignTask_removeFails_keepsBlocks() async throws {
        let task = issue(212, assignees: ["octo", "lea-m"])
        github.tasks = [task]
        let (tools, _, blocks, planStore) = await makeWithPlanning()
        _ = try blocks.createBlock(for: task, start: at(19, 9), minutes: 60)
        let day = planStore.assignment(for: task.id)
        #expect(day != nil)
        github.applyError = .failed("Netzwerkfehler")

        let result = await run(tools, "assign_task", assignArguments(task, remove: ["octo"]))

        #expect(result["error"] != nil)
        #expect(result["ok"] == nil)
        #expect(taskList.items.contains { $0.id == task.id })
        #expect(calendarStore.storedEvents.count == 1)
        #expect(planStore.assignment(for: task.id) == day)
    }

    @Test func assignTask_localTask_fails() async {
        let task = makeTask("Fahrrad", source: .local)
        local.tasks = [task]
        let result = await run(await make(), "assign_task", assignArguments(task, add: ["lea-m"]))
        #expect(result["error"] as? String == "Zuweisen geht nur bei GitHub-Issues.")
        #expect(github.appliedEdits.isEmpty && local.appliedEdits.isEmpty)
    }

    @Test func assignTask_droppedPerson_isReported() async {
        let task = issue(212, assignees: ["octo"])
        github.tasks = [task]
        github.droppedAssignees = ["lea-m"]
        let result = await run(await make(), "assign_task", assignArguments(task, add: ["lea-m"]))
        #expect(result["ok"] as? Bool == true)
        #expect(result["not_assigned"] as? [String] == ["lea-m"])
    }

    @Test func getTask_listsAssignees() async throws {
        let task = issue(212, assignees: ["octo", "lea-m"])
        github.tasks = [task]
        let result = await run(await make(), "get_task", #"{"id":"\#(task.id.key)"}"#)
        let detail = try #require(result["task"] as? [String: Any])
        #expect(detail["assignees"] as? [String] == ["octo", "lea-m"])
        #expect(result["me"] as? String == "octo")
    }

    @Test func definitions_withoutGitHub_haveNoAssignTask() async {
        #expect(!(await make(signedIn: false)).definitions.contains { $0.name == "assign_task" })
        let signedIn = await make()
        #expect(signedIn.definitions.contains { $0.name == "assign_task" })
        #expect(signedIn.kind(of: "assign_task") == .write)
    }
}
