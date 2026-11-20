import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
private final class FakeControlReloader: ControlReloading {
    private(set) var reloadedKinds: [String] = []
    func reloadControls(ofKind kind: String) { reloadedKinds.append(kind) }
}

@MainActor
struct FocusControlStateTests {
    let container = try! ModelContainerFactory.make(inMemory: true)
    let clock = FocusTestClock()
    let activity = FakeFocusActivity()
    let notifications = FakeFocusNotifications()
    private let reloader = FakeControlReloader()
    private let state: ControlState

    init() {
        let suite = "test.focus.\(UUID().uuidString)"
        state = ControlState(defaults: UserDefaults(suiteName: suite)!)
    }

    private func makeModel(activity override: FakeFocusActivity? = nil) -> FocusTimerModel {
        FocusTimerModel(store: FocusStore(context: container.mainContext), settings: { FocusTimerSettings() },
                        activity: override ?? activity, notifications: notifications, now: { [clock] in clock.now },
                        wakesAtPhaseEnd: false, controlState: state, controlReloader: reloader)
    }

    @Test func writesRunningOnStart() async {
        let model = makeModel()
        await model.start(task: nil, block: nil)
        #expect(state.isFocusOn(at: clock.now))
        #expect(state.isFocusOn(at: clock.now.addingTimeInterval(129 * 60)))
        // 4 x 25 min work and the breaks between: the whole session ends after 130 minutes.
        #expect(state.isFocusOn(at: clock.now.addingTimeInterval(131 * 60)) == false)
    }

    @Test func pausing_keepsItOn_withoutAnEnd() async {
        let model = makeModel()
        await model.start(task: nil, block: nil)
        await model.pause()
        #expect(state.isFocusOn(at: clock.now.addingTimeInterval(86_400)))
    }

    @Test func writesRunningAndClearsOnFinish() async {
        let model = makeModel()
        await model.start(task: nil, block: nil)
        clock.advance(minutes: 3)
        await model.stop()
        #expect(state.isFocusOn(at: clock.now) == false)
    }

    @Test func completingFromTheLiveActivity_clearsIt() async {
        let model = makeModel()
        await model.start(task: makeTask("Aufgabe", source: .local), block: nil)
        await model.handle(.complete)
        #expect(state.isFocusOn(at: clock.now) == false)
    }

    @Test func aSessionThatRanOutWhileAsleep_isOffWithoutTheAppRunning() async {
        let model = makeModel()
        await model.start(task: nil, block: nil)
        // Nothing runs while the app sleeps; the control decides by the clock.
        #expect(state.isFocusOn(at: clock.now.addingTimeInterval(3 * 3600)) == false)
    }

    @Test func finishedSessionWaitingForAChoice_countsAsNotRunning() async {
        let model = makeModel()
        await model.start(task: nil, block: nil)
        clock.advance(minutes: 131)
        await model.refresh()
        #expect(model.snapshot(at: clock.now)?.phase == .finished)
        #expect(state.isFocusOn(at: clock.now) == false)
    }

    @Test func restoredSession_writesRunning() async {
        await makeModel().start(task: nil, block: nil)
        state.writeFocus(isRunning: false, endsAt: nil)  // e.g. the defaults were cleared
        clock.advance(minutes: 10)
        let survivor = FakeFocusActivity()
        survivor.existing = true
        await makeModel(activity: survivor).restore()
        #expect(state.isFocusOn(at: clock.now))
    }

    @Test func restoreWithNoSession_clearsAStaleRunningState() async {
        state.writeFocus(isRunning: true, endsAt: nil)
        await makeModel().restore()
        #expect(state.isFocusOn(at: clock.now) == false)
    }

    @Test func reloadsTheFocusControl_onlyWhenTheStateChanged() async {
        let model = makeModel()
        await model.start(task: nil, block: nil)
        #expect(reloader.reloadedKinds == [ControlKind.focus])
        await model.refresh()  // same state again
        #expect(reloader.reloadedKinds == [ControlKind.focus])
        await model.stop()
        #expect(reloader.reloadedKinds == [ControlKind.focus, ControlKind.focus])
    }

    // MARK: The toggle itself

    @Test func setRunningTrue_startsAFreeSession_withoutOpeningTheSheet() async {
        let model = makeModel()
        #expect(await model.setRunning(true))
        #expect(model.isRunning)
        #expect(model.session?.taskKey == nil && model.session?.title == "")
        #expect(model.isPresented == false)
        #expect(activity.started.count == 1)
    }

    @Test func setRunningTrue_whileRunning_changesNothing() async {
        let model = makeModel()
        await model.start(task: makeTask("Aufgabe", source: .local), block: nil)
        let id = model.session?.id
        #expect(await model.setRunning(true) == false)
        #expect(model.session?.id == id)
        #expect(activity.started.count == 1)
    }

    @Test func setRunningFalse_endsTheSession() async {
        let model = makeModel()
        await model.start(task: nil, block: nil)
        clock.advance(minutes: 5)
        #expect(await model.setRunning(false))
        #expect(model.isRunning == false)
        #expect(activity.endCount == 1)
    }

    @Test func setRunningFalse_whenIdle_changesNothing() async {
        #expect(await makeModel().setRunning(false) == false)
    }

    @Test func setRunningTrue_afterABackgroundLaunch_takesOverTheStoredSession() async {
        await makeModel().start(task: nil, block: nil)
        clock.advance(minutes: 10)
        let survivor = FakeFocusActivity()
        survivor.existing = true
        let restarted = makeModel(activity: survivor)
        // Nothing called `restore()` yet: no second session may appear next to the stored one.
        #expect(await restarted.setRunning(true) == false)
        #expect(FocusStore(context: container.mainContext).openSessions().count == 1)
    }

    @Test func setRunningFalse_afterABackgroundLaunch_endsTheStoredSession() async {
        await makeModel().start(task: nil, block: nil)
        clock.advance(minutes: 10)
        let survivor = FakeFocusActivity()
        survivor.existing = true
        let restarted = makeModel(activity: survivor)
        #expect(await restarted.setRunning(false))
        #expect(FocusStore(context: container.mainContext).openSessions().isEmpty)
        #expect(survivor.endCount == 1)
    }

    @Test func setRunningTrue_overAFinishedSession_startsANewOneAndCompletesNoTask() async {
        let model = makeModel()
        var completed: [String] = []
        model.completeTask = { completed.append($0) }
        await model.start(task: makeTask("Aufgabe", source: .local), block: nil)
        clock.advance(minutes: 131)
        await model.refresh()
        #expect(await model.setRunning(true))
        #expect(model.isRunning)
        #expect(model.snapshot(at: clock.now)?.phase != .finished)
        #expect(completed.isEmpty)
        #expect(model.session?.taskKey == nil)
    }
}
