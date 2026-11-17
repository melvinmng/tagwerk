import Foundation
import SwiftData
import TagwerkCore

/// A task that exists only in Tagwerk.
/// Schema rule: later attributes must be optional or have a default value (data survives reinstalls).
@Model
final class LocalTask {
    @Attribute(.unique) var id: UUID
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
    /// Incremented on every change; serves as the task version for conflict checks.
    var revision: Int
    var createdAt: Date

    init(id: UUID = UUID(), title: String, createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.isCompleted = false
        self.revision = 1
        self.createdAt = createdAt
    }

    var due: DueDate? {
        get {
            guard let dueYear, let dueMonth, let dueDay else { return nil }
            return DueDate(year: dueYear, month: dueMonth, day: dueDay, hour: dueHour, minute: dueMinute)
        }
        set {
            dueYear = newValue?.year
            dueMonth = newValue?.month
            dueDay = newValue?.day
            dueHour = newValue?.hour
            dueMinute = newValue?.minute
        }
    }

    var priority: Priority? {
        get { priorityRaw.flatMap(Priority.init(rawValue:)) }
        set { priorityRaw = newValue?.rawValue }
    }
}
