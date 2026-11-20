import Foundation
import Testing
@testable import TagwerkCore

struct WatchNextUpTests {
    let calendar = makeCalendar()
    let today = PlanDay(year: 2026, month: 11, day: 20)

    private func at(_ hour: Int, _ minute: Int = 0, day: Int = 20) -> Date { instant(2026, 11, day, hour, minute, in: calendar) }

    private func entry(_ title: String, _ start: Int, _ end: Int, kind: SnapshotEntry.Kind = .event, day: Int = 20, allDay: Bool = false) -> SnapshotEntry {
        SnapshotEntry(id: "\(title):\(day)", title: title, start: at(start, day: day), end: at(end, day: day), kind: kind, colorHex: nil, isAllDay: allDay)
    }

    private func task(_ title: String, hour: Int? = nil, minute: Int = 0) -> WatchTask {
        WatchTask(key: "local:\(title)", title: title, due: hour.map { at($0, minute) } ?? at(0), hasTime: hour != nil, isDeadline: false,
                  source: .local, version: "1")
    }

    private func snapshot(entries: [SnapshotEntry] = [], tasks: [WatchTask] = []) -> WatchSnapshot {
        WatchSnapshot(createdAt: at(8), day: today, entries: entries, tasks: tasks, habits: [], habitCounter: nil, water: nil, appliedActionIDs: [])
    }

    @Test func runningEvent_winsOverTask() {
        let result = WatchNextUp.select(snapshot: snapshot(entries: [entry("Meeting", 9, 10)], tasks: [task("Call", hour: 9, minute: 30)]),
                                        now: at(9, 15), calendar: calendar)
        guard case .entry(let entry, let running) = result else { Issue.record("expected entry, got \(result)"); return }
        #expect(entry.title == "Meeting")
        #expect(running)
    }

    @Test func eventStartingSoon_winsOverTask() {
        let result = WatchNextUp.select(snapshot: snapshot(entries: [entry("Meeting", 11, 12)], tasks: [task("Call", hour: 10)]),
                                        now: at(9), calendar: calendar)
        guard case .entry(let entry, let running) = result else { Issue.record("expected entry, got \(result)"); return }
        #expect(entry.title == "Meeting")
        #expect(!running)
    }

    @Test func eventInFourHours_losesToTimedTask() {
        let result = WatchNextUp.select(snapshot: snapshot(entries: [entry("Meeting", 13, 14)], tasks: [task("Call", hour: 12)]),
                                        now: at(9), calendar: calendar)
        guard case .timedTask(let task) = result else { Issue.record("expected task, got \(result)"); return }
        #expect(task.title == "Call")
    }

    @Test func onlyUntimedTasks_showsFirstWithCount() {
        let tasks = ["A", "B", "C", "D", "E"].map { task($0) }
        let result = WatchNextUp.select(snapshot: snapshot(tasks: tasks), now: at(9), calendar: calendar)
        guard case .untimedTask(let first, let more) = result else { Issue.record("expected untimed task, got \(result)"); return }
        #expect(first.title == "A")
        #expect(more == 4)
    }

    @Test func pastTimedTask_countsAsOtherTask() {
        let result = WatchNextUp.select(snapshot: snapshot(tasks: [task("Missed", hour: 8)]), now: at(9), calendar: calendar)
        guard case .untimedTask(let first, let more) = result else { Issue.record("expected untimed task, got \(result)"); return }
        #expect(first.title == "Missed")
        #expect(more == 0)
    }

    @Test func afterLastEvent_showsTomorrow() {
        let result = WatchNextUp.select(snapshot: snapshot(entries: [entry("Done", 8, 9), entry("Early", 9, 10, day: 21), entry("Late", 15, 16, day: 21)]),
                                        now: at(12), calendar: calendar)
        guard case .tomorrow(let entry) = result else { Issue.record("expected tomorrow, got \(result)"); return }
        #expect(entry.title == "Early")
    }

    @Test func nothingLeft() {
        #expect(WatchNextUp.select(snapshot: snapshot(entries: [entry("Done", 8, 9)]), now: at(12), calendar: calendar) == .nothingLeft)
    }

    @Test func allDayIgnored() {
        let result = WatchNextUp.select(snapshot: snapshot(entries: [entry("Holiday", 0, 23, allDay: true), entry("Birthday", 0, 23, day: 21, allDay: true)]),
                                        now: at(9), calendar: calendar)
        #expect(result == .nothingLeft)
    }

    @Test func staleSnapshot() {
        #expect(WatchNextUp.select(snapshot: snapshot(), now: at(9, day: 21), calendar: calendar) == .stale)
    }

    @Test func timelineDates_includeTaskTimesAndMidnight() {
        let dates = WatchNextUp.timelineDates(snapshot: snapshot(entries: [entry("Meeting", 14, 15)], tasks: [task("Call", hour: 11)]),
                                              from: at(9), calendar: calendar)
        #expect(dates.first == at(9))
        #expect(dates.contains(at(11)))
        #expect(dates.contains(at(14)))
        #expect(dates.contains(at(15)))
        // The meeting enters the three-hour window at 11:00.
        #expect(dates.contains(at(11)))
        #expect(dates.contains(at(0, day: 21)))
        #expect(dates == dates.sorted())
    }

    @Test func timelineDates_areCapped() {
        let entries = (0..<20).map { entry("E\($0)", 9 + ($0 % 12), 10 + ($0 % 12)) }
        #expect(WatchNextUp.timelineDates(snapshot: snapshot(entries: entries), from: at(0), calendar: calendar, limit: 30).count <= 30)
    }
}
