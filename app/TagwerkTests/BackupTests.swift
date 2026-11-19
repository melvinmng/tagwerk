import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// The data backup (#158). All data is invented.
@MainActor
struct BackupTests {
    final class Clock { var now = testNow() }
    let clock = Clock()
    let calendar = testCalendar()
    let source: ModelContainer
    let sourceSettings: AppSettings
    let backup: BackupService

    init() throws {
        source = try ModelContainerFactory.make(inMemory: true)
        sourceSettings = try AppSettings.current(in: source.mainContext)
        let clock = self.clock
        backup = BackupService(context: source.mainContext, settings: sourceSettings, calendar: calendar, appVersion: "1.0-test",
                               now: { clock.now })
        Self.populate(source.mainContext, settings: sourceSettings, now: clock.now)
    }

    /// A target with its own settings record, as a fresh install has.
    private func makeTarget() throws -> (container: ModelContainer, settings: AppSettings, service: BackupService) {
        let container = try ModelContainerFactory.make(inMemory: true)
        let settings = try AppSettings.current(in: container.mainContext)
        let clock = self.clock
        let service = BackupService(context: container.mainContext, settings: settings, calendar: calendar, appVersion: "1.0-test",
                                    now: { clock.now })
        return (container, settings, service)
    }

    // MARK: Test data

    /// One record of every model in the backup, with values that differ from the defaults.
    static func populate(_ context: ModelContext, settings: AppSettings, now: Date) {
        let day = PlanDay(year: 2026, month: 11, day: 18)
        settings.goalKilocalories = 2100
        settings.bedtimeMinutes = 1320
        settings.selectedCalendarIDs = ["cal-1", "cal-2"]
        settings.shoppingListID = "list-7"
        settings.noteSortOrderRaw = "title"
        settings.aiModelsData = Data("[models]".utf8)
        settings.backupIncludesPrivateNotes = true
        settings.autoBackupEnabled = true
        settings.backupFolderBookmark = Data("bookmark".utf8)

        let task = LocalTask(title: "Quellen sichten", createdAt: now)
        task.notes = "Drei Quellen"
        task.dueYear = 2026; task.dueMonth = 11; task.dueDay = 20
        task.priorityRaw = 2
        task.estimateMinutes = 45
        task.recurrenceData = Data("{\"rule\":1}".utf8)
        context.insert(task)
        context.insert(LocalOccurrenceCompletion(taskID: task.id, completedAt: now, previousDue: DueDate(year: 2026, month: 11, day: 19),
                                                 previousCount: 3, revision: 2))
        let assignment = DayAssignment(taskKey: "local|1", day: day, order: 3, createdAt: now)
        context.insert(assignment)
        context.insert(DayOverrideRecord(day: day, override: .off))
        context.insert(ReminderEstimateRecord(reminderID: "rem-1", minutes: 25))
        context.insert(EventTaskLink(eventKey: "evt-1", taskKey: "local|1", createdAt: now))
        context.insert(RecurringEffortValue(reminderID: "rem-2", from: day, minutes: 30))
        context.insert(RecurringEffortOverride(reminderID: "rem-2", day: day, minutes: 0))
        context.insert(RecurringOccurrenceDone(reminderID: "rem-2", day: day))
        context.insert(DayLunchRecord(day: day, startMinutes: 750, minutes: 45))
        context.insert(EventAvailabilityMark(eventKey: "evt-2", seriesFrom: now, isFree: true))
        context.insert(EventMergeDecision(key: "merge-1", placeholderEventID: "evt-3", ruleTitle: "Vorlesung", ruleCalendarID: "cal-1", isMerged: true))
        let mark = EventDeadlineMark(eventKey: "evt-4", externalID: "ext-4", calendarID: "cal-2", title: "Klausur", start: now, isAllDay: true,
                                     isSeries: false, createdAt: now)
        mark.lastSeen = now
        context.insert(mark)
        context.insert(DeadlineEventLink(deadlineKey: "event:evt-4", eventKey: "evt-5", isSeries: true, externalID: "ext-5", calendarID: "cal-2",
                                         title: "Lernen", start: now, deadlineTitle: "Klausur", until: now.addingTimeInterval(86_400), createdAt: now))
        context.insert(DeadlineSuggestionDismissal(eventKey: "evt-6", start: now))
        let meal = MealRecord(MealValue(id: UUID(), date: now, kind: .lunch, title: "Nudeln", items: [], origin: .manual), estimatedAt: now, healthVersion: 3)
        meal.healthSynced = true
        context.insert(meal)
        context.insert(DrinkRecord(DrinkValue(id: UUID(), date: now, milliliters: 250), healthVersion: 2))
        context.insert(WorkoutRecord(id: UUID(), activity: .running, start: now, minutes: 40, kilocalories: 310.5, healthVersion: 2))
        let category = ShoppingCategory(name: "Backwaren", sortIndex: 4, builtinKey: nil, createdAt: now)
        context.insert(category)
        context.insert(ShoppingAssignment(nameKey: "brot", categoryID: category.id, sourceRaw: "manual", updatedAt: now))

        let folder = NoteFolderRecord(name: "Studium", parentID: nil, order: 2, now: now)
        context.insert(folder)
        let own = NoteRecord(text: "Geschenkidee\nBuch", wasDictated: true, now: now)
        own.folderID = folder.id
        own.isPinned = true
        own.processedAt = now
        own.derivedActionCount = 2
        context.insert(own)
        let thought = NoteRecord(text: "Ruhiger Tag", kind: .evening, dayKey: "2026-11-18", now: now)
        context.insert(thought)
        let trashed = NoteRecord(text: "Alt", now: now)
        trashed.deletedAt = now
        trashed.importSourceID = "abc"
        context.insert(trashed)
        let journalFolder = NoteFolderRecord(name: "Tagebuch mit Gott", role: .journal, now: now)
        context.insert(journalFolder)
        let journal = NoteRecord(text: "Allgemeine Stimmung\nDankbar", kind: .journal, dayKey: "2026-11-18", now: now)
        journal.folderID = journalFolder.id
        context.insert(journal)
        let bibleFolder = NoteFolderRecord(name: "Bible Study", role: .bibleStudy, now: now)
        context.insert(bibleFolder)
        let bibleNote = NoteRecord(text: "Römer\n\nNotizen", kind: .bibleStudy, now: now)
        bibleNote.folderID = bibleFolder.id
        bibleNote.bookKey = "45"
        context.insert(bibleNote)
        let session = BibleStudySessionRecord(dayKey: "2026-11-18", book: "45", passage: "3,21-31", noteID: bibleNote.id, startedAt: now)
        session.completedAt = now
        context.insert(session)

        let habit = Habit(name: "Lesen", symbol: "book", order: 1, source: .journal, daysPerWeek: 5, daylightMinutes: 30, start: day,
                          pausedSince: nil, pauses: [HabitPause(from: day, to: day.adding(days: 2, calendar: testCalendar()))])
        context.insert(HabitRecord(habit, createdAt: now))
        context.insert(HabitCheckRecord(habitID: habit.id, day: day, checkedAt: now))
        let routineDay = RoutineDayRecord(day: day)
        routineDay.gratitudeData = Data("[\"Sonne\"]".utf8)
        routineDay.startCompletedAt = now
        routineDay.startDismissed = true
        routineDay.closeCompletedAt = now
        routineDay.checkedItemIDsData = Data("[]".utf8)
        context.insert(routineDay)
        context.insert(EveningChecklistItemRecord(ChecklistItem(title: "Handy weglegen", order: 2, offsetMinutes: 60), createdAt: now))
        let focus = FocusMarkRecord(taskKey: "local|1", title: "Quellen sichten", day: day, order: 1, createdAt: now)
        focus.doneAt = now
        context.insert(focus)
        let reflection = WeekReflectionRecord(weekStart: day, updatedAt: now)
        reflection.wentWell = "Viel geschafft"
        reflection.burdens = "Wenig Schlaf"
        reflection.plannedHabits = true
        context.insert(reflection)
        try? context.save()
    }

    // MARK: Helpers

    /// Each list of a `BackupEntities` as a set of its JSON texts, so the comparison ignores the order of a fetch.
    private func canonical(_ entities: BackupEntities) throws -> [String: Set<String>] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var result: [String: Set<String>] = [:]
        for child in Mirror(reflecting: entities).children {
            guard let label = child.label else { continue }
            if let settings = child.value as? AppSettingsBackup? {
                result[label] = settings.map { [String(decoding: (try? encoder.encode($0)) ?? Data(), as: UTF8.self)] } ?? []
            } else if let list = child.value as? [any BackupEntity] {
                result[label] = Set(try list.map { String(decoding: try encoder.encode($0), as: UTF8.self) })
            }
        }
        return result
    }

    private func entities(of context: ModelContext, settings: AppSettings, includePrivate: Bool = true) -> BackupEntities {
        BackupEntities(collecting: context, settings: settings, includePrivate: includePrivate)
    }

    // MARK: Completeness

    @Test func everyModelOfTheSchema_isInTheBackupOrExcludedWithAReason() {
        let schemaNames = Set(ModelContainerFactory.schema.entities.map(\.name))
        let included = BackupEntities.modelNames
        let excluded = Set(BackupCoverage.excluded.keys)
        #expect(included.isDisjoint(with: excluded), "a model cannot be both in the backup and excluded")
        let undecided = schemaNames.subtracting(included).subtracting(excluded)
        #expect(undecided.isEmpty, "models without a backup decision: \(undecided.sorted())")
        let unknown = included.union(excluded).subtracting(schemaNames)
        #expect(unknown.isEmpty, "backup or exclusion entries for models that are not in the schema: \(unknown.sorted())")
        #expect(BackupCoverage.excluded.values.allSatisfy { !$0.isEmpty })
    }

    @Test func theTestData_holdsARecordOfEveryModelInTheBackup() {
        var counts: [String: Int] = [:]
        for child in Mirror(reflecting: entities(of: source.mainContext, settings: sourceSettings)).children {
            if let list = child.value as? [any BackupEntity], let first = list.first { counts[type(of: first).modelName, default: 0] += list.count }
        }
        let missing = BackupEntities.modelNames.subtracting(counts.keys).subtracting(["AppSettings"])
        #expect(missing.isEmpty, "no test record for: \(missing.sorted())")
    }

    // MARK: Round trip

    @Test func roundTrip_everyModelSurvivesExportAndImport() throws {
        let data = try backup.makeBackupData()
        let target = try makeTarget()
        let inspection = try target.service.inspect(data)
        target.service.restore(inspection)
        let before = try canonical(entities(of: source.mainContext, settings: sourceSettings))
        let after = try canonical(entities(of: target.container.mainContext, settings: target.settings))
        for key in before.keys.sorted() { #expect(before[key] == after[key], "\(key) differs after the round trip") }
        #expect(before.values.contains { !$0.isEmpty })
    }

    @Test func roundTrip_survivesAFileOnDiskAndASecondRestore() throws {
        let data = try backup.makeBackupData()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let target = try makeTarget()
        let reloaded = try Data(contentsOf: url)
        target.service.restore(try target.service.inspect(reloaded))
        // Restoring the same file again replaces, it does not duplicate.
        target.service.restore(try target.service.inspect(reloaded))
        let counts = entities(of: target.container.mainContext, settings: target.settings)
        #expect(counts.localTasks.count == 1 && counts.notes.count == 5 && counts.habits.count == 1 && counts.noteFolders.count == 3)
    }

    @Test func settings_areAppliedInPlace_withoutDeviceBoundValues() throws {
        let target = try makeTarget()
        target.settings.aiModelsData = Data("[local models]".utf8)
        target.settings.backupFolderBookmark = Data("local bookmark".utf8)
        target.settings.autoBackupEnabled = false
        let record = target.settings
        target.service.restore(try target.service.inspect(try backup.makeBackupData()))
        #expect(target.settings === record, "the settings record must stay the same instance")
        #expect(record.goalKilocalories == 2100 && record.bedtimeMinutes == 1320 && record.selectedCalendarIDs == ["cal-1", "cal-2"])
        #expect(record.shoppingListID == "list-7" && record.noteSortOrderRaw == "title")
        // The cache and everything tied to this device stay as they were.
        #expect(record.aiModelsData == Data("[local models]".utf8))
        #expect(record.backupFolderBookmark == Data("local bookmark".utf8) && record.autoBackupEnabled == false)
    }

    @Test func restore_replacesWhatIsInTheFile_andKeepsWhatIsNot() throws {
        let target = try makeTarget()
        let context = target.container.mainContext
        context.insert(LocalTask(title: "Nur auf dem Ziel", createdAt: clock.now))
        context.insert(CachedGitHubIssue(issueID: "i-1", payload: Data(), fetchedAt: clock.now))
        try context.save()
        target.service.restore(try target.service.inspect(try backup.makeBackupData()))
        let titles = try context.fetch(FetchDescriptor<LocalTask>()).map(\.title)
        #expect(titles == ["Quellen sichten"])
        // Models that are not in the backup are not touched.
        #expect(try context.fetchCount(FetchDescriptor<CachedGitHubIssue>()) == 1)
    }

    // MARK: Safety rules

    @Test func theFile_holdsNoSecrets() throws {
        let text = String(decoding: try backup.makeBackupData(), as: UTF8.self)
        for forbidden in ["github.credentials", "chatgpt.tokens", "chatgpt.client-id", "chatgpt.host-id", "accessToken", "access_token",
                          "refreshToken", "refresh_token", "idToken", "Bearer ", "apiKey", "client_secret"] {
            #expect(!text.contains(forbidden), "the backup mentions \(forbidden)")
        }
        // The Keychain accounts are the only places for secrets; none of their names is in the code that writes the file.
        #expect(KeychainChatGPTCredentialStore.tokensAccount == "chatgpt.tokens" && KeychainCredentialStore.account == "github.credentials")
        #expect(text.contains("\"format\" : \"tagwerk-backup\"") && text.contains("\"schemaVersion\" : 1"))
    }

    @Test func aHigherVersion_isRefused_andNothingChanges() throws {
        var object = try #require(try JSONSerialization.jsonObject(with: try backup.makeBackupData()) as? [String: Any])
        object["schemaVersion"] = BackupRules.schemaVersion + 1
        let data = try JSONSerialization.data(withJSONObject: object)
        let target = try makeTarget()
        #expect(throws: BackupService.BackupError.newerVersion(BackupRules.schemaVersion + 1)) { try target.service.inspect(data) }
        #expect(try target.container.mainContext.fetchCount(FetchDescriptor<LocalTask>()) == 0)
    }

    @Test func otherFiles_areRefused() throws {
        let target = try makeTarget()
        #expect(throws: BackupService.BackupError.notABackup) { try target.service.inspect(Data("not json".utf8)) }
        #expect(throws: BackupService.BackupError.notABackup) { try target.service.inspect(Data("{\"format\":\"other\",\"schemaVersion\":1}".utf8)) }
        let broken = Data("{\"format\":\"tagwerk-backup\",\"schemaVersion\":1,\"appVersion\":\"1\",\"createdAt\":\"x\",\"includesPrivateNotes\":true,\"entities\":{\"localTasks\":5}}".utf8)
        #expect(throws: BackupService.BackupError.unreadable) { try target.service.inspect(broken) }
    }

    @Test func aFileWithoutSomeLists_readsThemAsEmpty() throws {
        let minimal = Data("{\"format\":\"tagwerk-backup\",\"schemaVersion\":1,\"appVersion\":\"1\",\"createdAt\":\"x\",\"includesPrivateNotes\":true,\"entities\":{}}".utf8)
        let inspection = try makeTarget().service.inspect(minimal)
        #expect(inspection.entities.localTasks.isEmpty && inspection.entities.notes.isEmpty && inspection.entities.settings == nil)
    }

    // MARK: Journal and Bible Study

    @Test func withoutThePrivateSwitch_noJournalOrBibleStudyContentIsWritten() throws {
        let data = try backup.makeBackupData(includePrivate: false)
        let inspection = try makeTarget().service.inspect(data)
        #expect(!inspection.header.includesPrivateNotes)
        let kinds = Set(inspection.entities.notes.map(\.kindRaw))
        #expect(kinds == ["free", "evening"])
        #expect(inspection.entities.noteFolders.map(\.name) == ["Studium"])
        #expect(inspection.entities.bibleStudySessions.isEmpty)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("Dankbar") && !text.contains("3,21-31") && !text.contains("Allgemeine Stimmung"))
    }

    @Test func restoringAFileWithoutPrivateContent_keepsTheExistingJournalAndBibleStudy() throws {
        let target = try makeTarget()
        let context = target.container.mainContext
        let folder = NoteFolderRecord(name: "Tagebuch mit Gott", role: .journal, now: clock.now)
        context.insert(folder)
        let entry = NoteRecord(text: "Mein Eintrag", kind: .journal, dayKey: "2026-11-01", now: clock.now)
        entry.folderID = folder.id
        context.insert(entry)
        context.insert(BibleStudySessionRecord(dayKey: "2026-11-01", book: "43", passage: "1", noteID: entry.id, startedAt: clock.now))
        context.insert(NoteRecord(text: "Normale Notiz, wird ersetzt", now: clock.now))
        try context.save()
        target.service.restore(try target.service.inspect(try backup.makeBackupData(includePrivate: false)))
        let notes = try context.fetch(FetchDescriptor<NoteRecord>())
        #expect(notes.contains { $0.text == "Mein Eintrag" } && !notes.contains { $0.text.hasPrefix("Normale Notiz") })
        #expect(try context.fetchCount(FetchDescriptor<BibleStudySessionRecord>()) == 1)
        #expect(try context.fetch(FetchDescriptor<NoteFolderRecord>()).contains { $0.role == .journal })
    }

    @Test func restoringAFileWithPrivateContent_replacesTheExistingJournal() throws {
        let target = try makeTarget()
        let context = target.container.mainContext
        context.insert(NoteRecord(text: "Alter Eintrag", kind: .journal, dayKey: "2026-11-01", now: clock.now))
        try context.save()
        target.service.restore(try target.service.inspect(try backup.makeBackupData(includePrivate: true)))
        let journal = try context.fetch(FetchDescriptor<NoteRecord>()).filter { $0.kind == .journal }
        #expect(journal.map(\.text) == ["Allgemeine Stimmung\nDankbar"])
    }

    // MARK: Safety copy and automatic backup

    @Test func safetyCopy_holdsEverything_andIsNotAnOwnFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        sourceSettings.backupIncludesPrivateNotes = false
        let url = try backup.writeSafetyCopy(into: directory)
        #expect(!BackupRules.isOwnFile(url.lastPathComponent))
        let inspection = try makeTarget().service.inspect(try Data(contentsOf: url))
        #expect(inspection.header.includesPrivateNotes && inspection.entities.bibleStudySessions.count == 1)
    }

    private func makeFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("backup-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func automaticBackup_writesWhenDue_andOnceADay() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        sourceSettings.autoBackupEnabled = false
        #expect(backup.runAutomaticBackupIfDue() == .disabled)
        sourceSettings.autoBackupEnabled = true
        try backup.chooseFolder(folder)
        let name = BackupRules.fileName(for: clock.now, calendar: calendar)
        #expect(backup.runAutomaticBackupIfDue() == .written(name))
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path))
        #expect(sourceSettings.lastAutoBackupAt == clock.now && sourceSettings.lastBackupError == nil)
        clock.now = clock.now.addingTimeInterval(3600)
        #expect(backup.runAutomaticBackupIfDue() == .notDue)
        clock.now = clock.now.addingTimeInterval(86_400)
        #expect(backup.runAutomaticBackupIfDue() != .notDue)
        #expect(backup.folderName == folder.lastPathComponent)
    }

    @Test func automaticBackup_keepsSevenOwnFiles_andNeverTouchesOthers() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        for day in 1...9 {
            try Data("old".utf8).write(to: folder.appendingPathComponent(String(format: "Tagwerk-Sicherung-2026-10-%02d-0800.json", day)))
        }
        for foreign in ["Notizen.txt", "Tagwerk-Sicherung-2026-10-01-0800.json.bak", "Tagwerk-Vor-Wiederherstellung-2026-10-01-0800.json"] {
            try Data("keep".utf8).write(to: folder.appendingPathComponent(foreign))
        }
        sourceSettings.autoBackupEnabled = true
        try backup.chooseFolder(folder)
        backup.runAutomaticBackup()
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(names.filter(BackupRules.isOwnFile).count == BackupRules.keptFiles)
        #expect(names.contains("Notizen.txt") && names.contains("Tagwerk-Sicherung-2026-10-01-0800.json.bak")
                && names.contains("Tagwerk-Vor-Wiederherstellung-2026-10-01-0800.json"))
        #expect(names.contains(BackupRules.fileName(for: clock.now, calendar: calendar)) && !names.contains("Tagwerk-Sicherung-2026-10-01-0800.json"))
    }

    @Test func automaticBackup_reportsAMissingOrBrokenFolder_withoutThrowing() throws {
        sourceSettings.autoBackupEnabled = true
        sourceSettings.backupFolderBookmark = nil
        #expect(backup.runAutomaticBackupIfDue() == .failed(.noFolder))
        #expect(sourceSettings.lastBackupError == BackupService.message(for: .noFolder))
        sourceSettings.backupFolderBookmark = Data("not a bookmark".utf8)
        #expect(backup.runAutomaticBackupIfDue() == .failed(.folderUnavailable))
        #expect(sourceSettings.lastAutoBackupAt == nil)
        // A folder that went away after it was chosen.
        let folder = try makeFolder()
        try backup.chooseFolder(folder)
        try FileManager.default.removeItem(at: folder)
        #expect(backup.runAutomaticBackupIfDue() != .written(""))
        #expect(sourceSettings.lastBackupError != nil)
        backup.clearFolder()
        #expect(sourceSettings.backupFolderBookmark == nil && sourceSettings.lastBackupError == nil)
    }
}
