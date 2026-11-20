import Foundation

/// An open task as the watch shows it. Carries no notes, labels, project or container (issue #170, privacy).
public struct WatchTask: Sendable, Hashable, Codable, Identifiable {
    /// `TaskID.key`, the stable identity across reloads.
    public var key: String
    public var title: String
    public var due: Date?
    public var hasTime: Bool
    public var isDeadline: Bool
    public var source: TaskSource
    /// Opaque change marker of the source; the phone compares it before it completes the task.
    public var version: String

    public var id: String { key }

    public init(key: String, title: String, due: Date?, hasTime: Bool, isDeadline: Bool, source: TaskSource, version: String) {
        self.key = key
        self.title = title
        self.due = due
        self.hasTime = hasTime
        self.isDeadline = isDeadline
        self.source = source
        self.version = version
    }
}

/// A habit active today: name, symbol and status only, never a streak or a rate.
public struct WatchHabit: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var name: String
    public var symbol: String
    public var done: Bool
    /// The source fulfils the habit by itself (steps, workout, ...): the row is shown but cannot be checked.
    public var isAutomatic: Bool

    public var isCheckable: Bool { !isAutomatic }

    public init(id: UUID, name: String, symbol: String, done: Bool, isAutomatic: Bool) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.done = done
        self.isAutomatic = isAutomatic
    }

    public init(habit: Habit, done: Bool, isAutomatic: Bool) {
        self.init(id: habit.id, name: habit.name, symbol: habit.symbol, done: done, isAutomatic: isAutomatic)
    }
}

/// Today's water with the goal and the amounts of the quick buttons.
public struct WatchWater: Sendable, Hashable, Codable {
    public static let defaultQuickAmounts = [250, 500]

    public var milliliters: Int
    public var goalMilliliters: Int
    public var quickAmounts: [Int]
    /// Mirrors the widget switch for nutrition: only then does a complication show the water ring.
    public var showsInComplication: Bool

    public init(milliliters: Int, goalMilliliters: Int, quickAmounts: [Int] = WatchWater.defaultQuickAmounts,
                showsInComplication: Bool) {
        self.milliliters = milliliters
        self.goalMilliliters = goalMilliliters
        self.quickAmounts = quickAmounts
        self.showsInComplication = showsInComplication
    }
}

/// What the iPhone sends to the watch (via `updateApplicationContext`) and the complications read from the watch's
/// App Group container. Today only; it holds exactly the data that may appear in the widget or in a notification.
public struct WatchSnapshot: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1
    public static let maximumTasks = 20
    public static let maximumTitleLength = 120
    public static let maximumAppliedActionIDs = 50
    /// `updateApplicationContext` accepts at most this many bytes in total.
    public static let contextSizeLimit = 64 * 1024
    public static let fileName = "watch-snapshot.json"

    public var schemaVersion: Int
    public var createdAt: Date
    public var day: PlanDay
    /// Timed entries of today and tomorrow, all-day entries included (they never count as "next").
    public var entries: [SnapshotEntry]
    public var tasks: [WatchTask]
    public var habits: [WatchHabit]
    /// The counter as the widget shows it ("3 of 5"); weekly goals are already counted in.
    public var habitCounter: HabitCounter?
    public var water: WatchWater?
    /// The last actions the phone applied; the watch removes them from its queue.
    public var appliedActionIDs: [UUID]

    public init(schemaVersion: Int = WatchSnapshot.currentSchemaVersion, createdAt: Date, day: PlanDay, entries: [SnapshotEntry],
                tasks: [WatchTask], habits: [WatchHabit], habitCounter: HabitCounter?, water: WatchWater?,
                appliedActionIDs: [UUID]) {
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.day = day
        self.entries = entries
        self.tasks = tasks
        self.habits = habits
        self.habitCounter = habitCounter
        self.water = water
        self.appliedActionIDs = appliedActionIDs
    }

    // MARK: Building

    /// Builds the snapshot from the data the phone already has. `deadlineTaskKeys` are the keys of the tasks the plan
    /// shows as deadlines.
    public static func make(widget: WidgetSnapshot, tasks: [TaskItem], habits: [WatchHabit], water: WatchWater?,
                            deadlineTaskKeys: Set<String> = [], appliedActionIDs: [UUID] = [], now: Date,
                            calendar: Calendar) -> WatchSnapshot {
        let today = PlanDay(date: now, calendar: calendar)
        let tomorrow = today.adding(days: 1, calendar: calendar)
        let entries = widget.days.filter { $0.day == today || $0.day == tomorrow }
            .sorted { $0.day < $1.day }
            .flatMap(\.entries)
            .map { entry in
                var copy = entry
                copy.title = truncated(entry.title)
                return copy
            }
        let open = tasks.filter { task in
            guard !task.isCompleted else { return false }
            let taskSection = section(for: task, now: now, calendar: calendar)
            return taskSection == .overdue || taskSection == .today
        }
        let watchTasks = sortedTasks(open, calendar: calendar).prefix(maximumTasks).map { task in
            WatchTask(key: task.id.key, title: truncated(task.title), due: task.due?.startDate(in: calendar),
                      hasTime: task.due?.hasTime ?? false, isDeadline: deadlineTaskKeys.contains(task.id.key),
                      source: task.id.source, version: task.version)
        }
        return WatchSnapshot(createdAt: now, day: today, entries: entries, tasks: Array(watchTasks),
                             habits: habits.map { var copy = $0; copy.name = truncated($0.name); return copy },
                             habitCounter: widget.habits(at: now, calendar: calendar), water: water,
                             appliedActionIDs: Array(appliedActionIDs.suffix(maximumAppliedActionIDs)))
    }

    private static func truncated(_ text: String) -> String {
        text.count <= maximumTitleLength ? text : String(text.prefix(maximumTitleLength - 1)) + "…"
    }

    // MARK: Reading

    /// The snapshot does not describe the day of `date` (the phone was not opened for a day).
    public func isStale(at date: Date, calendar: Calendar) -> Bool {
        day != PlanDay(date: date, calendar: calendar)
    }

    /// Tasks for the list: those with a time first (earliest first), then the others in the order of the plan.
    public var tasksForDisplay: [WatchTask] {
        let timed = tasks.filter(\.hasTime).sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
        return timed + tasks.filter { !$0.hasTime }
    }

    // MARK: Encoding

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    /// `nil` for unreadable data and unknown schema versions.
    public static func decode(_ data: Data) -> WatchSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let snapshot = try? decoder.decode(WatchSnapshot.self, from: data),
              snapshot.schemaVersion == currentSchemaVersion else { return nil }
        return snapshot
    }

    /// The same content without the creation time and the acknowledgements; the phone sends a new context only when
    /// this changes.
    public func contentFingerprint() -> Data? {
        var copy = self
        copy.createdAt = Date(timeIntervalSince1970: 0)
        return try? copy.encoded()
    }

    // MARK: File

    /// Reads the snapshot file of `directory`; `nil` when missing, unreadable or of an unknown version.
    public static func load(from directory: URL?) -> WatchSnapshot? {
        guard let directory, let data = try? Data(contentsOf: directory.appending(path: fileName)) else { return nil }
        return decode(data)
    }

    /// Writes atomically; the file stays readable after the first unlock so complications render on a locked watch.
    public func write(to directory: URL?) throws {
        guard let directory else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoded().write(to: directory.appending(path: Self.fileName),
                            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
