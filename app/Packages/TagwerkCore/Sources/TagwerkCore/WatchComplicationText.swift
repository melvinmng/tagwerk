import Foundation

/// The texts of the watch complications and of the first watch page, built from pure rules so they are tested on the
/// phone's simulator. A complication counts like the lock screen: titles are shown only where the view marks them
/// as privacy sensitive, and habit names never appear (only counts).
public struct WatchNextUpText: Sendable, Equatable {
    /// "Läuft", "Als Nächstes", "Morgen" or the empty-state line.
    public var caption: String
    /// "09:30" for entries and timed tasks.
    public var time: String?
    /// Contains user content; `nil` for the empty states.
    public var title: String?
    /// "+4": further open tasks.
    public var suffix: String?
    /// SF Symbol name for the kind of the item.
    public var symbolName: String
    /// The row is a task that can be checked off.
    public var isTask: Bool

    /// Titles in the inline family are cut at this length; the system truncates the rest.
    public static let inlineTitleLimit = 18

    public init(caption: String, time: String?, title: String?, suffix: String?, symbolName: String, isTask: Bool) {
        self.caption = caption
        self.time = time
        self.title = title
        self.suffix = suffix
        self.symbolName = symbolName
        self.isTask = isTask
    }

    public static func make(_ next: WatchNextUp, calendar: Calendar, locale: Locale = .current) -> WatchNextUpText {
        func time(_ date: Date) -> String { DateText.time(date, calendar: calendar, locale: locale) }
        switch next {
        case .entry(let entry, let isRunning):
            return WatchNextUpText(caption: isRunning ? String(localized: "Läuft", bundle: .module)
                                                      : String(localized: "Als Nächstes", bundle: .module),
                                   time: time(entry.start), title: entry.title, suffix: nil, symbolName: symbol(for: entry.kind), isTask: false)
        case .timedTask(let task):
            return WatchNextUpText(caption: String(localized: "Als Nächstes", bundle: .module), time: task.due.map(time), title: task.title,
                                   suffix: nil, symbolName: task.isDeadline ? "flag.fill" : "checkmark.circle", isTask: true)
        case .untimedTask(let task, let more):
            return WatchNextUpText(caption: String(localized: "Als Nächstes", bundle: .module), time: nil, title: task.title,
                                   suffix: more > 0 ? "+\(more)" : nil, symbolName: task.isDeadline ? "flag.fill" : "checkmark.circle", isTask: true)
        case .tomorrow(let entry):
            return WatchNextUpText(caption: String(localized: "Morgen", bundle: .module), time: time(entry.start), title: entry.title,
                                   suffix: nil, symbolName: symbol(for: entry.kind), isTask: false)
        case .nothingLeft:
            return WatchNextUpText(caption: String(localized: "Nichts mehr heute", bundle: .module), time: nil, title: nil, suffix: nil,
                                   symbolName: "checkmark.seal", isTask: false)
        case .stale:
            return WatchNextUpText(caption: String(localized: "Öffne Tagwerk auf dem iPhone", bundle: .module), time: nil, title: nil,
                                   suffix: nil, symbolName: "iphone", isTask: false)
        }
    }

    private static func symbol(for kind: SnapshotEntry.Kind) -> String {
        switch kind {
        case .event: "calendar"
        case .block: "rectangle.inset.filled"
        case .deadline: "flag.fill"
        }
    }

    /// One line for the inline family: "09:30 Meeting", "Mail schreiben +4", "Morgen 09:00 Zahnarzt".
    public var inline: String {
        guard let title else { return caption }
        let short = WatchComplicationText.shortened(title, limit: Self.inlineTitleLimit)
        if caption == String(localized: "Morgen", bundle: .module), let time {
            return "\(caption) \(time) \(short)"
        }
        var parts: [String] = []
        if let time { parts.append(time) }
        parts.append(short)
        if let suffix { parts.append(suffix) }
        return parts.joined(separator: " ")
    }
}

/// Counts and shortening for the other complication texts.
public enum WatchComplicationText {
    /// Cuts `text` to `limit` characters, the last one an ellipsis.
    public static func shortened(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard limit > 1, trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// "3/5": only numbers, never a habit name.
    public static func habitCounter(_ counter: HabitCounter) -> String {
        "\(counter.done)/\(counter.total)"
    }

    /// Fill of a progress ring between 0 and 1; a goal of 0 gives an empty ring.
    public static func fraction(done: Int, goal: Int) -> Double {
        guard goal > 0 else { return 0 }
        return min(max(Double(done) / Double(goal), 0), 1)
    }

    /// "1,2 l" for the water ring.
    public static func liters(milliliters: Int, locale: Locale = .current) -> String {
        Measurement(value: Double(milliliters) / 1000, unit: UnitVolume.liters)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided,
                                    numberFormatStyle: .number.precision(.fractionLength(0...1)).locale(locale)).locale(locale))
    }
}
