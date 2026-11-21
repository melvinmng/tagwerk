import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct FocusTimerModelTests {
    let container: ModelContainer
    let store: FocusStore
    let clock = FocusTestClock()
    let activity = FakeFocusActivity()
    let notifications = FakeFocusNotifications()
    var timerSettings = FocusTimerSettings()

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        store = FocusStore(context: container.mainContext)
    }

    private func makeModel(settings: FocusTimerSettings = FocusTimerSettings(), store: FocusStore? = nil,
                           activity: FakeFocusActivity? = nil) -> FocusTimerModel {
        FocusTimerModel(store: store ?? self.store, settings: { settings }, activity: activity ?? self.activity,
                        notifications: notifications, now: { [clock] in clock.now }, wakesAtPhaseEnd: false)
    }

    private func block(from start: Date, minutes: Int) -> CalendarEvent {
        CalendarEvent(id: "b1", externalID: nil, calendarID: "plan", title: "Block", start: start,
                      end: start.addingTimeInterval(TimeInterval(minutes * 60)), isAllDay: false, url: nil, isBusy: true, version: "1")
    }

    @Test func startFromBlock_usesTheRemainingBlockLength() async {
        let single = FocusTimerSettings(isPomodoro: false)
        let model = makeModel(settings: single)
        // The block runs 10:00 to 11:00, it is 10:20 now: 40 minutes are left.
        clock.advance(minutes: 20)
        await model.start(task: makeTask("Aufgabe", source: .local), block: block(from: testNow(), minutes: 60))
        #expect(model.session?.state.settings.workMinutes == 40)
        #expect(model.session?.blockEventID == "b1")
        #expect(model.isPresented)
        await model.stop()
        // Almost over: at least five minutes.
        clock.advance(minutes: 38)
        await model.start(task: nil, block: block(from: testNow(), minutes: 60))
        #expect(model.session?.state.settings.workMinutes == 5)
    }

    @Test func start_schedulesOneNotificationAndStartsTheActivity() async {
        let model = makeModel()
        await model.start(task: makeTask("Aufgabe", source: .local), block: nil)
        #expect(activity.started.count == 1)
        #expect(activity.latest?.kind == .work)
        #expect(notifications.pending?.fireDate == testNow().addingTimeInterval(25 * 60))
        #expect(notifications.pending?.endingKind == .work)
        #expect(notifications.pending?.taskKey == "local:Aufgabe")
    }

    @Test func pause_removesThePendingNotification() async {
        let model = makeModel()
        await model.start(task: nil, block: nil)
        clock.advance(minutes: 10)
        await model.pause()
        #expect(notifications.pending == nil)
        #expect(activity.latest?.pausedRemaining == 15 * 60)
        #expect(activity.latest?.phaseEnd == nil)
        clock.advance(minutes: 30)
        await model.resume()
        // The clock stopped for the thirty minutes of the pause.
        #expect(notifications.pending?.fireDate == clock.now.addingTimeInterval(15 * 60))
        #expect(model.snapshot(at: clock.now)?.focusedSeconds == 10 * 60)
    }

    @Test func skipBreak_startsTheNextRound() async {
        let model = makeModel()
        await model.start(task: nil, block: nil)
        clock.advance(minutes: 26)
        #expect(model.snapshot(at: clock.now)?.phase == .shortBreak(round: 1))
        await model.skipBreak()
        #expect(model.snapshot(at: clock.now)?.phase == .work(round: 2))
        #expect(activity.latest?.kind == .work && activity.latest?.round == 2)
        #expect(notifications.pending?.fireDate == clock.now.addingTimeInterval(25 * 60))
    }

    @Test func finishComplete_completesTheTaskOnce() async {
        let model = makeModel(settings: FocusTimerSettings(isPomodoro: false))
        var completed: [String] = []
        var sessionWasSaved = false
        model.completeTask = { [store] key in
            completed.append(key)
            // The session is already ended and saved, so the effort of the completion sees its focus time.
            sessionWasSaved = store.runningSession() == nil && store.sessions(for: key, since: nil).first?.focusedSeconds == 25 * 60
        }
        await model.start(task: makeTask("Aufgabe", source: .local), block: nil)
        clock.advance(minutes: 25)
        await model.finish(.complete)
        #expect(completed == ["local:Aufgabe"])
        #expect(sessionWasSaved)
        #expect(model.session == nil)
        #expect(model.lastPiece == .completed(.three))
        #expect(activity.endCount == 1)
        #expect(notifications.pending == nil)
        // A second tap changes nothing.
        await model.finish(.complete)
        #expect(completed.count == 1)
    }

    @Test func finishPostpone_assignsTomorrow() async {
        let model = makeModel(settings: FocusTimerSettings(isPomodoro: false))
        var postponed: [String] = []
        model.postponeTask = { postponed.append($0) }
        await model.start(task: makeTask("Aufgabe", source: .local), block: nil)
        clock.advance(minutes: 25)
        await model.finish(.postpone)
        #expect(postponed == ["local:Aufgabe"])
        #expect(model.session == nil)
        #expect(store.finishedSessions().first?.outcome == .completed)
    }

    @Test func finishKeepGoing_afterTheEnd_startsAFollowUpSession() async {
        let model = makeModel(settings: FocusTimerSettings(isPomodoro: false))
        await model.start(task: makeTask("Aufgabe", source: .local), block: nil)
        let first = model.session?.id
        clock.advance(minutes: 26)
        await model.finish(.keepGoing)
        #expect(model.session != nil && model.session?.id != first)
        #expect(model.session?.taskKey == "local:Aufgabe")
        #expect(store.finishedSessions().count == 1)
        #expect(store.finishedSessions().first?.outcome == .completed)
    }

    @Test func stopWithinAMinute_discardsTheSession() async {
        let model = makeModel()
        await model.start(task: nil, block: nil)
        clock.advance(minutes: 0.5)
        await model.stop()
        #expect(model.session == nil)
        #expect(model.lastPiece == nil)
        #expect(store.finishedSessions().first?.outcome == .discarded)
        #expect(activity.endCount == 1)
    }

    @Test func stopDuringThePhase_leavesAnEarlyPiece() async {
        let model = makeModel()
        await model.start(task: nil, block: nil)
        clock.advance(minutes: 10)
        await model.stop()
        #expect(model.lastPiece == .endedEarly(.two))
        #expect(store.finishedSessions().first?.outcome == .aborted)
    }

    @Test func completeDuringTheWorkPhase_isCompleted_withTheReachedStage() async {
        let model = makeModel()
        var completed: [String] = []
        model.completeTask = { completed.append($0) }
        await model.start(task: makeTask("Aufgabe", source: .local), block: nil)
        // 18 of 25 minutes: "Erledigt" ends the session as completed, with the stage reached and not marked early.
        clock.advance(minutes: 18)
        await model.finish(.complete)
        #expect(completed == ["local:Aufgabe"])
        #expect(store.finishedSessions().first?.outcome == .completed)
        #expect(store.finishedSessions().first?.focusedSeconds == 18 * 60)
        #expect(model.lastPiece == .completed(.two))
        #expect(model.lastPiece?.isEndedEarly == false)
    }

    @Test func completeDuringABreak_isCompleted() async {
        let model = makeModel()
        await model.start(task: makeTask("Aufgabe", source: .local), block: nil)
        // 25 minutes of work, 2 minutes into the short break.
        clock.advance(minutes: 27)
        #expect(model.snapshot(at: clock.now)?.phase == .shortBreak(round: 1))
        await model.finish(.complete)
        #expect(store.finishedSessions().first?.outcome == .completed)
        #expect(model.lastPiece == .completed(.three))
    }

    @Test func completeWithinTheFirstMinute_leavesNoPiece() async {
        let model = makeModel()
        await model.start(task: makeTask("Aufgabe", source: .local), block: nil)
        clock.advance(minutes: 0.5)
        await model.finish(.complete)
        #expect(model.session == nil)
        #expect(model.lastPiece == nil)
        #expect(store.finishedSessions().first?.piece == nil)
    }

    @Test func storedAbortedSession_readsAsEndedEarly() {
        // Sessions stored before the rename keep their raw value "aborted" and read as "ended early".
        let record = FocusSessionRecord(taskKey: nil, blockEventID: nil, title: "Alt",
                                        state: FocusTimerState(start: clock.now, settings: FocusTimerSettings()))
        record.outcomeRaw = "aborted"
        record.focusedSeconds = 12 * 60
        #expect(record.piece == .endedEarly(.two))
        record.outcomeRaw = "completed"
        #expect(record.piece == .completed(.two))
    }

    @Test func relaunch_restoresTheRunningSession() async {
        let first = makeModel()
        await first.start(task: makeTask("Aufgabe", source: .local), block: nil)
        clock.advance(minutes: 31)
        // The app was killed; a new model starts with the same store, the Live Activity still exists.
        let secondActivity = FakeFocusActivity()
        secondActivity.existing = true
        let second = makeModel(activity: secondActivity)
        await second.restore()
        #expect(second.session?.taskKey == "local:Aufgabe")
        #expect(second.snapshot(at: clock.now)?.phase == .work(round: 2))
        #expect(secondActivity.adoptCount == 1)
        #expect(secondActivity.started.isEmpty)
        #expect(secondActivity.latest?.kind == .work && secondActivity.latest?.round == 2)
        #expect(notifications.pending?.fireDate == testNow().addingTimeInterval(55 * 60))
    }

    @Test func relaunch_withoutActivity_startsOne() async {
        let first = makeModel()
        await first.start(task: nil, block: nil)
        let secondActivity = FakeFocusActivity()
        let second = makeModel(activity: secondActivity)
        await second.restore()
        #expect(secondActivity.started.count == 1)
    }

    @Test func relaunch_endsAStaleSession() async {
        let first = makeModel()
        await first.start(task: nil, block: nil)
        clock.advance(minutes: 13 * 60)
        let secondActivity = FakeFocusActivity()
        secondActivity.existing = true
        let second = makeModel(activity: secondActivity)
        await second.restore()
        #expect(second.session == nil)
        #expect(store.runningSession() == nil)
        #expect(secondActivity.endCount == 1)
        #expect(notifications.pending == nil)
        // It ran through (pomodoro finished long ago), so it counts as completed with its 100 focus minutes.
        let ended = store.finishedSessions().first
        #expect(ended?.outcome == .completed)
        #expect(ended?.focusedSeconds == 100 * 60)
    }

    @Test func relaunch_endsAnAbandonedSessionWithoutFocusAsDiscarded() async {
        let first = makeModel(settings: FocusTimerSettings(workMinutes: 120, isPomodoro: false))
        await first.start(task: nil, block: nil)
        await first.pause()
        clock.advance(minutes: 13 * 60)
        let second = makeModel()
        await second.restore()
        #expect(store.finishedSessions().first?.outcome == .discarded)
    }

    @Test func onlyOneSessionRuns() async {
        let model = makeModel()
        await model.start(task: makeTask("Erste", source: .local), block: nil)
        model.isPresented = false
        await model.start(task: makeTask("Zweite", source: .local), block: nil)
        #expect(model.session?.taskKey == "local:Erste")
        #expect(model.isPresented)
        #expect(activity.started.count == 1)
        let count = (try? container.mainContext.fetchCount(FetchDescriptor<FocusSessionRecord>())) ?? 0
        #expect(count == 1)
    }

    @Test func completingTheTaskElsewhere_endsTheSession() async {
        let model = makeModel()
        await model.start(task: makeTask("Aufgabe", source: .local), block: nil)
        clock.advance(minutes: 12)
        await model.didComplete(taskKey: "local:Andere")
        #expect(model.session != nil)
        await model.didComplete(taskKey: "local:Aufgabe")
        #expect(model.session == nil)
        #expect(store.finishedSessions().first?.outcome == .completed)
        #expect(store.finishedSessions().first?.focusedSeconds == 12 * 60)
    }
}
