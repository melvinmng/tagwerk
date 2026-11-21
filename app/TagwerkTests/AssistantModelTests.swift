import AIKit
import Foundation
import GitHubKit
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

    @Test func instructions_mentionSearch() async throws {
        let (model, _, _) = await make()
        model.open(context: .settings)
        #expect(model.instructions().contains("search"))
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

    @Test func instructions_inVoiceMode_answerInTheChosenLanguage() async throws {
        let (model, _, _) = await make()
        model.open(context: .settings)
        model.fixedVoiceLanguage = { .english }
        // A typed chat keeps answering in the language the user writes, whatever the voice chat language is.
        #expect(!model.instructions().contains("immer auf"))
        model.onTurnFinished = { _ in }
        #expect(model.instructions().contains("Im Sprechmodus antwortest du immer auf Englisch (English)"))
        model.fixedVoiceLanguage = { .german }
        #expect(model.instructions().contains("Im Sprechmodus antwortest du immer auf Deutsch"))
        // "Wie die App": the base rule stays, the language of the last message.
        model.fixedVoiceLanguage = { nil }
        let automatic = model.instructions()
        #expect(!automatic.contains("immer auf"))
        #expect(automatic.contains("in der Sprache der letzten Nachricht des Nutzers"))
    }

    /// L5: the assistant writes new shopping items in the language of the shopping list setting.
    @Test func instructions_nameTheShoppingLanguage() async throws {
        let (model, _, _) = await make()
        model.open(context: .settings)
        model.shoppingLanguage = { .german }
        #expect(model.instructions().contains("Schreibe neue Einkaufsartikel auf Deutsch."))
        model.shoppingLanguage = { .english }
        let english = model.instructions()
        #expect(english.contains("Schreibe neue Einkaufsartikel auf Englisch."))
        #expect(!english.contains("Schreibe neue Einkaufsartikel auf Deutsch."))
        // The sentence belongs to the shopping list rules.
        let rules = try #require(english.range(of: "Lege Einkaufsartikel nie über create_task an."))
        let sentence = try #require(english.range(of: "Schreibe neue Einkaufsartikel auf Englisch."))
        #expect(rules.upperBound <= sentence.lowerBound)
    }

    @Test func autoRead_ofAShortAnswer_usesTheChosenVoiceLanguage() async throws {
        let (model, _, _) = await make()
        var languages: [VoiceLanguage] = []
        model.readAutomatically = { _, _, language in languages.append(language) }
        model.readPolicy = { .always }
        model.open(context: .settings)
        model.fixedVoiceLanguage = { .english }
        responder.enqueue("Okay.")
        await model.send("Ja", spoken: true)
        model.fixedVoiceLanguage = { nil }
        responder.enqueue("Okay.")
        await model.send("Ja", spoken: true)
        #expect(languages == [.english, VoiceLanguage.app])
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

@MainActor
struct AssistantGitHubCardTests {
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

    private func make(signedIn: Bool = true) async -> AssistantModel {
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
        let tools = AppTools(taskList: taskList, planning: planning, planner: nil, events: { _ in [] },
                             gitHub: { signedIn ? directory : nil })
        let model = AssistantModel(responder: responder, tools: tools, model: { "gpt-test" },
                                   store: ChatStore(context: container.mainContext), planning: planning, now: testNow)
        model.language = { .german }
        model.gitHubDirectory = { signedIn ? directory : nil }
        return model
    }

    /// Arguments of a create_task call for an issue; `repository`, `projects` and `assignees` are raw JSON.
    private func arguments(_ title: String = "Export", repository: String = #""beispiel/app""#, projects: String = #"["PVT_1"]"#,
                           assignees: String = "null", due: String = "null", notes: String = "null") -> String {
        #"{"title":"\#(title)","due":\#(due),"priority":null,"minutes":null,"notes":\#(notes),"source":"github","#
            + #""repository":\#(repository),"project_ids":\#(projects),"assignees":\#(assignees)}"#
    }

    private func call(_ arguments: String, id: String = "c1") -> ToolCall {
        ToolCall(id: id, name: "create_task", arguments: Data(arguments.utf8))
    }

    @Test func describe_gitHubIssue_namesRepositoryProjectAndAssignees() async {
        let model = await make()
        let card = model.describe(call(arguments(assignees: #"["lea-m"]"#, due: #""2026-11-20""#, notes: #""Details""#)))
        #expect(card.title == "Export")
        let lines = card.change.split(separator: "\n").map(String.init)
        #expect(lines.count == 3)
        #expect(lines[0].hasPrefix("Issue anlegen · beispiel/app · Projekt App · fällig "))
        #expect(lines[1] == "Zugewiesen: lea-m (nicht dir)")
        #expect(lines[2] == "Notizen: „Details“")
    }

    @Test func describe_gitHubIssue_assigneeVariants() async {
        let model = await make()
        func line(_ assignees: String) -> String {
            String(model.describe(call(arguments(assignees: assignees))).change.split(separator: "\n").last ?? "")
        }
        #expect(line("null") == "Zugewiesen: dir")
        #expect(line(#"["octo"]"#) == "Zugewiesen: dir")
        #expect(line(#"["octo","lea-m"]"#) == "Zugewiesen: dir und lea-m")
        #expect(line(#"["lea-m","jonas-k","sam","x"]"#) == "Zugewiesen: lea-m, jonas-k, sam und x (nicht dir)")
        #expect(line("[]") == "Niemandem zugewiesen")
    }

    @Test func describe_gitHubIssue_nullTargets_resolveFromStoredCatalog() async {
        let model = await make()
        let card = model.describe(call(arguments(repository: "null", projects: "null")))
        #expect(card.change.hasPrefix("Issue anlegen · beispiel/app · Projekt App"))
    }

    @Test func describe_gitHubIssue_emptyProjectList_saysNoProject_notMissing() async {
        let model = await make()
        let card = model.describe(call(arguments(repository: #""beispiel/app""#, projects: "[]")))
        #expect(card.change.hasPrefix("Issue anlegen · beispiel/app · Kein Projekt"))
        #expect(!card.change.contains("Projekt fehlt"))
        let inferred = model.describe(call(arguments(repository: "null", projects: "[]")))
        #expect(inferred.change.hasPrefix("Issue anlegen · beispiel/app · Kein Projekt"))
    }

    @Test func describe_gitHubIssue_unresolvableTargets_sayMissing() async {
        directory.storedCatalog = GitHubCatalog(repositories: ["beispiel/app", "beispiel/web"], projects: [],
                                                fetchedAt: Date(timeIntervalSince1970: 0))
        let model = await make()
        let card = model.describe(call(arguments(repository: "null", projects: "null")))
        #expect(card.change.hasPrefix("Issue anlegen · Repository fehlt · Projekt fehlt"))
        let named = model.describe(call(arguments(repository: #""beispiel/web""#, projects: "null")))
        #expect(named.change.hasPrefix("Issue anlegen · beispiel/web · Projekt fehlt"))
    }

    @Test func describe_gitHubIssue_inEnglish() async {
        let model = await make()
        let card = model.describe(call(arguments(assignees: #"["lea-m"]"#)), language: .english)
        #expect(card.change == "Create issue · beispiel/app · Project App\nAssigned to: lea-m (not you)")
        let mine = model.describe(call(arguments(assignees: #"["octo","lea-m"]"#)), language: .english)
        #expect(mine.change.hasSuffix("Assigned to: you and lea-m"))
        let nobody = model.describe(call(arguments(assignees: "[]")), language: .english)
        #expect(nobody.change.hasSuffix("Not assigned to anyone"))
    }

    @Test func describe_otherSources_stayAsBefore() async {
        let model = await make()
        let local = ToolCall(id: "c1", name: "create_task", arguments: Data(
            #"{"title":"Neu","due":null,"priority":"P2","minutes":null,"notes":null,"source":"local","repository":null,"project_ids":null,"assignees":null}"#.utf8))
        #expect(model.describe(local).change == "Neue Aufgabe · local · P2")
    }

    @Test func assignsBeyondMe_onlyForIssuesWithOthersOrNoOne() {
        func beyond(_ arguments: String, me: String? = "octo") -> Bool {
            AssistantModel.assignsBeyondMe(call(arguments), me: me)
        }
        #expect(!beyond(arguments()))
        #expect(!beyond(arguments(assignees: #"["Octo"]"#)))
        #expect(beyond(arguments(assignees: #"["octo","lea-m"]"#)))
        #expect(beyond(arguments(assignees: "[]")))
        #expect(beyond(arguments(assignees: #"["octo"]"#), me: nil))
        let complete = ToolCall(id: "c", name: "complete_task", arguments: Data(#"{"id":"local:x"}"#.utf8))
        #expect(!AssistantModel.assignsBeyondMe(complete, me: "octo"))
    }

    private func sendTwoCards(_ model: AssistantModel) async {
        responder.enqueueEvents([.functionCall(callID: "c1", name: "create_task", arguments: arguments("Für Lea", assignees: #"["lea-m"]"#)),
                                 .functionCall(callID: "c2", name: "create_task", arguments: arguments("Für mich")),
                                 .completed(usage: nil)])
        await model.send("Leg zwei Issues an", spoken: true)
    }

    @Test func openCards_countGuardedAssignmentCards() async {
        let model = await make()
        model.open(context: .tasks)
        await sendTwoCards(model)
        #expect(model.openCards == OpenCards(ids: ["c1", "c2"], deletes: 0, guarded: 1))
    }

    @Test func confirmCards_refusesGuardedCardTogetherWithOthers() async {
        let model = await make()
        var turns: [AssistantModel.TurnOutcome] = []
        // The voice mode keeps the open conversation, so the chat opens before the turn handler is set.
        model.open(context: .tasks)
        model.onTurnFinished = { turns.append($0) }
        await sendTwoCards(model)

        await model.confirmCards(["c1", "c2"])
        #expect(turns.last == .rejected)
        #expect(github.createdDrafts.isEmpty)

        responder.enqueue("Angelegt.")
        await model.confirmCards(["c1"])
        #expect(github.createdDrafts.map(\.title) == ["Für Lea"])
        #expect(github.createdDrafts.last?.assignees == ["lea-m"])
        #expect(model.openCards.ids == ["c2"])
    }

    // MARK: Guarded cards (assign_task)

    private func issue(_ number: Int, assignees: [String] = ["octo"]) -> TaskItem {
        TaskItem(id: TaskID(source: .github, rawValue: "ISSUE_\(number)"), title: "Export \(number)", notes: nil, due: nil,
                 priority: nil, estimateMinutes: nil, isCompleted: false,
                 container: TaskContainer(id: "beispiel/app", name: "beispiel/app", colorHex: nil),
                 url: URL(string: "https://github.com/beispiel/app/issues/\(number)"), version: "1",
                 editableFields: [.title, .notes, .due, .priority, .assignees], assignees: assignees)
    }

    private func assignCall(_ id: String = "c1", task: String = "github:ISSUE_212", add: [String] = ["lea-m"]) -> ToolCall {
        let list = add.map { "\"\($0)\"" }.joined(separator: ",")
        return ToolCall(id: id, name: "assign_task", arguments: Data(#"{"id":"\#(task)","add":[\#(list)],"remove":[]}"#.utf8))
    }

    private func renameCall(_ id: String, task: String, title: String) -> ToolCall {
        ToolCall(id: id, name: "update_task", arguments: Data(
            #"{"id":"\#(task)","title":"\#(title)","notes":null,"due":null,"priority":null,"minutes":null}"#.utf8))
    }

    /// Two ordinary cards and one assign_task card are open.
    private func sendGuardedBatch(_ model: AssistantModel) async {
        github.tasks = [issue(212), issue(213), issue(214)]
        await taskList.reload()
        responder.enqueueEvents([
            .functionCall(callID: "c1", name: "update_task", arguments: #"{"id":"github:ISSUE_213","title":"Neu 213","notes":null,"due":null,"priority":null,"minutes":null}"#),
            .functionCall(callID: "c2", name: "update_task", arguments: #"{"id":"github:ISSUE_214","title":"Neu 214","notes":null,"due":null,"priority":null,"minutes":null}"#),
            .functionCall(callID: "c3", name: "assign_task", arguments: #"{"id":"github:ISSUE_212","add":["lea-m"],"remove":[]}"#),
            .completed(usage: nil)])
        await model.send("Mach drei Änderungen")
    }

    @Test func needsSingleConfirmation_coversAssignTask() {
        #expect(AssistantModel.needsSingleConfirmation(assignCall(), me: "octo"))
        #expect(AssistantModel.needsSingleConfirmation(assignCall(), me: nil))
        #expect(!AssistantModel.needsSingleConfirmation(renameCall("c", task: "github:x", title: "y"), me: "octo"))
        // The rule for issues created for others stays.
        #expect(AssistantModel.needsSingleConfirmation(call(arguments(assignees: #"["lea-m"]"#)), me: "octo"))
        #expect(!AssistantModel.needsSingleConfirmation(call(arguments()), me: "octo"))
    }

    @Test func needsSingleConfirmation_usesSingleConfirmationTools() {
        #expect(AssistantModel.singleConfirmationTools.contains("assign_task"))
        for name in AssistantModel.singleConfirmationTools {
            let guarded = ToolCall(id: "c", name: name, arguments: Data("{}".utf8))
            #expect(AssistantModel.needsSingleConfirmation(guarded, me: "octo"), "\(name)")
        }
    }

    @Test func confirmAll_skipsGuardedCards() async {
        let model = await make()
        model.open(context: .tasks)
        await sendGuardedBatch(model)
        #expect(model.batchConfirmable.map(\.id) == ["c1", "c2"])

        responder.enqueue("Zwei geändert.")
        await model.confirmAll()

        #expect(taskList.items.first { $0.id.rawValue == "ISSUE_213" }?.title == "Neu 213")
        #expect(taskList.items.first { $0.id.rawValue == "ISSUE_214" }?.title == "Neu 214")
        #expect(model.conversation?.pendingActions.map(\.id) == ["c3"])
        #expect(github.appliedEdits.allSatisfy { if case .set = $0.edit.assignees { false } else { true } })
    }

    @Test func confirmCards_rejectsGuardedInBatch() async {
        let model = await make()
        var turns: [AssistantModel.TurnOutcome] = []
        model.open(context: .tasks)
        model.onTurnFinished = { turns.append($0) }
        await sendGuardedBatch(model)

        await model.confirmCards(["c1", "c3"])
        #expect(turns.last == .rejected)
        #expect(github.appliedEdits.isEmpty)

        responder.enqueue("Zugewiesen.")
        await model.confirmCards(["c3"])
        #expect(github.appliedEdits.count == 1)
    }

    @Test func openCards_countsAssignTaskAsGuarded() async {
        let model = await make()
        model.open(context: .tasks)
        await sendGuardedBatch(model)
        #expect(model.openCards == OpenCards(ids: ["c1", "c2", "c3"], deletes: 0, guarded: 1))
    }

    @Test func singleConfirmationNotice_onlyWithGuardedCards() {
        #expect(AssistantModel.singleConfirmationNotice(for: [renameCall("c1", task: "github:x", title: "y")], me: "octo") == nil)
        #expect(AssistantModel.singleConfirmationNotice(for: [], me: "octo") == nil)
        #expect(AssistantModel.singleConfirmationNotice(
            for: [renameCall("c1", task: "github:x", title: "y"), assignCall("c2")], me: "octo") == "Zuweisungen bestätigst du einzeln.")
    }

    @Test func instructions_mentionGitHubToolsOnlyWithGitHub() async {
        let signedIn = await make()
        signedIn.open(context: .tasks)
        #expect(signedIn.instructions().contains("list_github_targets"))
        #expect(signedIn.instructions().contains("list_assignees"))
        let signedOut = await make(signedIn: false)
        signedOut.open(context: .tasks)
        #expect(!signedOut.instructions().contains("list_github_targets"))
        #expect(!signedOut.instructions().contains("list_assignees"))
    }

    @Test func instructions_inAnIssueChat_nameItsRepositoryAsTarget() async {
        var issue = makeTask("Login", source: .github)
        issue.assignees = ["octo"]
        github.tasks = [issue]
        let model = await make()
        model.issueReference = { _ in IssueReference(repository: "beispiel/app", number: 42, nodeID: "I_42") }
        model.open(task: issue)
        #expect(model.instructions().contains("Naheliegendes Ziel für neue Issues: beispiel/app."))
    }
}
