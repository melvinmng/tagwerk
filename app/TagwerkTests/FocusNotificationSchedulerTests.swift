import Foundation
import Testing
@testable import Tagwerk

@MainActor
struct FocusNotificationSchedulerTests {
    let center = FakeFocusNotificationCenter()

    private func scheduler() -> FocusNotificationScheduler { FocusNotificationScheduler(center: center) }
    private var future: Date { Date.now.addingTimeInterval(600) }

    @Test func workEnd_hasTheFocusTitleAndTheTaskAsBody() async {
        await scheduler().schedule(FocusPhaseNotice(endingKind: .work, fireDate: future, taskTitle: "Bericht", taskKey: "local:Bericht"))
        let request = center.requests[FocusNotificationScheduler.identifier]
        #expect(request?.identifier == "focus.phaseEnd")
        #expect(request?.title == "Fokuszeit vorbei")
        #expect(request?.body == "Bericht")
        #expect(request?.userInfo == ["taskKey": "local:Bericht"])
    }

    @Test func breakEnd_andFreeSession() async {
        await scheduler().schedule(FocusPhaseNotice(endingKind: .shortBreak, fireDate: future, taskTitle: nil, taskKey: nil))
        let request = center.requests[FocusNotificationScheduler.identifier]
        #expect(request?.title == "Pause vorbei")
        #expect(request?.body == "")
        #expect(request?.userInfo.isEmpty == true)
    }

    @Test func scheduling_replacesTheSingleRequest_andCancelRemovesIt() async {
        let scheduler = scheduler()
        await scheduler.schedule(FocusPhaseNotice(endingKind: .work, fireDate: future, taskTitle: nil, taskKey: nil))
        await scheduler.schedule(FocusPhaseNotice(endingKind: .longBreak, fireDate: future, taskTitle: nil, taskKey: nil))
        #expect(center.requests.count == 1)
        await scheduler.cancel()
        #expect(center.requests.isEmpty)
    }

    @Test func aPastDate_schedulesNothing() async {
        await scheduler().schedule(FocusPhaseNotice(endingKind: .work, fireDate: .now.addingTimeInterval(-5), taskTitle: nil, taskKey: nil))
        #expect(center.requests.isEmpty)
    }
}
