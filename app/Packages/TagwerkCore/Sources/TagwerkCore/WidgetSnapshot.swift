import Foundation

/// One row of the widget: an event, a time block or a deadline with a time.
public struct SnapshotEntry: Sendable, Hashable, Codable, Identifiable {
    public enum Kind: String, Sendable, Hashable, Codable {
        case event, block, deadline
    }

    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var kind: Kind
    public var colorHex: String?
    public var isAllDay: Bool

    public init(id: String, title: String, start: Date, end: Date, kind: Kind, colorHex: String?, isAllDay: Bool) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.kind = kind
        self.colorHex = colorHex
        self.isAllDay = isAllDay
    }
}

/// Today's calories and water, only present while the user allows nutrition in the widget.
public struct SnapshotIntake: Sendable, Hashable, Codable {
    public var kcal: Double
    public var hasEstimate: Bool
    public var goalKcal: Int
    public var waterMilliliters: Int
    public var goalWaterMilliliters: Int

    public init(kcal: Double, hasEstimate: Bool, goalKcal: Int, waterMilliliters: Int, goalWaterMilliliters: Int) {
        self.kcal = kcal
        self.hasEstimate = hasEstimate
        self.goalKcal = goalKcal
        self.waterMilliliters = waterMilliliters
        self.goalWaterMilliliters = goalWaterMilliliters
    }
}

public struct SnapshotDay: Sendable, Hashable, Codable {
    public var day: PlanDay
    public var entries: [SnapshotEntry]
    public var deadlineCount: Int
    public var intake: SnapshotIntake?
    /// Counts before the entry limit, for Siri's overview; `nil` falls back to counting `entries`.
    public var eventCount: Int?
    public var blockCount: Int?

    public init(day: PlanDay, entries: [SnapshotEntry], deadlineCount: Int, intake: SnapshotIntake?,
                eventCount: Int? = nil, blockCount: Int? = nil) {
        self.day = day
        self.entries = entries
        self.deadlineCount = deadlineCount
        self.intake = intake
        self.eventCount = eventCount
        self.blockCount = blockCount
    }
}

/// Input of the builder for one day; the app collects it from EventKit and the plan store.
public struct SnapshotDayInput: Sendable {
    public var day: PlanDay
    public var events: [CalendarEvent]
    public var blocks: [CalendarEvent]
    public var deadlines: [ImportantDeadline]
    /// Color of a calendar, by calendar ID.
    public var colorHex: @Sendable (String) -> String?

    public init(day: PlanDay, events: [CalendarEvent], blocks: [CalendarEvent], deadlines: [ImportantDeadline],
                colorHex: @escaping @Sendable (String) -> String?) {
        self.day = day
        self.events = events
        self.blocks = blocks
        self.deadlines = deadlines
        self.colorHex = colorHex
    }
}

/// What the widget extension reads from the shared App Group file (phase 4 design §4.1).
/// The widget never reads SwiftData, EventKit, Health or the network; this file is its only source.
public struct WidgetSnapshot: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1
    /// Timed entries per day; all-day entries are limited separately, so they never push late events out.
    public static let maximumEntriesPerDay = 12
    public static let maximumAllDayEntriesPerDay = 3
    public static let maximumTimelineEntries = 30
    public static let fileName = "widget-snapshot.json"
    /// Info.plist key of both targets holding the App Group identifier.
    public static let appGroupInfoKey = "TagwerkAppGroup"

    public var schemaVersion: Int
    public var createdAt: Date
    public var days: [SnapshotDay]

    public init(schemaVersion: Int = WidgetSnapshot.currentSchemaVersion, createdAt: Date, days: [SnapshotDay]) {
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.days = days
    }

    // MARK: Building

    /// Builds the snapshot; `todayIntake` belongs to the first day and is dropped when nutrition is hidden.
    public static func make(createdAt: Date, days inputs: [SnapshotDayInput], todayIntake: SnapshotIntake?,
                            showsNutrition: Bool, calendar: Calendar) -> WidgetSnapshot {
        let days = inputs.enumerated().map { index, input in
            let all = entries(of: input, calendar: calendar)
            let allDay = all.filter(\.isAllDay).prefix(maximumAllDayEntriesPerDay)
            let timed = all.filter { !$0.isAllDay }.prefix(maximumEntriesPerDay)
            return SnapshotDay(day: input.day, entries: Array(allDay) + Array(timed), deadlineCount: input.deadlines.count,
                               intake: index == 0 && showsNutrition ? todayIntake : nil,
                               eventCount: all.filter { $0.kind == .event }.count,
                               blockCount: all.filter { $0.kind == .block }.count)
        }
        return WidgetSnapshot(createdAt: createdAt, days: days)
    }

    /// The same plan with new intake for `day`; used where the plan sources are not loaded (Siri in the background),
    /// so the plan part of an existing file is kept instead of being replaced by an empty one. Older days lose their
    /// intake. A file without `day` stays stale: adding an empty day would claim "nothing planned".
    public func replacingIntake(_ intake: SnapshotIntake?, on day: PlanDay, createdAt: Date) -> WidgetSnapshot {
        var copy = self
        for index in copy.days.indices where copy.days[index].day != day { copy.days[index].intake = nil }
        guard let index = copy.days.firstIndex(where: { $0.day == day }) else { return copy }
        copy.createdAt = createdAt
        copy.days[index].intake = intake
        return copy
    }

    private static func entries(of input: SnapshotDayInput, calendar: Calendar) -> [SnapshotEntry] {
        // IDs carry the day, so an event across midnight has one entry per day.
        let suffix = "\(input.day.year)-\(input.day.month)-\(input.day.day)"
        // Events of deadline calendars appear once, as deadline rows (they are also listed as deadlines).
        let deadlineEventIDs = Set(input.deadlines.compactMap(\.eventID))
        var result = input.events.map { event in
            SnapshotEntry(id: "event:\(event.id):\(suffix)", title: event.title, start: event.start, end: event.end,
                          kind: deadlineEventIDs.contains(event.id) ? .deadline : .event,
                          colorHex: input.colorHex(event.calendarID), isAllDay: event.isAllDay)
        }
        result += input.blocks.map { block in
            SnapshotEntry(id: "block:\(block.id):\(suffix)", title: block.title, start: block.start, end: block.end, kind: .block,
                          colorHex: input.colorHex(block.calendarID), isAllDay: block.isAllDay)
        }
        // Timed task deadlines become rows; deadline-calendar events are already rows above.
        result += input.deadlines.compactMap { deadline in
            guard deadline.eventID == nil, let time = deadline.time else { return nil }
            return SnapshotEntry(id: "deadline:\(deadline.id)", title: deadline.title, start: time, end: time, kind: .deadline,
                                 colorHex: nil, isAllDay: false)
        }
        result.sort { lhs, rhs in
            if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            return lhs.title < rhs.title
        }
        return result
    }

    // MARK: Encoding

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    /// The same content without the creation time; the app reloads widgets only when this changes.
    public func contentFingerprint() -> Data? {
        var copy = self
        copy.createdAt = Date(timeIntervalSince1970: 0)
        return try? copy.encoded()
    }

    /// `nil` for unreadable data and unknown schema versions.
    public static func decode(_ data: Data) -> WidgetSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data),
              snapshot.schemaVersion == currentSchemaVersion else { return nil }
        return snapshot
    }

    /// Reads the snapshot file of the App Group container; `nil` when missing or unreadable.
    public static func load(from directory: URL?) -> WidgetSnapshot? {
        guard let directory, let data = try? Data(contentsOf: directory.appending(path: fileName)) else { return nil }
        return decode(data)
    }

    // MARK: Reading

    /// Stale when the snapshot does not describe the day of `date` (the app was not opened for days).
    public func isStale(at date: Date, calendar: Calendar) -> Bool {
        !days.contains { $0.day == PlanDay(date: date, calendar: calendar) }
    }

    public struct Upcoming: Sendable, Hashable {
        public var entries: [SnapshotEntry]
        /// The entries belong to the next day because nothing is left today.
        public var isTomorrow: Bool
    }

    /// Timed entries that have not ended at `date`, starting with the day of `date`; the next day when today is done.
    public func upcoming(at date: Date, calendar: Calendar, limit: Int) -> Upcoming {
        let today = PlanDay(date: date, calendar: calendar)
        let todayEntries = timedEntries(on: today).filter { $0.end > date || ($0.kind == .deadline && $0.start >= date) }
        if !todayEntries.isEmpty {
            return Upcoming(entries: Array(todayEntries.prefix(limit)), isTomorrow: false)
        }
        let tomorrow = timedEntries(on: today.adding(days: 1, calendar: calendar))
        return Upcoming(entries: Array(tomorrow.prefix(limit)), isTomorrow: !tomorrow.isEmpty)
    }

    private func timedEntries(on day: PlanDay) -> [SnapshotEntry] {
        days.first { $0.day == day }?.entries.filter { !$0.isAllDay } ?? []
    }

    /// Today's intake, only while the snapshot still describes the day of `date` (never yesterday's sums).
    public func intake(at date: Date, calendar: Calendar) -> SnapshotIntake? {
        days.first { $0.day == PlanDay(date: date, calendar: calendar) }?.intake
    }

    public func deadlineCount(at date: Date, calendar: Calendar) -> Int {
        days.first { $0.day == PlanDay(date: date, calendar: calendar) }?.deadlineCount ?? 0
    }

    /// Moments at which the widget content changes: now, starts and ends within 24 hours, and each midnight.
    public func timelineDates(from date: Date, calendar: Calendar) -> [Date] {
        let horizon = date.addingTimeInterval(86_400)
        var moments = Set<Date>([date])
        for day in days {
            for entry in day.entries where !entry.isAllDay {
                for moment in [entry.start, entry.end] where moment > date && moment <= horizon { moments.insert(moment) }
            }
        }
        let tomorrow = PlanDay(date: date, calendar: calendar).adding(days: 1, calendar: calendar).startDate(in: calendar)
        if tomorrow <= horizon { moments.insert(tomorrow) }
        return Array(moments.sorted().prefix(Self.maximumTimelineEntries))
    }

    /// Siri's answer to "Was steht heute an?": counts and the next entry, never nutrition.
    public func overviewText(at date: Date, calendar: Calendar, locale: Locale = .current) -> String {
        let today = PlanDay(date: date, calendar: calendar)
        let day = days.first { $0.day == today }
        let entries = day?.entries ?? []
        let events = day?.eventCount ?? entries.filter { $0.kind == .event }.count
        let blocks = day?.blockCount ?? entries.filter { $0.kind == .block }.count
        let deadlines = deadlineCount(at: date, calendar: calendar)
        var parts: [String] = []
        // One key per count; the catalog holds the singular ("1 Termin") as a plural variation.
        if events > 0 { parts.append(String(localized: "\(events) Termine", bundle: .module)) }
        if blocks > 0 { parts.append(String(localized: "\(blocks) Blöcke", bundle: .module)) }
        if deadlines > 0 { parts.append(String(localized: "\(deadlines) Deadlines", bundle: .module)) }
        guard !parts.isEmpty else { return String(localized: "Heute steht nichts an.", bundle: .module) }
        let summary = parts.joined(separator: ", ")
        let next = upcoming(at: date, calendar: calendar, limit: 1)
        if let entry = next.entries.first, !next.isTomorrow {
            let time = DateText.time(entry.start, calendar: calendar, locale: locale), title = entry.title
            return String(localized: "Heute: \(summary). Als Nächstes \(time) \(title).", bundle: .module)
        }
        return String(localized: "Heute: \(summary). Davon steht nichts mehr an.", bundle: .module)
    }

    /// "09:00" in the calendar's time zone.
    public static func time(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}
