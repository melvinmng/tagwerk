import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct PlanStoreTests {
    let container: ModelContainer
    let store: PlanStore
    let a = TaskID(source: .reminders, rawValue: "a")
    let b = TaskID(source: .github, rawValue: "I_b")
    let today = PlanDay(year: 2026, month: 11, day: 18)

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        store = PlanStore(context: container.mainContext)
    }

    @Test func assign_replacesPreviousDay() {
        store.assign(a, to: today)
        store.assign(a, to: PlanDay(year: 2026, month: 11, day: 20))
        #expect(store.assignment(for: a) == PlanDay(year: 2026, month: 11, day: 20))
        #expect(store.assignments(in: today...PlanDay(year: 2026, month: 11, day: 30)).count == 1)
    }

    // MARK: Moves of the planned day (the activity log of #332)

    @Test func onDayMoved_reportsAMoveFromOneDayToAnother() {
        var moves: [(TaskID, PlanDay, PlanDay)] = []
        store.onDayMoved = { moves.append(($0, $1, $2)) }
        let later = PlanDay(year: 2026, month: 11, day: 20)
        store.assign(a, to: today)
        store.assign(a, to: later)
        #expect(moves.count == 1)
        #expect(moves.first?.0 == a && moves.first?.1 == today && moves.first?.2 == later)
    }

    @Test func onDayMoved_isSilentForFirstPlanningRemovalAndTheSameDay() {
        var moves = 0
        store.onDayMoved = { _, _, _ in moves += 1 }
        store.assign(a, to: today)
        store.assign(a, to: today)
        store.unassign(a)
        store.assign(a, to: today)
        #expect(moves == 0)
    }

    @Test func restore_putsTheTaskBackAndReportsTheUndoInsteadOfAMove() {
        var moves = 0
        var undone: [(TaskID, PlanDay, PlanDay)] = []
        let later = PlanDay(year: 2026, month: 11, day: 20)
        store.assign(a, to: today)
        store.assign(a, to: later)
        store.onDayMoved = { _, _, _ in moves += 1 }
        store.onDayMoveUndone = { undone.append(($0, $1, $2)) }
        store.restore(a, to: today)
        #expect(moves == 0)
        #expect(undone.count == 1 && undone.first?.1 == later && undone.first?.2 == today)
        #expect(store.assignments(in: today...today).count == 1)
    }

    @Test func unassign_removes() {
        store.assign(a, to: today)
        store.unassign(a)
        #expect(store.assignment(for: a) == nil)
    }

    @Test func leftovers_onlyOpenPastAssignments() {
        store.assign(a, to: PlanDay(year: 2026, month: 11, day: 16))
        store.assign(b, to: today)
        let done = TaskID(source: .local, rawValue: "done")
        store.assign(done, to: PlanDay(year: 2026, month: 11, day: 15))
        #expect(store.leftovers(before: today, openTaskIDs: [a, b]) == [a])
    }

    @Test func prune_removesCompletedOrMissing() {
        store.assign(a, to: today)
        store.assign(b, to: today)
        store.prune(keeping: [b])
        #expect(store.assignment(for: a) == nil)
        #expect(store.assignment(for: b) == today)
    }

    @Test func override_setAndClear() {
        let hours = WorkHours(startMinutes: 600, endMinutes: 1200)
        store.setOverride(.hours(hours), on: today)
        #expect(store.override(on: today) == .hours(hours))
        store.setOverride(.off, on: today)
        #expect(store.override(on: today) == .off)
        #expect(store.overrides(in: today...today) == [today: .off])
        store.setOverride(nil, on: today)
        #expect(store.override(on: today) == nil)
    }

    @Test func settings_weekSchedule_defaultsToStandard() throws {
        let settings = try AppSettings.current(in: container.mainContext)
        #expect(settings.weekSchedule == .standard)
        #expect(settings.defaultTaskMinutes == 30)
        #expect(settings.planCalendarID == nil)
        #expect(settings.deadlineCalendarIDs == nil)
    }

    @Test func settings_weekSchedule_roundTrip() throws {
        let settings = try AppSettings.current(in: container.mainContext)
        var custom = WeekSchedule.standard
        custom.hoursByWeekday[7] = WorkHours(startMinutes: 600, endMinutes: 840)
        settings.weekSchedule = custom
        #expect(settings.weekSchedule == custom)
    }

    @Test func reminderEstimates_storeAndClear() {
        let estimates = SwiftDataEstimateStore(context: container.mainContext)
        estimates.setMinutes(180, for: "r1")
        #expect(estimates.minutes(for: "r1") == 180)
        estimates.setMinutes(nil, for: "r1")
        #expect(estimates.minutes(for: "r1") == nil)
    }
}
