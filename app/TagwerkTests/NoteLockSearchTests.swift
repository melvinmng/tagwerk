import Foundation
import RemindersKit
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// A hidden note is found by its title only, in the app search and in the search field of the list (NL4a), and closing the lock
/// takes the text of the hidden notes out of an open search.
@MainActor
struct NoteLockSearchTests {
    let environment: AppEnvironment
    let authenticator = FakeDeviceOwnerAuthenticator()

    init() throws {
        environment = try AppEnvironment(modelContainer: ModelContainerFactory.make(inMemory: true),
                                         notificationCenter: FakeNotificationCenter(), health: FakeHealthStore(),
                                         reminderStore: InMemoryReminderStore(lists: [], records: []),
                                         deviceOwnerAuthenticator: authenticator)
        environment.settings.setupCompleted = true
    }

    private func note(_ text: String = "Zugangsdaten Router\nFritz-7590 Passwort 1234", folderID: UUID? = nil) throws -> NoteRecord {
        try #require(environment.notes.create(text: text, folderID: folderID))
    }

    private func noteItems(_ model: SearchModel) -> [NoteSearchItem] {
        model.results.sections.flatMap(\.rows).compactMap { row in
            if case .note(let item, _) = row { item } else { nil }
        }
    }

    @Test func searchItem_concealedNote_hasOnlyTitle() throws {
        let locked = try note()
        let item = AppEnvironment.searchItem(for: locked, folderNames: [:], isConcealed: true)
        #expect(item.text == "Zugangsdaten Router" && item.isConcealed)
        #expect(!item.text.contains("Passwort"))
    }

    @Test func searchItem_unlocked_hasFullText() throws {
        let locked = try note()
        locked.isLocked = true
        let item = AppEnvironment.searchItem(for: locked, folderNames: [:], isConcealed: false)
        #expect(item.text.contains("Passwort 1234") && !item.isConcealed)
    }

    @Test func appSearch_concealedMorningNote_leavesOutItsGratitude() throws {
        let day = PlanDay(year: 2026, month: 11, day: 19)
        let morning = try #require(environment.notes.create(text: "Abgabe heute", kind: .morning, dayKey: "2026-11-19"))
        let items = AppEnvironment.appSearchNotes(live: [morning], folderNames: [:], gratitudeDays: [day: ["Kaffee mit Jonas"]],
                                                  calendar: testCalendar(), isConcealed: { _ in true })
        #expect(items.count == 1 && !items[0].text.contains("Kaffee"))
    }

    @Test func searchItem_privateFolderNote_followsFolderSwitch() async throws {
        let journalFolder = environment.notes.ensureJournalFolder()
        _ = try note("Geheimer Titel\nzweite Zeile Eifersucht", folderID: journalFolder.id)
        let model = environment.makeSearchModel()
        // Switch off: the note is searched in full.
        model.text = "eifersucht"
        #expect(noteItems(model).first?.text.contains("Eifersucht") == true)
        // Switch on and the lock closed: only the title is searched.
        #expect(await environment.noteLock.setEnabled(true))
        #expect(await environment.noteLock.setLocksPrivateFolders(true))
        environment.noteLock.lockNow()
        model.text = ""
        model.text = "eifersucht"
        #expect(noteItems(model).isEmpty)
        model.text = "geheimer"
        let hit = try #require(noteItems(model).first)
        #expect(hit.isConcealed && hit.text == "Geheimer Titel")
        // Unlocked: the whole text again.
        #expect(await environment.noteLock.unlock(reason: "Test"))
        model.text = ""
        model.text = "eifersucht"
        #expect(noteItems(model).first?.isConcealed == false)
    }

    @Test func listSearch_concealedNote_matchesTitleOnly() throws {
        let locked = try note()
        #expect(NotesListView.matchesSearch(locked, gratitude: [], query: "router", titleOnly: true))
        #expect(!NotesListView.matchesSearch(locked, gratitude: [], query: "passwort", titleOnly: true))
        #expect(NotesListView.matchesSearch(locked, gratitude: [], query: "passwort", titleOnly: false))
    }

    @Test func lockNow_rebuildsSearchItems() async throws {
        let locked = try note()
        #expect(await environment.noteLock.setEnabled(true))
        environment.notes.setLocked([locked.id], true)
        environment.openSearch()
        let model = try #require(environment.activeSearch)
        model.text = "passwort"
        // The session is open: the passage is there.
        #expect(noteItems(model).first?.text.contains("Passwort") == true)
        environment.noteLock.lockNow()
        // The open search lost the text of the note by itself.
        #expect(noteItems(model).isEmpty)
        #expect(!"\(model.results)".contains("1234"))
    }

    @Test func lockingANote_endsTheAssistantNoteSession() async throws {
        let locked = try note()
        let session = environment.assistant.tools.noteSession
        session.remember(locked.id, text: "Fritz-7590 Passwort 1234", truncated: false)
        #expect(!session.readTexts.isEmpty)
        environment.notes.setLocked([locked.id], true)
        #expect(session.readTexts.isEmpty)
    }
}
