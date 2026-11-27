import Foundation
import RemindersKit
import TagwerkCore

/// Reads what the app recorded about time for the project page (#332, stage 2): the blocks Tagwerk planned, the finished focus
/// sessions and the measured completions. The records are the app's own; nothing is written and nothing leaves the device.
@MainActor
struct ProjectTimeReader {
    let focusStore: FocusStore
    /// Tagwerk's own blocks of the tasks that overlap the interval (`BlockPlanner.blocks(forTaskKeys:in:)`): one read for all tasks.
    let blocks: (Set<String>, DateInterval) -> [CalendarEvent]
    /// Full access to the calendar. Without it the blocks cannot be read, which is not the same as having planned nothing.
    let calendarAvailable: () -> Bool

    /// The records of the given tasks for `range`. A session or block that only overlaps the range is included whole; the calculation
    /// cuts it at the weeks.
    func inputs(taskKeys: Set<String>, range: ProjectRange) -> ProjectTimeInputs {
        let available = calendarAvailable()
        guard !taskKeys.isEmpty else { return ProjectTimeInputs(calendarAvailable: available) }

        // Completions later than the range still decide whether a block of the range counts as spent time.
        let samples = focusStore.samples(in: DateInterval(start: range.start, end: .distantFuture)).filter { taskKeys.contains($0.taskKey) }
        let completions = samples.map {
            ProjectCompletion(taskKey: $0.taskKey, completedAt: $0.completedAt,
                              countsBlocks: EffortMethod(rawValue: $0.methodRaw).map { $0 != .focus } ?? false)
        }

        var timeBlocks: [ProjectTimeBlock] = []
        if available, range.end > range.start {
            let cuts = Dictionary(samples.compactMap { sample -> (String, EffortSampleRecord)? in
                sample.trimmedEventID.map { ($0, sample) }
            }, uniquingKeysWith: { first, _ in first })
            for event in blocks(taskKeys, DateInterval(start: range.start, end: range.end)) {
                guard let key = event.url.flatMap(TaskLinkURL.parse)?.key else { continue }
                // A block that was cut at a completion is planned with the end it had before, as long as nobody changed it since
                // (the rule of `EffortTracker.trimmedBlocks`).
                var plannedEnd: Date?
                if let cut = cuts[event.id], cut.trimmedNewEnd == event.end, let original = cut.trimmedOriginalEnd, original > event.end {
                    plannedEnd = original
                }
                timeBlocks.append(ProjectTimeBlock(taskKey: key, start: event.start, end: event.end, plannedEnd: plannedEnd))
            }
        }

        // Finished sessions only (a running one has no end yet); a discarded one was thrown away by the user.
        let spans = focusStore.finishedSessions(in: DateInterval(start: range.start, end: .distantFuture))
            .filter { session in
                guard let key = session.taskKey, taskKeys.contains(key) else { return false }
                return session.outcome != .discarded
            }
            .flatMap { session in
                FocusTimerRules.workIntervals(of: session.state).map {
                    ProjectFocusSpan(taskKey: session.taskKey ?? "", start: $0.start, end: $0.end)
                }
            }
        return ProjectTimeInputs(blocks: timeBlocks, focus: spans, completions: completions, calendarAvailable: available)
    }
}
