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
    let sourceFiles: NoteAttachmentStore
    let sourceDirectory = FileManager.default.temporaryDirectory.appending(path: "backup-source-" + UUID().uuidString, directoryHint: .isDirectory)

    init() throws {
        source = try ModelContainerFactory.make(inMemory: true)
        sourceSettings = try AppSettings.current(in: source.mainContext)
        let clock = self.clock
        sourceFiles = NoteAttachmentStore(context: source.mainContext, directory: sourceDirectory, now: { clock.now })
        backup = BackupService(context: source.mainContext, settings: sourceSettings, calendar: calendar, appVersion: "1.0-test",
                               now: { clock.now }, attachments: sourceFiles)
        Self.populate(source.mainContext, settings: sourceSettings, now: clock.now)
        Self.addAttachments(sourceFiles, context: source.mainContext)
    }

    /// A target with its own settings record, as a fresh install has.
    private func makeTarget() throws -> (container: ModelContainer, settings: AppSettings, service: BackupService, files: NoteAttachmentStore) {
        let container = try ModelContainerFactory.make(inMemory: true)
        let settings = try AppSettings.current(in: container.mainContext)
        let clock = self.clock
        let directory = FileManager.default.temporaryDirectory.appending(path: "backup-target-" + UUID().uuidString, directoryHint: .isDirectory)
        let files = NoteAttachmentStore(context: container.mainContext, directory: directory, now: { clock.now })
        let service = BackupService(context: container.mainContext, settings: settings, calendar: calendar, appVersion: "1.0-test",
                                    now: { clock.now }, attachments: files)
        return (container, settings, service, files)
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
        context.insert(EventTravelOverride(TravelOverride(eventKey: "evt-2", seriesFrom: now, mode: .fixed(minutes: 35))))
        context.insert(EventMergeDecision(key: "merge-1", placeholderEventID: "evt-3", ruleTitle: "Vorlesung", ruleCalendarID: "cal-1", isMerged: true))
        let mark = EventDeadlineMark(eventKey: "evt-4", externalID: "ext-4", calendarID: "cal-2", title: "Klausur", start: now, isAllDay: true,
                                     isSeries: false, createdAt: now)
        mark.lastSeen = now
        context.insert(mark)
        context.insert(DeadlineEventLink(deadlineKey: "event:evt-4", eventKey: "evt-5", isSeries: true, externalID: "ext-5", calendarID: "cal-2",
                                         title: "Lernen", start: now, deadlineTitle: "Klausur", until: now.addingTimeInterval(86_400), createdAt: now))
        context.insert(DeadlineSuggestionDismissal(eventKey: "evt-6", start: now))
        context.insert(ReminderOverrideRecord(ReminderOverride(itemKey: "deadline:evt-4", scope: .seriesFrom(day), storage: .tagwerk,
                                                               offsets: [.before(amount: 2, unit: .days)]), updatedAt: now))
        settings.reminderDefaultsData = ReminderDefaults.legacy(leadTimeMinutes: 90).encoded()
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
        let eveningFolder = NoteFolderRecord(name: "Tagesabschluss", order: 4, role: .eveningRoutine, now: now)
        context.insert(eveningFolder)
        let thought = NoteRecord(text: "Ruhiger Tag", kind: .evening, dayKey: "2026-11-18", now: now)
        thought.folderID = eveningFolder.id
        context.insert(thought)
        let brainDumpFolder = NoteFolderRecord(name: "Brain Dump", order: 3, role: .brainDump, now: now)
        context.insert(brainDumpFolder)
        let brainDumpNote = NoteRecord(text: "Kopf leeren", now: now)
        brainDumpNote.folderID = brainDumpFolder.id
        context.insert(brainDumpNote)
        let dreamFolder = NoteFolderRecord(name: "Dream Log", order: 5, role: .dreamLog, now: now)
        context.insert(dreamFolder)
        let dream = NoteRecord(text: "Traum vom Meer", kind: .dream, dayKey: "2026-11-18", now: now)
        dream.folderID = dreamFolder.id
        context.insert(dream)
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
        let focusState = FocusTimerState(start: now, settings: FocusTimerSettings(), pauses: [DateInterval(start: now.addingTimeInterval(600), duration: 120)],
                                         skips: [now.addingTimeInterval(1500)], endedAt: now.addingTimeInterval(1800))
        let focusSession = FocusSessionRecord(taskKey: "local|1", blockEventID: "evt-7", title: "Quellen sichten", state: focusState)
        focusSession.outcome = .completed
        focusSession.focusedSeconds = 1500
        focusSession.activityID = "activity-1"
        context.insert(focusSession)
        let effort = EffortSampleRecord(taskKey: "local|1", source: .local, labels: ["Studium"], estimateMinutes: 45, actualMinutes: 38,
                                        method: .partialBlock, completedAt: now)
        effort.trimmedEventID = "evt-7"
        effort.trimmedOriginalEnd = now.addingTimeInterval(3600)
        effort.trimmedNewEnd = now.addingTimeInterval(2400)
        context.insert(effort)
        settings.focusWorkMinutes = 50
        settings.focusShortBreakMinutes = 10
        settings.focusLongBreakMinutes = 30
        settings.focusRounds = 3
        settings.focusUsesPomodoro = false
        settings.effortHistoryInPlanning = false
        let reflection = WeekReflectionRecord(weekStart: day, updatedAt: now)
        reflection.wentWell = "Viel geschafft"
        reflection.burdens = "Wenig Schlaf"
        reflection.plannedHabits = true
        reflection.goalsProgress = "Projekt läuft"
        reflection.gratitudeTaken = true
        context.insert(reflection)
        try? context.save()
    }

    /// One attachment of an own note and one of the journal entry, so the backup has to tell them apart.
    static func addAttachments(_ files: NoteAttachmentStore, context: ModelContext) {
        let notes = (try? context.fetch(FetchDescriptor<NoteRecord>())) ?? []
        let folder = FileManager.default.temporaryDirectory.appending(path: "backup-files-" + UUID().uuidString, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (text, name, bytes) in [("Geschenkidee\nBuch", "Plan.pdf", 1500), ("Allgemeine Stimmung\nDankbar", "Gebet.pdf", 900)] {
            // A different byte pattern per file, so one file's base64 is never a part of the other's.
            let factor = name == "Plan.pdf" ? 1 : 7
            guard let note = notes.first(where: { $0.text == text }) else { continue }
            let url = folder.appending(path: name)
            try? Data((0..<bytes).map { UInt8(($0 * factor + 3) % 251) }).write(to: url)
            _ = try? files.addFile(at: url, to: note.id)
            note.text += "\n" + (files.attachments(of: note.id).last.map { MarkdownText.reference(for: $0.id, name: name, isImage: false) } ?? "")
        }
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

    private func entities(of context: ModelContext, settings: AppSettings, includePrivate: Bool = true,
                          attachments: NoteAttachmentStore? = nil) -> BackupEntities {
        BackupEntities(collecting: context, settings: settings, includePrivate: includePrivate, attachments: attachments)
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

    @Test func settingsBackup_roundTripsWeekPlanningReminder() throws {
        sourceSettings.weekPlanningReminderEnabled = true
        sourceSettings.weekPlanningReminderWeekday = 6
        sourceSettings.weekPlanningReminderMinutes = 1140
        let data = try JSONEncoder().encode(AppSettingsBackup(sourceSettings))
        let decoded = try JSONDecoder().decode(AppSettingsBackup.self, from: data)
        let target = try makeTarget()
        decoded.apply(to: target.settings)
        #expect(target.settings.weekPlanningReminderEnabled)
        #expect(target.settings.weekPlanningReminderWeekday == 6 && target.settings.weekPlanningReminderMinutes == 1140)
        // An older backup without the three fields keeps the defaults of the target.
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["weekPlanningReminderEnabled", "weekPlanningReminderWeekday", "weekPlanningReminderMinutes"] { object[key] = nil }
        let older = try JSONDecoder().decode(AppSettingsBackup.self, from: JSONSerialization.data(withJSONObject: object))
        let fresh = try makeTarget()
        older.apply(to: fresh.settings)
        #expect(!fresh.settings.weekPlanningReminderEnabled)
        #expect(fresh.settings.weekPlanningReminderWeekday == 1 && fresh.settings.weekPlanningReminderMinutes == 1080)
    }

    @Test func weekReflectionBackup_roundTripsNewFields() throws {
        let record = WeekReflectionRecord(weekStart: PlanDay(year: 2026, month: 11, day: 16), updatedAt: clock.now)
        record.goalsProgress = "Projekt läuft"
        record.gratitudeTaken = true
        let decoded = try JSONDecoder().decode(WeekReflectionBackup.self, from: JSONEncoder().encode(WeekReflectionBackup(record)))
        let restored = decoded.makeRecord()
        #expect(restored.goalsProgress == "Projekt läuft" && restored.gratitudeTaken)
    }

    @Test func weekReflectionBackup_decodesAnOlderBackupWithoutNewFields() throws {
        let json = """
        {"weekKey":"2026-11-16","wentWell":"Viel geschafft","burdens":"Wenig Schlaf","plannedAppointments":true,
         "plannedHabits":true,"plannedTasks":false,"updatedAt":0}
        """
        let decoder = JSONDecoder()
        let backup = try decoder.decode(WeekReflectionBackup.self, from: Data(json.utf8))
        let record = backup.makeRecord()
        #expect(record.wentWell == "Viel geschafft" && record.goalsProgress.isEmpty && !record.gratitudeTaken)
        #expect(record.value.calendarPlanned)
    }

    @Test func theTestData_holdsARecordOfEveryModelInTheBackup() {
        var counts: [String: Int] = [:]
        for child in Mirror(reflecting: entities(of: source.mainContext, settings: sourceSettings, attachments: sourceFiles)).children {
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
        try target.service.restore(inspection)
        let before = try canonical(entities(of: source.mainContext, settings: sourceSettings, attachments: sourceFiles))
        let after = try canonical(entities(of: target.container.mainContext, settings: target.settings, attachments: target.files))
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
        try target.service.restore(try target.service.inspect(reloaded))
        // Restoring the same file again replaces, it does not duplicate.
        try target.service.restore(try target.service.inspect(reloaded))
        let counts = entities(of: target.container.mainContext, settings: target.settings)
        #expect(counts.localTasks.count == 1 && counts.notes.count == 7 && counts.habits.count == 1 && counts.noteFolders.count == 6)
    }

    @Test func settings_areAppliedInPlace_withoutDeviceBoundValues() throws {
        let target = try makeTarget()
        target.settings.aiModelsData = Data("[local models]".utf8)
        target.settings.backupFolderBookmark = Data("local bookmark".utf8)
        target.settings.autoBackupEnabled = false
        let record = target.settings
        try target.service.restore(try target.service.inspect(try backup.makeBackupData()))
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
        try target.service.restore(try target.service.inspect(try backup.makeBackupData()))
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
        #expect(text.contains("\"format\" : \"tagwerk-backup\"") && text.contains("\"schemaVersion\" : 2"))
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

    @Test func backup_roundTripsReminderDefaultsAndOverrides() throws {
        let data = try backup.makeBackupData()
        let target = try makeTarget()
        try target.service.restore(try target.service.inspect(data))
        #expect(target.settings.reminderDefaultsData == ReminderDefaults.legacy(leadTimeMinutes: 90).encoded())
        let records = try target.container.mainContext.fetch(FetchDescriptor<ReminderOverrideRecord>())
        let override = try #require(records.first?.override)
        #expect(records.count == 1)
        #expect(override.itemKey == "deadline:evt-4")
        #expect(override.scope == .seriesFrom(PlanDay(year: 2026, month: 11, day: 18)))
        #expect(override.offsets == [.before(amount: 2, unit: .days)])
    }

    /// A backup from before every task source got its own default list holds one list "task"; it applies to all three.
    @Test func backupWithFormerTaskDefaults_restoresToEveryTaskKind() throws {
        let data = try backup.makeBackupData()
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var entities = try #require(object["entities"] as? [String: Any])
        var settings = try #require(entities["settings"] as? [String: Any])
        var former = ReminderDefaults()
        former.set([.before(amount: 3, unit: .hours)], for: .localTask, isAllDay: false)
        let formerJSON = String(decoding: former.encoded(), as: UTF8.self).replacingOccurrences(of: "\"localTask\"", with: "\"task\"")
        #expect(formerJSON.contains("\"task\""))
        settings["reminderDefaultsData"] = Data(formerJSON.utf8).base64EncodedString()
        entities["settings"] = settings
        object["entities"] = entities
        let old = try JSONSerialization.data(withJSONObject: object)
        let target = try makeTarget()
        try target.service.restore(try target.service.inspect(old))
        for kind in [ReminderKind.localTask, .githubIssue, .appleReminder] {
            #expect(target.settings.reminderDefaults.offsets(for: kind, isAllDay: false) == [.before(amount: 3, unit: .hours)])
        }
    }

    @Test func oldBackupWithoutReminderFields_restores() throws {
        let data = try backup.makeBackupData()
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var entities = try #require(object["entities"] as? [String: Any])
        entities.removeValue(forKey: "reminderOverrides")
        var settings = try #require(entities["settings"] as? [String: Any])
        settings.removeValue(forKey: "reminderDefaultsData")
        entities["settings"] = settings
        object["entities"] = entities
        let old = try JSONSerialization.data(withJSONObject: object)
        let target = try makeTarget()
        target.settings.reminderDefaultsData = ReminderDefaults.legacy(leadTimeMinutes: 30).encoded()
        try target.service.restore(try target.service.inspect(old))
        #expect(try target.container.mainContext.fetchCount(FetchDescriptor<ReminderOverrideRecord>()) == 0)
        // The file knows nothing of reminder defaults, so they fall back to the ones derived from the lead time.
        #expect(target.settings.reminderDefaultsData == nil)
        #expect(target.settings.reminderDefaults == .legacy(leadTimeMinutes: target.settings.leadTimeMinutes))
    }

    // MARK: Manual travel time (F2)

    @Test func backup_roundTripsManualTravelTimes() throws {
        let context = source.mainContext
        context.insert(EventTravelOverride(TravelOverride(eventKey: "evt-8|1800000000", seriesFrom: nil, mode: .none)))
        context.insert(EventTravelOverride(TravelOverride(eventKey: "evt-9", seriesFrom: nil, mode: .automatic)))
        try context.save()
        let target = try makeTarget()
        try target.service.restore(try target.service.inspect(try backup.makeBackupData()))
        let restored = try target.container.mainContext.fetch(FetchDescriptor<EventTravelOverride>()).map(\.asOverride)
        #expect(Set(restored.map(\.mode)) == [.fixed(minutes: 35), .none, .automatic])
        #expect(restored.contains { $0.eventKey == "evt-2" && $0.seriesFrom != nil && $0.mode == .fixed(minutes: 35) })
        #expect(restored.contains { $0.eventKey == "evt-8|1800000000" && $0.seriesFrom == nil && $0.mode == .none })
    }

    @Test func oldBackupWithoutManualTravelTimes_restores() throws {
        let data = try backup.makeBackupData()
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var entities = try #require(object["entities"] as? [String: Any])
        entities.removeValue(forKey: "eventTravelOverrides")
        object["entities"] = entities
        let old = try JSONSerialization.data(withJSONObject: object)
        let target = try makeTarget()
        target.container.mainContext.insert(EventTravelOverride(TravelOverride(eventKey: "left-over", seriesFrom: nil, mode: .none)))
        try target.container.mainContext.save()
        try target.service.restore(try target.service.inspect(old))
        // The file stands for the state it was written in, which had no manual travel times.
        #expect(try target.container.mainContext.fetchCount(FetchDescriptor<EventTravelOverride>()) == 0)
        #expect(try target.container.mainContext.fetchCount(FetchDescriptor<EventAvailabilityMark>()) == 1)
    }

    // MARK: Focus timer data

    @Test func backup_roundTripsFocusSessionsEffortSamplesAndSettings() throws {
        let target = try makeTarget()
        try target.service.restore(try target.service.inspect(try backup.makeBackupData()))
        let context = target.container.mainContext
        let session = try #require(try context.fetch(FetchDescriptor<FocusSessionRecord>()).first)
        #expect(session.outcome == .completed && session.focusedSeconds == 1500 && session.taskKey == "local|1" && session.blockEventID == "evt-7")
        #expect(session.state.pauses.count == 1 && session.state.skips.count == 1 && session.endedAt == clock.now.addingTimeInterval(1800))
        #expect(session.activityID == nil, "the Live Activity belongs to this device and is not restored")
        #expect(session.piece != nil)
        let sample = try #require(try context.fetch(FetchDescriptor<EffortSampleRecord>()).first)
        #expect(sample.actualMinutes == 38 && sample.estimateMinutes == 45 && sample.methodRaw == EffortMethod.partialBlock.rawValue && sample.value.labels == ["Studium"])
        #expect(sample.trimmedEventID == "evt-7" && sample.trimmedNewEnd == clock.now.addingTimeInterval(2400))
        #expect(target.settings.focusWorkMinutes == 50 && target.settings.focusRounds == 3 && !target.settings.focusUsesPomodoro)
        #expect(!target.settings.effortHistoryInPlanning)
    }

    @Test func aRunningFocusSession_isNotBackedUp_andSurvivesARestore() throws {
        let running = FocusSessionRecord(taskKey: "local|2", blockEventID: nil, title: "Läuft", state: FocusTimerState(start: clock.now, settings: FocusTimerSettings()))
        source.mainContext.insert(running)
        try source.mainContext.save()
        let data = try backup.makeBackupData()
        let inspection = try makeTarget().service.inspect(data)
        #expect(inspection.entities.focusSessions?.count == 1, "only the closed session is written")
        // On a device with its own running session and an older closed one, only the closed one is replaced.
        let target = try makeTarget()
        let context = target.container.mainContext
        let local = FocusSessionRecord(taskKey: "local|3", blockEventID: nil, title: "Hier", state: FocusTimerState(start: clock.now, settings: FocusTimerSettings()))
        context.insert(local)
        let oldClosed = FocusSessionRecord(taskKey: "local|4", blockEventID: nil, title: "Alt", state: FocusTimerState(start: clock.now, settings: FocusTimerSettings()))
        oldClosed.outcome = .aborted
        context.insert(oldClosed)
        try context.save()
        try target.service.restore(inspection)
        let titles = try context.fetch(FetchDescriptor<FocusSessionRecord>()).map(\.title).sorted()
        #expect(titles == ["Hier", "Quellen sichten"])
        #expect(local.isRunning && !local.isDeleted)
    }

    @Test func oldBackupWithoutFocusData_restores_andKeepsTheFocusDataOfTheDevice() throws {
        let data = try backup.makeBackupData()
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var entities = try #require(object["entities"] as? [String: Any])
        entities.removeValue(forKey: "focusSessions")
        entities.removeValue(forKey: "effortSamples")
        var settings = try #require(entities["settings"] as? [String: Any])
        for key in ["focusWorkMinutes", "focusShortBreakMinutes", "focusLongBreakMinutes", "focusRounds", "focusUsesPomodoro", "effortHistoryInPlanning"] {
            settings.removeValue(forKey: key)
        }
        entities["settings"] = settings
        object["entities"] = entities
        let old = try JSONSerialization.data(withJSONObject: object)
        let target = try makeTarget()
        let context = target.container.mainContext
        let closed = FocusSessionRecord(taskKey: "local|4", blockEventID: nil, title: "Lokal", state: FocusTimerState(start: clock.now, settings: FocusTimerSettings()))
        closed.outcome = .completed
        context.insert(closed)
        context.insert(EffortSampleRecord(taskKey: "local|4", source: .local, labels: [], estimateMinutes: nil, actualMinutes: 20, method: .focus, completedAt: clock.now))
        target.settings.focusWorkMinutes = 40
        try context.save()
        try target.service.restore(try target.service.inspect(old))
        #expect(try context.fetchCount(FetchDescriptor<LocalTask>()) == 1, "the rest of the file is restored")
        #expect(try context.fetch(FetchDescriptor<FocusSessionRecord>()).map(\.title) == ["Lokal"])
        #expect(try context.fetchCount(FetchDescriptor<EffortSampleRecord>()) == 1)
        #expect(target.settings.focusWorkMinutes == 40 && target.settings.focusRounds == 4 && target.settings.focusUsesPomodoro)
    }

    @Test func aFileWithEmptyFocusLists_replacesTheFocusDataOfTheDevice() throws {
        let emptySource = try ModelContainerFactory.make(inMemory: true)
        let emptySettings = try AppSettings.current(in: emptySource.mainContext)
        let clock = self.clock
        let emptyBackup = BackupService(context: emptySource.mainContext, settings: emptySettings, calendar: calendar, appVersion: "1.0-test", now: { clock.now })
        let data = try emptyBackup.makeBackupData()
        let target = try makeTarget()
        let context = target.container.mainContext
        context.insert(EffortSampleRecord(taskKey: "local|4", source: .local, labels: [], estimateMinutes: nil, actualMinutes: 20, method: .focus, completedAt: clock.now))
        try context.save()
        try target.service.restore(try target.service.inspect(data))
        #expect(try context.fetchCount(FetchDescriptor<EffortSampleRecord>()) == 0)
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
        #expect(kinds == ["free", "evening", "dream"])
        #expect(Set(inspection.entities.noteFolders.map(\.name)) == ["Studium", "Brain Dump", "Tagesabschluss", "Dream Log"])
        #expect(inspection.entities.bibleStudySessions.isEmpty)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("Dankbar") && !text.contains("3,21-31") && !text.contains("Allgemeine Stimmung"))
    }

    @Test func backupWithoutPrivate_keepsBrainDumpRoutineAndDreamFolders() throws {
        let inspection = try makeTarget().service.inspect(try backup.makeBackupData(includePrivate: false))
        let roles = Set(inspection.entities.noteFolders.compactMap(\.roleRaw))
        #expect(roles == ["brainDump", "eveningRoutine", "dreamLog"])
        let texts = Set(inspection.entities.notes.map(\.text))
        #expect(texts.contains("Kopf leeren") && texts.contains("Ruhiger Tag") && texts.contains("Traum vom Meer"))
    }

    @Test func backupWithoutPrivate_dropsJournalAndBibleStudyFolders() throws {
        let inspection = try makeTarget().service.inspect(try backup.makeBackupData(includePrivate: false))
        let roles = Set(inspection.entities.noteFolders.compactMap(\.roleRaw))
        #expect(!roles.contains("journal") && !roles.contains("bibleStudy"))
        #expect(!inspection.entities.notes.contains { $0.kindRaw == "journal" || $0.kindRaw == "bibleStudy" })
    }

    @Test func restore_routineNotesLandInTheirFolders() throws {
        // A file from before the fixed folders: thought notes without a folder. The restore files them afterwards.
        let target = try makeTarget()
        let context = target.container.mainContext
        let store = NoteStore(context: context, now: { self.clock.now })
        let service = BackupService(context: context, settings: target.settings, calendar: calendar, appVersion: "1.0-test",
                                    now: { self.clock.now }, afterRestore: { store.ensureDefaultFolders() })
        context.insert(NoteRecord(text: "Altes", kind: .morning, dayKey: "2026-11-18", now: clock.now))
        context.insert(NoteRecord(text: "Traum", kind: .dream, dayKey: "2026-11-18", now: clock.now))
        try context.save()
        let oldFile = try target.service.makeBackupData(includePrivate: false)
        try service.restore(try service.inspect(oldFile))
        let notes = try context.fetch(FetchDescriptor<NoteRecord>())
        let morning = try #require(notes.first { $0.kind == .morning })
        let dream = try #require(notes.first { $0.kind == .dream })
        #expect(morning.folderID == store.folder(role: .morningRoutine)?.id && morning.folderID != nil)
        #expect(dream.folderID == store.folder(role: .dreamLog)?.id && dream.folderID != nil)
        #expect(store.folders().compactMap(\.role).filter { $0 == .brainDump }.count == 1)
    }

    // MARK: Attachments

    @Test func backup_containsAttachmentData() throws {
        let inspection = try makeTarget().service.inspect(try backup.makeBackupData(includePrivate: true))
        let names = Set(inspection.entities.noteAttachments.map(\.fileName))
        #expect(names == ["Plan.pdf", "Gebet.pdf"])
        let plan = try #require(inspection.entities.noteAttachments.first { $0.fileName == "Plan.pdf" })
        #expect(plan.data.count == 1500 && plan.typeIdentifier == "com.adobe.pdf")
        #expect(plan.data == Data((0..<1500).map { UInt8(($0 + 3) % 251) }))
        #expect(sourceFiles.summary.count == 2 && sourceFiles.summary.bytes == 2400)
        #expect(BackupSettingsView.attachmentsText(sourceFiles.summary)?.hasPrefix("2 · ") == true)
        #expect(BackupSettingsView.attachmentsText((0, 0)) == nil && BackupSettingsView.attachmentsText(nil) == nil)
    }

    @Test func backupWithoutPrivate_dropsAttachmentsOfJournal() throws {
        let data = try backup.makeBackupData(includePrivate: false)
        let inspection = try makeTarget().service.inspect(data)
        #expect(inspection.entities.noteAttachments.map(\.fileName) == ["Plan.pdf"])
        // The bytes of the journal attachment are not in the file in any form.
        let journalBytes = Data((0..<900).map { UInt8(($0 * 7 + 3) % 251) }).base64EncodedString()
        #expect(!String(decoding: data, as: UTF8.self).contains(journalBytes.prefix(120)))
    }

    @Test func restore_writesAttachmentFiles() throws {
        let target = try makeTarget()
        try target.service.restore(try target.service.inspect(try backup.makeBackupData(includePrivate: true)))
        let restored = target.files.records()
        #expect(Set(restored.map(\.fileName)) == ["Plan.pdf", "Gebet.pdf"])
        for record in restored {
            let original = try #require(sourceFiles.record(id: record.id))
            #expect(record.noteID == original.noteID && record.byteCount == original.byteCount)
            #expect(target.files.data(for: record.id) == sourceFiles.data(for: record.id))
        }
        // A second restore replaces the files instead of doubling them.
        try target.service.restore(try target.service.inspect(try backup.makeBackupData(includePrivate: true)))
        #expect(target.files.records().count == 2)
    }

    @Test func restore_ofOlderFileWithoutAttachments_works() throws {
        let target = try makeTarget()
        let stray = NoteAttachmentRecord(noteID: UUID(), fileName: "alt.pdf", typeIdentifier: "com.adobe.pdf", byteCount: 1)
        target.container.mainContext.insert(stray)
        try target.container.mainContext.save()
        let minimal = Data("{\"format\":\"tagwerk-backup\",\"schemaVersion\":1,\"appVersion\":\"1\",\"createdAt\":\"x\",\"includesPrivateNotes\":true,\"entities\":{}}".utf8)
        try target.service.restore(try target.service.inspect(minimal))
        #expect(target.files.records().isEmpty)
    }

    @Test func restoreWithoutPrivate_keepsTheAttachmentsOfTheExistingJournal() throws {
        let target = try makeTarget()
        let context = target.container.mainContext
        let entry = NoteRecord(text: "Mein Eintrag", kind: .journal, dayKey: "2026-11-01", now: clock.now)
        context.insert(entry)
        try context.save()
        let file = FileManager.default.temporaryDirectory.appending(path: "keep-" + UUID().uuidString + ".pdf")
        try Data(repeating: 1, count: 10).write(to: file)
        let kept = try target.files.addFile(at: file, to: entry.id)
        try target.service.restore(try target.service.inspect(try backup.makeBackupData(includePrivate: false)))
        #expect(target.files.url(for: kept.id) != nil)
        #expect(Set(target.files.records().map(\.fileName)) == ["Plan.pdf", kept.fileName])
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
        try target.service.restore(try target.service.inspect(try backup.makeBackupData(includePrivate: false)))
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
        try target.service.restore(try target.service.inspect(try backup.makeBackupData(includePrivate: true)))
        let journal = try context.fetch(FetchDescriptor<NoteRecord>()).filter { $0.kind == .journal }
        #expect(journal.count == 1 && journal[0].text.hasPrefix("Allgemeine Stimmung\nDankbar"))
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
