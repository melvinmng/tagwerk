import AIKit
import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// `read_note` (issue #173, decision D4): the full text of a found note, never of a private one.
@MainActor
struct NoteReadToolTests {
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
        local = FakeTaskProvider(source: .local, tasks: [])
        taskList = TaskListModel(providers: [local], now: testNow, calendar: calendar)
    }

    private func makeTools(consent: Bool = true, withAccess: Bool = true) async -> AppTools {
        await taskList.reload()
        let planStore = PlanStore(context: container.mainContext)
        let blocks = BlockPlanner(store: calendarStore, planStore: planStore, links: EventLinkStore(context: container.mainContext),
                                  settings: settings, calendar: calendar)
        let planning = PlanningModel(taskList: taskList, calendarStore: calendarStore, reminderStore: FakeAccessStore(),
                                     planStore: planStore, efforts: RecurringEffortStore(context: container.mainContext),
                                     blocks: blocks, settings: settings, marks: EventMarkStore(context: container.mainContext),
                                     now: testNow, calendar: calendar)
        await planning.reload()
        let sources = SearchToolSources(events: { _ in [] }, calendarNames: { [:] }, completedTasks: { [] }, notesAllowed: { consent })
        return AppTools(taskList: taskList, planning: planning, planner: nil, events: { _ in [] }, search: sources,
                        noteAccess: withAccess ? NoteToolAccess(store: store) : nil)
    }

    private func read(_ tools: AppTools, _ ids: [String]) async -> (raw: String, json: [String: Any]) {
        let list = ids.map { "\"\($0)\"" }.joined(separator: ",")
        let raw = await tools.run(ToolCall(id: "c", name: "read_note", arguments: Data(#"{"note_ids":[\#(list)]}"#.utf8)))
        return (raw, (try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any]) ?? [:])
    }

    private func key(_ note: NoteRecord) -> String { NoteToolAccess.key(for: note.id) }

    @Test func readNote_returnsFullText() async throws {
        let note = try #require(store.create(text: "Wochenplan\nMontag: Teig kneten\nDienstag: [Foto](attachment:3F2504E0-4F89-41D3-9A0C-0305E82C3301)"))
        let tools = await makeTools()
        let (_, json) = await read(tools, [key(note)])
        let entry = try #require((json["notes"] as? [[String: Any]])?.first)
        #expect(entry["id"] as? String == key(note))
        #expect(entry["title"] as? String == "Wochenplan")
        #expect(entry["text"] as? String == note.text)   // attachment references stay in the text
        #expect(entry["truncated"] as? Bool == false)
        #expect(json["notFound"] == nil && json["not_read"] == nil)
    }

    @Test func readNote_privateOrTrashedID_answersLikeUnknown() async throws {
        let journal = try #require(store.create(text: "Dankbar für Ruhe", kind: .journal, dayKey: "2026-11-18"))
        let dream = try #require(store.create(text: "Flug über ein Feld", kind: .dream, dayKey: "2026-11-18"))
        let trashed = try #require(store.create(text: "Gelöscht und doch da"))
        store.trash(trashed.id)
        let tools = await makeTools()
        let unknown = await read(tools, [NoteToolAccess.key(for: UUID())])
        #expect(unknown.json["error"] as? String == "Notiz nicht gefunden.")
        for note in [journal, dream, trashed] {
            let answer = await read(tools, [key(note)])
            #expect(answer.raw == unknown.raw, "\(note.kind)")
            #expect(!answer.raw.contains("Dankbar") && !answer.raw.contains("Flug") && !answer.raw.contains("Gelöscht"))
        }
    }

    @Test func readNote_noteInSubfolderOfPrivateFolder_isNotFound() async throws {
        // Guard only: the app cannot create subfolders below system folders.
        let journalFolder = store.ensureJournalFolder()
        let sub = NoteFolderRecord(name: "Unterordner", parentID: journalFolder.id, order: 0)
        container.mainContext.insert(sub)
        store.save()
        let inSub = try #require(store.create(text: "Heimlich im Unterordner", folderID: sub.id))
        let inJournalFolder = try #require(store.create(text: "Heimlich im Tagebuch-Ordner", folderID: journalFolder.id))
        let tools = await makeTools()
        for note in [inSub, inJournalFolder] {
            let answer = await read(tools, [key(note)])
            #expect(answer.json["error"] as? String == "Notiz nicht gefunden.")
            #expect(!answer.raw.contains("Heimlich"))
        }
    }

    @Test func readNote_mixedIDs_listsNotFoundWithoutRevealingWhy() async throws {
        let normal = try #require(store.create(text: "Normale Notiz"))
        let dream = try #require(store.create(text: "Traum", kind: .dream, dayKey: "2026-11-18"))
        let tools = await makeTools()
        let invented = NoteToolAccess.key(for: UUID())
        let (_, json) = await read(tools, [key(normal), key(dream), invented])
        #expect((json["notes"] as? [[String: Any]])?.count == 1)
        #expect(Set(json["notFound"] as? [String] ?? []) == [key(dream), invented])
    }

    @Test func readNote_longNote_isTruncatedAndFlagged() async throws {
        let text = "Langer Anfang\n" + String(repeating: "x", count: 13_000)
        let note = try #require(store.create(text: text))
        let tools = await makeTools()
        let (raw, json) = await read(tools, [key(note)])
        let entry = try #require((json["notes"] as? [[String: Any]])?.first)
        #expect((entry["text"] as? String)?.count == AppTools.maxNoteTextLength)
        #expect(entry["truncated"] as? Bool == true)
        #expect(raw.utf8.count <= AppTools.maxReadOutputLength)
    }

    @Test func readNote_overBudget_reportsNotRead() async throws {
        // Five notes of 5 000 characters: the first two fit into 14 000 bytes, the rest does not.
        var notes: [NoteRecord] = []
        for index in 1...5 { notes.append(try #require(store.create(text: "Notiz \(index)\n" + String(repeating: "a", count: 5_000)))) }
        let tools = await makeTools()
        let (raw, json) = await read(tools, notes.map(key))
        #expect(raw.utf8.count <= AppTools.maxReadOutputLength)
        let delivered = (json["notes"] as? [[String: Any]]) ?? []
        let notRead = json["not_read"] as? [String] ?? []
        #expect(delivered.count >= 2)
        #expect(!notRead.isEmpty)
        #expect(delivered.count + notRead.count == 5)
        // The ids come back in the order asked.
        #expect(delivered.compactMap { $0["id"] as? String } + notRead == notes.map(key))
    }

    @Test func readNote_moreThanFiveIDs_fails() async throws {
        let tools = await makeTools()
        let ids = (1...6).map { _ in NoteToolAccess.key(for: UUID()) }
        let answer = await read(tools, ids)
        #expect(answer.json["error"] as? String == "Höchstens fünf Notizen auf einmal.")
        let none = await read(tools, [])
        #expect(none.json["error"] as? String == "Das Argument note_ids fehlt.")
    }

    @Test func readNote_remembersTextInSession() async throws {
        let note = try #require(store.create(text: "Merkzettel\nInhalt"))
        let tools = await makeTools()
        #expect(tools.noteSession.readTexts.isEmpty)
        _ = await read(tools, [key(note)])
        #expect(tools.noteSession.readTexts[note.id] == note.text)
        #expect(!tools.noteSession.truncated.contains(note.id))
        tools.noteSession.reset()
        #expect(tools.noteSession.readTexts.isEmpty && tools.noteSession.truncated.isEmpty)
    }

    @Test func readNote_withoutConsent_isNotOfferedAndDoesNotRun() async throws {
        let note = try #require(store.create(text: "Vertraulich genug"))
        let tools = await makeTools(consent: false)
        #expect(!tools.definitions.contains { $0.name == "read_note" })
        let answer = await read(tools, [key(note)])
        #expect(answer.json["error"] as? String == "Die Einwilligung „Notizen mit ChatGPT“ fehlt.")
        #expect(!answer.raw.contains("Vertraulich"))
        #expect(tools.noteSession.readTexts.isEmpty)
    }

    @Test func readNote_withoutNoteAccess_isNotOffered() async throws {
        let note = try #require(store.create(text: "Notiz"))
        let tools = await makeTools(withAccess: false)
        #expect(!tools.definitions.contains { $0.name == "read_note" })
        let answer = await read(tools, [key(note)])
        #expect(answer.json["error"] != nil)
        #expect(tools.noteSession.readTexts.isEmpty)
    }

    @Test func readNote_isOfferedWithConsentAndStrictSchema() async throws {
        let tools = await makeTools()
        let definition = try #require(tools.definitions.first { $0.name == "read_note" })
        let schema = try #require(try JSONSerialization.jsonObject(with: definition.parameters) as? [String: Any])
        #expect(Set(schema["required"] as? [String] ?? []) == ["note_ids"])
        #expect(schema["additionalProperties"] as? Bool == false && definition.strict)
        #expect(tools.kind(of: "read_note") == .read)
        #expect(!AppTools.allDefinitions.contains { $0.name == "read_note" })
    }

    @Test func storedForm_readNote_keepsTitlesOnly() async throws {
        let one = try #require(store.create(text: "Erster Titel\nGeheimer Inhalt Eins"))
        let two = try #require(store.create(text: "Zweiter Titel\nGeheimer Inhalt Zwei"))
        let tools = await makeTools()
        let (raw, _) = await read(tools, [key(one), key(two)])
        let call = ToolCall(id: "c", name: "read_note", arguments: Data(#"{"note_ids":["x"]}"#.utf8))
        let stored = try #require(tools.storedForm(of: call, output: raw).output)
        #expect(!stored.contains("Geheimer Inhalt"))
        let object = try #require(try JSONSerialization.jsonObject(with: Data(stored.utf8)) as? [String: Any])
        #expect(object["ok"] as? Bool == true)
        #expect(object["read"] as? [String] == ["Erster Titel", "Zweiter Titel"])
        #expect(object["note"] as? String == "Der Text ist nicht mehr verfügbar. Lies die Notiz erneut, wenn du ihn brauchst.")
        // Idempotent, and an error output stays as it is.
        #expect(tools.storedForm(of: call, output: stored).output == stored)
        let error = AppTools.error("Notiz nicht gefunden.")
        #expect(tools.storedForm(of: call, output: error).output == error)
        // Arguments hold only ids and stay.
        #expect(tools.storedForm(of: call, output: raw).arguments == #"{"note_ids":["x"]}"#)
    }

    @Test func showsActivity_onlyForReadNote() async throws {
        let tools = await makeTools()
        #expect(tools.showsActivity("read_note"))
        for name in AppTools.readTools.subtracting(["read_note"]) { #expect(!tools.showsActivity(name), "\(name)") }
        #expect(!tools.showsActivity("create_task"))
    }

    @Test func errorMessages_neverContainNoteText() async throws {
        let note = try #require(store.create(text: "Streng geheimer Wortlaut"))
        let private1 = try #require(store.create(text: "Tagebuch Wortlaut", kind: .journal, dayKey: "2026-11-18"))
        let tools = await makeTools()
        var outputs: [String] = []
        outputs.append(await read(tools, [key(private1)]).raw)
        outputs.append(await read(tools, ["kaputt"]).raw)
        outputs.append(await read(tools, (1...6).map { _ in key(note) + "x" }).raw)
        outputs.append(await tools.run(ToolCall(id: "c", name: "read_note", arguments: Data("kein json".utf8))))
        for output in outputs { #expect(!output.contains("Wortlaut"), "\(output)") }
    }
}
