import AIKit
import Foundation
import SwiftData

/// One saved chat: the assistant's (key "assistant") or the chat about one task ("task:<TaskID.key>").
@Model
final class ChatThreadRecord {
    var key: String = ""
    /// JSON of `[InputItem]`, the history exactly as it is sent.
    var historyData: Data = Data()
    /// JSON of `[String: Date]`: when each action (call ID) was carried out.
    var actionTimesData: Data = Data()
    var updatedAt: Date = Date.distantPast

    init(key: String) {
        self.key = key
    }
}

/// Keeps chats across app starts. Only the user's own messages, the answers and the function results are
/// stored, on this device.
@MainActor
final class ChatStore {
    static let assistantKey = "assistant"
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func history(for key: String) -> [InputItem] {
        guard let record = record(key) else { return [] }
        return (try? JSONDecoder().decode([InputItem].self, from: record.historyData)) ?? []
    }

    func actionTimes(for key: String) -> [String: Date] {
        guard let record = record(key) else { return [:] }
        return (try? JSONDecoder().decode([String: Date].self, from: record.actionTimesData)) ?? [:]
    }

    func save(_ history: [InputItem], actionTimes: [String: Date], for key: String, now: Date) {
        let record = record(key) ?? {
            let created = ChatThreadRecord(key: key)
            context.insert(created)
            return created
        }()
        record.historyData = (try? JSONEncoder().encode(history)) ?? Data()
        record.actionTimesData = (try? JSONEncoder().encode(actionTimes)) ?? Data()
        record.updatedAt = now
        try? context.save()
    }

    func delete(_ key: String) {
        if let record = record(key) { context.delete(record) }
        try? context.save()
    }

    private func record(_ key: String) -> ChatThreadRecord? {
        var descriptor = FetchDescriptor<ChatThreadRecord>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
