import AIKit
import Foundation
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
        for name in ["create_task", "update_task", "reschedule_task", "complete_task", "assign_to_day", "create_time_block",
                     "link_event_to_task", "set_day_hours", "set_lunch", "mark_events_free", "plan_period", "add_comment"] {
            #expect(tools.kind(of: name) == .write, "\(name)")
        }
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
                               #"{"title":"Neu","due":"2026-11-19","priority":"P2","minutes":30,"notes":null,"source":"local"}"#)
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
}
