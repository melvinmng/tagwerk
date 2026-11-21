import AIKit
import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// `create_note`, `update_note` and `delete_note` (issue #233): checks before every change, nothing for private notes.
extension NoteChatToolsTests {
    private func key(_ note: NoteRecord) -> String { NoteToolAccess.key(for: note.id) }

    private func read(_ tools: NoteChatTools, _ notes: [NoteRecord]) async {
        let ids = notes.map { "\"\(key($0))\"" }.joined(separator: ",")
        _ = await run(tools, "read_note", #"{"note_ids":[\#(ids)]}"#)
    }

    /// The arguments of `update_note` for a new text (JSON-escaped).
    private func updateArguments(_ note: NoteRecord, text: String) -> String {
        let escaped = String(decoding: (try? JSONEncoder().encode(text)) ?? Data(), as: UTF8.self)
        return #"{"note_id":"\#(key(note))","text":\#(escaped)}"#
    }

    private func createArguments(text: String, folder: String? = nil) -> String {
        let escaped = String(decoding: (try? JSONEncoder().encode(text)) ?? Data(), as: UTF8.self)
        return #"{"text":\#(escaped),"folder_id":\#(folder.map { "\"\($0)\"" } ?? "null")}"#
    }

    // MARK: create_note

    @Test func createNote_landsInGivenFolder() async throws {
        let folder = try store.createFolder(name: "Reisen")
        let tools = await makeTools()
        let (_, json) = await run(tools, "create_note", createArguments(text: "  Packliste\n- Schuhe  ", folder: NoteToolAccess.folderKey(for: folder.id)))
        #expect(json["ok"] as? Bool == true && json["title"] as? String == "Packliste")
        let createdID = try #require(UUID(uuidString: String((json["id"] as? String ?? "").dropFirst(5))))
        let created = try #require(store.note(id: createdID))
        #expect(created.folderID == folder.id && created.kind == .free)
        #expect(created.text == "Packliste\n- Schuhe")   // trimmed like every new note
        #expect(json["id"] as? String == key(created))
    }

    @Test func createNote_withoutFolder_usesTheDefaultFolderOfTheChatElseNotizen() async throws {
        store.ensureDefaultFolders()
        let brainDump = try #require(store.folder(role: .brainDump))
        let tools = await makeTools()
        let plain = await run(tools, "create_note", createArguments(text: "Lose Idee"))
        let plainNote = try #require(store.notes(.all).first { $0.text == "Lose Idee" })
        #expect(plain.json["ok"] as? Bool == true && plainNote.folderID == nil)
        tools.defaultFolderID = brainDump.id
        _ = await run(tools, "create_note", createArguments(text: "Idee im Brain Dump"))
        #expect(store.notes(.all).first { $0.text == "Idee im Brain Dump" }?.folderID == brainDump.id)
        // A default folder that takes no own notes falls back to "Notizen".
        tools.defaultFolderID = try #require(store.folder(role: .morningRoutine)).id
        _ = await run(tools, "create_note", createArguments(text: "Idee ohne Ziel"))
        #expect(store.notes(.all).first { $0.text == "Idee ohne Ziel" }?.folderID == nil)
    }

    @Test func createNote_privateFolder_isRejected() async throws {
        let journalFolder = store.ensureJournalFolder()
        let bibleFolder = store.ensureSystemFolder(.bibleStudy, name: "Bible Study")
        let sub = NoteFolderRecord(name: "Unterordner", parentID: journalFolder.id, order: 0)
        container.mainContext.insert(sub)
        store.save()
        let tools = await makeTools()
        let unknown = await run(tools, "create_note", createArguments(text: "Heimlich", folder: NoteToolAccess.folderKey(for: UUID())))
        for id in [journalFolder.id, bibleFolder.id, sub.id] {
            let answer = await run(tools, "create_note", createArguments(text: "Heimlich", folder: NoteToolAccess.folderKey(for: id)))
            #expect(answer.raw == unknown.raw)
        }
        #expect(unknown.json["error"] as? String == "Ordner nicht gefunden.")
        #expect(store.notes(.all).isEmpty)
    }

    @Test func createNote_routineFolder_isRejected() async throws {
        store.ensureDefaultFolders()
        let tools = await makeTools()
        for role in [NoteFolderRole.morningRoutine, .eveningRoutine] {
            let folder = try #require(store.folder(role: role))
            let answer = await run(tools, "create_note", createArguments(text: "Nicht hier", folder: NoteToolAccess.folderKey(for: folder.id)))
            #expect(answer.json["error"] as? String == "In diesen Ordner kann der Assistent keine Notiz anlegen.", "\(role)")
        }
        #expect(store.notes(.all).isEmpty)
    }

    @Test func createNote_withAttachmentReference_isRejected() async throws {
        let tools = await makeTools()
        let answer = await run(tools, "create_note", createArguments(text: "Foto\n![Bild](attachment:3F2504E0-4F89-41D3-9A0C-0305E82C3301)"))
        #expect(answer.json["error"] as? String == "Anhänge kann der Assistent nicht anlegen. Nimm den Verweis auf den Anhang nicht in den Text auf.")
        #expect(store.notes(.all).isEmpty)
    }

    @Test func createNote_emptyOrTooLong_isRejected() async throws {
        let tools = await makeTools()
        #expect((await run(tools, "create_note", createArguments(text: "  \n "))).json["error"] != nil)
        let long = await run(tools, "create_note", createArguments(text: String(repeating: "x", count: AppTools.maxNoteTextLength + 1)))
        #expect(long.json["error"] as? String == "Die Notiz ist zu lang (höchstens 12 000 Zeichen).")
        #expect(store.notes(.all).isEmpty)
    }

    @Test func createNote_textCountsAsReadInTheSession() async throws {
        let tools = await makeTools()
        let created = await run(tools, "create_note", createArguments(text: "  Entwurf\nZeile eins  "))
        let note = try #require(store.notes(.all).first)
        #expect(tools.base.noteSession.readTexts[note.id] == note.text)   // the stored text, not the argument
        _ = created
        let revised = await run(tools, "update_note", updateArguments(note, text: "Entwurf\nZeile eins\nZeile zwei"))
        #expect(revised.json["ok"] as? Bool == true)
    }

    // MARK: update_note

    @Test func updateNote_withoutRead_isRejected() async throws {
        let note = try #require(store.create(text: "Plan\nMontag"))
        let tools = await makeTools()
        let answer = await run(tools, "update_note", updateArguments(note, text: "Plan\nMontag\nDienstag"))
        #expect(answer.json["error"] as? String == "Lies die Notiz zuerst mit read_note, bevor du sie überarbeitest.")
        #expect(store.note(id: note.id)?.text == "Plan\nMontag")
    }

    @Test func updateNote_afterExternalChange_isRejected() async throws {
        let note = try #require(store.create(text: "Plan\nMontag"))
        let tools = await makeTools()
        await read(tools, [note])
        store.updateText(note.id, text: "Plan\nMontag\nvom Nutzer ergänzt")
        let answer = await run(tools, "update_note", updateArguments(note, text: "Plan\nMontag\nDienstag"))
        #expect(answer.json["error"] as? String == "Die Notiz wurde inzwischen geändert. Lies sie erneut.")
        #expect(store.note(id: note.id)?.text == "Plan\nMontag\nvom Nutzer ergänzt")
    }

    @Test func updateNote_truncatedRead_isRejected() async throws {
        let note = try #require(store.create(text: "Langer Anfang\n" + String(repeating: "x", count: 13_000)))
        let tools = await makeTools()
        await read(tools, [note])
        let answer = await run(tools, "update_note", updateArguments(note, text: "Kurz"))
        #expect(answer.json["error"] as? String == "Die Notiz ist zu lang und wurde beim Lesen gekürzt. Sie lässt sich nicht überarbeiten.")
        #expect(store.note(id: note.id)?.text.count == 13_014)
    }

    @Test func updateNote_droppingAttachment_isRejected() async throws {
        let id = "3F2504E0-4F89-41D3-9A0C-0305E82C3301"
        let note = try #require(store.create(text: "Urlaub\n![Strand](attachment:\(id))\nSonne"))
        let tools = await makeTools()
        await read(tools, [note])
        let dropped = await run(tools, "update_note", updateArguments(note, text: "Urlaub\nSonne"))
        #expect(dropped.json["error"] as? String == "Die Anhänge der Notiz müssen im Text bleiben. Übernimm die Verweise auf Anhänge unverändert.")
        let invented = await run(tools, "update_note", updateArguments(note, text: "Urlaub\n![Strand](attachment:\(id))\n![Neu](attachment:11111111-4F89-41D3-9A0C-0305E82C3301)"))
        #expect(invented.json["error"] != nil)
        #expect(store.note(id: note.id)?.text == "Urlaub\n![Strand](attachment:\(id))\nSonne")
        // Moving the reference is fine.
        let moved = await run(tools, "update_note", updateArguments(note, text: "Urlaub in der Sonne\n![Strand](attachment:\(id))"))
        #expect(moved.json["ok"] as? Bool == true)
    }

    @Test func updateNote_writesTextAndAllowsFollowUp() async throws {
        let note = try #require(store.create(text: "Plan\nMontag"))
        let tools = await makeTools()
        await read(tools, [note])
        let first = await run(tools, "update_note", updateArguments(note, text: "Wochenplan\n- Montag\n- Dienstag"))
        #expect(first.json["ok"] as? Bool == true && first.json["title"] as? String == "Wochenplan")
        #expect(store.note(id: note.id)?.text == "Wochenplan\n- Montag\n- Dienstag")
        #expect(tools.base.noteSession.readTexts[note.id] == "Wochenplan\n- Montag\n- Dienstag")
        // The session holds the new text: a second revision needs no new read.
        let second = await run(tools, "update_note", updateArguments(note, text: "Wochenplan\n- Montag\n- Dienstag\n- Mittwoch"))
        #expect(second.json["ok"] as? Bool == true)
        #expect(store.note(id: note.id)?.text.hasSuffix("- Mittwoch") == true)
    }

    @Test func updateNote_unchangedEmptyOrTooLongText_isRejected() async throws {
        let note = try #require(store.create(text: "Plan\nMontag"))
        let tools = await makeTools()
        await read(tools, [note])
        #expect((await run(tools, "update_note", updateArguments(note, text: "Plan\nMontag"))).json["error"] as? String == "Der neue Text ist gleich dem alten.")
        #expect((await run(tools, "update_note", updateArguments(note, text: "  "))).json["error"] != nil)
        let long = await run(tools, "update_note", updateArguments(note, text: String(repeating: "x", count: AppTools.maxNoteTextLength + 1)))
        #expect(long.json["error"] as? String == "Die Notiz ist zu lang (höchstens 12 000 Zeichen).")
        #expect(store.note(id: note.id)?.text == "Plan\nMontag")
    }

    @Test func updateNote_privateNote_isRejected() async throws {
        let journal = try #require(store.create(text: "Dankbar für Ruhe", kind: .journal, dayKey: "2026-11-18"))
        let trashed = try #require(store.create(text: "Gelöscht"))
        store.trash(trashed.id)
        let tools = await makeTools()
        // Even a text that sits in the session (it cannot get there through `read_note`) does not open the way.
        tools.base.noteSession.remember(journal.id, text: journal.text, truncated: false)
        tools.base.noteSession.remember(trashed.id, text: trashed.text, truncated: false)
        let unknown = await run(tools, "update_note", updateArguments(journal, text: "Überschrieben").replacingOccurrences(of: key(journal), with: NoteToolAccess.key(for: UUID())))
        for note in [journal, trashed] {
            let answer = await run(tools, "update_note", updateArguments(note, text: "Überschrieben"))
            #expect(answer.raw == unknown.raw)
        }
        #expect(unknown.json["error"] as? String == "Notiz nicht gefunden.")
        #expect(store.note(id: journal.id)?.text == "Dankbar für Ruhe" && store.note(id: trashed.id)?.text == "Gelöscht")
    }

    @Test func updateNote_inScopedChat_onlyTheOneNote() async throws {
        let mine = try #require(store.create(text: "Meine Notiz"))
        let other = try #require(store.create(text: "Andere Notiz"))
        let tools = await makeTools(scope: mine.id)
        await read(tools, [mine, other])
        let rejected = await run(tools, "update_note", updateArguments(other, text: "Andere Notiz geändert"))
        #expect(rejected.json["error"] as? String == "Dieses Gespräch betrifft nur eine andere Notiz.")
        #expect((await run(tools, "delete_note", #"{"note_id":"\#(key(other))","reason":null}"#)).json["error"] != nil)
        #expect(store.note(id: other.id)?.text == "Andere Notiz" && store.note(id: other.id)?.deletedAt == nil)
        let accepted = await run(tools, "update_note", updateArguments(mine, text: "Meine Notiz geändert"))
        #expect(accepted.json["ok"] as? Bool == true)
        // Creating stays possible in a chat about one note.
        #expect((await run(tools, "create_note", createArguments(text: "Neu daneben"))).json["ok"] as? Bool == true)
    }

    // MARK: delete_note

    @Test func deleteNote_movesToTrashAndKeepsAttachments() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "attachments-" + UUID().uuidString, directoryHint: .isDirectory)
        let attachments = NoteAttachmentStore(context: container.mainContext, directory: directory)
        let withFiles = NoteStore(context: container.mainContext, attachments: attachments)
        let note = try #require(withFiles.create(text: "Rechnung"))
        let source = FileManager.default.temporaryDirectory.appending(path: "rechnung-" + UUID().uuidString + ".txt")
        try Data("Rechnung 42".utf8).write(to: source)
        _ = try attachments.addFile(at: source, to: note.id)
        let tools = await makeTools(noteStore: withFiles)
        let answer = await run(tools, "delete_note", #"{"note_id":"\#(key(note))","reason":"Doppelt vorhanden"}"#)
        #expect(answer.json["ok"] as? Bool == true && answer.json["title"] as? String == "Rechnung" && answer.json["trash_days"] as? Int == 30)
        let trashed = try #require(withFiles.note(id: note.id))
        #expect(trashed.deletedAt != nil)
        #expect(attachments.attachments(of: note.id).count == 1)   // nothing is removed for good
        #expect(withFiles.notes(.trash).map(\.id) == [note.id])
    }

    @Test func deleteNote_privateNote_isRejected() async throws {
        let journal = try #require(store.create(text: "Dankbar für Ruhe", kind: .journal, dayKey: "2026-11-18"))
        let tools = await makeTools()
        let unknown = await run(tools, "delete_note", #"{"note_id":"\#(NoteToolAccess.key(for: UUID()))","reason":null}"#)
        let answer = await run(tools, "delete_note", #"{"note_id":"\#(key(journal))","reason":null}"#)
        #expect(answer.raw == unknown.raw && answer.json["error"] as? String == "Notiz nicht gefunden.")
        #expect(store.note(id: journal.id)?.deletedAt == nil)
    }

    @Test func deleteNote_alreadyTrashed_answersNotFound() async throws {
        let note = try #require(store.create(text: "Weg damit"))
        store.trash(note.id)
        let tools = await makeTools()
        let answer = await run(tools, "delete_note", #"{"note_id":"\#(key(note))","reason":null}"#)
        #expect(answer.json["error"] as? String == "Notiz nicht gefunden.")
    }

    // MARK: Definitions and stored form

    @Test func definitions_offerTheChangingToolsWithStrictSchemas() async throws {
        let tools = await makeTools()
        let expected: [String: Set<String>] = ["create_note": ["text", "folder_id"], "update_note": ["note_id", "text"],
                                               "delete_note": ["note_id", "reason"]]
        for (name, required) in expected {
            let definition = try #require(tools.definitions.first { $0.name == name }, "\(name)")
            let schema = try #require(try JSONSerialization.jsonObject(with: definition.parameters) as? [String: Any])
            #expect(Set(schema["required"] as? [String] ?? []) == required, "\(name)")
            #expect(schema["additionalProperties"] as? Bool == false && definition.strict)
        }
        // They stay available in a chat about one note.
        let scoped = await makeTools(scope: UUID())
        #expect(Set(scoped.definitions.map(\.name)).isSuperset(of: Set(expected.keys)))
    }

    @Test func storedForm_updateNote_dropsText() async throws {
        let tools = await makeTools()
        let call = ToolCall(id: "c", name: "update_note", arguments: Data(updateArguments(try #require(store.create(text: "x")), text: "Neuer Titel\nGeheime Zeile").utf8))
        for output in [nil, #"{"ok":true,"title":"Neuer Titel"}"#] as [String?] {
            let stored = tools.storedForm(of: call, output: output)
            #expect(!stored.arguments.contains("Geheime Zeile"))
            let object = try #require(try JSONSerialization.jsonObject(with: Data(stored.arguments.utf8)) as? [String: Any])
            #expect(object["title"] as? String == "Neuer Titel" && object["text"] == nil && object["note_id"] != nil)
            #expect(stored.output == output)
        }
    }

    @Test func storedForm_createNote_dropsText() async throws {
        let tools = await makeTools()
        let long = "Titel " + String(repeating: "t", count: 120) + "\nGeheime Zeile"
        let call = ToolCall(id: "c", name: "create_note", arguments: Data(createArguments(text: long, folder: "folder:x").utf8))
        let stored = tools.storedForm(of: call, output: nil)
        #expect(!stored.arguments.contains("Geheime Zeile"))
        let object = try #require(try JSONSerialization.jsonObject(with: Data(stored.arguments.utf8)) as? [String: Any])
        #expect((object["title"] as? String)?.count == 80 && object["text"] == nil && object["folder_id"] as? String == "folder:x")
        // Stored twice gives the same.
        #expect(tools.storedForm(of: ToolCall(id: "c", name: "create_note", arguments: Data(stored.arguments.utf8)), output: nil).arguments == stored.arguments)
    }

    @Test func storedForm_deleteNote_isUnchanged() async throws {
        let tools = await makeTools()
        let arguments = #"{"note_id":"note:1","reason":"Doppelt"}"#
        let call = ToolCall(id: "c", name: "delete_note", arguments: Data(arguments.utf8))
        let stored = tools.storedForm(of: call, output: #"{"ok":true,"title":"X","trash_days":30}"#)
        #expect(stored.arguments == arguments && stored.output == #"{"ok":true,"title":"X","trash_days":30}"#)
    }
}
