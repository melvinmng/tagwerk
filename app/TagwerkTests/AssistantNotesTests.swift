import AIKit
import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// The notes chat (issue #233): own context and history, tools only with the consent, note text only for the running session.
@MainActor
struct AssistantNotesTests {
    let container: ModelContainer
    let settings: AppSettings
    let calendarStore = FakeCalendarStore()
    let local: FakeTaskProvider
    let taskList: TaskListModel
    let responder = FakePlanResponder()
    let calendar = testCalendar()
    /// Words that occur in note texts only, never in titles.
    static let secret = "Zebrastreifen"

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        settings = try AppSettings.current(in: container.mainContext)
        settings.planCalendarID = "plan"
        settings.noteAssistantConsent = true
        local = FakeTaskProvider(source: .local, tasks: [makeTask("Fahrrad", source: .local, due: DueDate(year: 2026, month: 11, day: 18)),
                                                         makeTask("Auto", source: .local, due: DueDate(year: 2026, month: 11, day: 19))])
        taskList = TaskListModel(providers: [local], now: testNow, calendar: calendar)
    }

    struct Rig {
        let model: AssistantModel
        let store: ChatStore
        let notes: NoteStore
        let tools: AppTools
        let noteTools: NoteChatTools
    }

    /// The same wiring as `AppEnvironment`: note tools, consent, consent watcher.
    func make(notes existing: NoteStore? = nil) async -> Rig {
        let notes = existing ?? NoteStore(context: container.mainContext)
        await taskList.reload()
        let planStore = PlanStore(context: container.mainContext)
        let blocks = BlockPlanner(store: calendarStore, planStore: planStore, links: EventLinkStore(context: container.mainContext),
                                  settings: settings, calendar: calendar)
        let planning = PlanningModel(taskList: taskList, calendarStore: calendarStore, reminderStore: FakeAccessStore(),
                                     planStore: planStore, efforts: RecurringEffortStore(context: container.mainContext),
                                     blocks: blocks, settings: settings, marks: EventMarkStore(context: container.mainContext),
                                     now: testNow, calendar: calendar)
        await planning.reload()
        let access = NoteToolAccess(store: notes)
        let settings = self.settings
        let sources = SearchToolSources(events: { _ in [] }, calendarNames: { [:] }, completedTasks: { [] },
                                        notes: { access.visibleNotes().map { AppEnvironment.searchItem(for: $0, folderNames: [:]) } },
                                        notesAllowed: { settings.noteAssistantConsent })
        let tools = AppTools(taskList: taskList, planning: planning, planner: nil, events: { _ in [] }, search: sources, noteAccess: access)
        let noteTools = NoteChatTools(base: tools, access: access, hasConsent: { settings.noteAssistantConsent })
        let store = ChatStore(context: container.mainContext)
        let model = AssistantModel(responder: responder, tools: tools, model: { "gpt-test" }, store: store, planning: planning, now: testNow)
        model.language = { .german }
        model.noteTools = noteTools
        model.hasNoteConsent = { settings.noteAssistantConsent }
        model.watchNoteConsent { settings.noteAssistantConsent }
        return Rig(model: model, store: store, notes: notes, tools: tools, noteTools: noteTools)
    }

    private func key(_ note: NoteRecord) -> String { NoteToolAccess.key(for: note.id) }

    private func storedText(_ rig: Rig, key: String = ChatStore.notesKey) -> String {
        (try? String(decoding: JSONEncoder().encode(rig.store.history(for: key)), as: UTF8.self)) ?? ""
    }

    private func memory(_ model: AssistantModel) -> String {
        model.conversation?.history.map { "\($0)" }.joined(separator: "\n") ?? ""
    }

    private static func listCall(_ id: String = "l1", folder: String? = nil) -> StreamEvent {
        .functionCall(callID: id, name: "list_notes", arguments: #"{"folder_id":\#(folder.map { "\"\($0)\"" } ?? "null"),"query":null}"#)
    }

    private func readCall(_ note: NoteRecord, id: String = "r1") -> StreamEvent {
        .functionCall(callID: id, name: "read_note", arguments: #"{"note_ids":["\#(key(note))"]}"#)
    }

    private func updateCall(_ note: NoteRecord, text: String, id: String = "u1") -> StreamEvent {
        let escaped = String(decoding: (try? JSONEncoder().encode(text)) ?? Data(), as: UTF8.self)
        return .functionCall(callID: id, name: "update_note", arguments: #"{"note_id":"\#(key(note))","text":\#(escaped)}"#)
    }

    // MARK: Opening

    @Test func openNotes_withoutConsent_doesNothing() async throws {
        settings.noteAssistantConsent = false
        let rig = await make()
        rig.model.open(notes: nil)
        #expect(!rig.model.isPresented && rig.model.conversation == nil)
        rig.model.open(note: UUID())
        #expect(!rig.model.isPresented && rig.model.conversation == nil)
        // Without note tools the entries do nothing either.
        settings.noteAssistantConsent = true
        rig.model.noteTools = nil
        rig.model.open(notes: nil)
        #expect(!rig.model.isPresented)
    }

    @Test func openNotes_usesNotesThreadAndOffersNoteTools() async throws {
        let rig = await make()
        let note = try #require(rig.notes.create(text: "Umzug Ideen"))
        rig.model.open(notes: nil)
        #expect(rig.model.isPresented && rig.model.context == .notes(folderID: nil))
        responder.enqueue("Okay.")
        await rig.model.send("Welche Notizen habe ich?")
        #expect(!rig.store.history(for: ChatStore.notesKey).isEmpty)
        #expect(rig.store.history(for: ChatStore.assistantKey).isEmpty)
        let names = Set(rig.noteTools.definitions.map(\.name))
        #expect(names.isSuperset(of: ["list_notes", "read_note", "create_note", "update_note", "delete_note", "search"]))
        // A chat about one note keeps the history and only narrows the tools.
        rig.model.open(note: note.id)
        #expect(rig.model.context == .note(note.id) && rig.noteTools.scope == note.id)
        #expect(!rig.model.conversation!.history.isEmpty)
        #expect(!rig.noteTools.definitions.contains { $0.name == "list_notes" })
        // From a folder, new notes go to this folder.
        let folder = try rig.notes.createFolder(name: "Reisen")
        rig.model.open(notes: folder.id)
        #expect(rig.noteTools.scope == nil && rig.noteTools.defaultFolderID == folder.id)
        #expect(rig.model.task == nil)
    }

    @Test func openGeneral_offersNoNoteTools() async throws {
        let rig = await make()
        rig.model.open(context: .settings)
        #expect(rig.model.conversation != nil)
        responder.enqueue("Okay.")
        await rig.model.send("Hallo")
        let names = Set(rig.model.tools.definitions.map(\.name))
        #expect(names.contains("read_note") && names.contains("search"))
        #expect(names.isDisjoint(with: ["list_notes", "create_note", "update_note", "delete_note"]))
    }

    // MARK: Stored form and session

    @Test func listNotes_storedHistoryHoldsCountOnly_memoryHoldsTitles() async throws {
        let rig = await make()
        _ = try #require(rig.notes.create(text: "Zuckerbäckerei Planung\n\(Self.secret)"))
        _ = try #require(rig.notes.create(text: "Geschenk Mama"))
        rig.model.open(notes: nil)
        responder.enqueueEvents([Self.listCall(), .completed(usage: nil)])
        responder.enqueue("Du hast zwei Notizen.")
        await rig.model.send("Welche Notizen habe ich?")
        let inMemory = memory(rig.model)
        #expect(inMemory.contains("Zuckerbäckerei Planung") && inMemory.contains("Geschenk Mama") && !inMemory.contains(Self.secret))
        let stored = storedText(rig)
        #expect(!stored.contains("Zuckerbäckerei") && !stored.contains("Geschenk Mama") && stored.contains("listed"))
        // The chat shows the activity line.
        let activities = rig.model.conversation?.messages.filter { if case .activity = $0.content { true } else { false } }
        #expect(activities?.count == 1)
    }

    @Test func updateNote_storedHistoryHoldsNoText() async throws {
        let rig = await make()
        let note = try #require(rig.notes.create(text: "Plan\nAlter Geheimtext"))
        rig.model.open(note: note.id)
        responder.enqueueEvents([readCall(note), .completed(usage: nil)])
        responder.enqueueEvents([updateCall(note, text: "Plan\nNeuer Geheimtext"), .completed(usage: nil)])
        await rig.model.send("Überarbeite die Notiz")
        #expect(rig.model.conversation?.pendingActions.map(\.id) == ["u1"])
        // Open card: the saved chat has neither the old nor the new text, but the title.
        var stored = storedText(rig)
        #expect(!stored.contains("Alter Geheimtext") && !stored.contains("Neuer Geheimtext"))
        responder.enqueue("Erledigt.")
        await rig.model.confirm(try #require(rig.model.conversation?.pendingActions.first))
        #expect(rig.notes.note(id: note.id)?.text == "Plan\nNeuer Geheimtext")
        stored = storedText(rig)
        #expect(!stored.contains("Alter Geheimtext") && !stored.contains("Neuer Geheimtext") && stored.contains("Plan"))
        // In memory the model still sees what it wrote.
        #expect(memory(rig.model).contains("Neuer Geheimtext"))
    }

    @Test func noteText_staysAvailableAcrossTurnsOfTheSession() async throws {
        let rig = await make()
        let note = try #require(rig.notes.create(text: "Plan\nMontag"))
        rig.model.open(note: note.id)
        responder.enqueueEvents([readCall(note), .completed(usage: nil)])
        responder.enqueue("Gelesen.")
        await rig.model.send("Lies die Notiz")
        responder.enqueue("Ja.")
        await rig.model.send("Hast du alles?")
        responder.enqueue("Gleich.")
        await rig.model.send("Dann ändere gleich etwas")
        let sent = responder.calls.last?.input.map { "\($0)" }.joined() ?? ""
        #expect(sent.contains("Montag"))
        responder.enqueueEvents([updateCall(note, text: "Plan\nMontag\nDienstag"), .completed(usage: nil)])
        await rig.model.send("Mach es")
        let card = try #require(rig.model.conversation?.pendingActions.first)
        responder.enqueue("Fertig.")
        await rig.model.confirm(card)
        #expect(rig.notes.note(id: note.id)?.text == "Plan\nMontag\nDienstag")
    }

    @Test func reopenedAfterRestart_updateNeedsNewRead() async throws {
        let rig = await make()
        let note = try #require(rig.notes.create(text: "Plan\nMontag"))
        rig.model.open(note: note.id)
        responder.enqueueEvents([readCall(note), .completed(usage: nil)])
        responder.enqueue("Gelesen.")
        await rig.model.send("Lies die Notiz")
        let again = await make(notes: rig.notes)
        again.model.open(note: note.id)
        #expect(again.tools.noteSession.readTexts.isEmpty)
        #expect(!memory(again.model).contains("Montag"))
        responder.enqueueEvents([updateCall(note, text: "Plan\nMontag\nDienstag", id: "u2"), .completed(usage: nil)])
        await again.model.send("Ändere die Notiz")
        let card = try #require(again.model.conversation?.pendingActions.first)
        responder.enqueue("Das ging nicht.")
        await again.model.confirm(card)
        #expect(rig.notes.note(id: note.id)?.text == "Plan\nMontag")   // rejected: not read in this session
        let output = again.model.conversation?.history.compactMap { item -> String? in
            if case .functionOutput("u2", let output) = item { return output }
            return nil
        }.first
        #expect(output?.contains("read_note") == true)
    }

    @Test func switchingToGeneralChat_resetsSession() async throws {
        let rig = await make()
        let note = try #require(rig.notes.create(text: "Plan\nMontag"))
        rig.model.open(note: note.id)
        responder.enqueueEvents([readCall(note), .completed(usage: nil)])
        responder.enqueue("Gelesen.")
        await rig.model.send("Lies die Notiz")
        #expect(rig.tools.noteSession.readTexts[note.id] != nil)
        rig.model.open(context: .tasks)
        #expect(rig.tools.noteSession.readTexts.isEmpty)
        #expect(rig.model.context == .tasks)
    }

    @Test func readInGeneralChat_thenNotesChat_updateNeedsNewRead() async throws {
        let rig = await make()
        let note = try #require(rig.notes.create(text: "Plan\nMontag"))
        rig.model.open(context: .tasks)
        responder.enqueueEvents([readCall(note), .completed(usage: nil)])
        responder.enqueue("Gelesen.")
        await rig.model.send("Lies die Notiz")
        #expect(rig.tools.noteSession.readTexts[note.id] != nil)
        rig.model.open(note: note.id)
        #expect(rig.tools.noteSession.readTexts.isEmpty)
        responder.enqueueEvents([updateCall(note, text: "Plan\nMontag\nDienstag"), .completed(usage: nil)])
        await rig.model.send("Ändere die Notiz")
        let card = try #require(rig.model.conversation?.pendingActions.first)
        responder.enqueue("Erst lesen.")
        await rig.model.confirm(card)
        #expect(rig.notes.note(id: note.id)?.text == "Plan\nMontag")
    }

    @Test func consentWithdrawn_notesChatOffersNoNoteTools() async throws {
        let rig = await make()
        let note = try #require(rig.notes.create(text: "Plan\nMontag"))
        rig.model.open(note: note.id)
        responder.enqueueEvents([readCall(note), .completed(usage: nil)])
        responder.enqueue("Gelesen.")
        await rig.model.send("Lies die Notiz")
        settings.noteAssistantConsent = false
        responder.enqueue("Okay.")
        await rig.model.send("Und jetzt?")   // syncNoteConsent at the start of the turn ends the session
        #expect(rig.tools.noteSession.readTexts.isEmpty)
        let names = Set(rig.noteTools.definitions.map(\.name))
        #expect(names.isDisjoint(with: ["list_notes", "read_note", "create_note", "update_note", "delete_note"]))
        // The model no longer sees the text it read; the history stays.
        #expect(!memory(rig.model).contains("Montag"))
        #expect(!(rig.model.conversation?.history.isEmpty ?? true))
        // The instructions leave the notes section out and name no note.
        let instructions = rig.model.instructions()
        #expect(!instructions.contains("list_notes") && !instructions.contains("„Plan“") && !instructions.contains(key(note)))
    }

    @Test func consentWithdrawn_openNoteCard_failsCleanly() async throws {
        let rig = await make()
        let note = try #require(rig.notes.create(text: "Plan\nMontag"))
        rig.model.open(note: note.id)
        responder.enqueueEvents([readCall(note), .completed(usage: nil)])
        responder.enqueueEvents([updateCall(note, text: "Plan\nMontag\nDienstag"), .completed(usage: nil)])
        await rig.model.send("Ändere die Notiz")
        #expect(rig.model.conversation?.pendingActions.count == 1)
        settings.noteAssistantConsent = false
        rig.model.endNoteSession()   // what the watcher does
        // The card built from the stored form has no text; confirming still reaches the open call and fails without writing.
        let stored = try #require(rig.model.conversation?.messages.compactMap { message -> ToolCall? in
            if case .action(let call, _) = message.content { return call }
            return nil
        }.first)
        #expect(!String(decoding: stored.arguments, as: UTF8.self).contains("Dienstag"))
        responder.enqueue("Okay.")
        await rig.model.confirm(stored)
        #expect(rig.notes.note(id: note.id)?.text == "Plan\nMontag")
    }

    // MARK: Instructions, context and activity

    @Test func instructions_notesContext_containPrivateSentenceAndNoNoteText() async throws {
        let rig = await make()
        let note = try #require(rig.notes.create(text: "Umzug Ideen\n\(Self.secret)"))
        rig.model.open(notes: nil)
        let all = rig.model.instructions()
        #expect(all.contains("Darauf habe ich keinen Zugriff. Tagebuch mit Gott, Bible Study und Dream Log bleiben auf deinem iPhone und werden nie an ChatGPT gesendet."))
        #expect(all.contains("I don’t have access to that. Tagebuch mit Gott, Bible Study, and Dream Log stay on your iPhone and are never sent to ChatGPT."))
        #expect(all.contains("list_notes") && all.contains("update_note") && all.contains("Ansicht: Notizen (1 sichtbare Notizen"))
        #expect(!all.contains(Self.secret) && !all.contains("Umzug Ideen"))
        rig.model.open(note: note.id)
        let one = rig.model.instructions()
        #expect(one.contains("Das Gespräch betrifft die Notiz „Umzug Ideen“ (id \(key(note))). Lies sie mit read_note."))
        #expect(!one.contains(Self.secret))
        // The general chat has no notes section.
        rig.model.open(context: .tasks)
        #expect(!rig.model.instructions().contains("list_notes") && !rig.model.instructions().contains("Darauf habe ich keinen Zugriff"))
    }

    @Test func instructions_folderContext_namesTheFolder() async throws {
        let rig = await make()
        let folder = try rig.notes.createFolder(name: "Brain Dump 2")
        _ = try #require(rig.notes.create(text: "A", folderID: folder.id))
        _ = try #require(rig.notes.create(text: "B", folderID: folder.id))
        rig.model.open(notes: folder.id)
        #expect(rig.model.instructions().contains("Ansicht: Notizen im Ordner „Brain Dump 2“ (id \(NoteToolAccess.folderKey(for: folder.id)); 2 sichtbare Notizen"))
    }

    @Test func privateNotesSentence_followsRenamedFolders() async throws {
        let sentence = AssistantModel.privateNotesSentence(folderNames: ["Gebet", "Bible Study", "Dream Log"], language: .german)
        #expect(sentence == "Darauf habe ich keinen Zugriff. Gebet, Bible Study und Dream Log bleiben auf deinem iPhone und werden nie an ChatGPT gesendet.")
    }

    @Test func activityText_listNotes_fromFullAndFromStoredOutput() async throws {
        let rig = await make()
        let folder = try rig.notes.createFolder(name: "Brain Dump 2")
        for title in ["A", "B", "C"] { _ = try #require(rig.notes.create(text: title, folderID: folder.id)) }
        _ = try #require(rig.notes.create(text: "Lose"))
        rig.model.open(notes: nil)
        let folderKey = NoteToolAccess.folderKey(for: folder.id)
        responder.enqueueEvents([Self.listCall("l1"), Self.listCall("l2", folder: folderKey), .completed(usage: nil)])
        responder.enqueue("Fertig.")
        await rig.model.send("Zeig mir alles")
        func output(_ id: String, in history: [InputItem]) -> String? {
            history.compactMap { item -> String? in
                if case .functionOutput(let callID, let output) = item, callID == id { return output }
                return nil
            }.first
        }
        let all = ToolCall(id: "l1", name: "list_notes", arguments: Data(#"{"folder_id":null,"query":null}"#.utf8))
        let inFolder = ToolCall(id: "l2", name: "list_notes", arguments: Data(#"{"folder_id":"\#(folderKey)","query":null}"#.utf8))
        let full = try #require(rig.model.conversation?.history)
        let stored = rig.store.history(for: ChatStore.notesKey)
        for history in [full, stored] {
            #expect(rig.model.activityText(all, output: output("l1", in: history)) == "Gelesen: 4 Titel")
            #expect(rig.model.activityText(inFolder, output: output("l2", in: history)) == "Gelesen: 3 Titel aus „Brain Dump 2“")
        }
        #expect(rig.model.activityText(all, output: nil) == nil)
        #expect(rig.model.activityText(all, output: AppTools.error("Ordner nicht gefunden.")) == nil)
    }


    // MARK: Cards and single confirmation (B7)

    private static func completeCall(_ name: String, id: String) -> StreamEvent {
        .functionCall(callID: id, name: "complete_task", arguments: #"{"id":"local:\#(name)"}"#)
    }

    /// A notes chat where the note was read and one turn ended with the given function calls (open cards).
    private func openCards(_ rig: Rig, note: NoteRecord, calls: [StreamEvent]) async {
        rig.model.open(notes: nil)
        responder.enqueueEvents([readCall(note), .completed(usage: nil)])
        responder.enqueueEvents(calls + [.completed(usage: nil)])
        await rig.model.send("Mach das alles")
    }

    @Test func confirmAll_skipsNoteCards() async throws {
        let rig = await make()
        let note = try #require(rig.notes.create(text: "Plan\nMontag"))
        await openCards(rig, note: note, calls: [Self.completeCall("Fahrrad", id: "t1"), Self.completeCall("Auto", id: "t2"),
                                                updateCall(note, text: "Plan\nMontag\nDienstag")])
        #expect(Set(rig.model.conversation?.pendingActions.map(\.id) ?? []) == ["t1", "t2", "u1"])
        #expect(rig.model.batchConfirmable.map(\.id) == ["t1", "t2"])
        responder.enqueue("Okay.")
        await rig.model.confirmAll()
        #expect(rig.model.conversation?.pendingActions.map(\.id) == ["u1"])
        #expect(rig.notes.note(id: note.id)?.text == "Plan\nMontag")
        let notice = AssistantModel.singleConfirmationNotice(for: rig.model.conversation?.pendingActions ?? [])
        #expect(notice == "Notiz-Änderungen bestätigst du einzeln.")
    }

    @Test func batchConfirmable_onlyNoteCards_isEmpty() async throws {
        let rig = await make()
        let note = try #require(rig.notes.create(text: "Plan\nMontag"))
        let other = try #require(rig.notes.create(text: "Idee\nA"))
        await openCards(rig, note: note, calls: [updateCall(note, text: "Plan\nMontag\nDienstag"),
                                                .functionCall(callID: "n1", name: "create_note", arguments: #"{"text":"Neu\nZeile","folder_id":null}"#),
                                                .functionCall(callID: "d1", name: "delete_note", arguments: #"{"note_id":"\#(key(other))","reason":null}"#)])
        #expect(rig.model.conversation?.pendingActions.count == 3)
        #expect(rig.model.batchConfirmable.isEmpty)
        // `confirmAll` does nothing for them.
        await rig.model.confirmAll()
        #expect(rig.model.conversation?.pendingActions.count == 3)
        #expect(rig.notes.note(id: note.id)?.text == "Plan\nMontag" && rig.notes.note(id: other.id)?.deletedAt == nil)
    }

    @Test func confirmUpdate_declinesOtherOpenCardsForTheSameNote() async throws {
        let rig = await make()
        let note = try #require(rig.notes.create(text: "Plan\nMontag"))
        let other = try #require(rig.notes.create(text: "Idee\nA"))
        await openCards(rig, note: note, calls: [updateCall(note, text: "Plan\nMontag\nDienstag", id: "u1"),
                                                updateCall(note, text: "Plan\nMontag\nMittwoch", id: "u2"),
                                                .functionCall(callID: "d1", name: "delete_note", arguments: #"{"note_id":"\#(key(note))","reason":null}"#),
                                                .functionCall(callID: "u3", name: "update_note", arguments: #"{"note_id":"\#(key(other))","text":"Idee\nA\nB"}"#)])
        // The note of u3 was not read: its card stays open (and fails when confirmed); the three cards of `note` rest on one text.
        let first = try #require(rig.model.conversation?.pendingActions.first { $0.id == "u1" })
        await rig.model.confirm(first)
        #expect(rig.notes.note(id: note.id)?.text == "Plan\nMontag\nDienstag")
        #expect(rig.notes.note(id: note.id)?.deletedAt == nil)
        // u2 and d1 are declined without running; u3 belongs to another note and stays.
        #expect(rig.model.conversation?.pendingActions.map(\.id) == ["u3"])
        let outputs = rig.model.conversation?.history.compactMap { item -> (String, String)? in
            if case .functionOutput(let id, let output) = item { return (id, output) }
            return nil
        } ?? []
        #expect(outputs.contains { $0.0 == "u2" && $0.1 == Conversation.declinedOutput })
        #expect(outputs.contains { $0.0 == "d1" && $0.1 == Conversation.declinedOutput })
    }

    @Test func confirmDelete_movesToTrashAndDeclinesTheOtherCard() async throws {
        let rig = await make()
        let note = try #require(rig.notes.create(text: "Doppelt\nText"))
        await openCards(rig, note: note, calls: [.functionCall(callID: "d1", name: "delete_note", arguments: #"{"note_id":"\#(key(note))","reason":"Doppelt"}"#),
                                                updateCall(note, text: "Doppelt\nText\nMehr", id: "u1")])
        responder.enqueue("Erledigt.")
        await rig.model.confirm(try #require(rig.model.conversation?.pendingActions.first { $0.id == "d1" }))
        #expect(rig.notes.note(id: note.id)?.deletedAt != nil)
        #expect(rig.model.conversation?.pendingActions.isEmpty == true)
        #expect(rig.notes.note(id: note.id)?.text == "Doppelt\nText")
    }

    @Test func cardDescription_forAnOpenNoteCard_carriesTheProposal() async throws {
        let rig = await make()
        let note = try #require(rig.notes.create(text: "Plan\nMontag"))
        await openCards(rig, note: note, calls: [updateCall(note, text: "Plan\nMontag\nDienstag")])
        let call = try #require(rig.model.conversation?.pendingActions.first)
        let open = rig.model.describe(call)
        #expect(open.title == "Notiz „Plan“ überarbeiten" && open.detail == .update(title: "Plan", before: "Plan\nMontag", after: "Plan\nMontag\nDienstag"))
        #expect(rig.model.describe(call, isOpen: false).detail == nil)
    }

    // MARK: Voice mode (B8)

    @Test func openCards_countsNoteCards() async throws {
        let rig = await make()
        let note = try #require(rig.notes.create(text: "Plan\nMontag"))
        let other = try #require(rig.notes.create(text: "Idee\nA"))
        await openCards(rig, note: note, calls: [Self.completeCall("Fahrrad", id: "t1"), updateCall(note, text: "Plan\nMontag\nDienstag"),
                                                .functionCall(callID: "n1", name: "create_note", arguments: #"{"text":"Neu\nZeile","folder_id":null}"#),
                                                .functionCall(callID: "d1", name: "delete_note", arguments: #"{"note_id":"\#(key(other))","reason":null}"#)])
        let cards = rig.model.openCards
        #expect(cards.count == 4)
        #expect(cards.notes == 2)        // update_note and create_note
        #expect(cards.deletes == 1)      // delete_note counts as a deletion
        #expect(cards.guarded == 0)      // note cards are not "guarded": the voice mode has its own sentence
    }

    @Test func confirmCards_twoIDsWithNoteCard_isRejected() async throws {
        let rig = await make()
        let note = try #require(rig.notes.create(text: "Plan\nMontag"))
        await openCards(rig, note: note, calls: [Self.completeCall("Fahrrad", id: "t1"), updateCall(note, text: "Plan\nMontag\nDienstag")])
        var outcomes: [AssistantModel.TurnOutcome] = []
        rig.model.onTurnFinished = { outcomes.append($0) }
        await rig.model.confirmCards(["t1", "u1"])
        #expect(outcomes == [.rejected])
        #expect(rig.notes.note(id: note.id)?.text == "Plan\nMontag")
        #expect(rig.model.conversation?.pendingActions.count == 2)
        // A single note card is confirmed.
        responder.enqueue("Okay.")
        await rig.model.confirmCards(["u1"])
        #expect(rig.notes.note(id: note.id)?.text == "Plan\nMontag\nDienstag")
    }
}
