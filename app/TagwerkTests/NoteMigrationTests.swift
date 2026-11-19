import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// The notes as the app stored them before folders (stage 1 of #152): the same entity name and attributes, without `folderID`,
/// `deletedAt`, `importSourceID` and `bookKey`. Written into a real store file, then opened with the current schema.
enum LegacyNotes {
    @Model
    final class NoteRecord {
        var id: UUID = UUID()
        var text: String = ""
        var createdAt: Date = Date.now
        var updatedAt: Date = Date.now
        var kindRaw: String = "free"
        var dayKey: String? = nil
        var isPinned: Bool = false
        var wasDictated: Bool = false
        var processedAt: Date? = nil
        var derivedActionCount: Int = 0

        init(text: String, kindRaw: String, dayKey: String?, isPinned: Bool, now: Date) {
            self.text = text
            self.kindRaw = kindRaw
            self.dayKey = dayKey
            self.isPinned = isPinned
            self.createdAt = now
            self.updatedAt = now
        }
    }
}

/// Existing user data must survive the new attributes and models of the notes, journal, Bible Study and backup stages.
@MainActor
struct NoteMigrationTests {
    @Test func existingNotes_keepTextKindAndPin_whenTheStoreOpensWithTheNewSchema() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("migration-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tagwerk.store")
        let now = testNow()

        do {
            let legacySchema = Schema([LegacyNotes.NoteRecord.self])
            let legacy = try ModelContainer(for: legacySchema, configurations: ModelConfiguration(schema: legacySchema, url: url))
            let context = legacy.mainContext
            context.insert(LegacyNotes.NoteRecord(text: "Geschenkidee\nBuch", kindRaw: "free", dayKey: nil, isPinned: true, now: now))
            context.insert(LegacyNotes.NoteRecord(text: "Ruhiger Tag", kindRaw: "evening", dayKey: "2026-11-18", isPinned: false, now: now))
            try context.save()
        }

        let schema = ModelContainerFactory.schema
        let current = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
        let notes = try current.mainContext.fetch(FetchDescriptor<NoteRecord>()).sorted { $0.text < $1.text }
        #expect(notes.map(\.text) == ["Geschenkidee\nBuch", "Ruhiger Tag"])
        #expect(notes.map(\.kindRaw) == ["free", "evening"])
        #expect(notes.map(\.isPinned) == [true, false])
        #expect(notes[1].dayKey == "2026-11-18")
        // The new attributes read as their defaults: no folder, not deleted, not imported, no book.
        #expect(notes.allSatisfy { $0.folderID == nil && $0.deletedAt == nil && $0.importSourceID == nil && $0.bookKey == nil })
        // The notes show up where they did before: "Notizen" and "Gedanken".
        let store = NoteStore(context: current.mainContext)
        #expect(store.notes(.own).map(\.text) == ["Geschenkidee\nBuch"] && store.notes(.thoughts).map(\.text) == ["Ruhiger Tag"])
    }
}
