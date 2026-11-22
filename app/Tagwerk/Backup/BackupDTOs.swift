import Foundation
import SwiftData
import TagwerkCore

// Generated from the SwiftData models by the backup stage (#158); kept in the repository and maintained by hand from here on.
// One `Codable` value per model, with the same attribute names. Records are named by their natural keys, never by a
// `PersistentIdentifier`. A new attribute needs a line here, or the round-trip test fails; a new model needs a value type, or
// the completeness test fails.

/// A model that is part of the backup file.
protocol BackupEntity: Codable, Equatable {
    associatedtype Record: PersistentModel
    /// The name of the model class, for the completeness check against the schema.
    static var modelName: String { get }
    init(_ record: Record)
    /// A new record with every attribute set from the value; not yet inserted.
    func makeRecord() -> Record
}

struct LocalTaskBackup: BackupEntity {
    static let modelName = "LocalTask"
    var id: UUID
    var title: String
    var notes: String?
    var dueYear: Int?
    var dueMonth: Int?
    var dueDay: Int?
    var dueHour: Int?
    var dueMinute: Int?
    var priorityRaw: Int?
    var estimateMinutes: Int?
    var isCompleted: Bool
    var revision: Int
    var createdAt: Date
    var completedAt: Date?
    var recurrenceData: Data?

    init(_ record: LocalTask) {
        id = record.id
        title = record.title
        notes = record.notes
        dueYear = record.dueYear
        dueMonth = record.dueMonth
        dueDay = record.dueDay
        dueHour = record.dueHour
        dueMinute = record.dueMinute
        priorityRaw = record.priorityRaw
        estimateMinutes = record.estimateMinutes
        isCompleted = record.isCompleted
        revision = record.revision
        createdAt = record.createdAt
        completedAt = record.completedAt
        recurrenceData = record.recurrenceData
    }

    func makeRecord() -> LocalTask {
        let record = LocalTask(id: id, title: title, createdAt: createdAt)
        record.id = id
        record.title = title
        record.notes = notes
        record.dueYear = dueYear
        record.dueMonth = dueMonth
        record.dueDay = dueDay
        record.dueHour = dueHour
        record.dueMinute = dueMinute
        record.priorityRaw = priorityRaw
        record.estimateMinutes = estimateMinutes
        record.isCompleted = isCompleted
        record.revision = revision
        record.createdAt = createdAt
        record.completedAt = completedAt
        record.recurrenceData = recurrenceData
        return record
    }
}

struct LocalOccurrenceCompletionBackup: BackupEntity {
    static let modelName = "LocalOccurrenceCompletion"
    var taskID: UUID
    var completedAt: Date
    var previousDueYear: Int
    var previousDueMonth: Int
    var previousDueDay: Int
    var previousDueHour: Int?
    var previousDueMinute: Int?
    var previousCount: Int?
    var revision: Int

    init(_ record: LocalOccurrenceCompletion) {
        taskID = record.taskID
        completedAt = record.completedAt
        previousDueYear = record.previousDueYear
        previousDueMonth = record.previousDueMonth
        previousDueDay = record.previousDueDay
        previousDueHour = record.previousDueHour
        previousDueMinute = record.previousDueMinute
        previousCount = record.previousCount
        revision = record.revision
    }

    func makeRecord() -> LocalOccurrenceCompletion {
        let record = LocalOccurrenceCompletion(taskID: taskID, completedAt: completedAt, previousDue: DueDate(year: previousDueYear, month: previousDueMonth, day: previousDueDay), previousCount: previousCount, revision: revision)
        record.taskID = taskID
        record.completedAt = completedAt
        record.previousDueYear = previousDueYear
        record.previousDueMonth = previousDueMonth
        record.previousDueDay = previousDueDay
        record.previousDueHour = previousDueHour
        record.previousDueMinute = previousDueMinute
        record.previousCount = previousCount
        record.revision = revision
        return record
    }
}

struct DayAssignmentBackup: BackupEntity {
    static let modelName = "DayAssignment"
    var taskKey: String
    var year: Int
    var month: Int
    var day: Int
    var order: Int
    var createdAt: Date

    init(_ record: DayAssignment) {
        taskKey = record.taskKey
        year = record.year
        month = record.month
        day = record.day
        order = record.order
        createdAt = record.createdAt
    }

    func makeRecord() -> DayAssignment {
        let record = DayAssignment(taskKey: taskKey, day: PlanDay(year: year, month: month, day: day), order: order, createdAt: createdAt)
        record.taskKey = taskKey
        record.year = year
        record.month = month
        record.day = day
        record.order = order
        record.createdAt = createdAt
        return record
    }
}

struct DayOverrideBackup: BackupEntity {
    static let modelName = "DayOverrideRecord"
    var dayKey: String
    var year: Int
    var month: Int
    var day: Int
    var isOff: Bool
    var startMinutes: Int?
    var endMinutes: Int?

    init(_ record: DayOverrideRecord) {
        dayKey = record.dayKey
        year = record.year
        month = record.month
        day = record.day
        isOff = record.isOff
        startMinutes = record.startMinutes
        endMinutes = record.endMinutes
    }

    func makeRecord() -> DayOverrideRecord {
        let record = DayOverrideRecord(day: PlanDay(year: year, month: month, day: day), override: .off)
        record.dayKey = dayKey
        record.year = year
        record.month = month
        record.day = day
        record.isOff = isOff
        record.startMinutes = startMinutes
        record.endMinutes = endMinutes
        return record
    }
}

struct ReminderEstimateBackup: BackupEntity {
    static let modelName = "ReminderEstimateRecord"
    var reminderID: String
    var minutes: Int

    init(_ record: ReminderEstimateRecord) {
        reminderID = record.reminderID
        minutes = record.minutes
    }

    func makeRecord() -> ReminderEstimateRecord {
        let record = ReminderEstimateRecord(reminderID: reminderID, minutes: minutes)
        record.reminderID = reminderID
        record.minutes = minutes
        return record
    }
}

struct EventTaskLinkBackup: BackupEntity {
    static let modelName = "EventTaskLink"
    var eventKey: String
    var taskKey: String
    var createdAt: Date

    init(_ record: EventTaskLink) {
        eventKey = record.eventKey
        taskKey = record.taskKey
        createdAt = record.createdAt
    }

    func makeRecord() -> EventTaskLink {
        let record = EventTaskLink(eventKey: eventKey, taskKey: taskKey, createdAt: createdAt)
        record.eventKey = eventKey
        record.taskKey = taskKey
        record.createdAt = createdAt
        return record
    }
}

struct RecurringEffortValueBackup: BackupEntity {
    static let modelName = "RecurringEffortValue"
    var reminderID: String
    var fromYear: Int
    var fromMonth: Int
    var fromDay: Int
    var minutes: Int

    init(_ record: RecurringEffortValue) {
        reminderID = record.reminderID
        fromYear = record.fromYear
        fromMonth = record.fromMonth
        fromDay = record.fromDay
        minutes = record.minutes
    }

    func makeRecord() -> RecurringEffortValue {
        let record = RecurringEffortValue(reminderID: reminderID, from: PlanDay(year: fromYear, month: fromMonth, day: fromDay), minutes: minutes)
        record.reminderID = reminderID
        record.fromYear = fromYear
        record.fromMonth = fromMonth
        record.fromDay = fromDay
        record.minutes = minutes
        return record
    }
}

struct RecurringEffortOverrideBackup: BackupEntity {
    static let modelName = "RecurringEffortOverride"
    var key: String
    var reminderID: String
    var year: Int
    var month: Int
    var day: Int
    var minutes: Int

    init(_ record: RecurringEffortOverride) {
        key = record.key
        reminderID = record.reminderID
        year = record.year
        month = record.month
        day = record.day
        minutes = record.minutes
    }

    func makeRecord() -> RecurringEffortOverride {
        let record = RecurringEffortOverride(reminderID: reminderID, day: PlanDay(year: year, month: month, day: day), minutes: minutes)
        record.key = key
        record.reminderID = reminderID
        record.year = year
        record.month = month
        record.day = day
        record.minutes = minutes
        return record
    }
}

struct RecurringOccurrenceDoneBackup: BackupEntity {
    static let modelName = "RecurringOccurrenceDone"
    var key: String
    var reminderID: String

    init(_ record: RecurringOccurrenceDone) {
        key = record.key
        reminderID = record.reminderID
    }

    func makeRecord() -> RecurringOccurrenceDone {
        let record = RecurringOccurrenceDone(reminderID: reminderID, day: PlanDay(year: 1970, month: 1, day: 1))
        record.key = key
        record.reminderID = reminderID
        return record
    }
}

struct DayLunchBackup: BackupEntity {
    static let modelName = "DayLunchRecord"
    var dayKey: String
    var startMinutes: Int
    var minutes: Int

    init(_ record: DayLunchRecord) {
        dayKey = record.dayKey
        startMinutes = record.startMinutes
        minutes = record.minutes
    }

    func makeRecord() -> DayLunchRecord {
        let record = DayLunchRecord(day: PlanDay(year: 1970, month: 1, day: 1), startMinutes: startMinutes, minutes: minutes)
        record.dayKey = dayKey
        record.startMinutes = startMinutes
        record.minutes = minutes
        return record
    }
}

struct EventAvailabilityMarkBackup: BackupEntity {
    static let modelName = "EventAvailabilityMark"
    var key: String
    var eventKey: String
    var seriesFrom: Date?
    var isFree: Bool

    init(_ record: EventAvailabilityMark) {
        key = record.key
        eventKey = record.eventKey
        seriesFrom = record.seriesFrom
        isFree = record.isFree
    }

    func makeRecord() -> EventAvailabilityMark {
        let record = EventAvailabilityMark(eventKey: eventKey, seriesFrom: seriesFrom, isFree: isFree)
        record.key = key
        record.eventKey = eventKey
        record.seriesFrom = seriesFrom
        record.isFree = isFree
        return record
    }
}

struct EventTravelOverrideBackup: BackupEntity {
    static let modelName = "EventTravelOverride"
    var key: String
    var eventKey: String
    var seriesFrom: Date?
    var modeName: String
    var minutes: Int
    /// Transport and start per event (V1); absent in files written before, which read as "not chosen".
    var transportRaw: String?
    var startRaw: String?

    init(_ record: EventTravelOverride) {
        key = record.key
        eventKey = record.eventKey
        seriesFrom = record.seriesFrom
        modeName = record.modeName
        minutes = record.minutes
        transportRaw = record.transportRaw
        startRaw = record.startRaw
    }

    func makeRecord() -> EventTravelOverride {
        let record = EventTravelOverride(TravelOverride(eventKey: eventKey, seriesFrom: seriesFrom,
                                                        mode: TravelOverrideMode(storedName: modeName, minutes: minutes)))
        record.key = key
        record.modeName = modeName
        record.minutes = minutes
        record.transportRaw = transportRaw
        record.startRaw = startRaw
        return record
    }
}

struct EventMergeDecisionBackup: BackupEntity {
    static let modelName = "EventMergeDecision"
    var key: String
    var placeholderEventID: String?
    var ruleTitle: String?
    var ruleCalendarID: String?
    var isMerged: Bool

    init(_ record: EventMergeDecision) {
        key = record.key
        placeholderEventID = record.placeholderEventID
        ruleTitle = record.ruleTitle
        ruleCalendarID = record.ruleCalendarID
        isMerged = record.isMerged
    }

    func makeRecord() -> EventMergeDecision {
        let record = EventMergeDecision(key: key, placeholderEventID: placeholderEventID, ruleTitle: ruleTitle, ruleCalendarID: ruleCalendarID, isMerged: isMerged)
        record.key = key
        record.placeholderEventID = placeholderEventID
        record.ruleTitle = ruleTitle
        record.ruleCalendarID = ruleCalendarID
        record.isMerged = isMerged
        return record
    }
}

struct EventDeadlineMarkBackup: BackupEntity {
    static let modelName = "EventDeadlineMark"
    var eventKey: String
    var externalID: String?
    var calendarID: String
    var title: String
    var start: Date
    var isAllDay: Bool
    var isSeries: Bool
    var lastSeen: Date?
    var createdAt: Date

    init(_ record: EventDeadlineMark) {
        eventKey = record.eventKey
        externalID = record.externalID
        calendarID = record.calendarID
        title = record.title
        start = record.start
        isAllDay = record.isAllDay
        isSeries = record.isSeries
        lastSeen = record.lastSeen
        createdAt = record.createdAt
    }

    func makeRecord() -> EventDeadlineMark {
        let record = EventDeadlineMark(eventKey: eventKey, externalID: externalID, calendarID: calendarID, title: title, start: start, isAllDay: isAllDay, isSeries: isSeries, createdAt: createdAt)
        record.eventKey = eventKey
        record.externalID = externalID
        record.calendarID = calendarID
        record.title = title
        record.start = start
        record.isAllDay = isAllDay
        record.isSeries = isSeries
        record.lastSeen = lastSeen
        record.createdAt = createdAt
        return record
    }
}

struct DeadlineEventLinkBackup: BackupEntity {
    static let modelName = "DeadlineEventLink"
    var key: String
    var deadlineKey: String
    var eventKey: String
    var isSeries: Bool
    var externalID: String?
    var calendarID: String
    var title: String
    var start: Date
    var deadlineTitle: String
    var until: Date
    var createdAt: Date

    init(_ record: DeadlineEventLink) {
        key = record.key
        deadlineKey = record.deadlineKey
        eventKey = record.eventKey
        isSeries = record.isSeries
        externalID = record.externalID
        calendarID = record.calendarID
        title = record.title
        start = record.start
        deadlineTitle = record.deadlineTitle
        until = record.until
        createdAt = record.createdAt
    }

    func makeRecord() -> DeadlineEventLink {
        let record = DeadlineEventLink(deadlineKey: deadlineKey, eventKey: eventKey, isSeries: isSeries, externalID: externalID, calendarID: calendarID, title: title, start: start, deadlineTitle: deadlineTitle, until: until, createdAt: createdAt)
        record.key = key
        record.deadlineKey = deadlineKey
        record.eventKey = eventKey
        record.isSeries = isSeries
        record.externalID = externalID
        record.calendarID = calendarID
        record.title = title
        record.start = start
        record.deadlineTitle = deadlineTitle
        record.until = until
        record.createdAt = createdAt
        return record
    }
}

struct DeadlineSuggestionDismissalBackup: BackupEntity {
    static let modelName = "DeadlineSuggestionDismissal"
    var eventKey: String
    var start: Date

    init(_ record: DeadlineSuggestionDismissal) {
        eventKey = record.eventKey
        start = record.start
    }

    func makeRecord() -> DeadlineSuggestionDismissal {
        let record = DeadlineSuggestionDismissal(eventKey: eventKey, start: start)
        record.eventKey = eventKey
        record.start = start
        return record
    }
}

struct MealBackup: BackupEntity {
    static let modelName = "MealRecord"
    var id: UUID
    var date: Date
    var kindRaw: String
    var title: String
    var itemsData: Data
    var originRaw: String
    var estimatedAt: Date?
    var healthVersion: Int
    var healthSynced: Bool

    init(_ record: MealRecord) {
        id = record.id
        date = record.date
        kindRaw = record.kindRaw
        title = record.title
        itemsData = record.itemsData
        originRaw = record.originRaw
        estimatedAt = record.estimatedAt
        healthVersion = record.healthVersion
        healthSynced = record.healthSynced
    }

    func makeRecord() -> MealRecord {
        let record = MealRecord(MealValue(id: id, date: date, kind: .snack, title: title, items: [], origin: .manual), estimatedAt: estimatedAt)
        record.id = id
        record.date = date
        record.kindRaw = kindRaw
        record.title = title
        record.itemsData = itemsData
        record.originRaw = originRaw
        record.estimatedAt = estimatedAt
        record.healthVersion = healthVersion
        record.healthSynced = healthSynced
        return record
    }
}

struct DrinkBackup: BackupEntity {
    static let modelName = "DrinkRecord"
    var id: UUID
    var date: Date
    var milliliters: Int
    var healthVersion: Int
    var healthSynced: Bool

    init(_ record: DrinkRecord) {
        id = record.id
        date = record.date
        milliliters = record.milliliters
        healthVersion = record.healthVersion
        healthSynced = record.healthSynced
    }

    func makeRecord() -> DrinkRecord {
        let record = DrinkRecord(DrinkValue(id: id, date: date, milliliters: milliliters))
        record.id = id
        record.date = date
        record.milliliters = milliliters
        record.healthVersion = healthVersion
        record.healthSynced = healthSynced
        return record
    }
}

struct WorkoutBackup: BackupEntity {
    static let modelName = "WorkoutRecord"
    var id: UUID
    var activityRaw: String
    var start: Date
    var minutes: Int
    var kilocalories: Double?
    var healthVersion: Int
    var healthSynced: Bool

    init(_ record: WorkoutRecord) {
        id = record.id
        activityRaw = record.activityRaw
        start = record.start
        minutes = record.minutes
        kilocalories = record.kilocalories
        healthVersion = record.healthVersion
        healthSynced = record.healthSynced
    }

    func makeRecord() -> WorkoutRecord {
        let record = WorkoutRecord(id: id, activity: .other, start: start, minutes: minutes, kilocalories: kilocalories)
        record.id = id
        record.activityRaw = activityRaw
        record.start = start
        record.minutes = minutes
        record.kilocalories = kilocalories
        record.healthVersion = healthVersion
        record.healthSynced = healthSynced
        return record
    }
}

struct ShoppingCategoryBackup: BackupEntity {
    static let modelName = "ShoppingCategory"
    var id: UUID
    var name: String
    var sortIndex: Int
    var builtinKey: String?
    var createdAt: Date

    init(_ record: ShoppingCategory) {
        id = record.id
        name = record.name
        sortIndex = record.sortIndex
        builtinKey = record.builtinKey
        createdAt = record.createdAt
    }

    func makeRecord() -> ShoppingCategory {
        let record = ShoppingCategory(name: name, sortIndex: sortIndex, builtinKey: builtinKey, createdAt: createdAt)
        record.id = id
        record.name = name
        record.sortIndex = sortIndex
        record.builtinKey = builtinKey
        record.createdAt = createdAt
        return record
    }
}

struct ShoppingAssignmentBackup: BackupEntity {
    static let modelName = "ShoppingAssignment"
    var nameKey: String
    var categoryID: UUID?
    var sourceRaw: String
    var updatedAt: Date

    init(_ record: ShoppingAssignment) {
        nameKey = record.nameKey
        categoryID = record.categoryID
        sourceRaw = record.sourceRaw
        updatedAt = record.updatedAt
    }

    func makeRecord() -> ShoppingAssignment {
        let record = ShoppingAssignment(nameKey: nameKey, categoryID: categoryID, sourceRaw: sourceRaw, updatedAt: updatedAt)
        record.nameKey = nameKey
        record.categoryID = categoryID
        record.sourceRaw = sourceRaw
        record.updatedAt = updatedAt
        return record
    }
}

struct NoteBackup: BackupEntity {
    static let modelName = "NoteRecord"
    var id: UUID
    var text: String
    var createdAt: Date
    var updatedAt: Date
    var kindRaw: String
    var dayKey: String?
    var isPinned: Bool
    var wasDictated: Bool
    var processedAt: Date?
    var derivedActionCount: Int
    var folderID: UUID?
    var deletedAt: Date?
    var importSourceID: String?
    var bookKey: String?

    init(_ record: NoteRecord) {
        id = record.id
        text = record.text
        createdAt = record.createdAt
        updatedAt = record.updatedAt
        kindRaw = record.kindRaw
        dayKey = record.dayKey
        isPinned = record.isPinned
        wasDictated = record.wasDictated
        processedAt = record.processedAt
        derivedActionCount = record.derivedActionCount
        folderID = record.folderID
        deletedAt = record.deletedAt
        importSourceID = record.importSourceID
        bookKey = record.bookKey
    }

    func makeRecord() -> NoteRecord {
        let record = NoteRecord(text: text, now: createdAt)
        record.id = id
        record.text = text
        record.createdAt = createdAt
        record.updatedAt = updatedAt
        record.kindRaw = kindRaw
        record.dayKey = dayKey
        record.isPinned = isPinned
        record.wasDictated = wasDictated
        record.processedAt = processedAt
        record.derivedActionCount = derivedActionCount
        record.folderID = folderID
        record.deletedAt = deletedAt
        record.importSourceID = importSourceID
        record.bookKey = bookKey
        return record
    }
}

struct NoteFolderBackup: BackupEntity {
    static let modelName = "NoteFolderRecord"
    var id: UUID
    var name: String
    var parentID: UUID?
    var order: Int
    var createdAt: Date
    var roleRaw: String?

    init(_ record: NoteFolderRecord) {
        id = record.id
        name = record.name
        parentID = record.parentID
        order = record.order
        createdAt = record.createdAt
        roleRaw = record.roleRaw
    }

    func makeRecord() -> NoteFolderRecord {
        let record = NoteFolderRecord(name: name, now: createdAt)
        record.id = id
        record.name = name
        record.parentID = parentID
        record.order = order
        record.createdAt = createdAt
        record.roleRaw = roleRaw
        return record
    }
}

/// A file attached to a note, with its bytes (base64 in the JSON). `init(_:)` carries the metadata only: the bytes lie
/// in `NoteAttachmentStore`, so the collector uses `init(_:data:)`.
struct NoteAttachmentBackup: BackupEntity {
    static let modelName = "NoteAttachmentRecord"
    var id: UUID
    var noteID: UUID?
    var fileName: String
    var typeIdentifier: String
    var createdAt: Date
    var data: Data

    init(_ record: NoteAttachmentRecord) {
        self.init(record, data: Data())
    }

    init(_ record: NoteAttachmentRecord, data: Data) {
        id = record.id
        noteID = record.noteID
        fileName = record.fileName
        typeIdentifier = record.typeIdentifier
        createdAt = record.createdAt
        self.data = data
    }

    /// The record without its file; `BackupEntities.restore` writes the bytes through `NoteAttachmentStore`.
    func makeRecord() -> NoteAttachmentRecord {
        NoteAttachmentRecord(id: id, noteID: noteID, fileName: fileName, typeIdentifier: typeIdentifier, byteCount: data.count, createdAt: createdAt)
    }
}

struct BibleStudySessionBackup: BackupEntity {
    static let modelName = "BibleStudySessionRecord"
    var id: UUID
    var dayKey: String
    var book: String
    var passage: String
    var noteID: UUID
    var startedAt: Date
    var completedAt: Date?

    init(_ record: BibleStudySessionRecord) {
        id = record.id
        dayKey = record.dayKey
        book = record.book
        passage = record.passage
        noteID = record.noteID
        startedAt = record.startedAt
        completedAt = record.completedAt
    }

    func makeRecord() -> BibleStudySessionRecord {
        let record = BibleStudySessionRecord(dayKey: dayKey, book: book, passage: passage, noteID: noteID, startedAt: startedAt)
        record.id = id
        record.dayKey = dayKey
        record.book = book
        record.passage = passage
        record.noteID = noteID
        record.startedAt = startedAt
        record.completedAt = completedAt
        return record
    }
}

struct HabitBackup: BackupEntity {
    static let modelName = "HabitRecord"
    var id: UUID
    var name: String
    var symbol: String
    var order: Int
    var source: String
    var daysPerWeek: Int
    var daylightMinutes: Int
    var startYear: Int
    var startMonth: Int
    var startDay: Int
    var pausedSinceKey: String?
    var pausesData: Data?
    var createdAt: Date

    init(_ record: HabitRecord) {
        id = record.id
        name = record.name
        symbol = record.symbol
        order = record.order
        source = record.source
        daysPerWeek = record.daysPerWeek
        daylightMinutes = record.daylightMinutes
        startYear = record.startYear
        startMonth = record.startMonth
        startDay = record.startDay
        pausedSinceKey = record.pausedSinceKey
        pausesData = record.pausesData
        createdAt = record.createdAt
    }

    func makeRecord() -> HabitRecord {
        let record = HabitRecord(Habit(id: id, name: name, symbol: symbol, order: order, start: PlanDay(year: startYear, month: startMonth, day: startDay)), createdAt: createdAt)
        record.id = id
        record.name = name
        record.symbol = symbol
        record.order = order
        record.source = source
        record.daysPerWeek = daysPerWeek
        record.daylightMinutes = daylightMinutes
        record.startYear = startYear
        record.startMonth = startMonth
        record.startDay = startDay
        record.pausedSinceKey = pausedSinceKey
        record.pausesData = pausesData
        record.createdAt = createdAt
        return record
    }
}

struct HabitCheckBackup: BackupEntity {
    static let modelName = "HabitCheckRecord"
    var habitID: UUID
    var year: Int
    var month: Int
    var day: Int
    var checkedAt: Date

    init(_ record: HabitCheckRecord) {
        habitID = record.habitID
        year = record.year
        month = record.month
        day = record.day
        checkedAt = record.checkedAt
    }

    func makeRecord() -> HabitCheckRecord {
        let record = HabitCheckRecord(habitID: habitID, day: PlanDay(year: year, month: month, day: day), checkedAt: checkedAt)
        record.habitID = habitID
        record.year = year
        record.month = month
        record.day = day
        record.checkedAt = checkedAt
        return record
    }
}

struct RoutineDayBackup: BackupEntity {
    static let modelName = "RoutineDayRecord"
    var dayKey: String
    var year: Int
    var month: Int
    var day: Int
    var gratitudeData: Data?
    var startCompletedAt: Date?
    var startDismissed: Bool
    var closeCompletedAt: Date?
    var checkedItemIDsData: Data?

    init(_ record: RoutineDayRecord) {
        dayKey = record.dayKey
        year = record.year
        month = record.month
        day = record.day
        gratitudeData = record.gratitudeData
        startCompletedAt = record.startCompletedAt
        startDismissed = record.startDismissed
        closeCompletedAt = record.closeCompletedAt
        checkedItemIDsData = record.checkedItemIDsData
    }

    func makeRecord() -> RoutineDayRecord {
        let record = RoutineDayRecord(day: PlanDay(year: year, month: month, day: day))
        record.dayKey = dayKey
        record.year = year
        record.month = month
        record.day = day
        record.gratitudeData = gratitudeData
        record.startCompletedAt = startCompletedAt
        record.startDismissed = startDismissed
        record.closeCompletedAt = closeCompletedAt
        record.checkedItemIDsData = checkedItemIDsData
        return record
    }
}

struct EveningChecklistItemBackup: BackupEntity {
    static let modelName = "EveningChecklistItemRecord"
    var id: UUID
    var title: String
    var order: Int
    var offsetMinutes: Int?
    var createdAt: Date

    init(_ record: EveningChecklistItemRecord) {
        id = record.id
        title = record.title
        order = record.order
        offsetMinutes = record.offsetMinutes
        createdAt = record.createdAt
    }

    func makeRecord() -> EveningChecklistItemRecord {
        let record = EveningChecklistItemRecord(ChecklistItem(id: id, title: title, order: order, offsetMinutes: offsetMinutes), createdAt: createdAt)
        record.id = id
        record.title = title
        record.order = order
        record.offsetMinutes = offsetMinutes
        record.createdAt = createdAt
        return record
    }
}

struct FocusMarkBackup: BackupEntity {
    static let modelName = "FocusMarkRecord"
    var taskKey: String
    var year: Int
    var month: Int
    var day: Int
    var order: Int
    var doneAt: Date?
    var createdAt: Date
    var title: String

    init(_ record: FocusMarkRecord) {
        taskKey = record.taskKey
        year = record.year
        month = record.month
        day = record.day
        order = record.order
        doneAt = record.doneAt
        createdAt = record.createdAt
        title = record.title
    }

    func makeRecord() -> FocusMarkRecord {
        let record = FocusMarkRecord(taskKey: taskKey, title: title, day: PlanDay(year: year, month: month, day: day), order: order, createdAt: createdAt)
        record.taskKey = taskKey
        record.year = year
        record.month = month
        record.day = day
        record.order = order
        record.doneAt = doneAt
        record.createdAt = createdAt
        record.title = title
        return record
    }
}

/// A finished focus timer session (plan P3). A session that is still running is not part of the backup: its timer state is bound to
/// this device (Live Activity, notification), so only sessions with an outcome are written. `activityID` is device-bound too.
struct FocusSessionBackup: BackupEntity {
    static let modelName = "FocusSessionRecord"
    var id: UUID
    var taskKey: String?
    var blockEventID: String?
    var title: String
    var start: Date
    var pausesJSON: Data?
    var pausedSince: Date?
    var skipsJSON: Data?
    var settingsJSON: Data?
    var endedAt: Date?
    var outcomeRaw: String?
    var focusedSeconds: Int

    init(_ record: FocusSessionRecord) {
        id = record.id
        taskKey = record.taskKey
        blockEventID = record.blockEventID
        title = record.title
        start = record.start
        pausesJSON = record.pausesJSON
        pausedSince = record.pausedSince
        skipsJSON = record.skipsJSON
        settingsJSON = record.settingsJSON
        endedAt = record.endedAt
        outcomeRaw = record.outcomeRaw
        focusedSeconds = record.focusedSeconds
    }

    func makeRecord() -> FocusSessionRecord {
        let record = FocusSessionRecord(id: id, taskKey: taskKey, blockEventID: blockEventID, title: title, state: FocusTimerState(start: start, settings: FocusTimerSettings()))
        record.id = id
        record.taskKey = taskKey
        record.blockEventID = blockEventID
        record.title = title
        record.start = start
        record.pausesJSON = pausesJSON
        record.pausedSince = pausedSince
        record.skipsJSON = skipsJSON
        record.settingsJSON = settingsJSON
        record.endedAt = endedAt
        record.outcomeRaw = outcomeRaw
        record.focusedSeconds = focusedSeconds
        record.activityID = nil
        return record
    }
}

struct EffortSampleBackup: BackupEntity {
    static let modelName = "EffortSampleRecord"
    var id: UUID
    var taskKey: String
    var sourceRaw: String
    var labelsJSON: Data?
    var estimateMinutes: Int?
    var actualMinutes: Int
    var methodRaw: String
    var completedAt: Date
    var trimmedEventID: String?
    var trimmedOriginalEnd: Date?
    var trimmedNewEnd: Date?

    init(_ record: EffortSampleRecord) {
        id = record.id
        taskKey = record.taskKey
        sourceRaw = record.sourceRaw
        labelsJSON = record.labelsJSON
        estimateMinutes = record.estimateMinutes
        actualMinutes = record.actualMinutes
        methodRaw = record.methodRaw
        completedAt = record.completedAt
        trimmedEventID = record.trimmedEventID
        trimmedOriginalEnd = record.trimmedOriginalEnd
        trimmedNewEnd = record.trimmedNewEnd
    }

    func makeRecord() -> EffortSampleRecord {
        let record = EffortSampleRecord(taskKey: taskKey, source: .local, labels: [], estimateMinutes: estimateMinutes, actualMinutes: actualMinutes,
                                        method: .focus, completedAt: completedAt)
        record.id = id
        record.taskKey = taskKey
        record.sourceRaw = sourceRaw
        record.labelsJSON = labelsJSON
        record.estimateMinutes = estimateMinutes
        record.actualMinutes = actualMinutes
        record.methodRaw = methodRaw
        record.completedAt = completedAt
        record.trimmedEventID = trimmedEventID
        record.trimmedOriginalEnd = trimmedOriginalEnd
        record.trimmedNewEnd = trimmedNewEnd
        return record
    }
}

struct WeekReflectionBackup: BackupEntity {
    static let modelName = "WeekReflectionRecord"
    var weekKey: String
    var wentWell: String
    var burdens: String
    var plannedAppointments: Bool
    var plannedHabits: Bool
    var plannedTasks: Bool
    var updatedAt: Date
    /// Optional, so a backup written before the original weekly template still decodes.
    var goalsProgress: String?
    var gratitudeTaken: Bool?

    init(_ record: WeekReflectionRecord) {
        weekKey = record.weekKey
        wentWell = record.wentWell
        burdens = record.burdens
        plannedAppointments = record.plannedAppointments
        plannedHabits = record.plannedHabits
        plannedTasks = record.plannedTasks
        updatedAt = record.updatedAt
        goalsProgress = record.goalsProgress
        gratitudeTaken = record.gratitudeTaken
    }

    func makeRecord() -> WeekReflectionRecord {
        let record = WeekReflectionRecord(weekStart: PlanDay(year: 1970, month: 1, day: 1), updatedAt: updatedAt)
        record.weekKey = weekKey
        record.wentWell = wentWell
        record.burdens = burdens
        record.plannedAppointments = plannedAppointments
        record.plannedHabits = plannedHabits
        record.plannedTasks = plannedTasks
        record.updatedAt = updatedAt
        record.goalsProgress = goalsProgress ?? ""
        record.gratitudeTaken = gratitudeTaken ?? false
        return record
    }
}

struct ReminderOverrideBackup: BackupEntity {
    static let modelName = "ReminderOverrideRecord"
    var key: String
    var itemKey: String
    var scopeRaw: String
    var scopeValue: String?
    var storageRaw: String
    var offsetsData: Data
    var updatedAt: Date

    init(_ record: ReminderOverrideRecord) {
        key = record.key
        itemKey = record.itemKey
        scopeRaw = record.scopeRaw
        scopeValue = record.scopeValue
        storageRaw = record.storageRaw
        offsetsData = record.offsetsData
        updatedAt = record.updatedAt
    }

    func makeRecord() -> ReminderOverrideRecord {
        // The stored values are kept as they are; the record is built from a placeholder and then overwritten.
        let record = ReminderOverrideRecord(ReminderOverride(itemKey: itemKey, scope: .always, offsets: []), updatedAt: updatedAt)
        record.key = key
        record.scopeRaw = scopeRaw
        record.scopeValue = scopeValue
        record.storageRaw = storageRaw
        record.offsetsData = offsetsData
        return record
    }
}

/// The settings that travel with a backup. Left out: the model list from ChatGPT (a cache) and everything that names a place on
/// this device (the backup folder and its state). Secrets are not in the database at all; they live in the Keychain.
/// One goal plan ("Zielstand"): the goals that hold from `validFromKey` on.
struct GoalPlanBackup: BackupEntity {
    static let modelName = "GoalPlanRecord"
    var id: UUID
    var validFromKey: String
    var kcal: Int
    var proteinGrams: Int?
    var carbsGrams: Int?
    var fatGrams: Int?
    var fiberGrams: Int?
    var sugarLimitGrams: Int?
    var waterMilliliters: Int
    var stepsPerDay: Int
    var workoutMinutesPerWeek: Int
    var activeKcalPerDay: Int
    var targetWeightKg: Double?
    var paceKgPerWeek: Double?
    var originRaw: String
    var note: String

    init(_ record: GoalPlanRecord) {
        id = record.id
        validFromKey = record.validFromKey
        kcal = record.kcal
        proteinGrams = record.proteinGrams
        carbsGrams = record.carbsGrams
        fatGrams = record.fatGrams
        fiberGrams = record.fiberGrams
        sugarLimitGrams = record.sugarLimitGrams
        waterMilliliters = record.waterMilliliters
        stepsPerDay = record.stepsPerDay
        workoutMinutesPerWeek = record.workoutMinutesPerWeek
        activeKcalPerDay = record.activeKcalPerDay
        targetWeightKg = record.targetWeightKg
        paceKgPerWeek = record.paceKgPerWeek
        originRaw = record.originRaw
        note = record.note
    }

    func makeRecord() -> GoalPlanRecord {
        let record = GoalPlanRecord(GoalPlan(id: id, validFrom: PlanDay(dayKey: validFromKey) ?? PlanDay(year: 1970, month: 1, day: 1),
                                             kcal: kcal, waterMilliliters: waterMilliliters, stepsPerDay: stepsPerDay,
                                             workoutMinutesPerWeek: workoutMinutesPerWeek))
        record.id = id
        record.validFromKey = validFromKey
        record.kcal = kcal
        record.proteinGrams = proteinGrams
        record.carbsGrams = carbsGrams
        record.fatGrams = fatGrams
        record.fiberGrams = fiberGrams
        record.sugarLimitGrams = sugarLimitGrams
        record.waterMilliliters = waterMilliliters
        record.stepsPerDay = stepsPerDay
        record.workoutMinutesPerWeek = workoutMinutesPerWeek
        record.activeKcalPerDay = activeKcalPerDay
        record.targetWeightKg = targetWeightKg
        record.paceKgPerWeek = paceKgPerWeek
        record.originRaw = originRaw
        record.note = note
        return record
    }
}

/// The Health values Tagwerk keeps of one day (active energy, other apps' nutrition), so past days stay stable.
struct DayHealthBackup: BackupEntity {
    static let modelName = "DayHealthRecord"
    var dayKey: String
    var activeKcal: Double?
    var creditPercent: Int
    var foreignKcal: Double?
    var foreignProtein: Double?
    var foreignCarbs: Double?
    var foreignFat: Double?
    var foreignFiber: Double?
    var foreignSugar: Double?
    var foreignSaturatedFat: Double?
    var foreignSalt: Double?
    var foreignWaterMilliliters: Double?
    var foreignSources: [String]
    var updatedAt: Date

    init(_ record: DayHealthRecord) {
        dayKey = record.dayKey
        activeKcal = record.activeKcal
        creditPercent = record.creditPercent
        foreignKcal = record.foreignKcal
        foreignProtein = record.foreignProtein
        foreignCarbs = record.foreignCarbs
        foreignFat = record.foreignFat
        foreignFiber = record.foreignFiber
        foreignSugar = record.foreignSugar
        foreignSaturatedFat = record.foreignSaturatedFat
        foreignSalt = record.foreignSalt
        foreignWaterMilliliters = record.foreignWaterMilliliters
        foreignSources = record.foreignSources
        updatedAt = record.updatedAt
    }

    func makeRecord() -> DayHealthRecord {
        let record = DayHealthRecord(DayHealth(day: PlanDay(dayKey: dayKey) ?? PlanDay(year: 1970, month: 1, day: 1), activeKcal: activeKcal,
                                               creditPercent: creditPercent), updatedAt: updatedAt)
        record.dayKey = dayKey
        record.activeKcal = activeKcal
        record.creditPercent = creditPercent
        record.foreignKcal = foreignKcal
        record.foreignProtein = foreignProtein
        record.foreignCarbs = foreignCarbs
        record.foreignFat = foreignFat
        record.foreignFiber = foreignFiber
        record.foreignSugar = foreignSugar
        record.foreignSaturatedFat = foreignSaturatedFat
        record.foreignSalt = foreignSalt
        record.foreignWaterMilliliters = foreignWaterMilliliters
        record.foreignSources = foreignSources
        record.updatedAt = updatedAt
        return record
    }
}

struct AppSettingsBackup: Codable, Equatable {
    var workdayStartMinutes: Int
    var workdayEndMinutes: Int
    var lunchStartMinutes: Int
    var lunchDurationMinutes: Int
    var bufferMinutes: Int
    var leadTimeMinutes: Int
    var deadlineCalendarNotifications: Bool
    var githubTaskNotifications: Bool
    var reminderTaskNotifications: Bool
    var localTaskNotifications: Bool
    var selectedCalendarIDs: [String]?
    var selectedReminderListIDs: [String]?
    var setupCompleted: Bool
    var selectedProjectIDs: [String]?
    var weekScheduleData: Data?
    var planCalendarID: String?
    var deadlineCalendarIDs: [String]?
    var defaultTaskMinutes: Int
    var mergeDuplicateEvents: Bool
    var dayTimelineStyle: String
    var prefersTimelineList: Bool
    var aiModelSlug: String?
    var aiReasoningEffort: String?
    var aiWorkAhead: Bool
    var aiLongerDays: String
    var aiPlanningRulesData: Data?
    var goalKilocalories: Int
    var goalWaterMilliliters: Int
    var goalWorkoutsPerWeek: Int
    var goalWorkoutMinutesPerWeek: Int
    var goalStepsPerDay: Int
    var workoutGoalMigrated: Bool
    var proteinGoalEnabled: Bool
    var goalProteinGrams: Int
    /// Optional, so a backup written before the goal plans still decodes; a missing value keeps the device's value.
    var goalPlansMigrated: Bool?
    var activityCreditPercent: Int?
    var mealEstimationConsent: Bool
    var shoppingListID: String?
    var shoppingSuggestionDismissed: Bool
    var shoppingCategoriesSeeded: Bool
    var shoppingSortConsent: Bool
    /// Optional, so a backup written before the consent was versioned still decodes; it then counts as the old text (0) and the
    /// user is asked once more.
    var shoppingSortConsentVersion: Int?
    /// Added with "Rezept hinzufügen"; files without it read as `nil`, which leaves the setting as it is.
    var shoppingRecipeConsent: Bool?
    /// Added with the mail summary (#166); files without it read as `nil`, which leaves the setting as it is.
    var mailSummaryConsent: Bool?
    /// Added with the assistant's access to notes (#173); files without it read as `nil`, which leaves the setting as it is.
    var noteAssistantConsent: Bool?
    var healthCardDismissed: Bool
    var showsIntakeInPlan: Bool
    var widgetShowsNutrition: Bool
    var bedtimeMinutes: Int
    var eveningRemindersEnabled: Bool
    var morningReminderEnabled: Bool
    var morningReminderMinutes: Int
    /// Optional, so a backup written before the weekly planning reminder still decodes; a missing value keeps the default.
    var weekPlanningReminderEnabled: Bool?
    var weekPlanningReminderWeekday: Int?
    var weekPlanningReminderMinutes: Int?
    /// Optional, so a backup written before the choice of the place of Bible Study still decodes; a missing value keeps the default.
    var bibleStudyOfferRaw: String?
    /// Optional, so a backup written before the focus timer settings were part of it still decodes; a missing value keeps the default.
    var focusWorkMinutes: Int?
    var focusShortBreakMinutes: Int?
    var focusLongBreakMinutes: Int?
    var focusRounds: Int?
    var focusUsesPomodoro: Bool?
    /// Optional, so a backup written before the start sheet still decodes; a missing value keeps the default.
    var focusAsksDurationAtStart: Bool?
    var focusLastStartMinutes: Int?
    var effortHistoryInPlanning: Bool?
    /// Optional, so a backup written before the recipe language existed still decodes; a missing value keeps "auto".
    var recipeLanguage: String?
    /// Optional, so a backup written before the separate answer and shopping languages still decodes. A missing answer language
    /// is derived again from the restored dictation language; a missing shopping language keeps the device's value.
    var voiceAnswerLanguage: String?
    var shoppingLanguage: String?
    /// Optional, so a backup written before the adjustable drink portions still decodes; a missing value keeps the device's portions.
    var drinkPresets: [Int]?
    var showsRoutinesInPlan: Bool
    var noteSuggestionConsent: Bool
    var noteSortOrderRaw: String
    /// Optional, so a backup written before the sort direction and the date groups existed still decodes; a missing value keeps
    /// the device's value.
    var noteSortAscending: Bool?
    var noteGroupsByDate: Bool?
    var backupIncludesPrivateNotes: Bool
    var voiceInputEnabled: Bool
    var voiceExplained: Bool
    var voiceRecognitionLanguage: String
    var voiceReadAloud: String
    var voiceGermanVoiceID: String?
    var voiceEnglishVoiceID: String?
    var voiceRate: Double
    var voiceAnnounceActions: Bool
    var voiceModeSendDelay: Double
    var voiceModeSilenceLimit: Double
    var voiceModeExplained: Bool
    /// Optional, so a file from before flexible reminders still opens (it restores the defaults derived from the lead time).
    var reminderDefaultsData: Data?

    init(_ record: AppSettings) {
        reminderDefaultsData = record.reminderDefaultsData
        workdayStartMinutes = record.workdayStartMinutes
        workdayEndMinutes = record.workdayEndMinutes
        lunchStartMinutes = record.lunchStartMinutes
        lunchDurationMinutes = record.lunchDurationMinutes
        bufferMinutes = record.bufferMinutes
        leadTimeMinutes = record.leadTimeMinutes
        deadlineCalendarNotifications = record.deadlineCalendarNotifications
        githubTaskNotifications = record.githubTaskNotifications
        reminderTaskNotifications = record.reminderTaskNotifications
        localTaskNotifications = record.localTaskNotifications
        selectedCalendarIDs = record.selectedCalendarIDs
        selectedReminderListIDs = record.selectedReminderListIDs
        setupCompleted = record.setupCompleted
        selectedProjectIDs = record.selectedProjectIDs
        weekScheduleData = record.weekScheduleData
        planCalendarID = record.planCalendarID
        deadlineCalendarIDs = record.deadlineCalendarIDs
        defaultTaskMinutes = record.defaultTaskMinutes
        mergeDuplicateEvents = record.mergeDuplicateEvents
        dayTimelineStyle = record.dayTimelineStyle
        prefersTimelineList = record.prefersTimelineList
        aiModelSlug = record.aiModelSlug
        aiReasoningEffort = record.aiReasoningEffort
        aiWorkAhead = record.aiWorkAhead
        aiLongerDays = record.aiLongerDays
        aiPlanningRulesData = record.aiPlanningRulesData
        goalKilocalories = record.goalKilocalories
        goalWaterMilliliters = record.goalWaterMilliliters
        goalWorkoutsPerWeek = record.goalWorkoutsPerWeek
        goalWorkoutMinutesPerWeek = record.goalWorkoutMinutesPerWeek
        goalStepsPerDay = record.goalStepsPerDay
        workoutGoalMigrated = record.workoutGoalMigrated
        proteinGoalEnabled = record.proteinGoalEnabled
        goalProteinGrams = record.goalProteinGrams
        goalPlansMigrated = record.goalPlansMigrated
        activityCreditPercent = record.activityCreditPercent
        mealEstimationConsent = record.mealEstimationConsent
        shoppingListID = record.shoppingListID
        shoppingSuggestionDismissed = record.shoppingSuggestionDismissed
        shoppingCategoriesSeeded = record.shoppingCategoriesSeeded
        shoppingSortConsent = record.shoppingSortConsent
        shoppingSortConsentVersion = record.shoppingSortConsentVersion
        shoppingRecipeConsent = record.shoppingRecipeConsent
        mailSummaryConsent = record.mailSummaryConsent
        noteAssistantConsent = record.noteAssistantConsent
        healthCardDismissed = record.healthCardDismissed
        showsIntakeInPlan = record.showsIntakeInPlan
        widgetShowsNutrition = record.widgetShowsNutrition
        bedtimeMinutes = record.bedtimeMinutes
        eveningRemindersEnabled = record.eveningRemindersEnabled
        morningReminderEnabled = record.morningReminderEnabled
        morningReminderMinutes = record.morningReminderMinutes
        weekPlanningReminderEnabled = record.weekPlanningReminderEnabled
        weekPlanningReminderWeekday = record.weekPlanningReminderWeekday
        weekPlanningReminderMinutes = record.weekPlanningReminderMinutes
        bibleStudyOfferRaw = record.bibleStudyOfferRaw
        focusWorkMinutes = record.focusWorkMinutes
        focusShortBreakMinutes = record.focusShortBreakMinutes
        focusLongBreakMinutes = record.focusLongBreakMinutes
        focusRounds = record.focusRounds
        focusUsesPomodoro = record.focusUsesPomodoro
        focusAsksDurationAtStart = record.focusAsksDurationAtStart
        focusLastStartMinutes = record.focusLastStartMinutes
        effortHistoryInPlanning = record.effortHistoryInPlanning
        recipeLanguage = record.recipeLanguage
        voiceAnswerLanguage = record.voiceAnswerLanguage
        shoppingLanguage = record.shoppingLanguage
        drinkPresets = record.drinkPresets
        showsRoutinesInPlan = record.showsRoutinesInPlan
        noteSuggestionConsent = record.noteSuggestionConsent
        noteSortOrderRaw = record.noteSortOrderRaw
        noteSortAscending = record.noteSortAscending
        noteGroupsByDate = record.noteGroupsByDate
        backupIncludesPrivateNotes = record.backupIncludesPrivateNotes
        voiceInputEnabled = record.voiceInputEnabled
        voiceExplained = record.voiceExplained
        voiceRecognitionLanguage = record.voiceRecognitionLanguage
        voiceReadAloud = record.voiceReadAloud
        voiceGermanVoiceID = record.voiceGermanVoiceID
        voiceEnglishVoiceID = record.voiceEnglishVoiceID
        voiceRate = record.voiceRate
        voiceAnnounceActions = record.voiceAnnounceActions
        voiceModeSendDelay = record.voiceModeSendDelay
        voiceModeSilenceLimit = record.voiceModeSilenceLimit
        voiceModeExplained = record.voiceModeExplained
    }

    /// Writes the values into the one settings record the app already holds; it is never replaced.
    func apply(to record: AppSettings) {
        record.reminderDefaultsData = reminderDefaultsData
        record.workdayStartMinutes = workdayStartMinutes
        record.workdayEndMinutes = workdayEndMinutes
        record.lunchStartMinutes = lunchStartMinutes
        record.lunchDurationMinutes = lunchDurationMinutes
        record.bufferMinutes = bufferMinutes
        record.leadTimeMinutes = leadTimeMinutes
        record.deadlineCalendarNotifications = deadlineCalendarNotifications
        record.githubTaskNotifications = githubTaskNotifications
        record.reminderTaskNotifications = reminderTaskNotifications
        record.localTaskNotifications = localTaskNotifications
        record.selectedCalendarIDs = selectedCalendarIDs
        record.selectedReminderListIDs = selectedReminderListIDs
        record.setupCompleted = setupCompleted
        record.selectedProjectIDs = selectedProjectIDs
        record.weekScheduleData = weekScheduleData
        record.planCalendarID = planCalendarID
        record.deadlineCalendarIDs = deadlineCalendarIDs
        record.defaultTaskMinutes = defaultTaskMinutes
        record.mergeDuplicateEvents = mergeDuplicateEvents
        record.dayTimelineStyle = dayTimelineStyle
        record.prefersTimelineList = prefersTimelineList
        record.aiModelSlug = aiModelSlug
        record.aiReasoningEffort = aiReasoningEffort
        record.aiWorkAhead = aiWorkAhead
        record.aiLongerDays = aiLongerDays
        record.aiPlanningRulesData = aiPlanningRulesData
        record.goalKilocalories = goalKilocalories
        record.goalWaterMilliliters = goalWaterMilliliters
        record.goalWorkoutsPerWeek = goalWorkoutsPerWeek
        record.goalWorkoutMinutesPerWeek = goalWorkoutMinutesPerWeek
        record.goalStepsPerDay = goalStepsPerDay
        record.workoutGoalMigrated = workoutGoalMigrated
        record.proteinGoalEnabled = proteinGoalEnabled
        record.goalProteinGrams = goalProteinGrams
        if let goalPlansMigrated { record.goalPlansMigrated = goalPlansMigrated }
        if let activityCreditPercent { record.activityCreditPercent = activityCreditPercent }
        record.mealEstimationConsent = mealEstimationConsent
        record.shoppingListID = shoppingListID
        record.shoppingSuggestionDismissed = shoppingSuggestionDismissed
        record.shoppingCategoriesSeeded = shoppingCategoriesSeeded
        record.shoppingSortConsent = shoppingSortConsent
        record.shoppingSortConsentVersion = shoppingSortConsentVersion ?? 0
        if let shoppingRecipeConsent { record.shoppingRecipeConsent = shoppingRecipeConsent }
        if let mailSummaryConsent { record.mailSummaryConsent = mailSummaryConsent }
        if let noteAssistantConsent { record.noteAssistantConsent = noteAssistantConsent }
        record.healthCardDismissed = healthCardDismissed
        record.showsIntakeInPlan = showsIntakeInPlan
        record.widgetShowsNutrition = widgetShowsNutrition
        record.bedtimeMinutes = bedtimeMinutes
        record.eveningRemindersEnabled = eveningRemindersEnabled
        record.morningReminderEnabled = morningReminderEnabled
        record.morningReminderMinutes = morningReminderMinutes
        if let weekPlanningReminderEnabled { record.weekPlanningReminderEnabled = weekPlanningReminderEnabled }
        if let weekPlanningReminderWeekday { record.weekPlanningReminderWeekday = weekPlanningReminderWeekday }
        if let weekPlanningReminderMinutes { record.weekPlanningReminderMinutes = weekPlanningReminderMinutes }
        if let bibleStudyOfferRaw { record.bibleStudyOfferRaw = bibleStudyOfferRaw }
        if let focusWorkMinutes { record.focusWorkMinutes = focusWorkMinutes }
        if let focusShortBreakMinutes { record.focusShortBreakMinutes = focusShortBreakMinutes }
        if let focusLongBreakMinutes { record.focusLongBreakMinutes = focusLongBreakMinutes }
        if let focusRounds { record.focusRounds = focusRounds }
        if let focusUsesPomodoro { record.focusUsesPomodoro = focusUsesPomodoro }
        if let focusAsksDurationAtStart { record.focusAsksDurationAtStart = focusAsksDurationAtStart }
        if let focusLastStartMinutes { record.focusLastStartMinutes = focusLastStartMinutes }
        if let effortHistoryInPlanning { record.effortHistoryInPlanning = effortHistoryInPlanning }
        if let recipeLanguage { record.recipeLanguage = recipeLanguage }
        if let shoppingLanguage { record.shoppingLanguage = shoppingLanguage }
        if let drinkPresets { record.drinkPresets = drinkPresets }
        record.showsRoutinesInPlan = showsRoutinesInPlan
        record.noteSuggestionConsent = noteSuggestionConsent
        record.noteSortOrderRaw = noteSortOrderRaw
        if let noteSortAscending { record.noteSortAscending = noteSortAscending }
        if let noteGroupsByDate { record.noteGroupsByDate = noteGroupsByDate }
        record.backupIncludesPrivateNotes = backupIncludesPrivateNotes
        record.voiceInputEnabled = voiceInputEnabled
        record.voiceExplained = voiceExplained
        record.voiceRecognitionLanguage = voiceRecognitionLanguage
        // Device state, not part of the backup: the restored list adopts its language again instead of offering a translation.
        record.shoppingItemsLanguage = nil
        // The answer language of an older backup is derived from the restored dictation language, once.
        record.voiceAnswerLanguage = voiceAnswerLanguage
        record.migrateVoiceAnswerLanguageIfNeeded()
        record.voiceReadAloud = voiceReadAloud
        record.voiceGermanVoiceID = voiceGermanVoiceID
        record.voiceEnglishVoiceID = voiceEnglishVoiceID
        record.voiceRate = voiceRate
        record.voiceAnnounceActions = voiceAnnounceActions
        record.voiceModeSendDelay = voiceModeSendDelay
        record.voiceModeSilenceLimit = voiceModeSilenceLimit
        record.voiceModeExplained = voiceModeExplained
    }
}

/// Everything in a backup file. Missing lists read as empty, so a file written by an older version still opens.
struct BackupEntities: Codable, Equatable {
    var settings: AppSettingsBackup?
    var localTasks: [LocalTaskBackup] = []
    var localOccurrenceCompletions: [LocalOccurrenceCompletionBackup] = []
    var dayAssignments: [DayAssignmentBackup] = []
    var dayOverrides: [DayOverrideBackup] = []
    var reminderEstimates: [ReminderEstimateBackup] = []
    var eventTaskLinks: [EventTaskLinkBackup] = []
    var recurringEffortValues: [RecurringEffortValueBackup] = []
    var recurringEffortOverrides: [RecurringEffortOverrideBackup] = []
    var recurringOccurrencesDone: [RecurringOccurrenceDoneBackup] = []
    var dayLunches: [DayLunchBackup] = []
    var eventAvailabilityMarks: [EventAvailabilityMarkBackup] = []
    var eventMergeDecisions: [EventMergeDecisionBackup] = []
    /// Manual travel times (F2). A file from before that read as an empty list: a restore then leaves no overrides, like the
    /// state the file was written in.
    var eventTravelOverrides: [EventTravelOverrideBackup] = []
    var reminderOverrides: [ReminderOverrideBackup] = []
    var eventDeadlineMarks: [EventDeadlineMarkBackup] = []
    var deadlineEventLinks: [DeadlineEventLinkBackup] = []
    var deadlineSuggestionDismissals: [DeadlineSuggestionDismissalBackup] = []
    var meals: [MealBackup] = []
    var drinks: [DrinkBackup] = []
    var workouts: [WorkoutBackup] = []
    var shoppingCategories: [ShoppingCategoryBackup] = []
    var shoppingAssignments: [ShoppingAssignmentBackup] = []
    var notes: [NoteBackup] = []
    var noteFolders: [NoteFolderBackup] = []
    var noteAttachments: [NoteAttachmentBackup] = []
    var bibleStudySessions: [BibleStudySessionBackup] = []
    var habits: [HabitBackup] = []
    var habitChecks: [HabitCheckBackup] = []
    var routineDays: [RoutineDayBackup] = []
    var eveningChecklistItems: [EveningChecklistItemBackup] = []
    var focusMarks: [FocusMarkBackup] = []
    /// Optional on purpose: a file written before the focus data was part of the backup has no such lists. `nil` means "the file says
    /// nothing about it", and a restore then leaves the focus data of this device alone instead of wiping it.
    var focusSessions: [FocusSessionBackup]?
    var effortSamples: [EffortSampleBackup]?
    var weekReflections: [WeekReflectionBackup] = []
    /// Optional on purpose, like the focus data: a file written before the goal plans has no list. A restore then rebuilds the
    /// first plan from the restored single goals of the settings instead of keeping plans that do not match them.
    var goalPlans: [GoalPlanBackup]?
    /// Optional like the focus data: a file without the list leaves the stored Health values of this device alone.
    var dayHealth: [DayHealthBackup]?

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        settings = try container.decodeIfPresent(AppSettingsBackup.self, forKey: .settings)
        localTasks = try container.decodeIfPresent([LocalTaskBackup].self, forKey: .localTasks) ?? []
        localOccurrenceCompletions = try container.decodeIfPresent([LocalOccurrenceCompletionBackup].self, forKey: .localOccurrenceCompletions) ?? []
        dayAssignments = try container.decodeIfPresent([DayAssignmentBackup].self, forKey: .dayAssignments) ?? []
        dayOverrides = try container.decodeIfPresent([DayOverrideBackup].self, forKey: .dayOverrides) ?? []
        reminderEstimates = try container.decodeIfPresent([ReminderEstimateBackup].self, forKey: .reminderEstimates) ?? []
        eventTaskLinks = try container.decodeIfPresent([EventTaskLinkBackup].self, forKey: .eventTaskLinks) ?? []
        recurringEffortValues = try container.decodeIfPresent([RecurringEffortValueBackup].self, forKey: .recurringEffortValues) ?? []
        recurringEffortOverrides = try container.decodeIfPresent([RecurringEffortOverrideBackup].self, forKey: .recurringEffortOverrides) ?? []
        recurringOccurrencesDone = try container.decodeIfPresent([RecurringOccurrenceDoneBackup].self, forKey: .recurringOccurrencesDone) ?? []
        dayLunches = try container.decodeIfPresent([DayLunchBackup].self, forKey: .dayLunches) ?? []
        eventAvailabilityMarks = try container.decodeIfPresent([EventAvailabilityMarkBackup].self, forKey: .eventAvailabilityMarks) ?? []
        eventMergeDecisions = try container.decodeIfPresent([EventMergeDecisionBackup].self, forKey: .eventMergeDecisions) ?? []
        eventTravelOverrides = try container.decodeIfPresent([EventTravelOverrideBackup].self, forKey: .eventTravelOverrides) ?? []
        reminderOverrides = try container.decodeIfPresent([ReminderOverrideBackup].self, forKey: .reminderOverrides) ?? []
        eventDeadlineMarks = try container.decodeIfPresent([EventDeadlineMarkBackup].self, forKey: .eventDeadlineMarks) ?? []
        deadlineEventLinks = try container.decodeIfPresent([DeadlineEventLinkBackup].self, forKey: .deadlineEventLinks) ?? []
        deadlineSuggestionDismissals = try container.decodeIfPresent([DeadlineSuggestionDismissalBackup].self, forKey: .deadlineSuggestionDismissals) ?? []
        meals = try container.decodeIfPresent([MealBackup].self, forKey: .meals) ?? []
        drinks = try container.decodeIfPresent([DrinkBackup].self, forKey: .drinks) ?? []
        workouts = try container.decodeIfPresent([WorkoutBackup].self, forKey: .workouts) ?? []
        shoppingCategories = try container.decodeIfPresent([ShoppingCategoryBackup].self, forKey: .shoppingCategories) ?? []
        shoppingAssignments = try container.decodeIfPresent([ShoppingAssignmentBackup].self, forKey: .shoppingAssignments) ?? []
        notes = try container.decodeIfPresent([NoteBackup].self, forKey: .notes) ?? []
        noteFolders = try container.decodeIfPresent([NoteFolderBackup].self, forKey: .noteFolders) ?? []
        noteAttachments = try container.decodeIfPresent([NoteAttachmentBackup].self, forKey: .noteAttachments) ?? []
        bibleStudySessions = try container.decodeIfPresent([BibleStudySessionBackup].self, forKey: .bibleStudySessions) ?? []
        habits = try container.decodeIfPresent([HabitBackup].self, forKey: .habits) ?? []
        habitChecks = try container.decodeIfPresent([HabitCheckBackup].self, forKey: .habitChecks) ?? []
        routineDays = try container.decodeIfPresent([RoutineDayBackup].self, forKey: .routineDays) ?? []
        eveningChecklistItems = try container.decodeIfPresent([EveningChecklistItemBackup].self, forKey: .eveningChecklistItems) ?? []
        focusMarks = try container.decodeIfPresent([FocusMarkBackup].self, forKey: .focusMarks) ?? []
        focusSessions = try container.decodeIfPresent([FocusSessionBackup].self, forKey: .focusSessions)
        effortSamples = try container.decodeIfPresent([EffortSampleBackup].self, forKey: .effortSamples)
        weekReflections = try container.decodeIfPresent([WeekReflectionBackup].self, forKey: .weekReflections) ?? []
        goalPlans = try container.decodeIfPresent([GoalPlanBackup].self, forKey: .goalPlans)
        dayHealth = try container.decodeIfPresent([DayHealthBackup].self, forKey: .dayHealth)
    }

    /// Model names of everything the file holds, for the completeness check against the schema.
    static let modelNames: Set<String> = ["AppSettings", LocalTaskBackup.modelName, LocalOccurrenceCompletionBackup.modelName, DayAssignmentBackup.modelName, DayOverrideBackup.modelName, ReminderEstimateBackup.modelName, EventTaskLinkBackup.modelName, RecurringEffortValueBackup.modelName, RecurringEffortOverrideBackup.modelName, RecurringOccurrenceDoneBackup.modelName, DayLunchBackup.modelName, EventAvailabilityMarkBackup.modelName, EventMergeDecisionBackup.modelName, EventTravelOverrideBackup.modelName, ReminderOverrideBackup.modelName, EventDeadlineMarkBackup.modelName, DeadlineEventLinkBackup.modelName, DeadlineSuggestionDismissalBackup.modelName, MealBackup.modelName, DrinkBackup.modelName, WorkoutBackup.modelName, ShoppingCategoryBackup.modelName, ShoppingAssignmentBackup.modelName, NoteBackup.modelName, NoteFolderBackup.modelName, NoteAttachmentBackup.modelName, BibleStudySessionBackup.modelName, HabitBackup.modelName, HabitCheckBackup.modelName, RoutineDayBackup.modelName, EveningChecklistItemBackup.modelName, FocusMarkBackup.modelName, FocusSessionBackup.modelName, EffortSampleBackup.modelName, WeekReflectionBackup.modelName, GoalPlanBackup.modelName, DayHealthBackup.modelName]
}

extension BackupEntities {
    /// All records of the models in the backup. `includePrivate: false` leaves out journal and Bible Study content: the notes of
    /// those kinds, their system folders, the sessions and the attachments of those notes. `attachments` supplies the bytes
    /// of the attachments; without it the file holds none.
    @MainActor
    init(collecting context: ModelContext, settings: AppSettings, includePrivate: Bool, attachments: NoteAttachmentStore? = nil) {
        self.init()
        self.settings = AppSettingsBackup(settings)
        localTasks = Self.fetch(LocalTask.self, in: context).map(LocalTaskBackup.init)
        localOccurrenceCompletions = Self.fetch(LocalOccurrenceCompletion.self, in: context).map(LocalOccurrenceCompletionBackup.init)
        dayAssignments = Self.fetch(DayAssignment.self, in: context).map(DayAssignmentBackup.init)
        dayOverrides = Self.fetch(DayOverrideRecord.self, in: context).map(DayOverrideBackup.init)
        reminderEstimates = Self.fetch(ReminderEstimateRecord.self, in: context).map(ReminderEstimateBackup.init)
        eventTaskLinks = Self.fetch(EventTaskLink.self, in: context).map(EventTaskLinkBackup.init)
        recurringEffortValues = Self.fetch(RecurringEffortValue.self, in: context).map(RecurringEffortValueBackup.init)
        recurringEffortOverrides = Self.fetch(RecurringEffortOverride.self, in: context).map(RecurringEffortOverrideBackup.init)
        recurringOccurrencesDone = Self.fetch(RecurringOccurrenceDone.self, in: context).map(RecurringOccurrenceDoneBackup.init)
        dayLunches = Self.fetch(DayLunchRecord.self, in: context).map(DayLunchBackup.init)
        eventAvailabilityMarks = Self.fetch(EventAvailabilityMark.self, in: context).map(EventAvailabilityMarkBackup.init)
        eventMergeDecisions = Self.fetch(EventMergeDecision.self, in: context).map(EventMergeDecisionBackup.init)
        eventTravelOverrides = Self.fetch(EventTravelOverride.self, in: context).map(EventTravelOverrideBackup.init)
        reminderOverrides = Self.fetch(ReminderOverrideRecord.self, in: context).map(ReminderOverrideBackup.init)
        eventDeadlineMarks = Self.fetch(EventDeadlineMark.self, in: context).map(EventDeadlineMarkBackup.init)
        deadlineEventLinks = Self.fetch(DeadlineEventLink.self, in: context).map(DeadlineEventLinkBackup.init)
        deadlineSuggestionDismissals = Self.fetch(DeadlineSuggestionDismissal.self, in: context).map(DeadlineSuggestionDismissalBackup.init)
        meals = Self.fetch(MealRecord.self, in: context).map(MealBackup.init)
        drinks = Self.fetch(DrinkRecord.self, in: context).map(DrinkBackup.init)
        workouts = Self.fetch(WorkoutRecord.self, in: context).map(WorkoutBackup.init)
        shoppingCategories = Self.fetch(ShoppingCategory.self, in: context).map(ShoppingCategoryBackup.init)
        shoppingAssignments = Self.fetch(ShoppingAssignment.self, in: context).map(ShoppingAssignmentBackup.init)
        notes = Self.fetch(NoteRecord.self, in: context).filter { includePrivate || $0.kind.isInDefaultBackup }.map(NoteBackup.init)
        noteFolders = Self.fetch(NoteFolderRecord.self, in: context).filter { includePrivate || Self.isInDefaultBackup(folderRole: $0.role) }.map(NoteFolderBackup.init)
        let keptNoteIDs = Set(notes.map(\.id))
        noteAttachments = attachments.map { store in
            store.records().filter { $0.noteID.map(keptNoteIDs.contains) ?? false }
                .compactMap { record in store.data(for: record.id).map { NoteAttachmentBackup(record, data: $0) } }
        } ?? []
        bibleStudySessions = includePrivate ? Self.fetch(BibleStudySessionRecord.self, in: context).map(BibleStudySessionBackup.init) : []
        habits = Self.fetch(HabitRecord.self, in: context).map(HabitBackup.init)
        habitChecks = Self.fetch(HabitCheckRecord.self, in: context).map(HabitCheckBackup.init)
        routineDays = Self.fetch(RoutineDayRecord.self, in: context).map(RoutineDayBackup.init)
        eveningChecklistItems = Self.fetch(EveningChecklistItemRecord.self, in: context).map(EveningChecklistItemBackup.init)
        focusMarks = Self.fetch(FocusMarkRecord.self, in: context).map(FocusMarkBackup.init)
        // Only closed sessions: a running one is device-bound state and is left out.
        focusSessions = Self.fetch(FocusSessionRecord.self, in: context).filter { $0.outcomeRaw != nil }.map(FocusSessionBackup.init)
        effortSamples = Self.fetch(EffortSampleRecord.self, in: context).map(EffortSampleBackup.init)
        weekReflections = Self.fetch(WeekReflectionRecord.self, in: context).map(WeekReflectionBackup.init)
        goalPlans = Self.fetch(GoalPlanRecord.self, in: context).map(GoalPlanBackup.init)
        dayHealth = Self.fetch(DayHealthRecord.self, in: context).map(DayHealthBackup.init)
    }

    /// Replaces the data of every model in the file with the content of the file. The settings record is updated in place. When
    /// `replacePrivate` is false (the file was written without journal and Bible Study content), the journal and Bible Study
    /// notes, their folders and the sessions on this device stay as they are.
    @MainActor
    func restore(into context: ModelContext, settings: AppSettings, replacePrivate: Bool, attachments: NoteAttachmentStore? = nil) throws {
        self.settings?.apply(to: settings)
        if let attachments {
            // The attachments of notes that stay on this device (private notes not in the file) stay too.
            let protectedNoteIDs = Set(Self.fetch(NoteRecord.self, in: context)
                .filter { !replacePrivate && !$0.kind.isInDefaultBackup }.map(\.id))
            attachments.delete(ids: attachments.records().filter { $0.noteID.map { !protectedNoteIDs.contains($0) } ?? true }.map(\.id))
        }
        Self.delete(LocalTask.self, in: context) { _ in true }
        Self.delete(LocalOccurrenceCompletion.self, in: context) { _ in true }
        Self.delete(DayAssignment.self, in: context) { _ in true }
        Self.delete(DayOverrideRecord.self, in: context) { _ in true }
        Self.delete(ReminderEstimateRecord.self, in: context) { _ in true }
        Self.delete(EventTaskLink.self, in: context) { _ in true }
        Self.delete(RecurringEffortValue.self, in: context) { _ in true }
        Self.delete(RecurringEffortOverride.self, in: context) { _ in true }
        Self.delete(RecurringOccurrenceDone.self, in: context) { _ in true }
        Self.delete(DayLunchRecord.self, in: context) { _ in true }
        Self.delete(EventAvailabilityMark.self, in: context) { _ in true }
        Self.delete(EventMergeDecision.self, in: context) { _ in true }
        Self.delete(EventTravelOverride.self, in: context) { _ in true }
        Self.delete(ReminderOverrideRecord.self, in: context) { _ in true }
        Self.delete(EventDeadlineMark.self, in: context) { _ in true }
        Self.delete(DeadlineEventLink.self, in: context) { _ in true }
        Self.delete(DeadlineSuggestionDismissal.self, in: context) { _ in true }
        Self.delete(MealRecord.self, in: context) { _ in true }
        Self.delete(DrinkRecord.self, in: context) { _ in true }
        Self.delete(WorkoutRecord.self, in: context) { _ in true }
        Self.delete(ShoppingCategory.self, in: context) { _ in true }
        Self.delete(ShoppingAssignment.self, in: context) { _ in true }
        Self.delete(NoteRecord.self, in: context) { replacePrivate || $0.kind.isInDefaultBackup }
        Self.delete(NoteFolderRecord.self, in: context) { replacePrivate || Self.isInDefaultBackup(folderRole: $0.role) }
        if replacePrivate { Self.delete(BibleStudySessionRecord.self, in: context) { _ in true } }
        Self.delete(HabitRecord.self, in: context) { _ in true }
        Self.delete(HabitCheckRecord.self, in: context) { _ in true }
        Self.delete(RoutineDayRecord.self, in: context) { _ in true }
        Self.delete(EveningChecklistItemRecord.self, in: context) { _ in true }
        Self.delete(FocusMarkRecord.self, in: context) { _ in true }
        // A running focus session belongs to the live timer of this device and stays; only closed sessions are replaced. Files
        // from before the focus data was part of the backup leave the sessions and samples of this device untouched.
        if focusSessions != nil { Self.delete(FocusSessionRecord.self, in: context) { $0.outcomeRaw != nil } }
        if effortSamples != nil { Self.delete(EffortSampleRecord.self, in: context) { _ in true } }
        Self.delete(WeekReflectionRecord.self, in: context) { _ in true }
        Self.delete(GoalPlanRecord.self, in: context) { _ in true }
        // A file without goal plans: the plans of this device would not match the restored single goals, so the first plan is
        // rebuilt from them below.
        if goalPlans == nil { settings.goalPlansMigrated = false }
        // Files from before the stored Health values leave those of this device untouched.
        if dayHealth != nil { Self.delete(DayHealthRecord.self, in: context) { _ in true } }
        // Unique keys of the old records must be gone before records with the same keys come in.
        try context.save()
        for item in localTasks { context.insert(item.makeRecord()) }
        for item in localOccurrenceCompletions { context.insert(item.makeRecord()) }
        for item in dayAssignments { context.insert(item.makeRecord()) }
        for item in dayOverrides { context.insert(item.makeRecord()) }
        for item in reminderEstimates { context.insert(item.makeRecord()) }
        for item in eventTaskLinks { context.insert(item.makeRecord()) }
        for item in recurringEffortValues { context.insert(item.makeRecord()) }
        for item in recurringEffortOverrides { context.insert(item.makeRecord()) }
        for item in recurringOccurrencesDone { context.insert(item.makeRecord()) }
        for item in dayLunches { context.insert(item.makeRecord()) }
        for item in eventAvailabilityMarks { context.insert(item.makeRecord()) }
        for item in eventMergeDecisions { context.insert(item.makeRecord()) }
        for item in eventTravelOverrides { context.insert(item.makeRecord()) }
        for item in reminderOverrides { context.insert(item.makeRecord()) }
        for item in eventDeadlineMarks { context.insert(item.makeRecord()) }
        for item in deadlineEventLinks { context.insert(item.makeRecord()) }
        for item in deadlineSuggestionDismissals { context.insert(item.makeRecord()) }
        for item in meals { context.insert(item.makeRecord()) }
        for item in drinks { context.insert(item.makeRecord()) }
        for item in workouts { context.insert(item.makeRecord()) }
        for item in shoppingCategories { context.insert(item.makeRecord()) }
        for item in shoppingAssignments { context.insert(item.makeRecord()) }
        for item in notes where replacePrivate || (NoteKind(rawValue: item.kindRaw) ?? .free).isInDefaultBackup { context.insert(item.makeRecord()) }
        for item in noteFolders where replacePrivate || Self.isInDefaultBackup(folderRole: item.roleRaw.flatMap(NoteFolderRole.init(rawValue:))) { context.insert(item.makeRecord()) }
        if let attachments {
            for item in noteAttachments {
                try attachments.restore(id: item.id, noteID: item.noteID, fileName: item.fileName, typeIdentifier: item.typeIdentifier,
                                        createdAt: item.createdAt, data: item.data)
            }
        }
        if replacePrivate { for item in bibleStudySessions { context.insert(item.makeRecord()) } }
        for item in habits { context.insert(item.makeRecord()) }
        for item in habitChecks { context.insert(item.makeRecord()) }
        for item in routineDays { context.insert(item.makeRecord()) }
        for item in eveningChecklistItems { context.insert(item.makeRecord()) }
        for item in focusMarks { context.insert(item.makeRecord()) }
        let keptSessionIDs = Set(Self.fetch(FocusSessionRecord.self, in: context).map(\.id))
        for item in focusSessions ?? [] where item.outcomeRaw != nil && !keptSessionIDs.contains(item.id) { context.insert(item.makeRecord()) }
        for item in effortSamples ?? [] { context.insert(item.makeRecord()) }
        for item in weekReflections { context.insert(item.makeRecord()) }
        for item in goalPlans ?? [] { context.insert(item.makeRecord()) }
        for item in dayHealth ?? [] { context.insert(item.makeRecord()) }
        try context.save()
        if goalPlans == nil { GoalStore(context: context, settings: settings).migrateIfNeeded() }
    }

    /// Whether a note folder is part of a backup written without the switch "Tagebuch und Bible Study einschließen": the
    /// user's own folders and the fixed folders of Brain Dump, Tagesstart, Tagesabschluss and Dream Log are, journal and
    /// Bible Study are not.
    private static func isInDefaultBackup(folderRole: NoteFolderRole?) -> Bool {
        folderRole?.isInDefaultBackup ?? true
    }

    @MainActor
    private static func fetch<Record: PersistentModel>(_ type: Record.Type, in context: ModelContext) -> [Record] {
        (try? context.fetch(FetchDescriptor<Record>())) ?? []
    }

    @MainActor
    private static func delete<Record: PersistentModel>(_ type: Record.Type, in context: ModelContext, where matches: (Record) -> Bool) {
        for record in fetch(type, in: context) where matches(record) { context.delete(record) }
    }
}
