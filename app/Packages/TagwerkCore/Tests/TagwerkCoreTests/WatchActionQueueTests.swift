import Foundation
import Testing
@testable import TagwerkCore

struct WatchActionQueueTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func action(_ kind: WatchAction.Kind, at offset: TimeInterval = 0) -> WatchAction {
        WatchAction(createdAt: start.addingTimeInterval(offset), kind: kind)
    }

    private func complete(_ key: String, at offset: TimeInterval = 0) -> WatchAction {
        action(.completeTask(key: key, version: "1"), at: offset)
    }

    @Test func offline_thenOnline_deliversOnceInOrder() {
        var queue = WatchActionQueue()
        let first = complete("local:a", at: 0), second = complete("local:b", at: 5)
        let third = action(.checkHabit(id: UUID(), on: true), at: 9)
        [first, second, third].forEach { queue.enqueue($0) }
        // Offline: what is pending stays pending and keeps its order, however often it is asked.
        #expect(queue.pending(now: start.addingTimeInterval(10)).map(\.id) == [first.id, second.id, third.id])
        #expect(queue.pending(now: start.addingTimeInterval(20)).map(\.id) == [first.id, second.id, third.id])
        // Online: everything goes out once.
        let now = start.addingTimeInterval(60)
        for pending in queue.pending(now: now) { queue.markSent(pending.id, at: now) }
        #expect(queue.pending(now: now.addingTimeInterval(1)).isEmpty)
        queue.acknowledge([first.id, second.id, third.id])
        #expect(queue.isEmpty)
    }

    @Test func enqueueTwice_keepsOneEntry() {
        var queue = WatchActionQueue()
        let item = complete("local:a")
        queue.enqueue(item)
        queue.enqueue(item)
        #expect(queue.count == 1)
    }

    @Test func undoBeforeSend_dropsAction() {
        var queue = WatchActionQueue()
        let item = complete("local:a")
        queue.enqueue(item)
        let outcome = queue.requestUndo(of: item.id, at: start)
        #expect(outcome == .dropped)
        #expect(queue.isEmpty)
    }

    @Test func undoAfterSend_queuesCounterAction() {
        var queue = WatchActionQueue()
        let item = complete("local:a")
        queue.enqueue(item)
        queue.markSent(item.id, at: start)
        guard case .counterAction(let counter) = queue.requestUndo(of: item.id, at: start.addingTimeInterval(2)) else {
            Issue.record("expected a counter action"); return
        }
        #expect(counter.kind == .undo(of: item.id))
        #expect(queue.count == 2)
        #expect(queue.entries.last?.action.id == counter.id)
        let cancelled = queue.cancel(item.id)
        #expect(!cancelled)
    }

    @Test func acknowledged_removed() {
        var queue = WatchActionQueue()
        let first = complete("local:a"), second = complete("local:b")
        queue.enqueue(first)
        queue.enqueue(second)
        queue.acknowledge([first.id, UUID()])
        #expect(queue.entries.map(\.action.id) == [second.id])
    }

    @Test func unacknowledged_isResentAfterTimeout() {
        var queue = WatchActionQueue()
        let item = complete("local:a")
        queue.enqueue(item)
        queue.markSent(item.id, at: start)
        #expect(queue.pending(now: start.addingTimeInterval(WatchActionQueue.resendInterval - 1)).isEmpty)
        #expect(queue.pending(now: start.addingTimeInterval(WatchActionQueue.resendInterval)).map(\.id) == [item.id])
    }

    @Test func older48h_dropped() {
        var queue = WatchActionQueue()
        let old = complete("local:old", at: 0), fresh = complete("local:fresh", at: 47 * 3600)
        queue.enqueue(old)
        queue.enqueue(fresh)
        let now = start.addingTimeInterval(49 * 3600)
        #expect(queue.pending(now: now).map(\.id) == [fresh.id])
        let dropped = queue.dropExpired(now: now)
        #expect(dropped == 1)
        #expect(queue.droppedCount == 1)
        #expect(queue.entries.map(\.action.id) == [fresh.id])
        queue.clearDroppedNotice()
        #expect(queue.droppedCount == 0)
    }

    @Test func codableAsPropertyList() throws {
        let kinds: [WatchAction.Kind] = [.completeTask(key: "reminders:x", version: "v"), .checkHabit(id: UUID(), on: false),
                                         .logWater(milliliters: 250, entryID: UUID()), .undo(of: UUID())]
        for kind in kinds {
            let item = action(kind)
            let data = try item.encoded()
            #expect(WatchAction.decode(data) == item)
            // WatchConnectivity accepts property-list values only; the payload is one Data value.
            let message: [String: Any] = [WatchAction.transportKey: data]
            #expect(PropertyListSerialization.propertyList(message, isValidFor: .binary))
        }
        #expect(WatchAction.decode(Data("junk".utf8)) == nil)
    }

    @Test func queueFileRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "watch-queue-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        var queue = WatchActionQueue()
        queue.enqueue(complete("local:a"))
        queue.markSent(queue.entries[0].action.id, at: start)
        try queue.write(to: directory)
        #expect(WatchActionQueue.load(from: directory) == queue)
        #expect(WatchActionQueue.load(from: nil).isEmpty)
    }
}

struct WatchActionLogTests {
    @Test func appliedIsRememberedAndBounded() {
        var log = WatchActionLog()
        let ids = (0..<(WatchActionLog.maximumApplied + 10)).map { _ in UUID() }
        ids.forEach { log.markApplied($0) }
        log.markApplied(ids[100])
        #expect(log.applied.count == WatchActionLog.maximumApplied)
        #expect(log.hasApplied(ids.last!))
        #expect(!log.hasApplied(ids[0]))
        #expect(log.recentApplied == Array(ids.suffix(WatchSnapshot.maximumAppliedActionIDs)))
    }

    @Test func cancellationIsConsumedOnce() {
        var log = WatchActionLog()
        let id = UUID()
        log.markCancelled(id)
        let first = log.consumeCancellation(of: id)
        let second = log.consumeCancellation(of: id)
        #expect(first)
        #expect(!second)
    }

    @Test func fileRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "watch-log-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        var log = WatchActionLog()
        log.markApplied(UUID())
        log.markCancelled(UUID())
        try log.write(to: directory)
        #expect(WatchActionLog.load(from: directory) == log)
    }
}
