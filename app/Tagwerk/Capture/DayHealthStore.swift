import Foundation
import SwiftData
import TagwerkCore

/// Keeps the Health values of each day (active energy, other apps' nutrition), so past days do not change when Health answers
/// differently later. Written when a day is loaded and at the day change.
@MainActor
final class DayHealthStore {
    private let context: ModelContext
    private let now: () -> Date

    init(context: ModelContext, now: @escaping () -> Date = { Date() }) {
        self.context = context
        self.now = now
    }

    /// The stored values of `day`; `nil` when nothing was ever stored for it.
    func value(on day: PlanDay) -> DayHealth? { record(on: day)?.value }

    /// Stored values of the days from `first` to `last`, both included, oldest first.
    func values(from first: PlanDay, to last: PlanDay) -> [DayHealth] {
        let lower = first.dayKey, upper = last.dayKey
        let descriptor = FetchDescriptor<DayHealthRecord>(predicate: #Predicate { $0.dayKey >= lower && $0.dayKey <= upper },
                                                          sortBy: [SortDescriptor(\.dayKey)])
        return ((try? context.fetch(descriptor)) ?? []).map(\.value)
    }

    /// Stores a reading of a day. `isToday` replaces the stored values; a past day only takes what Health delivered (see
    /// `DayHealth.merged`). Returns the value that is stored afterwards.
    @discardableResult
    func record(_ reading: DayHealth, isToday: Bool) -> DayHealth {
        if let existing = record(on: reading.day) {
            let merged = existing.value.merged(with: reading, overwritingUnknown: isToday)
            if merged != existing.value {
                existing.apply(merged)
                existing.updatedAt = now()
                try? context.save()
            }
            return merged
        }
        context.insert(DayHealthRecord(reading, updatedAt: now()))
        try? context.save()
        return reading
    }

    private func record(on day: PlanDay) -> DayHealthRecord? {
        let key = day.dayKey
        let descriptor = FetchDescriptor<DayHealthRecord>(predicate: #Predicate { $0.dayKey == key })
        return (try? context.fetch(descriptor))?.first
    }
}
