import AIKit
import Foundation
import GitHubKit
import RemindersKit
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// The follow-up about one action card (plan ki-vorschlaege-anpassen, task B4, AN4a).
@MainActor
struct CardReviserTests {
    let container: ModelContainer
    let settings: AppSettings
    let calendarStore = FakeCalendarStore()
    let github = FakeTaskProvider(source: .github)
    let directory = FakeGitHubDirectory.single()
    let taskList: TaskListModel
    let responder = FakePlanResponder()
    let calendar = testCalendar()

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        settings = try AppSettings.current(in: container.mainContext)
        github.viewerLogin = "octo"
        taskList = TaskListModel(providers: [github], now: testNow, calendar: calendar)
    }

    private func make() async -> (AssistantModel, ChatStore) {
        await taskList.reload()
        let planStore = PlanStore(context: container.mainContext)
        let blocks = BlockPlanner(store: calendarStore, planStore: planStore, links: EventLinkStore(context: container.mainContext),
                                  settings: settings, calendar: calendar)
        let planning = PlanningModel(taskList: taskList, calendarStore: calendarStore, reminderStore: FakeAccessStore(),
                                     planStore: planStore, efforts: RecurringEffortStore(context: container.mainContext),
                                     blocks: blocks, settings: settings, marks: EventMarkStore(context: container.mainContext),
                                     now: testNow, calendar: calendar)
        await planning.reload()
        let directory = self.directory
        let tools = AppTools(taskList: taskList, planning: planning, planner: nil, events: { _ in [] }, gitHub: { directory })
        let store = ChatStore(context: container.mainContext)
        let model = AssistantModel(responder: responder, tools: tools, model: { "gpt-test" }, store: store, planning: planning, now: testNow)
        model.language = { .german }
        model.gitHubDirectory = { directory }
        model.adjustableTools = AssistantModel.adjustableToolNames
        return (model, store)
    }

    private let task = #"{"title":"Zahnarzt anrufen","due":"2026-11-27","priority":null,"minutes":null,"notes":null,"source":"local","repository":null,"project_ids":null,"assignees":null}"#

    private func proposeCards(_ model: AssistantModel, _ cards: [(id: String, name: String, arguments: String)]) async {
        responder.enqueueEvents(cards.map { .functionCall(callID: $0.id, name: $0.name, arguments: $0.arguments) } + [.completed(usage: nil)])
        await model.send("Leg das an")
    }

    /// An answer in the format of the request; `arguments` is the JSON of the object.
    private func answer(_ arguments: String, message: String = "Frist auf Dienstag gesetzt.", changed: Bool = true) -> String {
        #"{"arguments":\#(arguments),"message":"\#(message)","changed":\#(changed)}"#
    }

    private func requestText(_ index: Int = 0) throws -> String {
        let call = try #require(responder.calls.indices.contains(index) ? responder.calls[index] : nil)
        return call.input.compactMap { item -> String? in if case .user(let text) = item { text } else { nil } }.joined(separator: "\n")
    }

    // MARK: Request

    @Test func request_containsToolSchemaCurrentArgumentsMarksAndComment() async throws {
        let (model, _) = await make()
        model.open(context: .tasks)
        await proposeCards(model, [("c1", "create_task", task)])
        let call = try #require(model.conversation?.pendingActions.first)
        // The sheet changed the title by hand; the due date is as the model proposed it.
        let edited = task.replacingOccurrences(of: "Zahnarzt anrufen", with: "Zahnarzt Dr. Weber anrufen")
        let before = responder.calls.count
        responder.enqueue(answer(task, message: "Nichts zu ändern.", changed: false))

        _ = try await model.reviseCard(call, current: Data(edited.utf8), comment: "Lieber Dienstag")

        #expect(responder.calls.count == before + 1)
        let text = try requestText(before)
        #expect(text.contains("Function: create_task"))
        #expect(text.contains("Zahnarzt Dr. Weber anrufen"))
        #expect(text.contains("Fields set by the user by hand: title"))
        #expect(text.contains("Message from the user: Lieber Dienstag"))
        // The format is the schema of the function plus the sentence and the flag, strict.
        let schema = try #require(ProposalArguments.decode(responder.schemas[before]))
        #expect(responder.calls[before].schema == "card_revision")
        #expect((schema["required"] as? [String]) == ["arguments", "changed", "message"])
        let arguments = try #require((schema["properties"] as? [String: Any])?["arguments"] as? [String: Any])
        #expect(Set((arguments["properties"] as? [String: Any])?.keys.map { $0 } ?? []) ==
                ["title", "due", "priority", "minutes", "notes", "source", "repository", "project_ids", "assignees"])
        #expect(arguments["additionalProperties"] as? Bool == false)
        #expect(responder.instructions[before].contains("Never invent identifiers"))
    }

    @Test func request_containsNoChatHistoryAndNoNoteText() async throws {
        let (model, _) = await make()
        model.open(context: .tasks)
        responder.enqueueEvents([.textDelta("Antwort mit GEHEIMEM-NOTIZTEXT"),
                                 .functionCall(callID: "c1", name: "create_task", arguments: task), .completed(usage: nil)])
        await model.send("Frühere Nachricht VERLAUF-123")
        let call = try #require(model.conversation?.pendingActions.first)
        let before = responder.calls.count
        responder.enqueue(answer(task, changed: false))

        _ = try await model.reviseCard(call, current: Data(task.utf8), comment: "Später")

        #expect(responder.calls[before].input.count == 1)
        let text = try requestText(before)
        #expect(!text.contains("VERLAUF-123"))
        #expect(!text.contains("GEHEIMEM-NOTIZTEXT"))
    }

    @Test func conversationHistory_andOtherCards_unchangedByFollowUp() async throws {
        let (model, store) = await make()
        model.open(context: .tasks)
        await proposeCards(model, [("c1", "create_task", task), ("c2", "create_task", task.replacingOccurrences(of: "Zahnarzt anrufen", with: "Zweite"))])
        let first = try #require(model.conversation?.pendingActions.first { $0.id == "c1" })
        let second = try #require(model.conversation?.pendingActions.first { $0.id == "c2" })
        let historyBefore = model.conversation?.history
        let storedBefore = store.history(for: ChatStore.assistantKey)
        responder.enqueue(answer(task.replacingOccurrences(of: "2026-11-27", with: "2026-11-24")))

        let result = try await model.reviseCard(first, current: Data(task.utf8), comment: "Lieber Dienstag")

        #expect(result.changed)
        #expect(model.conversation?.history == historyBefore)
        #expect(store.history(for: ChatStore.assistantKey) == storedBefore)
        #expect(model.conversation?.pendingActions.map(\.id) == ["c1", "c2"])
        // The card itself changes only with "Fertig"; the other card never changes.
        #expect(model.conversation?.isAdjusted(first) == false)
        #expect(model.describe(second).mark == nil)
        #expect(model.conversation?.pendingActions.last == second)
    }

    // MARK: Answer

    @Test func answer_fillsFieldsAndSetsAssistantMark() async throws {
        let (model, _) = await make()
        model.open(context: .tasks)
        await proposeCards(model, [("c1", "create_task", task)])
        let call = try #require(model.conversation?.pendingActions.first)
        responder.enqueue(answer(task.replacingOccurrences(of: "2026-11-27", with: "2026-11-24")))

        let result = try await model.reviseCard(call, current: Data(task.utf8), comment: "Lieber Dienstag")

        #expect(result.message == "Frist auf Dienstag gesetzt.")
        let editor = try #require(model.proposalEditor(for: call, arguments: result.arguments) as? TaskProposalEditor)
        #expect(editor.due?.day == PlanDay(year: 2026, month: 11, day: 24))
        // "Fertig" with the answer carries the mark of ChatGPT; a change by hand afterwards makes it the user's.
        let adjusted = try #require(model.adjust(call, arguments: result.arguments, mark: .byAssistant))
        #expect(model.describe(adjusted).mark == .byAssistant)
        let again = try #require(model.adjust(adjusted, arguments: Data(task.replacingOccurrences(of: "2026-11-27", with: "2026-11-25").utf8)))
        #expect(model.describe(again).mark == .byUser)
        // Back to the proposal of the model: no mark.
        let reset = try #require(model.resetAdjustment(again))
        #expect(model.describe(reset).mark == nil)
    }

    @Test func answer_invalidForSchema_isRejectedWithMessage() async throws {
        let (model, _) = await make()
        model.open(context: .tasks)
        await proposeCards(model, [("c1", "create_task", task)])
        let call = try #require(model.conversation?.pendingActions.first)

        for broken in [#"{"arguments":{"title":"Nur ein Feld"},"message":"x","changed":true}"#,
                       #"{"arguments":{"title":"A","extra":1},"message":"x","changed":true}"#,
                       #"{"message":"x","changed":true}"#, "kein JSON"] {
            responder.enqueue(broken)
            await #expect(throws: CardReviser.Failure.invalidAnswer) {
                _ = try await model.reviseCard(call, current: Data(task.utf8), comment: "Später")
            }
        }
        #expect(CardReviser.Failure.invalidAnswer.message.contains("nichts geändert"))
    }

    @Test func answer_cannotChange_keepsValuesAndShowsSentence() async throws {
        let (model, _) = await make()
        model.open(context: .tasks)
        await proposeCards(model, [("c1", "create_task", task)])
        let call = try #require(model.conversation?.pendingActions.first)
        // The answer claims no change but sneaks in another title: the values stay as they were.
        responder.enqueue(answer(task.replacingOccurrences(of: "Zahnarzt anrufen", with: "Etwas anderes"),
                                 message: "Eine Telefonnummer kenne ich nicht.", changed: false))

        let result = try await model.reviseCard(call, current: Data(task.utf8), comment: "Schreib die Telefonnummer in die Notiz")

        #expect(!result.changed)
        #expect(result.message == "Eine Telefonnummer kenne ich nicht.")
        #expect(NSDictionary(dictionary: try #require(ProposalArguments.decode(result.arguments)))
            .isEqual(to: try #require(ProposalArguments.decode(Data(task.utf8)))))
    }

    @Test func answer_cannotInventIdentifiers() async throws {
        let (model, _) = await make()
        model.open(context: .tasks)
        let issue = #"{"title":"Export","due":null,"priority":null,"minutes":null,"notes":null,"source":"github","repository":"beispiel/app","project_ids":["PVT_1"],"assignees":["octo"]}"#
        await proposeCards(model, [("c1", "create_task", issue)])
        let call = try #require(model.conversation?.pendingActions.first)
        let invented = #"{"title":"Export 2","due":null,"priority":null,"minutes":null,"notes":null,"source":"github","repository":"erfunden/repo","project_ids":["PVT_X"],"assignees":["ghost"]}"#
        responder.enqueue(answer(invented))

        let result = try await model.reviseCard(call, current: Data(issue.utf8), comment: "Anderer Titel")

        let arguments = try #require(ProposalArguments.decode(result.arguments))
        #expect(arguments["title"] as? String == "Export 2")
        #expect(arguments["repository"] as? String == "beispiel/app")
        #expect(arguments["project_ids"] as? [String] == ["PVT_1"])
        #expect(arguments["assignees"] as? [String] == ["octo"])
    }

    @Test func answer_shoppingKeepsCheckOffIdsButMayChangeAdditions() async throws {
        let (model, _) = await make()
        model.open(context: .tasks)
        let shopping = #"{"add":[{"name":"Milch","quantity":"2"}],"check_off":["item-1"]}"#
        await proposeCards(model, [("c1", "update_shopping", shopping)])
        let call = try #require(model.conversation?.pendingActions.first)
        responder.enqueue(answer(#"{"add":[{"name":"Milch","quantity":null}],"check_off":["item-9"]}"#, message: "Menge entfernt."))

        let result = try await model.reviseCard(call, current: Data(shopping.utf8), comment: "Ohne Mengen")

        let arguments = try #require(ProposalArguments.decode(result.arguments))
        #expect((arguments["add"] as? [[String: Any]])?.first?["quantity"] is NSNull)
        #expect(arguments["check_off"] as? [String] == ["item-1"])
    }

    // MARK: Failures, consent

    @Test func failures_mapToMessages() async throws {
        let (model, _) = await make()
        model.open(context: .tasks)
        await proposeCards(model, [("c1", "create_task", task)])
        let call = try #require(model.conversation?.pendingActions.first)
        for (error, failure) in [(ChatGPTError.network, CardReviser.Failure.network), (.notSignedIn, .signedOut), (.usageLimit, .usageLimit)] {
            responder.enqueueFailure(error)
            await #expect(throws: failure) { _ = try await model.reviseCard(call, current: Data(task.utf8), comment: "Später") }
        }
    }

    @Test func noteDerivedCard_followUpNeedsNoteConsent() async throws {
        let (model, _) = await make()
        var consent = false
        model.hasNoteConsent = { consent }
        model.open(context: .tasks)
        #expect(model.cardFollowUpHasConsent)
        model.open(context: .notes(folderID: nil))
        #expect(!model.cardFollowUpHasConsent)
        consent = true
        #expect(model.cardFollowUpHasConsent)
    }

    @Test func signedOut_hidesFollowUp() {
        #expect(FollowUpAvailability.state(hasConsent: true, isSignedIn: false, isOffline: false) == .hidden)
        #expect(FollowUpAvailability.state(hasConsent: false, isSignedIn: true, isOffline: false) == .hidden)
    }

    @Test func revise_withoutConsent_sendsNothing() async throws {
        let reviser = CardReviser(responder: responder, model: { "gpt-test" }, hasConsent: { false })
        await #expect(throws: CardReviser.Failure.consentMissing) {
            _ = try await reviser.revise(name: "create_task", current: Data(task.utf8), proposed: nil, comment: "Später")
        }
        #expect(responder.calls.isEmpty)
    }

    @Test func quickReplies_existForEveryEditableFunction() {
        for name in AssistantModel.adjustableToolNames {
            #expect(!CardReviser.quickReplies(for: name).isEmpty, "\(name)")
        }
    }

    @Test func everyAdjustableFunction_hasASchemaForTheRevision() {
        let definitions = Dictionary(uniqueKeysWithValues: (AppTools.allDefinitions + AppTools.gitHubDefinitions + GoalChatTools.allDefinitions).map { ($0.name, $0) })
        for name in AssistantModel.adjustableToolNames {
            let definition = definitions[name]
            #expect(definition != nil, "\(name)")
            #expect(definition.flatMap(CardReviser.propertyNames(of:)) != nil, "\(name)")
        }
    }

    @Test func sameArguments_ignoresKeyOrder() {
        #expect(ProposalAdjustSheet.sameArguments(Data(#"{"a":1,"b":2}"#.utf8), Data(#"{"b":2,"a":1}"#.utf8)))
        #expect(!ProposalAdjustSheet.sameArguments(Data(#"{"a":1}"#.utf8), Data(#"{"a":2}"#.utf8)))
    }
}
