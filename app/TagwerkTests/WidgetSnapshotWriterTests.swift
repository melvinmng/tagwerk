import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct WidgetSnapshotWriterTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "snapshot-\(UUID().uuidString)/Library/Application Support")
    final class Counter { var reloads = 0 }

    private func snapshot(title: String = "Vorlesung", createdAt: Date = .now) -> WidgetSnapshot {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let entry = SnapshotEntry(id: "e", title: title, start: start, end: start.addingTimeInterval(3600), kind: .event,
                                  colorHex: nil, isAllDay: false)
        return WidgetSnapshot(createdAt: createdAt,
                              days: [SnapshotDay(day: PlanDay(year: 2026, month: 11, day: 18), entries: [entry], deadlineCount: 0,
                                                 intake: nil)])
    }

    @Test func writer_createsDirectory_writesFile_reloadsOnce() {
        let counter = Counter()
        let writer = WidgetSnapshotWriter(directory: directory, reload: { counter.reloads += 1 })
        writer.write(snapshot())
        #expect(writer.current()?.days.first?.entries.first?.title == "Vorlesung")
        #expect(counter.reloads == 1)
        let backup = try? directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
        #expect(backup == true)
    }

    @Test func writer_sameContent_noSecondReload() {
        let counter = Counter()
        let writer = WidgetSnapshotWriter(directory: directory, reload: { counter.reloads += 1 })
        writer.write(snapshot(createdAt: .now))
        writer.write(snapshot(createdAt: .now.addingTimeInterval(60)))
        #expect(counter.reloads == 1)
        writer.write(snapshot(title: "Sport"))
        #expect(counter.reloads == 2)
    }

    @Test func writer_nilDirectory_noop() {
        let counter = Counter()
        let writer = WidgetSnapshotWriter(directory: nil, reload: { counter.reloads += 1 })
        writer.write(snapshot())
        #expect(writer.current() == nil)
        #expect(counter.reloads == 0)
    }

    @Test func writer_corruptFile_loadsNil() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{".utf8).write(to: directory.appending(path: WidgetSnapshot.fileName))
        #expect(WidgetSnapshotWriter(directory: directory, reload: {}).current() == nil)
    }
}

@MainActor
struct WidgetSnapshotEnvironmentTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "env-\(UUID().uuidString)")

    private func environment() throws -> AppEnvironment {
        let container = try ModelContainerFactory.make(inMemory: true)
        let writer = WidgetSnapshotWriter(directory: directory, reload: {})
        let environment = try AppEnvironment(modelContainer: container, notificationCenter: FakeNotificationCenter(),
                                             health: FakeHealthStore(), snapshotWriter: writer)
        environment.settings.setupCompleted = true
        return environment
    }

    @Test func makeSnapshot_coversThreeDays_withIntake() async throws {
        let environment = try environment()
        await environment.capture.reload()
        await environment.capture.addWater(500, at: .now)
        await environment.capture.waitForHealth()
        let snapshot = environment.makeSnapshot()
        #expect(snapshot.days.count == 3)
        #expect(snapshot.days[0].intake?.waterMilliliters == 500)
        #expect(snapshot.days[1].intake == nil)
    }

    @Test func makeSnapshot_withoutNutritionSetting_noIntake() async throws {
        let environment = try environment()
        environment.settings.widgetShowsNutrition = false
        await environment.capture.reload()
        await environment.capture.addWater(500, at: .now)
        await environment.capture.waitForHealth()
        #expect(environment.makeSnapshot().days.allSatisfy { $0.intake == nil })
    }

    @Test func makeSnapshot_leavesPlanningUntouched() throws {
        let environment = try environment()
        let anchor = environment.planning.anchor.adding(days: 10, calendar: environment.planning.calendar)
        environment.planning.anchor = anchor
        environment.planning.scope = .week
        _ = environment.makeSnapshot()
        #expect(environment.planning.anchor == anchor)
        #expect(environment.planning.scope == .week)
    }

    @Test func writeSnapshot_sourcesNotLoaded_keepsPlanPart() async throws {
        let environment = try environment()
        let today = PlanDay(date: .now, calendar: environment.planning.calendar)
        let entry = SnapshotEntry(id: "e", title: "Vorlesung", start: .now.addingTimeInterval(3600),
                                  end: .now.addingTimeInterval(7200), kind: .event, colorHex: nil, isAllDay: false)
        environment.snapshotWriter.write(WidgetSnapshot(createdAt: .now,
                                                        days: [SnapshotDay(day: today, entries: [entry], deadlineCount: 0, intake: nil)]))
        #expect(environment.taskList.sourceStates.isEmpty)
        await environment.capture.reload()
        await environment.capture.addWater(250, at: .now)
        await environment.capture.waitForHealth()
        environment.writeSnapshot()
        let written = try #require(environment.snapshotWriter.current())
        #expect(written.days[0].entries.map(\.title) == ["Vorlesung"])
        #expect(written.days[0].intake?.waterMilliliters == 250)
    }

    @Test func writeSnapshot_beforeSetup_writesEmptyPlan() throws {
        let environment = try environment()
        environment.settings.setupCompleted = false
        environment.writeSnapshot()
        #expect(environment.snapshotWriter.current()?.days.isEmpty == true)
    }

    @Test func settingsChange_rewritesSnapshotWithoutNutrition() async throws {
        let environment = try environment()
        let today = PlanDay(date: .now, calendar: environment.planning.calendar)
        environment.snapshotWriter.write(WidgetSnapshot(createdAt: .now, days: [SnapshotDay(day: today, entries: [], deadlineCount: 0,
            intake: SnapshotIntake(kcal: 900, hasEstimate: true, goalKcal: 2300, waterMilliliters: 0, goalWaterMilliliters: 2000))]))
        environment.settings.widgetShowsNutrition = false
        environment.writeSnapshot()
        #expect(environment.snapshotWriter.current()?.days.allSatisfy { $0.intake == nil } == true)
    }

    @Test func backgroundRefresh_writesSnapshot() async {
        final class Counter { var writes = 0 }
        let counter = Counter()
        let refresh = BackgroundRefresh(prepare: { false }, reload: {}, reschedule: {}, writeSnapshot: { counter.writes += 1 },
                                        submit: { _ in })
        await refresh.run()
        #expect(counter.writes == 1)
    }
}
