import AIKit
import Foundation
import RemindersKit
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// The assistant's shopping functions (phase 5 design §5.8): reading at once, changing after confirmation,
/// and never touching a reminder outside the shopping list.
@MainActor
struct AppToolsShoppingTests {
    let container: ModelContainer
    let settings: AppSettings
    let store: InMemoryReminderStore
    let shopping: ShoppingModel
    let taskList: TaskListModel
    let responder = FakePlanResponder()
    let calendar = testCalendar()

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        settings = try AppSettings.current(in: container.mainContext)
        settings.shoppingListID = "shop"
        let now = testNow()
        func item(_ id: String, _ title: String, list: String = "shop", notes: String? = nil, completed: Date? = nil) -> ReminderRecord {
            ReminderRecord(id: id, title: title, notes: notes, due: nil, ekPriority: 0, isCompleted: completed != nil, listID: list,
                           lastModified: nil, createdAt: now.addingTimeInterval(-3600), completedAt: completed)
        }
        store = InMemoryReminderStore(
            lists: [ListInfo(id: "shop", title: "Einkauf", colorHex: nil, kind: .calDAV),
                    ListInfo(id: "uni", title: "Uni", colorHex: nil, kind: .calDAV)],
            records: [item("milk", "Milch", notes: "2"), item("eggs", "Eier"), item("essay", "Seminararbeit", list: "uni"),
                      item("bread", "Brot", completed: now.addingTimeInterval(-86_400)),
                      item("old", "Reis", completed: now.addingTimeInterval(-9 * 86_400))],
            now: { now })
        let categories = ShoppingCategoryStore(context: container.mainContext, settings: settings)
        categories.seedIfNeeded()
        shopping = ShoppingModel(store: store, settings: settings, categories: categories, now: { now })
        let settings = self.settings
        let reminders = RemindersTaskProvider(store: store, selectedListIDs: { nil }, excludedListID: { settings.shoppingListID })
        taskList = TaskListModel(providers: [reminders], now: testNow, calendar: calendar)
    }

    private func makePlanning() async -> PlanningModel {
        await taskList.reload()
        let calendarStore = FakeCalendarStore()
        let planStore = PlanStore(context: container.mainContext)
        let blocks = BlockPlanner(store: calendarStore, planStore: planStore, links: EventLinkStore(context: container.mainContext),
                                  settings: settings, calendar: calendar)
        let planning = PlanningModel(taskList: taskList, calendarStore: calendarStore, reminderStore: store, planStore: planStore,
                                     efforts: RecurringEffortStore(context: container.mainContext), blocks: blocks, settings: settings,
                                     marks: EventMarkStore(context: container.mainContext), now: testNow, calendar: calendar)
        await planning.reload()
        return planning
    }

    private func makeTools(shopping: ShoppingModel? = nil, withShopping: Bool = true) async -> AppTools {
        AppTools(taskList: taskList, planning: await makePlanning(), planner: nil, events: { _ in [] },
                 shopping: withShopping ? (shopping ?? self.shopping) : nil)
    }

    private func run(_ tools: AppTools, _ name: String, _ arguments: String) async -> [String: Any] {
        let output = await tools.run(ToolCall(id: "c1", name: name, arguments: Data(arguments.utf8)))
        return (try? JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any]) ?? ["raw": output]
    }

    // MARK: list_shopping

    @Test func listShopping_isReadTool_andListsOpenWithCategory() async {
        let tools = await makeTools()
        #expect(tools.kind(of: "list_shopping") == .read && tools.kind(of: "update_shopping") == .write)
        let result = await run(tools, "list_shopping", #"{"include_completed":false}"#)
        #expect(result["ok"] as? Bool == true)
        #expect(result["list"] as? String == "Einkauf")
        let open = result["open"] as? [[String: Any]] ?? []
        #expect(open.map { $0["name"] as? String } == ["Eier", "Milch"])
        #expect(open.map { $0["id"] as? String } == ["eggs", "milk"])
        #expect(open.last?["quantity"] as? String == "2" && open.last?["category"] as? String == "Kühlregal")
        #expect(open.first?["quantity"] is NSNull)
        #expect((result["completed"] as? [Any])?.isEmpty == true)
    }

    @Test func listShopping_includeCompleted_onlyLastSevenDays() async {
        let result = await run(await makeTools(), "list_shopping", #"{"include_completed":true}"#)
        let completed = result["completed"] as? [[String: Any]] ?? []
        #expect(completed.map { $0["name"] as? String } == ["Brot"])
        #expect(completed.first?["id"] as? String == "bread")
    }

    @Test func listShopping_capsAtHundred() async {
        for index in 1...120 {
            store.records["x\(index)"] = ReminderRecord(id: "x\(index)", title: "Artikel \(index)", notes: nil, due: nil, ekPriority: 0,
                                                        isCompleted: false, listID: "shop", lastModified: nil)
        }
        let result = await run(await makeTools(), "list_shopping", #"{"include_completed":false}"#)
        #expect((result["open"] as? [Any])?.count == 100)
    }

    @Test func listShopping_unknownCategory_isOther() async {
        store.records["screws"] = ReminderRecord(id: "screws", title: "Schrauben", notes: nil, due: nil, ekPriority: 0,
                                                 isCompleted: false, listID: "shop", lastModified: nil)
        let result = await run(await makeTools(), "list_shopping", #"{"include_completed":false}"#)
        let open = result["open"] as? [[String: Any]] ?? []
        #expect(open.first { $0["id"] as? String == "screws" }?["category"] as? String == "Sonstiges")
    }

    // MARK: update_shopping

    @Test func updateShopping_addsViaRuleR4_andChecksOff() async {
        let result = await run(await makeTools(), "update_shopping",
                               #"{"add":[{"name":"Kaffee","quantity":null},{"name":"milch","quantity":"3"},{"name":"brot","quantity":null}],"check_off":["eggs"]}"#)
        #expect(result["ok"] as? Bool == true)
        #expect(result["added"] as? [String] == ["Kaffee"] && result["already_on_list"] as? [String] == ["Milch"])
        #expect(result["reopened"] as? [String] == ["Brot"])
        #expect(result["checked_off"] as? [String] == ["Eier"])
        #expect((result["not_found"] as? [String])?.isEmpty == true)
        #expect(store.records["milk"]?.notes == "3")
        #expect(store.records["eggs"]?.isCompleted == true)
        #expect(store.records["bread"]?.isCompleted == false)
    }

    @Test func updateShopping_checkOffForeignReminder_isNotFound_andStaysOpen() async {
        let result = await run(await makeTools(), "update_shopping", #"{"add":[],"check_off":["essay","nope"]}"#)
        #expect(result["not_found"] as? [String] == ["essay", "nope"])
        #expect((result["checked_off"] as? [String])?.isEmpty == true)
        #expect(store.records["essay"]?.isCompleted == false)
    }

    @Test func updateShopping_trimsNames_dropsEmpty_cutsAtEighty() async {
        let long = String(repeating: "a", count: 100)
        let result = await run(await makeTools(), "update_shopping",
                               #"{"add":[{"name":"  ","quantity":null},{"name":" Hefe ","quantity":" "},{"name":"\#(long)","quantity":null}],"check_off":[]}"#)
        let added = result["added"] as? [String] ?? []
        #expect(added.count == 2 && added.first == "Hefe" && added.last?.count == 80)
        #expect(store.records.values.first { $0.title == "Hefe" }?.notes == nil)
    }

    @Test func updateShopping_moreThanThirty_isError() async {
        let adds = (1...31).map { #"{"name":"A\#($0)","quantity":null}"# }.joined(separator: ",")
        let result = await run(await makeTools(), "update_shopping", #"{"add":[\#(adds)],"check_off":[]}"#)
        #expect(result["error"] != nil && store.createCount == 0)
        let ids = (1...31).map { #""id\#($0)""# }.joined(separator: ",")
        #expect(await run(await makeTools(), "update_shopping", #"{"add":[],"check_off":[\#(ids)]}"#)["error"] != nil)
    }

    @Test func shoppingTools_withoutList_returnSetupError() async {
        let expected = "Es ist keine Einkaufsliste eingerichtet. Einstellungen › Einkaufsliste."
        settings.shoppingListID = nil
        let tools = await makeTools()
        #expect(await run(tools, "list_shopping", #"{"include_completed":false}"#)["error"] as? String == expected)
        #expect(await run(tools, "update_shopping", #"{"add":[{"name":"Kaffee","quantity":null}],"check_off":[]}"#)["error"] as? String == expected)
        #expect(store.createCount == 0)
        settings.shoppingListID = "shop"
        store.accessState = .denied
        #expect(await run(tools, "list_shopping", #"{"include_completed":false}"#)["error"] as? String == expected)
        let without = await makeTools(withShopping: false)
        #expect(await run(without, "list_shopping", #"{"include_completed":false}"#)["error"] as? String == expected)
    }

    // MARK: Definitions and neighbours

    @Test func definitions_areStrictWithAllFieldsRequired() async throws {
        let tools = await makeTools()
        let list = try #require(tools.definitions.first { $0.name == "list_shopping" })
        let update = try #require(tools.definitions.first { $0.name == "update_shopping" })
        #expect(list.strict && update.strict)
        #expect(update.description.hasSuffix("Needs confirmation."))
        let schema = try #require(try JSONSerialization.jsonObject(with: update.parameters) as? [String: Any])
        #expect(Set(schema["required"] as? [String] ?? []) == ["add", "check_off"])
        #expect(schema["additionalProperties"] as? Bool == false)
        let properties = try #require(schema["properties"] as? [String: Any])
        let item = try #require((properties["add"] as? [String: Any])?["items"] as? [String: Any])
        #expect(Set(item["required"] as? [String] ?? []) == ["name", "quantity"])
        #expect(item["additionalProperties"] as? Bool == false)
        let quantity = try #require((item["properties"] as? [String: Any])?["quantity"] as? [String: Any])
        #expect(quantity["type"] as? [String] == ["string", "null"])
    }

    @Test func listTasks_containsNoShoppingItem() async throws {
        let result = await run(await makeTools(), "list_tasks", #"{"filter":"all"}"#)
        let titles = (result["tasks"] as? [[String: Any]] ?? []).compactMap { $0["title"] as? String }
        #expect(titles == ["Seminararbeit"])
    }

    // MARK: Card and instructions

    private func makeAssistant() async -> AssistantModel {
        let planning = await makePlanning()
        let tools = AppTools(taskList: taskList, planning: planning, planner: nil, events: { _ in [] }, shopping: shopping)
        let model = AssistantModel(responder: responder, tools: tools, model: { "gpt-test" },
                                   store: ChatStore(context: container.mainContext), planning: planning, now: testNow)
        await shopping.reload()
        let shopping = self.shopping
        model.shoppingItemName = { id in shopping.openItems.first { $0.id == id }?.name }
        return model
    }

    @Test func describe_updateShopping_isOneCollectiveCard() async {
        let model = await makeAssistant()
        let call = ToolCall(id: "c1", name: "update_shopping", arguments: Data(
            #"{"add":[{"name":"Kaffee","quantity":null},{"name":"Reis","quantity":null},{"name":"Zwiebeln","quantity":null}],"check_off":["eggs"]}"#.utf8))
        let card = model.describe(call)
        #expect(card.title == "Einkaufsliste ändern" && card.change == "＋ Kaffee · ＋ Reis · ＋ Zwiebeln · ✓ Eier")
        #expect(model.describe(call, language: .english).title == "Change shopping list")
    }

    @Test func describe_updateShopping_showsQuantityAndUnknownID() async {
        let model = await makeAssistant()
        let call = ToolCall(id: "c1", name: "update_shopping", arguments: Data(
            #"{"add":[{"name":"Zwiebeln","quantity":"2"}],"check_off":["gone"]}"#.utf8))
        #expect(model.describe(call).change == "＋ 2 Zwiebeln · ✓ gone")
    }

    /// Spoken cards drop decorative symbols, so the announced card must name adding and checking off in words.
    @Test func describe_updateShopping_announcedCardUsesWords() async {
        let model = await makeAssistant()
        let call = ToolCall(id: "c1", name: "update_shopping", arguments: Data(
            #"{"add":[{"name":"Kaffee","quantity":null},{"name":"Zwiebeln","quantity":"2"}],"check_off":["eggs"]}"#.utf8))
        #expect(model.describe(call, language: .german, spoken: true).change == "Hinzufügen: Kaffee, 2 Zwiebeln · Abhaken: Eier")
        #expect(model.describe(call, language: .english, spoken: true).change == "Add: Kaffee, 2 Zwiebeln · Check off: Eier")
        let spoken = ActionAnnouncement.text(for: [(title: "Einkaufsliste ändern", change: model.describe(call, language: .german, spoken: true).change)],
                                             language: .german, byVoice: true)
        #expect(spoken?.contains("Abhaken: Eier") == true)
        // On screen the same call keeps the compact symbols.
        #expect(model.describe(call, language: .german).change == "＋ Kaffee · ＋ 2 Zwiebeln · ✓ Eier")
    }

    @Test func instructions_mentionShoppingTools() async {
        let text = await makeAssistant().instructions()
        #expect(text.contains("list_shopping") && text.contains("update_shopping") && text.contains("create_task"))
    }
}
