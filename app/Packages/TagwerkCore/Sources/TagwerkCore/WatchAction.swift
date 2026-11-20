import Foundation

/// Something the user did on the watch that the phone has to carry out. Plain data; every action has an ID so the
/// phone can apply it exactly once, however often it arrives.
public struct WatchAction: Sendable, Hashable, Codable, Identifiable {
    public enum Kind: Sendable, Hashable, Codable {
        /// `version` is the change marker of the task the watch showed.
        case completeTask(key: String, version: String)
        /// `on: false` removes today's manual check again.
        case checkHabit(id: UUID, on: Bool)
        /// `entryID` becomes the ID of the water entry, so an undo deletes exactly this entry.
        case logWater(milliliters: Int, entryID: UUID)
        /// Takes back the action with this ID.
        case undo(of: UUID)
    }

    public var id: UUID
    public var createdAt: Date
    public var kind: Kind

    public init(id: UUID = UUID(), createdAt: Date, kind: Kind) {
        self.id = id
        self.createdAt = createdAt
        self.kind = kind
    }

    // MARK: Transport

    /// Key of the single value in a `WCSession` message or user info. The payload is one `Data` value, a property-list
    /// type, so it passes the transport rules and never has to cross an actor as `[String: Any]`.
    public static let transportKey = "watchAction"

    public func encoded() throws -> Data {
        try PropertyListEncoder().encode(self)
    }

    public static func decode(_ data: Data) -> WatchAction? {
        try? PropertyListDecoder().decode(WatchAction.self, from: data)
    }
}

/// The actions of the watch that were not acknowledged yet, in the order of the user's taps. A pure value; the watch
/// stores it in a file (`WatchActionQueueFile`).
public struct WatchActionQueue: Sendable, Equatable, Codable {
    public struct Entry: Sendable, Equatable, Codable {
        public var action: WatchAction
        /// When the action was handed to the transport; `nil` while it was never sent.
        public var sentAt: Date?
    }

    /// A sent action that the phone did not acknowledge goes out again after this time; the phone is idempotent.
    public static let resendInterval: TimeInterval = 10 * 60
    /// Older actions are dropped (the user would not expect a check-off from two days ago to arrive).
    public static let maximumAge: TimeInterval = 48 * 3600

    public private(set) var entries: [Entry] = []
    /// Actions dropped for their age since the user last saw the notice ("Nicht übertragen").
    public private(set) var droppedCount = 0

    public init() {}

    public var isEmpty: Bool { entries.isEmpty }
    public var count: Int { entries.count }

    public mutating func enqueue(_ action: WatchAction) {
        guard !entries.contains(where: { $0.action.id == action.id }) else { return }
        entries.append(Entry(action: action, sentAt: nil))
    }

    /// Takes an action back before it was sent. `false` when it is not queued or already on its way.
    @discardableResult
    public mutating func cancel(_ id: UUID) -> Bool {
        guard let index = entries.firstIndex(where: { $0.action.id == id }), entries[index].sentAt == nil else { return false }
        entries.remove(at: index)
        return true
    }

    public enum UndoOutcome: Sendable, Equatable {
        /// The action had not left the watch; it was removed and nothing has to be sent.
        case dropped
        /// The action was sent; this counter-action goes after it.
        case counterAction(WatchAction)
    }

    /// "Rückgängig": drops an unsent action, otherwise queues an `undo` action behind the sent one.
    public mutating func requestUndo(of id: UUID, at now: Date) -> UndoOutcome {
        if cancel(id) { return .dropped }
        let counter = WatchAction(createdAt: now, kind: .undo(of: id))
        enqueue(counter)
        return .counterAction(counter)
    }

    public mutating func markSent(_ id: UUID, at date: Date) {
        guard let index = entries.firstIndex(where: { $0.action.id == id }) else { return }
        entries[index].sentAt = date
    }

    /// Removes what the phone reports as applied.
    public mutating func acknowledge(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let applied = Set(ids)
        entries.removeAll { applied.contains($0.action.id) }
    }

    /// Removes actions older than `maximumAge` and counts them.
    @discardableResult
    public mutating func dropExpired(now: Date) -> Int {
        let before = entries.count
        entries.removeAll { now.timeIntervalSince($0.action.createdAt) > Self.maximumAge }
        let dropped = before - entries.count
        droppedCount += dropped
        return dropped
    }

    public mutating func clearDroppedNotice() {
        droppedCount = 0
    }

    /// What has to be sent now, in the order of the taps: actions never sent and those whose last attempt is older
    /// than `resendInterval`.
    public func pending(now: Date) -> [WatchAction] {
        entries.filter { entry in
            guard now.timeIntervalSince(entry.action.createdAt) <= Self.maximumAge else { return false }
            guard let sentAt = entry.sentAt else { return true }
            return now.timeIntervalSince(sentAt) >= Self.resendInterval
        }.map(\.action)
    }

    // MARK: File

    public static let fileName = "watch-action-queue.json"

    public static func load(from directory: URL?) -> WatchActionQueue {
        guard let directory, let data = try? Data(contentsOf: directory.appending(path: fileName)) else { return WatchActionQueue() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode(WatchActionQueue.self, from: data)) ?? WatchActionQueue()
    }

    public func write(to directory: URL?) throws {
        guard let directory else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(self).write(to: directory.appending(path: Self.fileName),
                                       options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

/// What the phone remembers about the actions it received: which were applied (so a repeat does nothing), which were
/// taken back before they arrived, and the context needed to undo them later.
public struct WatchActionLog: Sendable, Equatable, Codable {
    public static let maximumApplied = 200
    public static let fileName = "watch-action-log.json"

    /// IDs in the order they were applied; the newest are reported to the watch.
    public private(set) var applied: [UUID] = []
    /// Undo requests whose original action did not arrive yet; the original is skipped when it does.
    public private(set) var cancelled: Set<UUID> = []

    public init() {}

    public func hasApplied(_ id: UUID) -> Bool { applied.contains(id) }

    public mutating func markApplied(_ id: UUID) {
        guard !applied.contains(id) else { return }
        applied.append(id)
        if applied.count > Self.maximumApplied { applied.removeFirst(applied.count - Self.maximumApplied) }
    }

    public mutating func markCancelled(_ id: UUID) {
        cancelled.insert(id)
        // Bounded like `applied`; a request for an action that never comes must not grow the file.
        if cancelled.count > Self.maximumApplied, let oldest = cancelled.first { cancelled.remove(oldest) }
    }

    /// Whether the original was taken back before it arrived; consumes the mark.
    public mutating func consumeCancellation(of id: UUID) -> Bool {
        cancelled.remove(id) != nil
    }

    /// The IDs for `WatchSnapshot.appliedActionIDs`.
    public var recentApplied: [UUID] { Array(applied.suffix(WatchSnapshot.maximumAppliedActionIDs)) }

    public static func load(from directory: URL?) -> WatchActionLog {
        guard let directory, let data = try? Data(contentsOf: directory.appending(path: fileName)) else { return WatchActionLog() }
        return (try? JSONDecoder().decode(WatchActionLog.self, from: data)) ?? WatchActionLog()
    }

    public func write(to directory: URL?) throws {
        guard let directory else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: directory.appending(path: Self.fileName), options: [.atomic])
    }
}
