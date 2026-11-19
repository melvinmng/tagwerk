import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct RoutineNotificationTests {
    let container: ModelContainer
    let settings: AppSettings
    let store: RoutineStore
    let center = FakeNotificationCenter()

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        settings = try AppSettings.current(in: container.mainContext)
        store = RoutineStore(context: container.mainContext)
    }

    private func makeScheduler() -> RoutineNotificationScheduler {
        RoutineNotificationScheduler(center: center, store: store, settings: settings, locale: { Locale(identifier: "de_DE") })
    }

    @Test func reschedule_replacesAllRoutineRequests() async {
        store.adoptSuggestion()
        center.seed("tagwerk.routine.evening.OLD", fireDate: nil)
        await makeScheduler().reschedule()
        #expect(!center.pendingIDs.contains("tagwerk.routine.evening.OLD"))
        #expect(center.pendingIDs.count == 3 && center.pendingIDs.allSatisfy { $0.hasPrefix("tagwerk.routine.evening.") })
        #expect(center.addedRepeating.map(\.title) == ["Tagesabschluss öffnen", "Handy weglegen", "Ins Bett"])
    }

    @Test func reschedule_keepsDeadlineRequests() async {
        store.adoptSuggestion()
        center.seed("tagwerk.task.local:1", fireDate: testNow().addingTimeInterval(3600))
        await makeScheduler().reschedule()
        #expect(center.pendingIDs.contains("tagwerk.task.local:1"))
    }

    @Test func reschedule_withoutPermission_addsNothing() async {
        store.adoptSuggestion()
        center.status = .denied
        center.seed("tagwerk.routine.evening.OLD", fireDate: nil)
        await makeScheduler().reschedule()
        #expect(center.addedRepeating.isEmpty)
        // Without permission nothing can stay pending either.
        #expect(!center.pendingIDs.contains("tagwerk.routine.evening.OLD"))
    }

    @Test func reschedule_whenSwitchedOff_removesTheRequests() async {
        store.adoptSuggestion()
        let scheduler = makeScheduler()
        await scheduler.reschedule()
        settings.eveningRemindersEnabled = false
        await scheduler.reschedule()
        #expect(center.pendingIDs.isEmpty)
    }

    @Test func reschedule_followsTheBedtime() async {
        store.adoptSuggestion()
        settings.bedtimeMinutes = 1320
        await makeScheduler().reschedule()
        let first = center.addedRepeating.first
        #expect(first?.hour == 20 && first?.minute == 30)
    }

    @Test func reschedule_addsTheMorningRequest_whenEnabled() async {
        store.adoptSuggestion()
        store.saveItem(ChecklistItem(title: "Vierter", order: 3, offsetMinutes: 15))
        settings.morningReminderEnabled = true
        await makeScheduler().reschedule()
        #expect(center.pendingIDs.contains("tagwerk.routine.morning"))
        #expect(center.pendingIDs.count == 5)
        #expect(center.addedRepeating.first { $0.id == "tagwerk.routine.morning" }?.route == .routineStart)
    }

    @Test func reschedule_morningStaysOffByDefault() async {
        await makeScheduler().reschedule()
        #expect(!center.pendingIDs.contains("tagwerk.routine.morning"))
    }

    @Test func reschedule_morningFollowsItsTime() async {
        settings.morningReminderEnabled = true
        settings.morningReminderMinutes = 8 * 60
        await makeScheduler().reschedule()
        #expect(center.addedRepeating.first?.hour == 8 && center.addedRepeating.first?.minute == 0)
    }
}
