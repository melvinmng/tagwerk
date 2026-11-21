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

    @Test func intentHandler_afterABackgroundLaunch_restoresTheSessionFirst() async {
        await makeModel().start(task: nil, block: nil)
        clock.advance(minutes: 10)
        // The app was started in the background by the button; nothing called `restore()` yet.
        let survivor = FakeFocusActivity()
        survivor.existing = true
        let restarted = makeModel(activity: survivor)
        await restarted.handle(.togglePause)
        #expect(restarted.snapshot(at: clock.now)?.isPaused == true)
        #expect(survivor.adoptCount == 1)
    }

    @Test func contentState_mapsPhaseAndTimes() {
        let end = testNow().addingTimeInterval(600)
        let content = FocusActivityContent(title: "T", isPomodoro: true, kind: .shortBreak, round: 2, rounds: 4, phaseEnd: end, pausedRemaining: nil)
        let state = FocusActivityController.state(for: content)
        #expect(state.kind == .shortBreak && state.round == 2 && state.rounds == 4 && state.phaseEnd == end)
    }

    @Test func link_beforeTheRestore_opensTheSheetOnceTheSessionIsBack() async {
        await makeModel().start(task: nil, block: nil)
        let restarted = makeModel(activity: FakeFocusActivity())
        // Cold launch: the link arrives first, `restore()` follows.
        #expect(restarted.open(url: FocusLink.url))
        #expect(!restarted.isPresented)
        await restarted.restore()
        #expect(restarted.isPresented)
        // Without a session the request is dropped and does not pop up later.
        let empty = makeModel(activity: FakeFocusActivity())
        #expect(empty.open(url: FocusLink.url))
        await empty.restore()
        await empty.start(task: nil, block: nil)
        empty.isPresented = false
        await empty.restore()
        #expect(!empty.isPresented)
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

    // MARK: Live Activity content (FO10b)

    private func content(_ phase: FocusPhase, settings: FocusTimerSettings = FocusTimerSettings(), at date: Date? = nil) -> FocusActivityContent {
        let state = FocusTimerState(start: testNow(), settings: settings)
        let moment = date ?? testNow()
        return FocusActivityContent(title: "T", state: state, snapshot: FocusTimerRules.snapshot(of: state, at: moment))
    }

    @Test func content_carriesPhaseSecondsAndTheNextPhase() {
        let work = content(.work(round: 1))
        #expect(work.phaseSeconds == 25 * 60)
        #expect(work.nextKind == .shortBreak && work.nextPhaseMinutes == 5)
        // During the break the work phase follows.
        let breakContent = content(.shortBreak(round: 1), at: testNow().addingTimeInterval(26 * 60))
        #expect(breakContent.kind == .shortBreak && breakContent.phaseSeconds == 5 * 60)
        #expect(breakContent.nextKind == .work && breakContent.nextPhaseMinutes == 25)
        // The last work round is followed by the long break.
        let last = content(.work(round: 4), at: testNow().addingTimeInterval((3 * 30 + 1) * 60))
        #expect(last.kind == .work && last.round == 4)
        #expect(last.nextKind == .longBreak && last.nextPhaseMinutes == 15)
    }

    @Test func content_lastRound_hasNoNextPhase() {
        // Without Pomodoro the work phase is the whole session.
        let single = content(.work(round: 1), settings: FocusTimerSettings(isPomodoro: false))
        #expect(single.nextKind == nil && single.nextPhaseMinutes == nil)
        // After the long break and when finished nothing follows either.
        let longBreak = content(.longBreak, at: testNow().addingTimeInterval((3 * 30 + 26) * 60))
        #expect(longBreak.kind == .longBreak && longBreak.nextKind == nil)
        let finished = content(.finished, at: testNow().addingTimeInterval(24 * 3600))
        #expect(finished.kind == .finished && finished.nextKind == nil && finished.phaseSeconds == nil)
    }

    @Test func state_carriesTheNewFields() {
        let state = FocusActivityController.state(for: content(.work(round: 1)))
        #expect(state.phaseSeconds == 25 * 60 && state.nextKind == .shortBreak && state.nextPhaseMinutes == 5)
    }

    @Test func decode_withoutNewFields_works() throws {
        // The JSON of a running activity written before the new fields existed.
        let json = """
        {"kind":"work","phaseEnd":786000000,"round":1,"rounds":4}
        """
        let state = try JSONDecoder().decode(FocusActivityAttributes.ContentState.self, from: Data(json.utf8))
        #expect(state.kind == .work && state.round == 1 && state.rounds == 4)
        #expect(state.phaseSeconds == nil && state.nextKind == nil && state.nextPhaseMinutes == nil)
        let attributes = try JSONDecoder().decode(FocusActivityAttributes.self, from: Data(#"{"title":"T","isPomodoro":true}"#.utf8))
        #expect(attributes.hasTask == nil)
    }

    @Test func handle_showCurrent_updatesTheActivity() async {
        let model = makeModel()
        await model.start(task: nil, block: nil)
        // The work phase ended while the activity was stale; the break runs by the timestamps.
        clock.advance(minutes: 26)
        let before = activity.updated.count
        await model.handle(.showCurrent)
        #expect(activity.updated.count > before)
        #expect(activity.latest?.kind == .shortBreak)
        #expect(model.session != nil)
    }

    @Test func handle_everyAction_refreshes() async {
        let model = makeModel()
        await model.start(task: makeTask("Aufgabe", source: .local), block: nil)
        var count = activity.updated.count
        for action in [FocusIntentAction.togglePause, .togglePause, .showCurrent, .keepGoing] {
            await model.handle(action)
            #expect(activity.updated.count > count, "\(action) refreshes the activity")
            count = activity.updated.count
        }
    }
}
