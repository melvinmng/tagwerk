import Foundation
import SwiftData
import TagwerkCore

/// A manual link between a calendar event (occurrence) and a task.
/// Schema rule: later attributes must be optional or have a default value.
@Model
final class EventTaskLink {
    @Attribute(.unique) var eventKey: String
    var taskKey: String
    var createdAt: Date

    init(eventKey: String, taskKey: String, createdAt: Date = .now) {
        self.eventKey = eventKey
        self.taskKey = taskKey
        self.createdAt = createdAt
    }
}

@MainActor
final class EventLinkStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func manualLinks() -> [String: TaskID] {
        let records = (try? context.fetch(FetchDescriptor<EventTaskLink>())) ?? []
        return Dictionary(records.compactMap { record in TaskID(key: record.taskKey).map { (record.eventKey, $0) } },
                          uniquingKeysWith: { first, _ in first })
    }

    func link(eventID: String, to taskID: TaskID) {
        if let existing = record(eventID) {
            existing.taskKey = taskID.key
        } else {
            context.insert(EventTaskLink(eventKey: eventID, taskKey: taskID.key))
        }
        try? context.save()
    }

    func unlink(eventID: String) {
        guard let existing = record(eventID) else { return }
        context.delete(existing)
        try? context.save()
    }

    private func record(_ eventID: String) -> EventTaskLink? {
        var descriptor = FetchDescriptor<EventTaskLink>(predicate: #Predicate { $0.eventKey == eventID })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
