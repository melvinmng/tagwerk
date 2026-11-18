import AIKit
import Foundation
import RemindersKit
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct AssistantModelTests {
    let container: ModelContainer
    let settings: AppSettings
    let calendarStore = FakeCalendarStore()
    let local: FakeTaskProvider
    let taskList: TaskListModel
    let responder = FakePlanResponder()
    let calendar = testCalendar()

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        settings = try AppSettings.current(in: container.mainContext)
        settings.planCalendarID = "plan"
        local = FakeTaskProvider(source: .local, tasks: [makeTask("Fahrrad", source: .local, due: DueDate(year: 2026, month: 11, day: 18))])
        taskList = TaskListModel(providers: [local], now: testNow, calendar: calendar)
    }

    private func make(language: VoiceLanguage = .german) async -> (AssistantModel, PlanningModel, ChatStore) {
        await taskList.reload()
        let planStore = PlanStore(context: container.mainContext)
        let blocks = BlockPlanner(store: calendarStore, planStore: planStore, links: EventLinkStore(context: container.mainContext),
                                  settings: settings, calendar: calendar)
        let planning = PlanningModel(taskList: taskList, calendarStore: calendarStore, reminderStore: FakeAccessStore(),
                                     planStore: planStore, efforts: RecurringEffortStore(context: container.mainContext),
                                     blocks: blocks, settings: settings, marks: EventMarkStore(context: container.mainContext),
                                     now: testNow, calendar: calendar)
        await planning.reload()
        let calendarStore = self.calendarStore
        let tools = AppTools(taskList: taskList, planning: planning, planner: nil,
                             events: { calendarStore.events(in: $0, calendarIDs: nil) })
        let store = ChatStore(context: container.mainContext)
        let model = AssistantModel(responder: responder, tools: tools, model: { "gpt-test" }, store: store,
                                   planning: planning, now: testNow)
        model.language = { language }
        return (model, planning, store)
    }

    // MARK: Voice

    @Test func sendSpoken_marksMessageAndPersists() async throws {
        responder.enqueue("Hallo zurück.")
        let (model, _, store) = await make()
        model.open(context: .settings)
        await model.send("Hallo", spoken: true)
        let message = try #require(model.conversation?.messages.first)
        #expect(model.isSpoken(message))
        #expect(store.spokenMarks(for: ChatStore.assistantKey) == [SpokenMark(index: 0, text: "Hallo")])
        let (reopened, _, _) = await make()
        reopened.open(context: .settings)
        #expect(reopened.isSpoken(try #require(reopened.conversation?.messages.first)))
    }

    @Test func autoRead_followsPolicy() async throws {
        let (model, _, _) = await make()
        var read: [String] = []
        model.readAutomatically = { _, text, _ in read.append(text) }
        model.open(context: .settings)
        responder.enqueue("Erste Antwort für dich.")
        await model.send("Hallo")
        #expect(read.isEmpty)
        model.readPolicy = { .afterSpoken }
        responder.enqueue("Zweite Antwort für dich.")
        await model.send("Getippt")
        #expect(read.isEmpty)
        responder.enqueue("Dritte Antwort für dich.")
        await model.send("Gesprochen", spoken: true)
        #expect(read == ["Dritte Antwort für dich."])
        model.readPolicy = { .always }
        model.isPresented = false
        responder.enqueue("Vierte Antwort.")
        await model.send("Zu", spoken: true)
        #expect(read.count == 1)
    }

    @Test func newActionCard_isAnnounced_andConfirmationSaysDone() async throws {
        responder.enqueueEvents([.textDelta("Ich hake das ab."),
                                 .functionCall(callID: "c1", name: "complete_task", arguments: #"{"id":"local:Fahrrad"}"#),
                                 .completed(usage: nil)])
        responder.enqueue("Erledigt, viel Spaß.")
        let (model, _, _) = await make()
        var read: [String] = []
        model.readAutomatically = { _, text, _ in read.append(text) }
        model.readPolicy = { .always }
        model.open(context: .tasks)
        await model.send("Fahrrad ist fertig", spoken: true)
        #expect(read.first?.contains("Ich hake das ab.") == true)
        #expect(read.first?.contains("Bitte bestätige auf dem Bildschirm.") == true)
        let call = try #require(model.conversation?.pendingActions.first)
        await model.confirm(call)
        #expect(read.last?.hasPrefix("Ausgeführt.") == true)
        #expect(read.last?.contains("Erledigt, viel Spaß.") == true)
    }

    // MARK: Voice mode turns (plan voice-chat, stage 2 point 9)

    @Test func voiceTurn_reportsAnswer_andSilencesAutoRead() async throws {
        responder.enqueue("Heute sind drei Termine.")
        let (model, _, _) = await make()
        var read: [String] = []
        var turns: [AssistantModel.TurnOutcome] = []
        model.readAutomatically = { _, text, _ in read.append(text) }
        model.readPolicy = { .always }
        model.open(context: .settings)
        model.onTurnFinished = { turns.append($0) }
        await model.send("Was steht an?", spoken: true)
        #expect(read.isEmpty)
        let turn = try #require(turns.first)
        guard case .answered(let id, let speech, let cards) = turn else { Issue.record("\(turn)"); return }
        #expect(speech == "Heute sind drei Termine.")
        #expect(cards.isEmpty)
        #expect(id == "message-1")
    }

    @Test func voiceTurn_cardIsAnnounced_confirmationContinues() async throws {
        responder.enqueueEvents([.textDelta("Ich hake das ab."),
                                 .functionCall(callID: "c1", name: "complete_task", arguments: #"{"id":"local:Fahrrad"}"#),
                                 .completed(usage: nil)])
        responder.enqueue("Erledigt, viel Spaß.")
        let (model, _, _) = await make()
        var turns: [AssistantModel.TurnOutcome] = []
        model.open(context: .tasks)
        model.onTurnFinished = { turns.append($0) }
        await model.send("Fahrrad ist fertig", spoken: true)
        guard case .answered(_, let speech, let cards) = turns.first else { Issue.record("no turn"); return }
        #expect(speech.contains("Ich hake das ab."))
        #expect(speech.contains("Sag ja oder nein, oder was anders sein soll."))
        #expect(cards == OpenCards(ids: ["c1"], deletes: 0))
        let call = try #require(model.conversation?.pendingActions.first)
        await model.confirm(call)
        guard case .answered(_, let next, let stillOpen) = turns.last else { Issue.record("no turn"); return }
        #expect(next.hasPrefix("Ausgeführt."))
        #expect(next.contains("Erledigt, viel Spaß."))
        #expect(stillOpen.isEmpty)
        #expect(turns.count == 2)
    }

    @Test func voiceTurn_declineReportsFollowUp() async throws {
        responder.enqueueEvents([.functionCall(callID: "c1", name: "complete_task", arguments: #"{"id":"local:Fahrrad"}"#),
                                 .completed(usage: nil)])
        responder.enqueue("Gut, ich lasse es offen.")
        let (model, _, _) = await make()
        var turns: [AssistantModel.TurnOutcome] = []
        model.open(context: .tasks)
        model.onTurnFinished = { turns.append($0) }
        await model.send("Fahrrad ist fertig", spoken: true)
        let call = try #require(model.conversation?.pendingActions.first)
        await model.decline(call)
        guard case .answered(_, let speech, let cards) = turns.last else { Issue.record("no turn"); return }
        #expect(speech == "Gut, ich lasse es offen.")
        #expect(cards.isEmpty)
    }

    @Test func voiceTurn_keepsTheConversationOpen() async throws {
        let (model, _, _) = await make()
        model.open(context: .settings)
        let before = model.conversation
        model.onTurnFinished = { _ in }
        model.open(context: .tasks)
        #expect(model.conversation === before)
        #expect(model.context == .settings)
    }

    @Test func voiceTurn_spokenConfirmation_checksTheCards() async throws {
        responder.enqueueEvents([.functionCall(callID: "c1", name: "complete_task", arguments: #"{"id":"local:Fahrrad"}"#),
                                 .completed(usage: nil)])
        responder.enqueue("Erledigt.")
        let (model, _, _) = await make()
        var turns: [AssistantModel.TurnOutcome] = []
        model.open(context: .tasks)
        model.onTurnFinished = { turns.append($0) }
        await model.send("Fahrrad ist fertig", spoken: true)
        await model.confirmCards(["other"])
        #expect(turns.last == .rejected)
        #expect(model.openCards.ids == ["c1"])
        await model.confirmCards(["c1"])
        #expect(model.openCards.isEmpty)
        guard case .answered(_, let speech, _) = turns.last else { Issue.record("no turn"); return }
        #expect(speech.hasPrefix("Ausgeführt."))
    }

    @Test func voiceTurn_offlineAndRejected() async throws {
        responder.enqueueFailure(.network)
        let (model, _, _) = await make()
        var turns: [AssistantModel.TurnOutcome] = []
        model.open(context: .settings)
        model.onTurnFinished = { turns.append($0) }
        await model.send("Hallo", spoken: true)
        #expect(turns == [.failed(offline: true)])
        await model.send("   ", spoken: true)
        #expect(turns.last == .rejected)
        responder.enqueueFailure(.server(500, nil))
        await model.retry()
        #expect(turns.last == .failed(offline: false))
    }

    @Test func eventCards_showWhenCalendarAndFit() async throws {
        let (model, _, _) = await make()
        let create = model.describe(ToolCall(id: "c1", name: "create_event", arguments: Data(#"{"title":"Zahnarzt","start":"2026-11-19T10:00","end":"2026-11-19T11:00","all_day":false,"calendar_id":null,"location":null,"notes":null}"#.utf8)))
        #expect(create.title == "Zahnarzt")
        #expect(create.change.hasPrefix("Termin anlegen · "))
        #expect(create.change.contains("Kalender Tagwerk"))
        #expect(create.change.contains("passt in die freie Zeit"))
        let allDay = model.describe(ToolCall(id: "c2", name: "create_event", arguments: Data(#"{"title":"Urlaub","start":"2026-11-23","end":"2026-11-27","all_day":true,"calendar_id":null,"location":null,"notes":null}"#.utf8)))
        #expect(allDay.change.contains("ganztägig"))
        #expect(allDay.change.contains(" bis "))
    }

    @Test func instructions_inVoiceMode_askForSpokenReplies() async throws {
        let (model, _, _) = await make()
        model.open(context: .settings)
        #expect(!model.instructions().contains("Sprechmodus"))
        model.onTurnFinished = { _ in }
        let text = model.instructions()
        #expect(text.contains("Sprechmodus"))
        #expect(text.contains("nie auf"))
    }

    @Test func instructions_answerInTheAppLanguage_whenTheUserLanguageIsUnclear() async throws {
        let (german, _, _) = await make(language: .german)
        let (english, _, _) = await make(language: .english)
        let germanText = german.instructions()
        let englishText = english.instructions()
        #expect(germanText.contains("in der Sprache der letzten Nachricht des Nutzers"))
        #expect(englishText.contains("in der Sprache der letzten Nachricht des Nutzers"))
        #expect(germanText.contains("noch keine Nachricht oder ist die Sprache unklar, antworte auf Deutsch"))
        #expect(englishText.contains("noch keine Nachricht oder ist die Sprache unklar, antworte auf Englisch (English)"))
        #expect(!englishText.contains("antworte auf Deutsch"))
    }

    @Test func instructions_mentionEventFunctions() async throws {
        let (model, _, _) = await make()
        let text = model.instructions()
        #expect(text.contains("create_event"))
        #expect(text.contains("eine Stunde"))
    }

    @Test func clear_dropsSpokenMarks() async throws {
        responder.enqueue("Hallo zurück.")
        let (model, _, _) = await make()
        model.open(context: .settings)
        await model.send("Hallo", spoken: true)
        model.clear()
        #expect(model.spokenMarks.isEmpty)
    }

    @Test func open_restoresHistory_withoutCalls() async throws {
        let (_, _, store) = await make()
        store.save([.user("Hallo"), .assistant("Hi")], actionTimes: [:], for: ChatStore.assistantKey, now: testNow())
        let (model, _, _) = await make()
        model.open(context: .settings)
        #expect(model.conversation?.history == [.user("Hallo"), .assistant("Hi")])
        #expect(responder.calls.isEmpty)
    }

    @Test func send_persistsHistory() async throws {
        responder.enqueue("Hallo zurück.")
        let (model, _, store) = await make()
        model.open(context: .settings)
        await model.send("Hallo")
        #expect(store.history(for: ChatStore.assistantKey) == [.user("Hallo"), .assistant("Hallo zurück.")])
    }

    @Test func instructions_containTheViewContext() async throws {
        responder.enqueue("ok")
        let (model, planning, _) = await make()
        model.open(context: .planning(scope: .day, anchor: planning.anchor))
        await model.send("Was steht an?")
        let instructions = try #require(responder.instructions.first)
        #expect(instructions.contains("Ansicht: Planen · Tag"))
        #expect(instructions.contains("2026-11-18"))
        #expect(instructions.contains("frei"))
    }

    @Test func confirm_runsTool_recordsTime_andPersists() async throws {
        responder.enqueueEvents([.functionCall(callID: "c1", name: "complete_task", arguments: #"{"id":"local:Fahrrad"}"#),
                                 .completed(usage: nil)])
        responder.enqueue("Erledigt.")
        let (model, _, store) = await make()
        model.open(context: .tasks)
        await model.send("Fahrrad ist fertig")
        let pending = try #require(model.conversation?.pendingActions.first)
        await model.confirm(pending)
        #expect(!taskList.items.contains { $0.title == "Fahrrad" })
        #expect(model.actionTimes["c1"] == testNow())
        #expect(store.actionTimes(for: ChatStore.assistantKey)["c1"] == testNow())
        #expect(store.history(for: ChatStore.assistantKey).last == .assistant("Erledigt."))
    }

    @Test func confirmAll_runsEveryPendingAction() async throws {
        local.tasks.append(makeTask("Abgabe", source: .local))
        responder.enqueueEvents([.functionCall(callID: "c1", name: "complete_task", arguments: #"{"id":"local:Fahrrad"}"#),
                                 .functionCall(callID: "c2", name: "complete_task", arguments: #"{"id":"local:Abgabe"}"#),
                                 .completed(usage: nil)])
        responder.enqueue("Beide erledigt.")
        let (model, _, _) = await make()
        model.open(context: .tasks)
        await model.send("Beides fertig")
        await model.confirmAll()
        #expect(taskList.items.isEmpty)
        #expect(responder.calls.count == 2)
    }

    @Test func clear_deletesTheStoredChat() async throws {
        responder.enqueue("ok")
        let (model, _, store) = await make()
        model.open(context: .settings)
        await model.send("Hallo")
        model.clear()
        #expect(store.history(for: ChatStore.assistantKey).isEmpty)
        #expect(model.conversation?.history.isEmpty == true)
    }

    @Test func describe_rescheduleShowsBeforeAndAfter() async throws {
        let (model, _, _) = await make()
        let call = ToolCall(id: "c", name: "reschedule_task", arguments: Data(#"{"id":"local:Fahrrad","due":"2026-11-20"}"#.utf8))
        let card = model.describe(call)
        #expect(card.title == "Fahrrad")
        #expect(card.change.contains("→"))
    }
}
