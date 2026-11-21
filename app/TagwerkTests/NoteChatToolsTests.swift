import AIKit
import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// The tool set of the notes chat (issue #233): `list_notes` and, in `NoteChatToolsWriteTests`, the changing tools.
/// Private and trashed notes never show up in any answer.
@MainActor
struct NoteChatToolsTests {
    let container: ModelContainer
    let store: NoteStore
    let settings: AppSettings
    let local: FakeTaskProvider
    let taskList: TaskListModel
    let calendarStore = FakeCalendarStore()
    let calendar = testCalendar()

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        settings = try AppSettings.current(in: container.mainContext)
        store = NoteStore(context: container.mainContext)
        local = FakeTaskProvider(source: .local, tasks: [makeTask("Fahrrad", source: .local, due: DueDate(year: 2026, month: 11, day: 18))])
        taskList = TaskListModel(providers: [local], now: testNow, calendar: calendar)
    }

    func makeTools(consent: Bool = true, scope: UUID? = nil, noteStore: NoteStore? = nil) async -> NoteChatTools {
        await taskList.reload()
        let planStore = PlanStore(context: container.mainContext)
        let blocks = BlockPlanner(store: calendarStore, planStore: planStore, links: EventLinkStore(context: container.mainContext),
                                  settings: settings, calendar: calendar)
        let planning = PlanningModel(taskList: taskList, calendarStore: calendarStore, reminderStore: FakeAccessStore(),
                                     planStore: planStore, efforts: RecurringEffortStore(context: container.mainContext),
                                     blocks: blocks, settings: settings, marks: EventMarkStore(context: container.mainContext),
                                     now: testNow, calendar: calendar)
        await planning.reload()
        let access = NoteToolAccess(store: noteStore ?? store)
        let sources = SearchToolSources(events: { _ in [] }, calendarNames: { [:] }, completedTasks: { [] }, notesAllowed: { consent })
        let base = AppTools(taskList: taskList, planning: planning, planner: nil, events: { _ in [] }, search: sources, noteAccess: access)
        let tools = NoteChatTools(base: base, access: access, hasConsent: { consent })
        tools.scope = scope
        return tools
    }

    func run(_ tools: NoteChatTools, _ name: String, _ arguments: String) async -> (raw: String, json: [String: Any]) {
        let raw = await tools.run(ToolCall(id: "c", name: name, arguments: Data(arguments.utf8)))
        return (raw, (try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any]) ?? [:])
    }

    func listNotes(_ tools: NoteChatTools, folder: String? = nil, query: String? = nil) async -> (raw: String, json: [String: Any]) {
        let folderJSON = folder.map { "\"\($0)\"" } ?? "null"
        let queryJSON = query.map { "\"\($0)\"" } ?? "null"
        return await run(tools, "list_notes", #"{"folder_id":\#(folderJSON),"query":\#(queryJSON)}"#)
    }

    func titles(_ json: [String: Any]) -> [String] {
        (json["notes"] as? [[String: Any]] ?? []).compactMap { $0["title"] as? String }
    }

    /// A subfolder below the journal folder: a guard against damaged data, the app cannot create one.
    func makeSubfolderOfJournal() -> NoteFolderRecord {
        let journalFolder = store.ensureJournalFolder()
        let sub = NoteFolderRecord(name: "Unterordner", parentID: journalFolder.id, order: 0)
        container.mainContext.insert(sub)
        store.save()
        return sub
    }

    // MARK: list_notes

    @Test func listNotes_excludesPrivateTrashedAndSubfolderOfPrivate() async throws {
        _ = try #require(store.create(text: "Einkaufsplan Wochenende"))
        _ = try #require(store.create(text: "Dankbar für Ruhe", kind: .journal, dayKey: "2026-11-18"))
        _ = try #require(store.create(text: "Römer acht", kind: .bibleStudy))
        _ = try #require(store.create(text: "Ich flog über ein Feld", kind: .dream, dayKey: "2026-11-18"))
        let journalFolder = store.ensureJournalFolder()
        _ = try #require(store.create(text: "Freie Notiz im Tagebuch-Ordner", folderID: journalFolder.id))
        _ = try #require(store.create(text: "Notiz im Unterordner", folderID: makeSubfolderOfJournal().id))
        let trashed = try #require(store.create(text: "Gelöschte Notiz"))
        store.trash(trashed.id)
        let tools = await makeTools()
        let (raw, json) = await listNotes(tools)
        #expect(titles(json) == ["Einkaufsplan Wochenende"])
        #expect(json["total"] as? Int == 1)
        for hidden in ["Dankbar", "Römer", "Feld", "Tagebuch-Ordner", "Unterordner", "Gelöschte"] { #expect(!raw.contains(hidden), "\(hidden)") }
        // The private folders are not listed either, the others are.
        let folderNames = (json["folders"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        #expect(!folderNames.contains("Tagebuch mit Gott") && !folderNames.contains("Bible Study") && !folderNames.contains("Dream Log"))
        #expect(!folderNames.contains("Unterordner"))
    }

    @Test func listNotes_neverContainsText() async throws {
        _ = try #require(store.create(text: "Umzug Ideen\nGeheimwort Zebrastreifen steht im Text"))
        let tools = await makeTools()
        let (raw, json) = await listNotes(tools)
        #expect(!raw.contains("Zebrastreifen"))
        let entry = try #require((json["notes"] as? [[String: Any]])?.first)
        #expect(Set(entry.keys).isSubset(of: ["id", "title", "folder", "updated", "matched_in"]))
        #expect(entry["id"] as? String == NoteToolAccess.key(for: try #require(store.notes(.all).first).id))
        #expect(entry["folder"] as? String == "Notizen")
    }

    @Test func listNotes_queryMatchesTextButReturnsOnlyTitle() async throws {
        _ = try #require(store.create(text: "Umzug Ideen\nKartons im Keller besorgen"))
        _ = try #require(store.create(text: "Keller aufräumen\nRegale"))
        _ = try #require(store.create(text: "Geschenk Mama\nBlumen"))
        let tools = await makeTools()
        let (raw, json) = await listNotes(tools, query: "keller")
        #expect(Set(titles(json)) == ["Umzug Ideen", "Keller aufräumen"])
        let byTitle = Dictionary(uniqueKeysWithValues: (json["notes"] as? [[String: Any]] ?? []).map { ($0["title"] as! String, $0["matched_in"] as? String) })
        #expect(byTitle["Umzug Ideen"] == "text" && byTitle["Keller aufräumen"] == "title")
        #expect(!raw.contains("Kartons"))
        #expect(json["total"] as? Int == 2)
        // Every word has to occur.
        let both = await listNotes(tools, query: "umzug keller")
        #expect(titles(both.json) == ["Umzug Ideen"])
    }

    @Test func listNotes_tooShortQuery_isRejected() async throws {
        _ = try #require(store.create(text: "Ab"))
        let tools = await makeTools()
        #expect((await listNotes(tools, query: "a")).json["error"] != nil)
    }

    @Test func listNotes_folderFilter() async throws {
        store.ensureDefaultFolders()
        let brainDump = try #require(store.folder(role: .brainDump))
        let own = try store.createFolder(name: "Reisen")
        let sub = try store.createFolder(name: "Italien", parentID: own.id)
        _ = try #require(store.create(text: "Umzug Ideen", folderID: brainDump.id))
        _ = try #require(store.create(text: "Geschenk Mama", folderID: brainDump.id))
        _ = try #require(store.create(text: "Packliste", folderID: own.id))
        _ = try #require(store.create(text: "Rom Hotels", folderID: sub.id))
        _ = try #require(store.create(text: "Lose Notiz"))
        let tools = await makeTools()
        let inBrainDump = await listNotes(tools, folder: NoteToolAccess.folderKey(for: brainDump.id))
        #expect(Set(titles(inBrainDump.json)) == ["Umzug Ideen", "Geschenk Mama"])
        #expect(inBrainDump.json["total"] as? Int == 2)
        // A folder includes the folders below it.
        let inOwn = await listNotes(tools, folder: NoteToolAccess.folderKey(for: own.id))
        #expect(Set(titles(inOwn.json)) == ["Packliste", "Rom Hotels"])
        let all = await listNotes(tools)
        #expect(all.json["total"] as? Int == 5)
        let folders = (all.json["folders"] as? [[String: Any]] ?? [])
        #expect(folders.contains { $0["id"] as? String == NoteToolAccess.folderKey(for: brainDump.id) && $0["name"] as? String == "Brain Dump" })
    }

    @Test func listNotes_privateFolderID_answersNotFound() async throws {
        let journalFolder = store.ensureJournalFolder()
        _ = try #require(store.create(text: "Freie Notiz im Tagebuch-Ordner", folderID: journalFolder.id))
        let sub = makeSubfolderOfJournal()
        let tools = await makeTools()
        let unknown = await listNotes(tools, folder: NoteToolAccess.folderKey(for: UUID()))
        #expect(unknown.json["error"] as? String == "Ordner nicht gefunden.")
        for id in [journalFolder.id, sub.id] {
            let answer = await listNotes(tools, folder: NoteToolAccess.folderKey(for: id))
            #expect(answer.raw == unknown.raw)
        }
        #expect((await listNotes(tools, folder: "kein-schluessel")).raw == unknown.raw)
    }

    @Test func listNotes_newestFirst_pinnedDoNotComeFirst() async throws {
        let old = try #require(store.create(text: "Alt"))
        old.updatedAt = testNow().addingTimeInterval(-86_400 * 10)
        let recent = try #require(store.create(text: "Neu"))
        recent.updatedAt = testNow()
        store.setPinned(old.id, true)
        let tools = await makeTools()
        #expect(titles(await listNotes(tools).json) == ["Neu", "Alt"])
        let updated = try #require(((await listNotes(tools).json)["notes"] as? [[String: Any]])?.first?["updated"] as? String)
        #expect(updated == AIPlanner.dayString(PlanDay(date: testNow(), calendar: calendar)))
    }

    @Test func listNotes_longList_staysInsideTheOutputBudget() async throws {
        for index in 1...250 { _ = store.create(text: "Notiz Nummer \(index) mit einem etwas längeren Titel für die Messung") }
        let tools = await makeTools()
        let (raw, json) = await listNotes(tools)
        #expect(raw.utf8.count <= NoteChatTools.maxListOutputLength)
        #expect(json["total"] as? Int == 250)
        let shown = titles(json).count
        #expect(shown > 50 && shown <= NoteChatTools.maxListedNotes)
        #expect(json["truncated"] as? Bool == true)
        // The answer is valid JSON (it parsed above) and below the 16 KB limit the conversation clips at.
        #expect(raw.utf8.count < 16_000)
    }

    @Test func scope_hidesListNotes() async throws {
        let note = try #require(store.create(text: "Eine Notiz"))
        let general = await makeTools()
        #expect(general.definitions.contains { $0.name == "list_notes" })
        let scoped = await makeTools(scope: note.id)
        #expect(!scoped.definitions.contains { $0.name == "list_notes" })
        // The tool does not run either when the model calls it anyway.
        #expect((await listNotes(scoped)).json["error"] != nil)
    }

    @Test func withoutConsent_offersNoNoteToolsAndRunsNone() async throws {
        let note = try #require(store.create(text: "Vertraulich genug"))
        let tools = await makeTools(consent: false)
        let names = Set(tools.definitions.map(\.name))
        #expect(names.isDisjoint(with: ["list_notes", "read_note", "create_note", "update_note", "delete_note"]))
        #expect(names.contains("list_tasks"))
        let list = await listNotes(tools)
        #expect(list.json["error"] as? String == "Die Einwilligung „Notizen mit ChatGPT“ fehlt.")
        #expect(!list.raw.contains("Vertraulich"))
        for name in ["create_note", "update_note", "delete_note"] {
            let answer = await run(tools, name, #"{"note_id":"\#(NoteToolAccess.key(for: note.id))","text":"x","folder_id":null,"reason":null}"#)
            #expect(answer.json["error"] as? String == "Die Einwilligung „Notizen mit ChatGPT“ fehlt.", Comment(rawValue: name))
        }
        #expect(store.note(id: note.id)?.text == "Vertraulich genug" && store.note(id: note.id)?.deletedAt == nil)
    }

    @Test func kinds_listIsRead_changesAreWrite_restFollowsTheBase() async throws {
        let tools = await makeTools()
        #expect(tools.kind(of: "list_notes") == .read)
        for name in ["create_note", "update_note", "delete_note"] { #expect(tools.kind(of: name) == .write, "\(name)") }
        #expect(tools.kind(of: "read_note") == .read && tools.kind(of: "search") == .read)
        #expect(tools.kind(of: "complete_task") == .write)
    }

    @Test func listNotes_isOfferedWithStrictSchema() async throws {
        let tools = await makeTools()
        let definition = try #require(tools.definitions.first { $0.name == "list_notes" })
        let schema = try #require(try JSONSerialization.jsonObject(with: definition.parameters) as? [String: Any])
        #expect(Set(schema["required"] as? [String] ?? []) == ["folder_id", "query"])
        #expect(schema["additionalProperties"] as? Bool == false && definition.strict)
    }

    // MARK: Stored form and activity

    @Test func storedForm_listNotes_keepsCountOnly() async throws {
        _ = try #require(store.create(text: "Umzug Ideen\nGeheimwort Zebrastreifen"))
        _ = try #require(store.create(text: "Geschenk Mama"))
        let tools = await makeTools()
        let (raw, _) = await listNotes(tools, query: "ideen")
        let call = ToolCall(id: "c", name: "list_notes", arguments: Data(#"{"folder_id":null,"query":"ideen"}"#.utf8))
        let stored = tools.storedForm(of: call, output: raw)
        #expect(stored.output == #"{"listed":1,"ok":true}"#)
        #expect(stored.arguments == #"{"folder_id":null,"query":"ideen"}"#)
        // An error output and a still open call stay as they are.
        let error = AppTools.error("Ordner nicht gefunden.")
        #expect(tools.storedForm(of: call, output: error).output == error)
        #expect(tools.storedForm(of: call, output: nil).output == nil)
        // Idempotent.
        #expect(tools.storedForm(of: call, output: stored.output).output == stored.output)
    }

    @Test func storedForm_readNote_isForwardedToBase() async throws {
        let note = try #require(store.create(text: "Erster Titel\nGeheimer Inhalt Eins"))
        let tools = await makeTools()
        let (raw, _) = await run(tools, "read_note", #"{"note_ids":["\#(NoteToolAccess.key(for: note.id))"]}"#)
        let call = ToolCall(id: "c", name: "read_note", arguments: Data(#"{"note_ids":["x"]}"#.utf8))
        let stored = try #require(tools.storedForm(of: call, output: raw).output)
        #expect(!stored.contains("Geheimer Inhalt") && stored.contains("Erster Titel"))
    }

    @Test func showsActivity_listAndRead_independentOfConsent() async throws {
        for consent in [true, false] {
            let tools = await makeTools(consent: consent)
            #expect(tools.showsActivity("list_notes") && tools.showsActivity("read_note"), "consent \(consent)")
            #expect(!tools.showsActivity("search") && !tools.showsActivity("create_note"))
        }
    }

    // MARK: Through the base

    @Test func readNote_runsThroughBaseAndFillsTheSharedSession() async throws {
        let note = try #require(store.create(text: "Merkzettel\nInhalt"))
        let tools = await makeTools()
        #expect(tools.base.noteSession.readTexts.isEmpty)
        let (_, json) = await run(tools, "read_note", #"{"note_ids":["\#(NoteToolAccess.key(for: note.id))"]}"#)
        #expect((json["notes"] as? [[String: Any]])?.first?["title"] as? String == "Merkzettel")
        #expect(tools.base.noteSession.readTexts[note.id] == note.text)
    }

    @Test func baseToolsStillWork() async throws {
        let tools = await makeTools()
        let (_, json) = await run(tools, "list_tasks", #"{"filter":"all"}"#)
        #expect((json["tasks"] as? [[String: Any]])?.first?["title"] as? String == "Fahrrad")
    }
}
