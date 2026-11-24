import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// The steps and the list of conflicts of the Notion import. The export files are invented and written to a temporary folder.
@MainActor
struct NotionImportModelTests {
    let container: ModelContainer
    let store: NoteStore
    let calendar: Calendar
    let german = Locale(identifier: "de_DE")

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        let now = testNow()
        store = NoteStore(context: container.mainContext, now: { now })
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        self.calendar = calendar
    }

    private func model(fixedTarget: NotionImportTarget? = nil) -> NotionImportModel {
        NotionImportModel(store: store, calendar: calendar, fixedTarget: fixedTarget)
    }

    /// Writes one journal page per (day title, text) into a new temporary folder and returns it.
    private func exportFolder(_ pages: [(title: String, text: String)]) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("notion-import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (index, page) in pages.enumerated() {
            let id = String(format: "%032x", index + 1)
            let content = "# \(page.title)\n\n🗄️ Resource / FACH: 📓 Mein Tagebuch mit Gott (https://www.notion.so/x-1)\n\n"
                + "## TAGEBUCH\n\n\(page.text)\n"
            try content.write(to: folder.appendingPathComponent("\(page.title) \(id).md"), atomically: true, encoding: .utf8)
        }
        return folder
    }

    private func preview(of model: NotionImportModel) throws -> NotionImportModel.Preview {
        guard case .preview(let preview) = model.phase else { throw PhaseError.notAPreview }
        return preview
    }

    private enum PhaseError: Error { case notAPreview }

    // MARK: Steps (TB4b)

    @Test func fixedTarget_hidesTargetChoice() {
        let open = model()
        #expect(open.showsTargetChoice && open.target == .journal)
        let fixed = model(fixedTarget: .bibleStudy)
        #expect(!fixed.showsTargetChoice && fixed.target == .bibleStudy)
    }

    @Test func step_followsPhase() async throws {
        let folder = try exportFolder([("16.03.2024", "Ruhig.")])
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = model()
        #expect(model.step == .instructions && model.step.rawValue == 1)
        await model.load(folder: folder)
        #expect(model.step == .preview && model.step.rawValue == 2)
        model.runImport()
        #expect(model.step == .result && model.step.rawValue == 3)
        model.reset()
        #expect(model.step == .instructions)

        // An empty folder fails and stays on the first step, with its message.
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent("notion-import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }
        await model.load(folder: empty)
        #expect(model.step == .instructions)
        guard case .failed = model.phase else { Issue.record("expected a failure"); return }
    }

    @Test func importButtonTitle_countsNewAndAppended() {
        func title(new: Int, conflicts: Int, bibleStudy: Bool = false) -> String {
            let counts = NotionImportPreview(newCount: new, conflictCount: conflicts, alreadyImportedCount: 4)
            let payload: NotionImportModel.Payload = bibleStudy ? .bibleStudy([]) : .journal(NotionJournalPlan(entries: [], skipped: []))
            return NotionImportModel.Preview(payload: payload, counts: counts, foundCount: 0, firstDay: nil, lastDay: nil,
                                             leftOutTitles: [], conflicts: []).importButtonTitle
        }
        #expect(title(new: 198, conflicts: 9) == "207 Einträge importieren")
        #expect(title(new: 1, conflicts: 0) == "1 Eintrag importieren")
        #expect(title(new: 0, conflicts: 1) == "1 Eintrag importieren")
        #expect(title(new: 2, conflicts: 1, bibleStudy: true) == "3 Seiten importieren")
        #expect(title(new: 1, conflicts: 0, bibleStudy: true) == "1 Seite importieren")
    }

    // MARK: Conflicts (TB5a)

    @Test func preview_listsConflictsNewestFirst() async throws {
        for (key, text) in [("2024-03-16", "Alt A."), ("2024-03-18", "Alt C.")] {
            store.updateText(store.openJournalEntry(dayKey: key, locale: german).id, text: text)
        }
        let folder = try exportFolder([("16.03.2024", "Notion A."), ("17.03.2024", "Notion B."), ("18.03.2024", "Notion C.")])
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = model()
        await model.load(folder: folder)
        let preview = try preview(of: model)
        #expect(preview.counts.conflictCount == 2 && preview.counts.newCount == 1)
        #expect(preview.conflicts.map(\.day) == [PlanDay(year: 2024, month: 3, day: 18), PlanDay(year: 2024, month: 3, day: 16)])
        #expect(preview.conflicts.map(\.existingExcerpt) == ["Alt C.", "Alt A."])
        #expect(preview.conflicts.map(\.importedExcerpt) == ["Notion C.", "Notion A."])
    }

    @Test func conflict_onlyForDaysWithRealEntry() async throws {
        // 16th: an entry that only holds the template (replaced by the import, so no conflict); 17th: a written entry.
        store.openJournalEntry(dayKey: "2024-03-16", locale: german)
        store.updateText(store.openJournalEntry(dayKey: "2024-03-17", locale: german).id, text: "Heute war gut.")
        let folder = try exportFolder([("16.03.2024", "Notion A."), ("17.03.2024", "Notion B.")])
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = model()
        await model.load(folder: folder)
        let preview = try preview(of: model)
        #expect(preview.conflicts.map(\.day) == [PlanDay(year: 2024, month: 3, day: 17)])
        #expect(preview.counts.conflictCount == 1 && preview.counts.newCount == 1)
    }

    @Test func bibleStudyPreview_hasNoDayConflicts() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("notion-import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let page = "# Römer\n\n🗄️ Resource / FACH: 📚 Bible Studies (https://www.notion.so/x-2)\n\n## NOTIZEN:\n\n3,23: alle haben gesündigt\n"
        try page.write(to: folder.appendingPathComponent("Römer \(String(format: "%032x", 9)).md"), atomically: true, encoding: .utf8)
        let model = model(fixedTarget: .bibleStudy)
        await model.load(folder: folder)
        let preview = try preview(of: model)
        #expect(preview.isBibleStudy && preview.conflicts.isEmpty && preview.counts.newCount == 1)
    }
}
