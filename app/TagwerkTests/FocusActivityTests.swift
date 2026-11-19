import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct FocusActivityTests {
    let container = try! ModelContainerFactory.make(inMemory: true)
    let clock = FocusTestClock()
    let activity = FakeFocusActivity()
    let notifications = FakeFocusNotifications()

    private func makeModel(activity override: FakeFocusActivity? = nil) -> FocusTimerModel {
        FocusTimerModel(store: FocusStore(context: container.mainContext), settings: { FocusTimerSettings() },
                        activity: override ?? activity, notifications: notifications, now: { [clock] in clock.now }, wakesAtPhaseEnd: false)
    }

    @Test func start_startsOneActivity() async {
        let model = makeModel()
        await model.start(task: makeTask("Aufgabe", source: .local), block: nil)
        await model.start(task: makeTask("Andere", source: .local), block: nil)
        #expect(activity.started.count == 1)
        #expect(activity.started.first?.title == "Aufgabe")
        #expect(activity.started.first?.isPomodoro == true)
        #expect(activity.started.first?.rounds == 4)
    }

    @Test func restore_adoptsTheExistingActivity() async {
        await makeModel().start(task: nil, block: nil)
        let survivor = FakeFocusActivity()
        survivor.existing = true
        let restarted = makeModel(activity: survivor)
        await restarted.restore()
        #expect(survivor.started.isEmpty)
        #expect(survivor.adoptCount == 1)
        #expect(survivor.isActive)
    }

    @Test func phaseChange_updatesTheContentState() async {
        let model = makeModel()
        await model.start(task: nil, block: nil)
        #expect(activity.latest?.kind == .work)
        clock.advance(minutes: 26)
        await model.refresh()
        #expect(activity.latest?.kind == .shortBreak)
        #expect(activity.latest?.phaseEnd == testNow().addingTimeInterval(30 * 60))
        clock.advance(minutes: 5)
        await model.refresh()
        #expect(activity.latest?.kind == .work && activity.latest?.round == 2)
    }

    @Test func end_endsTheActivityImmediately() async {
        let model = makeModel()
        await model.start(task: nil, block: nil)
        clock.advance(minutes: 3)
        await model.stop()
        #expect(activity.endCount == 1)
        #expect(!activity.isActive)
    }

    @Test func intentHandler_routesToTheModel() async {
        let model = makeModel()
        await model.start(task: nil, block: nil)
        model.installIntentHandler()
        // Read at once: other tests may install their own handler once this one suspends.
        let handler = FocusActionBridge.handler
        await handler?(.togglePause)
        #expect(model.snapshot(at: clock.now)?.isPaused == true)
        await handler?(.togglePause)
        #expect(model.snapshot(at: clock.now)?.isPaused == false)
    }

    @Test func contentState_mapsPhaseAndTimes() {
        let end = testNow().addingTimeInterval(600)
        let content = FocusActivityContent(title: "T", isPomodoro: true, kind: .shortBreak, round: 2, rounds: 4, phaseEnd: end, pausedRemaining: nil)
        let state = FocusActivityController.state(for: content)
        #expect(state.kind == .shortBreak && state.round == 2 && state.rounds == 4 && state.phaseEnd == end)
    }

    @Test func link_opensTheSheetOnlyWhileRunning() async {
        let model = makeModel()
        #expect(model.open(url: FocusLink.url))
        #expect(!model.isPresented)
        #expect(!model.open(url: URL(string: "tagwerk://capture")!))
        await model.start(task: nil, block: nil)
        model.isPresented = false
        #expect(model.open(url: FocusLink.url))
        #expect(model.isPresented)
    }
}
