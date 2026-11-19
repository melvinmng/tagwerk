import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct NoteStoreTests {
    final class Clock { var now = testNow() }
    let container: ModelContainer
    let clock = Clock()
    let store: NoteStore

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        let clock = self.clock
        store = NoteStore(context: container.mainContext, now: { clock.now })
    }

    private func advance(_ seconds: TimeInterval = 60) { clock.now = clock.now.addingTimeInterval(seconds) }

    @Test func create_trims_andIgnoresEmpty() throws {
        #expect(store.create(text: "  \n ") == nil)
        #expect(store.count == 0)
        let note = try #require(store.create(text: " a "))
        #expect(note.text == "a" && note.kindRaw == "free" && note.dayKey == nil && !note.wasDictated && !note.isPinned)
        #expect(note.createdAt == clock.now && note.updatedAt == clock.now && note.processedAt == nil)
        #expect(store.count == 1 && store.note(id: note.id)?.text == "a")
        #expect(store.create(text: "diktiert", wasDictated: true)?.wasDictated == true)
    }

    @Test func notes_pinnedFirst_thenByUpdatedAtDescending() throws {
        let a = try #require(store.create(text: "a")); advance()
        let b = try #require(store.create(text: "b")); advance()
        let c = try #require(store.create(text: "c"))
        #expect(store.notes().map(\.text) == ["c", "b", "a"])
        store.setPinned(a.id, true)
        #expect(store.notes().map(\.text) == ["a", "c", "b"])
        #expect(store.latest?.id == c.id)
        _ = b
    }

    @Test func updateText_changesUpdatedAtOnlyForNewText() throws {
        let note = try #require(store.create(text: "a"))
        let created = note.updatedAt
        advance()
        store.updateText(note.id, text: "a")
        #expect(note.updatedAt == created)
        store.updateText(note.id, text: "b")
        #expect(note.text == "b" && note.updatedAt == clock.now && note.createdAt == created)
    }

    @Test func setPinned_keepsUpdatedAt() throws {
        let note = try #require(store.create(text: "a"))
        let created = note.updatedAt
        advance()
        store.setPinned(note.id, true)
        #expect(note.isPinned && note.updatedAt == created)
    }

    @Test func filter_thoughtsAndOwn() throws {
        #expect(!store.hasThoughts)
        let a = try #require(store.create(text: "a")); advance()
        let b = try #require(store.create(text: "b", kind: .morning, dayKey: "2026-11-18")); advance()
        let c = try #require(store.create(text: "c", kind: .evening, dayKey: "2026-11-18"))
        #expect(store.notes(.thoughts).map(\.id) == [c.id, b.id])
        #expect(store.notes(.own).map(\.id) == [a.id])
        #expect(store.notes(.all).count == 3)
        #expect(store.hasThoughts)
        #expect(store.note(kind: .morning, dayKey: "2026-11-18")?.id == b.id)
        #expect(store.note(kind: .morning, dayKey: "2026-11-19") == nil)
    }

    @Test func create_thoughtForSameKindAndDay_updatesExisting() throws {
        let first = try #require(store.create(text: "erst", kind: .evening, dayKey: "2026-11-18"))
        advance()
        let second = try #require(store.create(text: "dann", kind: .evening, dayKey: "2026-11-18"))
        #expect(store.count == 1 && first.id == second.id && second.text == "dann" && second.updatedAt == clock.now)
        _ = store.create(text: "anderer Tag", kind: .evening, dayKey: "2026-11-19")
        _ = store.create(text: "andere Art", kind: .morning, dayKey: "2026-11-18")
        #expect(store.count == 3)
    }

    @Test func markProcessed_andDelete() throws {
        let note = try #require(store.create(text: "a"))
        store.markProcessed(note.id, at: clock.now)
        #expect(note.processedAt == clock.now)
        store.delete(note.id)
        #expect(store.count == 0 && store.note(id: note.id) == nil)
    }

    @Test func deleteIfEmpty_removesOnlyEmptyNotes() throws {
        let kept = try #require(store.create(text: "a"))
        let emptied = try #require(store.create(text: "b"))
        store.updateText(emptied.id, text: "  \n")
        store.deleteIfEmpty(kept.id)
        store.deleteIfEmpty(emptied.id)
        #expect(store.notes().map(\.id) == [kept.id])
    }

    @Test func unknownKindRaw_readsAsFree() throws {
        let note = try #require(store.create(text: "a"))
        note.kindRaw = "weekly"
        #expect(note.kind == .free)
        #expect(store.notes(.own).count == 1 && !store.hasThoughts)
    }

    @Test func writes_bumpRevision() throws {
        let before = store.revision
        let note = try #require(store.create(text: "a"))
        store.setPinned(note.id, true)
        #expect(store.revision == before + 2)
    }

    @Test func schema_containsNoteRecord() {
        #expect(ModelContainerFactory.schema.entities.contains { $0.name == "NoteRecord" })
    }
}
