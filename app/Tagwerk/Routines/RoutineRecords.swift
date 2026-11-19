import Foundation
import Observation
import SwiftData
import TagwerkCore

/// What a day holds for the routines (phase 7 design §5.2). Local only; `dayKey` is unique like `DayOverrideRecord`.
@Model
final class RoutineDayRecord {
    @Attribute(.unique) var dayKey: String = ""
    var year: Int = 1970
    var month: Int = 1
    var day: Int = 1
    /// JSON of `[String]`, at most three.
    var gratitudeData: Data? = nil
    var startCompletedAt: Date? = nil
    /// "✕" on the morning card.
    var startDismissed: Bool = false
    var closeCompletedAt: Date? = nil
    /// JSON of `[UUID]`, the checked checklist points.
    var checkedItemIDsData: Data? = nil

    init(day: PlanDay) {
        self.dayKey = day.dayKey
        self.year = day.year
        self.month = day.month
        self.day = day.day
    }

    var value: RoutineDayValue {
        let gratitude = gratitudeData.flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        let checked = checkedItemIDsData.flatMap { try? JSONDecoder().decode([UUID].self, from: $0) } ?? []
        return RoutineDayValue(gratitude: gratitude, startCompletedAt: startCompletedAt, startDismissed: startDismissed,
                               closeCompletedAt: closeCompletedAt, checkedItemIDs: Set(checked))
    }

    func apply(_ value: RoutineDayValue) {
        gratitudeData = value.gratitude.isEmpty ? nil : try? JSONEncoder().encode(value.gratitude)
        startCompletedAt = value.startCompletedAt
        startDismissed = value.startDismissed
        closeCompletedAt = value.closeCompletedAt
        checkedItemIDsData = value.checkedItemIDs.isEmpty ? nil : try? JSONEncoder().encode(value.checkedItemIDs.sorted { $0.uuidString < $1.uuidString })
    }
}

/// A point of the evening checklist (design §5.2).
@Model
final class EveningChecklistItemRecord {
    var id: UUID = UUID()
    var title: String = ""
    var order: Int = 0
    /// Minutes before the target bedtime; `nil` means no reminder.
    var offsetMinutes: Int? = nil
    var createdAt: Date = Date.now

    init(_ item: ChecklistItem, createdAt: Date) {
        self.id = item.id
        self.createdAt = createdAt
        apply(item)
    }

    func apply(_ item: ChecklistItem) {
        title = item.title
        order = item.order
        offsetMinutes = item.offsetMinutes
    }

    var value: ChecklistItem { ChecklistItem(id: id, title: title, order: order, offsetMinutes: offsetMinutes) }
}

/// Reads and writes the routine days and the evening checklist. Reading never inserts. Nothing here leaves the device.
@MainActor
@Observable
final class RoutineStore {
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let now: () -> Date
    /// Bumped by every write; views read it to follow changes.
    private(set) var revision = 0

    init(context: ModelContext, now: @escaping () -> Date = Date.init) {
        self.context = context
        self.now = now
    }

    // MARK: Days

    /// `.empty` without a record.
    func day(_ day: PlanDay) -> RoutineDayValue {
        _ = revision
        return dayRecord(day)?.value ?? .empty
    }

    /// Applies the change; the record is inserted on the first write.
    func update(_ day: PlanDay, _ change: (inout RoutineDayValue) -> Void) {
        let record = dayRecord(day) ?? { let new = RoutineDayRecord(day: day); context.insert(new); return new }()
        var value = record.value
        change(&value)
        value.gratitude = RoutineDayValue.normalizedGratitude(value.gratitude)
        record.apply(value)
        save()
    }

    private func dayRecord(_ day: PlanDay) -> RoutineDayRecord? {
        let key = day.dayKey
        return try? context.fetch(FetchDescriptor<RoutineDayRecord>(predicate: #Predicate { $0.dayKey == key })).first
    }

    // MARK: Checklist

    /// By order.
    func checklist() -> [ChecklistItem] {
        _ = revision
        return itemRecords().sorted { ($0.order, $0.createdAt) < ($1.order, $1.createdAt) }.map(\.value)
    }

    /// Inserts or updates by id. `false` for a ninth point or a fifth reminder; the title is cut to 40 characters and
    /// the offset is rounded to steps of five minutes within 0 to 240.
    @discardableResult
    func saveItem(_ item: ChecklistItem) -> Bool {
        var item = item
        item.title = String(item.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(RoutineSchedule.titleLimit))
        item.offsetMinutes = item.offsetMinutes.map(Self.normalizedOffset)
        let others = checklist().filter { $0.id != item.id }
        let existing = itemRecord(item.id)
        if existing == nil, others.count >= RoutineSchedule.maximumItems { return false }
        if item.offsetMinutes != nil, others.filter({ $0.offsetMinutes != nil }).count >= RoutineSchedule.maximumReminders { return false }
        if let existing { existing.apply(item) } else { context.insert(EveningChecklistItemRecord(item, createdAt: now())) }
        save()
        return true
    }

    func deleteItem(_ id: UUID) {
        if let record = itemRecord(id) { context.delete(record) }
        save()
    }

    func reorderItems(_ ids: [UUID]) {
        for (index, id) in ids.enumerated() { itemRecord(id)?.order = index }
        save()
    }

    /// Creates the suggested points (design §11), only into an empty list.
    func adoptSuggestion() {
        guard checklist().isEmpty else { return }
        for (index, suggestion) in RoutineSchedule.suggestedItems.enumerated() {
            saveItem(ChecklistItem(title: suggestion.title, order: index, offsetMinutes: suggestion.offsetMinutes))
        }
    }

    static func normalizedOffset(_ minutes: Int) -> Int {
        let clamped = min(RoutineSchedule.offsetRange.upperBound, max(RoutineSchedule.offsetRange.lowerBound, minutes))
        return Int((Double(clamped) / Double(RoutineSchedule.offsetStep)).rounded()) * RoutineSchedule.offsetStep
    }

    private func itemRecords() -> [EveningChecklistItemRecord] {
        (try? context.fetch(FetchDescriptor<EveningChecklistItemRecord>())) ?? []
    }

    private func itemRecord(_ id: UUID) -> EveningChecklistItemRecord? {
        itemRecords().first { $0.id == id }
    }

    private func save() {
        try? context.save()
        revision += 1
    }
}
