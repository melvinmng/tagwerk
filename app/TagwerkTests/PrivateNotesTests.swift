import AIKit
import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// Journal entries and Bible Study notes never go to ChatGPT, the assistant's tools or the widget. These tests
/// guard every place that sends or shares note content.
@MainActor
struct PrivateNotesTests {
    @Test func everyPrivateKind_isCoveredByThePredicate() {
        let privateKinds = NoteKind.allCases.filter(\.isPrivate)
        #expect(privateKinds.contains(.journal) && privateKinds.contains(.bibleStudy) && privateKinds.contains(.dream))
        #expect(!NoteKind.free.isPrivate && !NoteKind.morning.isPrivate && !NoteKind.evening.isPrivate)
    }

    @Test func assistantTools_haveNoAccessToNotesOfAnyKind() {
        let names = AppTools.allDefinitions.map(\.name)
        for forbidden in ["note", "journal", "tagebuch", "bible", "diary"] {
            #expect(!names.contains { $0.localizedCaseInsensitiveContains(forbidden) }, "tool name contains \(forbidden)")
        }
        // The note suggestions may only call these tools, and none of them reads or writes notes.
        for name in NoteSuggestionRules.allowedTools { #expect(!name.localizedCaseInsensitiveContains("note")) }
    }

    @Test func assistantSearch_hasNoNoteSourceWithoutWiring() {
        // `SearchToolSources.notes` is the only door for notes into the assistant's `search`; without wiring it is empty.
        // `AppEnvironment` fills it from `NoteToolAccess`, which leaves private notes out (`NoteToolAccessTests`).
        let sources = SearchToolSources(events: { _ in nil }, calendarNames: { [:] }, completedTasks: { [] })
        let labels = Mirror(reflecting: sources).children.compactMap(\.label)
        #expect(labels.sorted() == ["calendarNames", "completedTasks", "events", "notes", "notesAllowed", "searchOnline", "shopping"])
        #expect(sources.notes().isEmpty)
        #expect(!sources.notesAllowed())
    }

    @Test func storeIsPrivate_freeNoteInJournalFolder() throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let notes = NoteStore(context: container.mainContext)
        let journalFolder = notes.ensureJournalFolder()
        let inJournal = try #require(notes.create(text: "Frei im Tagebuch-Ordner", folderID: journalFolder.id))
        let own = try #require(notes.create(text: "Normal"))
        #expect(notes.isPrivate(inJournal))
        #expect(!notes.isPrivate(own))
    }

    @Test func storeIsPrivate_freeNoteInSubfolderOfBibleStudy() throws {
        // Guard only: the app cannot create subfolders below system folders, so this needs directly inserted data.
        let container = try ModelContainerFactory.make(inMemory: true)
        let notes = NoteStore(context: container.mainContext)
        let bibleFolder = notes.ensureSystemFolder(.bibleStudy, name: "Bible Study")
        let sub = NoteFolderRecord(name: "Römer", parentID: bibleFolder.id, order: 0)
        container.mainContext.insert(sub)
        notes.save()
        let inSub = try #require(notes.create(text: "Notiz im Unterordner", folderID: sub.id))
        #expect(notes.isPrivate(inSub))
    }

    @Test func storeIsPrivate_dreamNote() throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let notes = NoteStore(context: container.mainContext)
        let dream = try #require(notes.create(text: "Traum", kind: .dream, dayKey: "2026-11-18"))
        let morning = try #require(notes.create(text: "Gedanken", kind: .morning, dayKey: "2026-11-18"))
        #expect(notes.isPrivate(dream))
        #expect(!notes.isPrivate(morning))
    }

    @Test func storeIsPrivate_lockedNote() throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let notes = NoteStore(context: container.mainContext)
        let own = try #require(notes.create(text: "Normal"))
        let thought = try #require(notes.create(text: "Gedanken", kind: .morning, dayKey: "2026-11-18"))
        #expect(!notes.isPrivate(own) && !notes.isPrivate(thought))
        notes.setLocked([own.id, thought.id], true)
        #expect(notes.isPrivate(own) && notes.isPrivate(thought))
        notes.setLocked([own.id], false)
        #expect(!notes.isPrivate(own) && notes.isPrivate(thought))
    }

    /// Rule 4 of the lock: a locked note is private while the lock is closed and open to the assistant while the lock session is
    /// open (decision of 2026-11-22, #188). A private kind or folder is private in both states. `NoteLockTests` covers the real session.
    @Test func lockedNote_isPrivateOnlyWhileTheSessionIsClosed() throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let notes = NoteStore(context: container.mainContext)
        var sessionIsOpen = false
        notes.lockHoldsBack = { $0 && !sessionIsOpen }
        let locked = try #require(notes.create(text: "Geheim"))
        let free = try #require(notes.create(text: "Offen"))
        let dream = try #require(notes.create(text: "Traum", kind: .dream, dayKey: "2026-11-18"))
        notes.setLocked([locked.id, dream.id], true)
        #expect(notes.isPrivate(locked) && !notes.isPrivate(free) && notes.isPrivate(dream))
        sessionIsOpen = true
        #expect(!notes.isPrivate(locked) && !notes.isPrivate(free))
        // The mark of a private kind changes nothing: it never leaves the device.
        #expect(notes.isPrivate(dream))
        sessionIsOpen = false
        #expect(notes.isPrivate(locked))
    }

    @Test func lockSwitchOff_stillPrivate() throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let notes = NoteStore(context: container.mainContext)
        let settings = try AppSettings.current(in: container.mainContext)
        let note = try #require(notes.create(text: "Geheim"))
        notes.setLocked([note.id], true)
        settings.noteLockEnabled = false
        settings.noteLockPrivateFolders = false
        #expect(notes.isPrivate(note))
        #expect(!NoteToolAccess(store: notes).visibleNotes().contains { $0.id == note.id })
    }

    @Test func recipeSource_neverOffersALockedNote_whileLocked() throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let notes = NoteStore(context: container.mainContext)
        let folder = notes.ensureSystemFolder(.recipes, name: "Rezepte")
        let locked = try #require(notes.create(text: "Rezept gesperrt", folderID: folder.id))
        let open = try #require(notes.create(text: "Rezept offen", folderID: folder.id))
        notes.setLocked([locked.id], true)
        #expect(!RecipeNoteSource.isOffered(locked, store: notes))
        #expect(RecipeNoteSource.isOffered(open, store: notes))
        #expect(RecipeNoteSource.recipeNotes(in: notes).map(\.id) == [open.id])
        #expect(RecipeNoteSource.otherNotes(in: notes).isEmpty)
    }

    @Test func recipeSource_neverOffersNoteBelowPrivateFolder() throws {
        // Guard only (see `storeIsPrivate_freeNoteInSubfolderOfBibleStudy`).
        let container = try ModelContainerFactory.make(inMemory: true)
        let notes = NoteStore(context: container.mainContext)
        let journalFolder = notes.ensureJournalFolder()
        let sub = NoteFolderRecord(name: "Unterordner", parentID: journalFolder.id, order: 0)
        container.mainContext.insert(sub)
        notes.save()
        let inSub = try #require(notes.create(text: "Rezept im Unterordner", folderID: sub.id))
        let direct = try #require(notes.create(text: "Rezept im Tagebuch-Ordner", folderID: journalFolder.id))
        let own = try #require(notes.create(text: "Rezept frei"))
        #expect(!RecipeNoteSource.isOffered(inSub, store: notes))
        #expect(!RecipeNoteSource.isOffered(direct, store: notes))
        #expect(RecipeNoteSource.isOffered(own, store: notes))
    }

    @Test func search_matchesPlainText_notMarkup() throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let notes = NoteStore(context: container.mainContext)
        let reference = MarkdownText.reference(for: UUID(uuidString: "3F2504E0-4F89-41D3-9A0C-0305E82C3301")!, name: "Foto", isImage: true)
        let note = try #require(notes.create(text: "# Urlaub\n**Packliste** <i>Sonnencreme</i> \(reference)"))
        let item = AppEnvironment.searchItem(for: note, folderNames: [:])
        #expect(item.text == "Urlaub\nPackliste Sonnencreme")
        #expect(NoteText.matches(item.text, query: "packliste sonnencreme"))
        #expect(!NoteText.matches(item.text, query: "attachment") && !NoteText.matches(item.text, query: "3F2504E0"))
        // The label of a note in a folder or of a routine note does not change.
        #expect(AppEnvironment.searchItem(for: try #require(notes.create(text: "Traum", kind: .dream, dayKey: "2026-11-18")), folderNames: [:]).kindLabel == "Dream Log")
    }

    @Test func widgetSnapshot_hasNoFieldForNoteText() {
        let entry = SnapshotEntry(id: "e", title: "Termin", start: .now, end: .now, kind: .event, colorHex: nil, isAllDay: false)
        let day = SnapshotDay(day: PlanDay(year: 2026, month: 11, day: 19), entries: [entry], deadlineCount: 0, intake: nil)
        let labels = (Array(Mirror(reflecting: entry).children) + Array(Mirror(reflecting: day).children)).compactMap(\.label)
        #expect(!labels.contains { $0.localizedCaseInsensitiveContains("note") || $0.localizedCaseInsensitiveContains("journal") })
    }

    @Test func suggestions_neverSendAPrivateNote_evenWithConsent() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let notes = NoteStore(context: container.mainContext)
        let settings = try AppSettings.current(in: container.mainContext)
        _ = settings
        let responder = NoteSuggestionResponder()
        let tools = NoteSuggestionTools()
        final class Counter { var models = 0 }
        let counter = Counter()
        let calendar = testCalendar()
        let local = FakeTaskProvider(source: .local, tasks: [])
        let taskList = TaskListModel(providers: [local], now: { testNow() }, calendar: calendar)
        let planStore = PlanStore(context: container.mainContext)
        let calendarStore = FakeCalendarStore()
        let blocks = BlockPlanner(store: calendarStore, planStore: planStore, links: EventLinkStore(context: container.mainContext),
                                  settings: settings, calendar: calendar)
        let planning = PlanningModel(taskList: taskList, calendarStore: calendarStore, reminderStore: FakeAccessStore(), planStore: planStore,
                                     efforts: RecurringEffortStore(context: container.mainContext), blocks: blocks, settings: settings,
                                     marks: EventMarkStore(context: container.mainContext), now: { testNow() }, calendar: calendar)
        let model = NoteSuggestionModel(responder: responder, model: { counter.models += 1; return "gpt-test" }, tools: tools,
                                        describer: ActionCardDescriber(planning: planning), notes: notes, hasConsent: { true },
                                        context: { NoteSuggestionContext(json: "[]", taskIDs: [], eventIDs: [], blockEventIDs: []) })
        let entry = notes.openJournalEntry(dayKey: "2026-11-19", locale: Locale(identifier: "de_DE"))
        // Whatever kind the caller names, the stored kind of the note decides as well.
        await model.fetch(noteID: entry.id, text: "Erfundener Text", kind: .journal)
        await model.fetch(noteID: entry.id, text: "Erfundener Text", kind: .evening)
        let study = notes.openBibleNote(book: BibleBooks.book(number: 45)!, locale: Locale(identifier: "de_DE"))
        await model.fetch(noteID: study.id, text: "Erfundener Text", kind: .free)
        // The dream log never goes to ChatGPT either.
        let dream = try #require(notes.create(text: "Erfundener Traum", kind: .dream, dayKey: "2026-11-19"))
        await model.fetch(noteID: dream.id, text: "Erfundener Traum", kind: .dream)
        await model.fetch(noteID: dream.id, text: "Erfundener Traum", kind: .evening)
        #expect(responder.calls == 0 && counter.models == 0)
        #expect(model.phase == .idle)
    }
}
