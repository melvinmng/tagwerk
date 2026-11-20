import Foundation
import Testing
@testable import TagwerkCore

struct WatchSnapshotTests {
    let calendar = makeCalendar()
    var now: Date { instant(2026, 11, 20, 9, 0, in: calendar) }
    var today: PlanDay { PlanDay(year: 2026, month: 11, day: 20) }

    private func entry(_ title: String, day: Int = 20, _ hour: Int, kind: SnapshotEntry.Kind = .event, allDay: Bool = false) -> SnapshotEntry {
        SnapshotEntry(id: "\(title):\(day)", title: title, start: instant(2026, 11, day, hour, 0, in: calendar),
                      end: instant(2026, 11, day, hour + 1, 0, in: calendar), kind: kind, colorHex: nil, isAllDay: allDay)
    }

    private func widget(entries: [SnapshotEntry] = [], tomorrow: [SnapshotEntry] = [], habits: SnapshotHabits? = nil) -> WidgetSnapshot {
        WidgetSnapshot(createdAt: now, days: [
            SnapshotDay(day: today, entries: entries, deadlineCount: 0, intake: nil, habits: habits),
            SnapshotDay(day: today.adding(days: 1, calendar: calendar), entries: tomorrow, deadlineCount: 0, intake: nil),
            SnapshotDay(day: today.adding(days: 2, calendar: calendar), entries: [entry("Later", day: 22, 8)], deadlineCount: 0, intake: nil),
        ])
    }

    private func make(tasks: [TaskItem] = [], habits: [WatchHabit] = [], water: WatchWater? = nil, entries: [SnapshotEntry] = [],
                      tomorrow: [SnapshotEntry] = [], counter: SnapshotHabits? = nil, applied: [UUID] = []) -> WatchSnapshot {
        WatchSnapshot.make(widget: widget(entries: entries, tomorrow: tomorrow, habits: counter), tasks: tasks, habits: habits,
                           water: water, appliedActionIDs: applied, now: now, calendar: calendar)
    }

    private func task(_ title: String, day: Int = 20, hour: Int? = nil, priority: Priority? = nil, completed: Bool = false) -> TaskItem {
        var item = makeItem(title, due: DueDate(year: 2026, month: 11, day: day, hour: hour, minute: hour == nil ? nil : 0), priority: priority)
        item.isCompleted = completed
        item.notes = "private note of \(title)"
        item.labels = ["secret"]
        return item
    }

    @Test func roundTrip() throws {
        let snapshot = make(tasks: [task("A", hour: 10)], habits: [WatchHabit(id: UUID(), name: "Lesen", symbol: "book", done: false, isAutomatic: false)],
                            water: WatchWater(milliliters: 500, goalMilliliters: 2000, showsInComplication: true),
                            entries: [entry("Meeting", 11)], counter: SnapshotHabits(done: 1, total: 2), applied: [UUID()])
        let decoded = try #require(WatchSnapshot.decode(try snapshot.encoded()))
        #expect(decoded == snapshot)
        #expect(decoded.habitCounter == SnapshotHabits(done: 1, total: 2))
    }

    @Test func unknownVersion_decodesAsNil() throws {
        var snapshot = make()
        snapshot.schemaVersion = WatchSnapshot.currentSchemaVersion + 1
        #expect(WatchSnapshot.decode(try snapshot.encoded()) == nil)
        #expect(WatchSnapshot.decode(Data("not json".utf8)) == nil)
    }

    /// The format has no place for notes, labels, containers or journal data: checked on the encoded keys.
    @Test func containsNoNoteFields() throws {
        let snapshot = make(tasks: [task("A", hour: 10)], habits: [WatchHabit(id: UUID(), name: "Lesen", symbol: "book", done: true, isAutomatic: false)],
                            water: WatchWater(milliliters: 1, goalMilliliters: 2, showsInComplication: false), entries: [entry("Meeting", 11)])
        let object = try #require(JSONSerialization.jsonObject(with: try snapshot.encoded()))
        var keys = Set<String>()
        func collect(_ node: Any) {
            if let dictionary = node as? [String: Any] {
                for (key, value) in dictionary { keys.insert(key); collect(value) }
            } else if let array = node as? [Any] {
                array.forEach(collect)
            }
        }
        collect(object)
        let forbidden: Set<String> = ["notes", "note", "labels", "container", "url", "journal", "gratitude", "dream", "kcal", "calories",
                                      "estimateMinutes", "assignees", "epic", "statuses", "body", "text"]
        #expect(keys.isDisjoint(with: forbidden), "unexpected keys: \(keys.intersection(forbidden))")
        let text = String(decoding: try snapshot.encoded(), as: UTF8.self)
        #expect(!text.contains("private note"))
        #expect(!text.contains("secret"))
    }

    @Test func limits20Tasks_sortedLikePlan() {
        var tasks = (1...30).map { task("Task \(String(format: "%02d", $0))", hour: 8 + ($0 % 10)) }
        tasks.append(task("Overdue", day: 19))
        tasks.append(task("Urgent", hour: 8, priority: .p1))
        let snapshot = make(tasks: tasks)
        #expect(snapshot.tasks.count == WatchSnapshot.maximumTasks)
        let expected = sortedTasks(tasks, calendar: calendar).prefix(20).map(\.id.key)
        #expect(snapshot.tasks.map(\.key) == Array(expected))
        #expect(snapshot.tasks.first?.title == "Overdue")
    }

    @Test func onlyOpenTasksOfTodayAndOverdue() {
        let snapshot = make(tasks: [task("Done", completed: true), task("Tomorrow", day: 21), makeItem("NoDate"), task("Today"),
                                    task("Late", day: 18)])
        #expect(Set(snapshot.tasks.map(\.title)) == ["Today", "Late"])
    }

    @Test func entriesCoverTodayAndTomorrowOnly() {
        let snapshot = make(entries: [entry("Now", 10)], tomorrow: [entry("Next", day: 21, 9)])
        #expect(snapshot.entries.map(\.title) == ["Now", "Next"])
    }

    @Test func automaticHabit_isNotCheckable() {
        let habit = Habit(name: "Schritte", symbol: "figure.walk", order: 0, source: .steps, start: today)
        let row = WatchHabit(habit: habit, done: true, isAutomatic: true)
        #expect(!row.isCheckable)
        #expect(WatchHabit(id: UUID(), name: "Lesen", symbol: "book", done: false, isAutomatic: false).isCheckable)
    }

    @Test func sizeStaysBelowContextLimit() throws {
        let longTitle = String(repeating: "Ä", count: 400)
        let tasks = (1...30).map { task("\($0) " + longTitle, hour: 8) }
        let entries = (0..<14).map { entry("\($0) " + longTitle, $0 % 12 + 6) }
        let habits = (0..<10).map { _ in WatchHabit(id: UUID(), name: longTitle, symbol: "figure.walk", done: false, isAutomatic: false) }
        let snapshot = make(tasks: tasks, habits: habits, water: WatchWater(milliliters: 1, goalMilliliters: 2, showsInComplication: true),
                            entries: entries, tomorrow: entries, applied: (0..<80).map { _ in UUID() })
        #expect(snapshot.appliedActionIDs.count == WatchSnapshot.maximumAppliedActionIDs)
        #expect(snapshot.tasks.allSatisfy { $0.title.count <= WatchSnapshot.maximumTitleLength })
        let size = try snapshot.encoded().count
        #expect(size < WatchSnapshot.contextSizeLimit, "size \(size)")
    }

    @Test func displayOrder_putsTimedTasksFirst() {
        let snapshot = make(tasks: [task("Untimed", priority: .p1), task("Later", hour: 15), task("Earlier", hour: 11)])
        #expect(snapshot.tasksForDisplay.map(\.title) == ["Earlier", "Later", "Untimed"])
    }

    @Test func staleWhenDayDiffers() {
        let snapshot = make()
        #expect(!snapshot.isStale(at: now, calendar: calendar))
        #expect(snapshot.isStale(at: instant(2026, 11, 21, 0, 1, in: calendar), calendar: calendar))
    }

    @Test func fileRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "watch-snapshot-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshot = make(tasks: [task("A", hour: 10)])
        try snapshot.write(to: directory)
        #expect(WatchSnapshot.load(from: directory) == snapshot)
        #expect(WatchSnapshot.load(from: nil) == nil)
    }
}
