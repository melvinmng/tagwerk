import Foundation
import Testing
import TagwerkCore
@testable import RemindersKit

@MainActor
struct CompletedRemindersTests {
    let store = FakeReminderStore()
    let t0 = Date(timeIntervalSince1970: 100_000)

    init() {
        store.listInfos = [
            ListInfo(id: "shop", title: "Einkauf", colorHex: nil, kind: .calDAV),
            ListInfo(id: "other", title: "Privat", colorHex: nil, kind: .local),
        ]
        store.records = [
            "a": record("a", list: "shop", completedAt: t0.addingTimeInterval(10)),
            "b": record("b", list: "shop", completedAt: t0.addingTimeInterval(-100)),
            "c": record("c", list: "other", completedAt: t0.addingTimeInterval(10)),
            "d": record("d", list: "shop", completedAt: nil),
        ]
    }

    private func record(_ id: String, list: String, completedAt: Date?) -> ReminderRecord {
        ReminderRecord(id: id, title: id, notes: nil, due: nil, ekPriority: 0, isCompleted: completedAt != nil,
                       listID: list, lastModified: nil, completedAt: completedAt)
    }

    @Test func completedReminders_onlyInIntervalAndLists() async {
        let found = await store.completedReminders(in: DateInterval(start: t0, duration: 60), listIDs: ["shop"])
        #expect(found.map(\.id) == ["a"])
    }

    @Test func completedReminders_emptyListSet_returnsNothing() async {
        #expect(await store.completedReminders(in: DateInterval(start: t0, duration: 60), listIDs: []).isEmpty)
    }

    @Test func save_completing_setsCompletedAt_reopeningClearsIt() throws {
        var record = try #require(store.records["d"])
        record.isCompleted = true
        #expect(try store.save(record, recurrence: .unchanged).completedAt != nil)
        record.isCompleted = false
        #expect(try store.save(record, recurrence: .unchanged).completedAt == nil)
    }

    @Test func create_setsCreatedAt() throws {
        let created = try store.create(title: "Neu", notes: nil, due: nil, ekPriority: 0, listID: "shop", recurrence: nil)
        #expect(created.createdAt != nil)
    }

    @Test func newFields_defaultToNilAndWritable() {
        let record = ReminderRecord(id: "x", title: "", notes: nil, due: nil, ekPriority: 0, isCompleted: false,
                                    listID: "l", lastModified: nil)
        #expect(record.createdAt == nil && record.completedAt == nil)
        #expect(ListInfo(id: "l", title: "L", colorHex: nil, kind: .local).isWritable)
    }

    @Test func defaultListID_reportsTheStoresDefault() {
        store.defaultList = "shop"
        #expect((store as any ReminderStore).defaultListID() == "shop")
    }
}
