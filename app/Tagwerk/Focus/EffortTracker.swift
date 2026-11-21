import Foundation
import OSLog
import RemindersKit
import TagwerkCore

/// Measures the actual effort when a task is completed and cuts a time block that ended early (plan P3, #162).
///
/// The rules are in `EffortRules`: the time blocks of the task decide, focus time only adds what lies outside them.
/// This class reads the blocks and the focus intervals, writes the cut through
/// `CalendarStore.moveBlock` (with the version check) and stores the sample. Only Tagwerk's own blocks (the task link in
/// the event's URL) are read and cut, so Tagwerk never touches an appointment of the user.
@MainActor
final class EffortTracker {
    /// How far back the blocks of a task are searched, and how far ahead (a block that starts after midnight).
    static let lookBack: TimeInterval = 14 * 86_400
    static let lookAhead: TimeInterval = 86_400
    /// "Rückgängig" restores the block only for a completion this recent.
    static let undoWindow: TimeInterval = 24 * 3600

    private let store: FocusStore
    private let blocks: BlockPlanner
    private let calendarStore: CalendarStore
    private let settings: AppSettings
    private let now: () -> Date
    private let log = Logger(subsystem: "local.tagwerk", category: "effort")

    init(store: FocusStore, blocks: BlockPlanner, calendarStore: CalendarStore, settings: AppSettings,
         now: @escaping () -> Date = Date.init) {
        self.store = store
        self.blocks = blocks
        self.calendarStore = calendarStore
        self.settings = settings
        self.now = now
    }

    /// Records the effort of a completion. Returns whether a time block was cut, so the plan can read the calendar again.
    @discardableResult
    func didComplete(_ item: TaskItem, at completedAt: Date) async -> Bool {
        let key = item.id.key
        let previous = store.latestSample(for: key)?.completedAt
        let window = DateInterval(start: completedAt.addingTimeInterval(-Self.lookBack), end: completedAt.addingTimeInterval(Self.lookAhead))
        let events = blocks.blocks(for: item.id, in: window)
        // The work phases of the timer sessions; only the part outside the task's blocks adds to the blocks' time.
        let focus = store.sessions(for: key, since: previous).flatMap { FocusTimerRules.workIntervals(of: $0.state) }
        let outcome = EffortRules.outcome(completedAt: completedAt,
                                          blocks: events.map { EffortBlock(id: $0.id, start: $0.start, end: $0.end) },
                                          focus: focus, since: previous)
        var trimmed: (eventID: String, oldEnd: Date, newEnd: Date)?
        if let trim = outcome.trim, let block = events.first(where: { $0.id == trim.blockID }) {
            if let updated = cut(block, to: trim.newEnd) { trimmed = (updated.id, trim.oldEnd, updated.end) }
        } else if outcome.trim == nil, !outcome.tooShortToTrim {
            log.debug("No block cut for \(key, privacy: .private): \(events.count) blocks found, none running or none to shorten")
        }
        guard let minutes = outcome.actualMinutes, let method = outcome.method else { return trimmed != nil }
        let sample = EffortSampleRecord(taskKey: key, source: item.id.source, labels: item.labels ?? [],
                                        estimateMinutes: item.estimateMinutes, actualMinutes: minutes, method: method,
                                        completedAt: completedAt)
        sample.trimmedEventID = trimmed?.eventID
        sample.trimmedOriginalEnd = trimmed?.oldEnd
        sample.trimmedNewEnd = trimmed?.newEnd
        store.add(sample)
        return trimmed != nil
    }

    /// Writes the new end of a block. A write that fails only because the version moved on (a sync touched the event) is
    /// repeated once against the current event, as long as its start and end are still the ones that were read. A block
    /// somebody changed stays as it is. The reason of every failure is logged, because the block just stays long
    /// otherwise.
    private func cut(_ block: CalendarEvent, to newEnd: Date) -> CalendarEvent? {
        do {
            return try calendarStore.moveBlock(id: block.id, to: block.start, end: newEnd, expectedVersion: block.version)
        } catch {
            log.error("Block cut failed: \(String(describing: error), privacy: .public)")
            guard let current = calendarStore.event(id: block.id), current.version != block.version,
                  current.start == block.start, current.end == block.end else { return nil }
            do {
                return try calendarStore.moveBlock(id: block.id, to: block.start, end: newEnd, expectedVersion: current.version)
            } catch {
                log.error("Block cut failed again: \(String(describing: error), privacy: .public)")
                return nil
            }
        }
    }

    /// "Rückgängig": the newest sample of the task goes, and a block cut for it gets its old end back, but only while
    /// nobody changed the block since.
    @discardableResult
    func didReopen(_ id: TaskID) async -> Bool {
        let key = id.key
        guard let sample = store.latestSample(for: key), now().timeIntervalSince(sample.completedAt) <= Self.undoWindow else { return false }
        var restored = false
        if let eventID = sample.trimmedEventID, let oldEnd = sample.trimmedOriginalEnd, let newEnd = sample.trimmedNewEnd,
           let event = calendarStore.event(id: eventID), event.end == newEnd {
            restored = (try? calendarStore.moveBlock(id: eventID, to: event.start, end: oldEnd, expectedVersion: event.version)) != nil
        }
        store.deleteSample(for: key, completedAt: sample.completedAt)
        return restored
    }

    // MARK: Blocks that ended early (FO15b)

    /// The cut blocks among `events`: a sample names the event and its stored new end still equals the event's end. A block
    /// whose end somebody changed afterwards is no longer marked.
    func trimmedBlocks(among events: [CalendarEvent]) -> [String: TrimmedBlock] {
        guard let first = events.map(\.start).min(), let last = events.map(\.end).max() else { return [:] }
        // A block is cut when its task is completed, which lies in or right after the block.
        let window = DateInterval(start: first.addingTimeInterval(-86_400), end: last.addingTimeInterval(86_400))
        let byID = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [String: TrimmedBlock] = [:]
        for sample in store.samples(in: window) {
            guard let id = sample.trimmedEventID, let event = byID[id], let newEnd = sample.trimmedNewEnd, event.end == newEnd,
                  let originalEnd = sample.trimmedOriginalEnd, originalEnd > event.end else { continue }
            let planned = Int(originalEnd.timeIntervalSince(event.start) / 60)
            let actual = Int(event.end.timeIntervalSince(event.start) / 60)
            result[id] = TrimmedBlock(plannedMinutes: planned, actualMinutes: actual)
        }
        return result
    }

    // MARK: Statistics

    /// The samples of the last eight weeks up to `date`.
    func samples(until date: Date) -> [EffortSample] {
        let window = DateInterval(start: date.addingTimeInterval(-EffortStats.window), end: date)
        return store.samples(in: window).map(\.value)
    }

    /// Expected minutes per task (`TaskID.key`) from the measured samples: the estimate times the correction factor of
    /// the task's label or source, rounded to 5 minutes. Empty while the setting is off and for tasks without estimate or
    /// without enough samples. This is the only number derived from the samples that ever leaves the device.
    func expectedMinutes(for tasks: [TaskItem]) -> [String: Int] {
        guard settings.effortHistoryInPlanning else { return [:] }
        let current = now()
        let samples = samples(until: current.addingTimeInterval(1))
        guard !samples.isEmpty else { return [:] }
        var result: [String: Int] = [:]
        for task in tasks {
            guard let estimate = task.estimateMinutes, estimate > 0 else { continue }
            let factor = EffortStats.factor(source: task.id.source, labels: task.labels ?? [], samples: samples, now: current)
            guard factor != 1 else { continue }
            result[task.id.key] = EffortStats.expectedMinutes(estimate: estimate, factor: factor)
        }
        return result
    }
}
