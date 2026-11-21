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
    /// JSON of `[SpokenMark]`: the user messages that came from a recording (plan voice-chat).
    var spokenData: Data = Data()
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
    /// The chat about notes; one history for the chat about all notes and the chat about one note (#233).
    static let notesKey = "notes"
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

    func spokenMarks(for key: String) -> [SpokenMark] {
        guard let record = record(key) else { return [] }
        return (try? JSONDecoder().decode([SpokenMark].self, from: record.spokenData)) ?? []
    }

    func saveSpokenMarks(_ marks: [SpokenMark], for key: String) {
        guard let record = record(key) else { return }
        record.spokenData = (try? JSONEncoder().encode(marks)) ?? Data()
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

/// A spoken user message: its position in the history and the start of its text, so a mark never sticks to
/// another message after the history changed.
struct SpokenMark: Codable, Equatable, Sendable {
    let index: Int
    let prefix: String

    init(index: Int, text: String) {
        self.index = index
        prefix = String(text.prefix(40))
    }

    func matches(index: Int, text: String) -> Bool { self.index == index && prefix == String(text.prefix(40)) }
}
