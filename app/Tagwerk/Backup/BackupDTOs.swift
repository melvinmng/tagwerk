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

struct WeekReflectionBackup: BackupEntity {
    static let modelName = "WeekReflectionRecord"
    var weekKey: String
    var wentWell: String
    var burdens: String
    var plannedAppointments: Bool
    var plannedHabits: Bool
    var plannedTasks: Bool
    var updatedAt: Date

    init(_ record: WeekReflectionRecord) {
        weekKey = record.weekKey
        wentWell = record.wentWell
        burdens = record.burdens
        plannedAppointments = record.plannedAppointments
        plannedHabits = record.plannedHabits
        plannedTasks = record.plannedTasks
        updatedAt = record.updatedAt
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
        return record
    }
}

/// The settings that travel with a backup. Left out: the model list from ChatGPT (a cache) and everything that names a place on
/// this device (the backup folder and its state). Secrets are not in the database at all; they live in the Keychain.
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
    var mealEstimationConsent: Bool
    var shoppingListID: String?
    var shoppingSuggestionDismissed: Bool
    var shoppingCategoriesSeeded: Bool
    var shoppingSortConsent: Bool
    var healthCardDismissed: Bool
    var showsIntakeInPlan: Bool
    var widgetShowsNutrition: Bool
    var bedtimeMinutes: Int
    var eveningRemindersEnabled: Bool
    var morningReminderEnabled: Bool
    var morningReminderMinutes: Int
    var showsRoutinesInPlan: Bool
    var noteSuggestionConsent: Bool
    var noteSortOrderRaw: String
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

    init(_ record: AppSettings) {
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
        mealEstimationConsent = record.mealEstimationConsent
        shoppingListID = record.shoppingListID
        shoppingSuggestionDismissed = record.shoppingSuggestionDismissed
        shoppingCategoriesSeeded = record.shoppingCategoriesSeeded
        shoppingSortConsent = record.shoppingSortConsent
        healthCardDismissed = record.healthCardDismissed
        showsIntakeInPlan = record.showsIntakeInPlan
        widgetShowsNutrition = record.widgetShowsNutrition
        bedtimeMinutes = record.bedtimeMinutes
        eveningRemindersEnabled = record.eveningRemindersEnabled
        morningReminderEnabled = record.morningReminderEnabled
        morningReminderMinutes = record.morningReminderMinutes
        showsRoutinesInPlan = record.showsRoutinesInPlan
        noteSuggestionConsent = record.noteSuggestionConsent
        noteSortOrderRaw = record.noteSortOrderRaw
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
        record.mealEstimationConsent = mealEstimationConsent
        record.shoppingListID = shoppingListID
        record.shoppingSuggestionDismissed = shoppingSuggestionDismissed
        record.shoppingCategoriesSeeded = shoppingCategoriesSeeded
        record.shoppingSortConsent = shoppingSortConsent
        record.healthCardDismissed = healthCardDismissed
        record.showsIntakeInPlan = showsIntakeInPlan
        record.widgetShowsNutrition = widgetShowsNutrition
        record.bedtimeMinutes = bedtimeMinutes
        record.eveningRemindersEnabled = eveningRemindersEnabled
        record.morningReminderEnabled = morningReminderEnabled
        record.morningReminderMinutes = morningReminderMinutes
        record.showsRoutinesInPlan = showsRoutinesInPlan
        record.noteSuggestionConsent = noteSuggestionConsent
        record.noteSortOrderRaw = noteSortOrderRaw
        record.backupIncludesPrivateNotes = backupIncludesPrivateNotes
        record.voiceInputEnabled = voiceInputEnabled
        record.voiceExplained = voiceExplained
        record.voiceRecognitionLanguage = voiceRecognitionLanguage
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
    var bibleStudySessions: [BibleStudySessionBackup] = []
    var habits: [HabitBackup] = []
    var habitChecks: [HabitCheckBackup] = []
    var routineDays: [RoutineDayBackup] = []
    var eveningChecklistItems: [EveningChecklistItemBackup] = []
    var focusMarks: [FocusMarkBackup] = []
    var weekReflections: [WeekReflectionBackup] = []

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
        bibleStudySessions = try container.decodeIfPresent([BibleStudySessionBackup].self, forKey: .bibleStudySessions) ?? []
        habits = try container.decodeIfPresent([HabitBackup].self, forKey: .habits) ?? []
        habitChecks = try container.decodeIfPresent([HabitCheckBackup].self, forKey: .habitChecks) ?? []
        routineDays = try container.decodeIfPresent([RoutineDayBackup].self, forKey: .routineDays) ?? []
        eveningChecklistItems = try container.decodeIfPresent([EveningChecklistItemBackup].self, forKey: .eveningChecklistItems) ?? []
        focusMarks = try container.decodeIfPresent([FocusMarkBackup].self, forKey: .focusMarks) ?? []
        weekReflections = try container.decodeIfPresent([WeekReflectionBackup].self, forKey: .weekReflections) ?? []
    }

    /// Model names of everything the file holds, for the completeness check against the schema.
    static let modelNames: Set<String> = ["AppSettings", LocalTaskBackup.modelName, LocalOccurrenceCompletionBackup.modelName, DayAssignmentBackup.modelName, DayOverrideBackup.modelName, ReminderEstimateBackup.modelName, EventTaskLinkBackup.modelName, RecurringEffortValueBackup.modelName, RecurringEffortOverrideBackup.modelName, RecurringOccurrenceDoneBackup.modelName, DayLunchBackup.modelName, EventAvailabilityMarkBackup.modelName, EventMergeDecisionBackup.modelName, EventDeadlineMarkBackup.modelName, DeadlineEventLinkBackup.modelName, DeadlineSuggestionDismissalBackup.modelName, MealBackup.modelName, DrinkBackup.modelName, WorkoutBackup.modelName, ShoppingCategoryBackup.modelName, ShoppingAssignmentBackup.modelName, NoteBackup.modelName, NoteFolderBackup.modelName, BibleStudySessionBackup.modelName, HabitBackup.modelName, HabitCheckBackup.modelName, RoutineDayBackup.modelName, EveningChecklistItemBackup.modelName, FocusMarkBackup.modelName, WeekReflectionBackup.modelName]
}

extension BackupEntities {
    /// All records of the models in the backup. `includePrivate: false` leaves out journal and Bible Study content: the notes of
    /// those kinds, their system folders and the sessions.
    @MainActor
    init(collecting context: ModelContext, settings: AppSettings, includePrivate: Bool) {
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
        eventDeadlineMarks = Self.fetch(EventDeadlineMark.self, in: context).map(EventDeadlineMarkBackup.init)
        deadlineEventLinks = Self.fetch(DeadlineEventLink.self, in: context).map(DeadlineEventLinkBackup.init)
        deadlineSuggestionDismissals = Self.fetch(DeadlineSuggestionDismissal.self, in: context).map(DeadlineSuggestionDismissalBackup.init)
        meals = Self.fetch(MealRecord.self, in: context).map(MealBackup.init)
        drinks = Self.fetch(DrinkRecord.self, in: context).map(DrinkBackup.init)
        workouts = Self.fetch(WorkoutRecord.self, in: context).map(WorkoutBackup.init)
        shoppingCategories = Self.fetch(ShoppingCategory.self, in: context).map(ShoppingCategoryBackup.init)
        shoppingAssignments = Self.fetch(ShoppingAssignment.self, in: context).map(ShoppingAssignmentBackup.init)
        notes = Self.fetch(NoteRecord.self, in: context).filter { includePrivate || !$0.kind.isPrivate }.map(NoteBackup.init)
        noteFolders = Self.fetch(NoteFolderRecord.self, in: context).filter { includePrivate || $0.role == nil }.map(NoteFolderBackup.init)
        bibleStudySessions = includePrivate ? Self.fetch(BibleStudySessionRecord.self, in: context).map(BibleStudySessionBackup.init) : []
        habits = Self.fetch(HabitRecord.self, in: context).map(HabitBackup.init)
        habitChecks = Self.fetch(HabitCheckRecord.self, in: context).map(HabitCheckBackup.init)
        routineDays = Self.fetch(RoutineDayRecord.self, in: context).map(RoutineDayBackup.init)
        eveningChecklistItems = Self.fetch(EveningChecklistItemRecord.self, in: context).map(EveningChecklistItemBackup.init)
        focusMarks = Self.fetch(FocusMarkRecord.self, in: context).map(FocusMarkBackup.init)
        weekReflections = Self.fetch(WeekReflectionRecord.self, in: context).map(WeekReflectionBackup.init)
    }

    /// Replaces the data of every model in the file with the content of the file. The settings record is updated in place. When
    /// `replacePrivate` is false (the file was written without journal and Bible Study content), the journal and Bible Study
    /// notes, their folders and the sessions on this device stay as they are.
    @MainActor
    func restore(into context: ModelContext, settings: AppSettings, replacePrivate: Bool) {
        self.settings?.apply(to: settings)
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
        Self.delete(EventDeadlineMark.self, in: context) { _ in true }
        Self.delete(DeadlineEventLink.self, in: context) { _ in true }
        Self.delete(DeadlineSuggestionDismissal.self, in: context) { _ in true }
        Self.delete(MealRecord.self, in: context) { _ in true }
        Self.delete(DrinkRecord.self, in: context) { _ in true }
        Self.delete(WorkoutRecord.self, in: context) { _ in true }
        Self.delete(ShoppingCategory.self, in: context) { _ in true }
        Self.delete(ShoppingAssignment.self, in: context) { _ in true }
        Self.delete(NoteRecord.self, in: context) { replacePrivate || !$0.kind.isPrivate }
        Self.delete(NoteFolderRecord.self, in: context) { replacePrivate || $0.role == nil }
        if replacePrivate { Self.delete(BibleStudySessionRecord.self, in: context) { _ in true } }
        Self.delete(HabitRecord.self, in: context) { _ in true }
        Self.delete(HabitCheckRecord.self, in: context) { _ in true }
        Self.delete(RoutineDayRecord.self, in: context) { _ in true }
        Self.delete(EveningChecklistItemRecord.self, in: context) { _ in true }
        Self.delete(FocusMarkRecord.self, in: context) { _ in true }
        Self.delete(WeekReflectionRecord.self, in: context) { _ in true }
        // Unique keys of the old records must be gone before records with the same keys come in.
        try? context.save()
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
        for item in eventDeadlineMarks { context.insert(item.makeRecord()) }
        for item in deadlineEventLinks { context.insert(item.makeRecord()) }
        for item in deadlineSuggestionDismissals { context.insert(item.makeRecord()) }
        for item in meals { context.insert(item.makeRecord()) }
        for item in drinks { context.insert(item.makeRecord()) }
        for item in workouts { context.insert(item.makeRecord()) }
        for item in shoppingCategories { context.insert(item.makeRecord()) }
        for item in shoppingAssignments { context.insert(item.makeRecord()) }
        for item in notes where replacePrivate || !(NoteKind(rawValue: item.kindRaw) ?? .free).isPrivate { context.insert(item.makeRecord()) }
        for item in noteFolders where replacePrivate || NoteFolderRole(rawValue: item.roleRaw ?? "") == nil { context.insert(item.makeRecord()) }
        if replacePrivate { for item in bibleStudySessions { context.insert(item.makeRecord()) } }
        for item in habits { context.insert(item.makeRecord()) }
        for item in habitChecks { context.insert(item.makeRecord()) }
        for item in routineDays { context.insert(item.makeRecord()) }
        for item in eveningChecklistItems { context.insert(item.makeRecord()) }
        for item in focusMarks { context.insert(item.makeRecord()) }
        for item in weekReflections { context.insert(item.makeRecord()) }
        try? context.save()
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
