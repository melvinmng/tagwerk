import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct FocusStoreTests {
    let container: ModelContainer
    let store: FocusStore
    let start = testNow()

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        store = FocusStore(context: container.mainContext)
    }

    private func session(task: String? = "local:a", endedAfter minutes: Double? = nil, outcome: FocusOutcome? = nil,
                         focused: Int = 0, startOffset: Double = 0) -> FocusSessionRecord {
        let begin = start.addingTimeInterval(startOffset * 60)
        var state = FocusTimerState(start: begin, settings: FocusTimerSettings())
        state.endedAt = minutes.map { begin.addingTimeInterval($0 * 60) }
        let record = FocusSessionRecord(taskKey: task, blockEventID: nil, title: "Test", state: state)
        record.outcome = outcome
        record.focusedSeconds = focused
        return record
    }

    private func sample(_ key: String = "local:a", completedAt: Date, actual: Int = 30) -> EffortSampleRecord {
        EffortSampleRecord(taskKey: key, source: .local, labels: ["x"], estimateMinutes: 30, actualMinutes: actual,
                           method: .blocks, completedAt: completedAt)
    }

    @Test func runningSession_isNilWithoutRecords() {
        #expect(store.runningSession() == nil)
        store.insert(session(endedAfter: 20, outcome: .completed, focused: 1200))
        #expect(store.runningSession() == nil)
        store.insert(session())
        #expect(store.runningSession() != nil)
    }

    @Test func reading_neverInserts() {
        _ = store.runningSession()
        _ = store.sessions(for: "local:a", since: nil)
        _ = store.finishedSessions()
        _ = store.samples(in: DateInterval(start: start, duration: 3600))
        _ = store.latestSample(for: "local:a")
        store.deleteSample(for: "local:a", completedAt: start)
        let sessions = (try? container.mainContext.fetchCount(FetchDescriptor<FocusSessionRecord>())) ?? -1
        let samples = (try? container.mainContext.fetchCount(FetchDescriptor<EffortSampleRecord>())) ?? -1
        #expect(sessions == 0 && samples == 0)
    }

    @Test func state_roundTripsThroughTheRecord() {
        let pause = DateInterval(start: start.addingTimeInterval(60), duration: 120)
        let state = FocusTimerState(start: start, settings: FocusTimerSettings(workMinutes: 40, rounds: 2), pauses: [pause],
                                    pausedSince: start.addingTimeInterval(900), skips: [start.addingTimeInterval(1700)])
        let record = FocusSessionRecord(taskKey: nil, blockEventID: "e", title: "", state: state)
        store.insert(record)
        #expect(store.runningSession()?.state == state)
    }

    @Test func sessions_forTaskSinceDate() {
        store.insert(session(endedAfter: 25, outcome: .completed, focused: 1500, startOffset: 0))
        store.insert(session(endedAfter: 25, outcome: .completed, focused: 1500, startOffset: 120))
        store.insert(session(endedAfter: 1, outcome: .discarded, focused: 20, startOffset: 200))
        store.insert(session(task: "local:b", endedAfter: 25, outcome: .completed, focused: 1500, startOffset: 0))
        #expect(store.sessions(for: "local:a", since: nil).count == 2)
        #expect(store.sessions(for: "local:a", since: start.addingTimeInterval(60 * 60)).count == 1)
    }

    @Test func samples_inRange() {
        store.add(sample(completedAt: start.addingTimeInterval(-3600)))
        store.add(sample(completedAt: start.addingTimeInterval(60)))
        store.add(sample(completedAt: start.addingTimeInterval(7200)))
        let inRange = store.samples(in: DateInterval(start: start, duration: 3600))
        #expect(inRange.count == 1)
        #expect(inRange.first?.value.labels == ["x"])
        #expect(store.latestSample(for: "local:a")?.completedAt == start.addingTimeInterval(7200))
    }

    @Test func deleteSample_removesOnlyThatCompletion() {
        let first = start, second = start.addingTimeInterval(86_400)
        store.add(sample(completedAt: first))
        store.add(sample(completedAt: second))
        store.add(sample("local:b", completedAt: first))
        store.deleteSample(for: "local:a", completedAt: second)
        let all = store.samples(in: DateInterval(start: start.addingTimeInterval(-1), duration: 3 * 86_400))
        #expect(all.map(\.taskKey).sorted() == ["local:a", "local:b"])
        #expect(all.allSatisfy { $0.completedAt == first })
    }

    @Test func settings_haveTheDocumentedDefaults() throws {
        let settings = try AppSettings.current(in: container.mainContext)
        #expect(settings.focusTimerSettings == FocusTimerSettings())
        #expect(settings.effortHistoryInPlanning)
    }
}
