import Foundation
import Observation
import OSLog
import SwiftData
import TagwerkCore

/// Reads and writes focus sessions and effort samples. Reading never inserts anything.
@MainActor
@Observable
final class FocusStore {
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let logger = Logger(subsystem: "local.tagwerk", category: "focus")
    /// Bumped by every write; views read it to follow changes.
    private(set) var revision = 0

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: Sessions

    /// The session that has not ended yet; the newest one if a crash ever left several.
    func runningSession() -> FocusSessionRecord? {
        _ = revision
        var descriptor = FetchDescriptor<FocusSessionRecord>(predicate: #Predicate { $0.outcomeRaw == nil && $0.endedAt == nil },
                                                             sortBy: [SortDescriptor(\.start, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// Every session without an outcome, for cleaning up after a crash.
    func openSessions() -> [FocusSessionRecord] {
        (try? context.fetch(FetchDescriptor<FocusSessionRecord>(predicate: #Predicate { $0.outcomeRaw == nil }))) ?? []
    }

    func insert(_ session: FocusSessionRecord) {
        context.insert(session)
        save()
    }

    /// Persists changes made to a record.
    /// A failed write is logged and does not bump `revision`: nothing was persisted.
    func save() {
        do {
            try context.save()
        } catch {
            logger.error("Saving focus data failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        revision += 1
    }

    /// Sessions of a task that ended after `since` (all of them without `since`), without the discarded ones.
    func sessions(for taskKey: String, since: Date?) -> [FocusSessionRecord] {
        let all = ((try? context.fetch(FetchDescriptor<FocusSessionRecord>(
            predicate: #Predicate { $0.taskKey == taskKey }, sortBy: [SortDescriptor(\.start)]))) ?? [])
            .filter { $0.endedAt != nil && $0.outcome != .discarded }
        guard let since else { return all }
        return all.filter { ($0.endedAt ?? .distantPast) > since }
    }

    /// Sessions that ended inside `interval` and left a piece of the collection or not, newest first.
    func finishedSessions(in interval: DateInterval? = nil) -> [FocusSessionRecord] {
        _ = revision
        let all = (try? context.fetch(FetchDescriptor<FocusSessionRecord>(
            predicate: #Predicate { $0.endedAt != nil }, sortBy: [SortDescriptor(\.start, order: .reverse)]))) ?? []
        guard let interval else { return all }
        return all.filter { interval.contains($0.endedAt ?? .distantPast) }
    }

    // MARK: Samples

    func add(_ sample: EffortSampleRecord) {
        context.insert(sample)
        save()
    }

    /// Samples completed inside `interval`, oldest first.
    func samples(in interval: DateInterval) -> [EffortSampleRecord] {
        _ = revision
        let start = interval.start, end = interval.end
        return (try? context.fetch(FetchDescriptor<EffortSampleRecord>(
            predicate: #Predicate { $0.completedAt >= start && $0.completedAt < end }, sortBy: [SortDescriptor(\.completedAt)]))) ?? []
    }

    /// The newest sample of a task.
    func latestSample(for taskKey: String) -> EffortSampleRecord? {
        var descriptor = FetchDescriptor<EffortSampleRecord>(predicate: #Predicate { $0.taskKey == taskKey },
                                                             sortBy: [SortDescriptor(\.completedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// Removes the sample of exactly this completion; other completions of the task stay.
    func deleteSample(for taskKey: String, completedAt: Date) {
        let matches = (try? context.fetch(FetchDescriptor<EffortSampleRecord>(
            predicate: #Predicate { $0.taskKey == taskKey && $0.completedAt == completedAt }))) ?? []
        guard !matches.isEmpty else { return }
        for sample in matches { context.delete(sample) }
        save()
    }
}
