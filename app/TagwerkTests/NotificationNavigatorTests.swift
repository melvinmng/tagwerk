import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct NotificationNavigatorTests {
    let local = FakeTaskProvider(source: .local)
    let github = FakeTaskProvider(source: .github)

    @Test func payload_roundTrip() {
        let task = PlannedNotification.Target.task(TaskID(source: .github, rawValue: "I_1"))
        let event = PlannedNotification.Target.event(id: "abc", day: PlanDay(year: 2026, month: 11, day: 20))
        #expect(NotificationPayload.target(from: NotificationPayload.userInfo(for: task)) == task)
        #expect(NotificationPayload.target(from: NotificationPayload.userInfo(for: event)) == event)
        #expect(NotificationPayload.target(from: ["foreign": "x"]) == nil)
    }

    @Test func taskTarget_selectsTaskAndKeepsFilter() async {
        local.tasks = [makeTask("A", source: .local, due: nil)]
        let list = TaskListModel(providers: [local])
        await list.reload()
        let navigator = NotificationNavigator()
        navigator.receive(NotificationPayload.userInfo(for: .task(TaskID(source: .local, rawValue: "A"))))
        #expect(navigator.takeRoute(taskList: list) == .task(TaskID(source: .local, rawValue: "A")))
        #expect(navigator.takeRoute(taskList: list) == nil)
    }

    @Test func taskTarget_hiddenByFilter_resetsFilterToAll() async {
        local.tasks = [makeTask("A", source: .local, due: nil)]
        let list = TaskListModel(providers: [local, github])
        await list.reload()
        list.filter = .github
        let navigator = NotificationNavigator()
        navigator.receive(NotificationPayload.userInfo(for: .task(TaskID(source: .local, rawValue: "A"))))
        _ = navigator.takeRoute(taskList: list)
        #expect(list.filter == .all)
    }

    @Test func taskTarget_gone_showsTasksTabOnly() async {
        let list = TaskListModel(providers: [local])
        await list.reload()
        let navigator = NotificationNavigator()
        navigator.receive(NotificationPayload.userInfo(for: .task(TaskID(source: .local, rawValue: "weg"))))
        #expect(navigator.takeRoute(taskList: list) == .tasksTab)
    }

    @Test func targetBeforeLoad_appliedAfterLoad() async {
        github.tasks = [makeTask("Issue", source: .github, due: nil)]
        let list = TaskListModel(providers: [github])
        let navigator = NotificationNavigator()
        navigator.receive(NotificationPayload.userInfo(for: .task(TaskID(source: .github, rawValue: "Issue"))))
        // GitHub has not loaded yet: wait instead of giving up.
        #expect(navigator.takeRoute(taskList: list) == nil)
        #expect(navigator.hasPendingTarget)
        await list.reload()
        #expect(navigator.takeRoute(taskList: list) == .task(TaskID(source: .github, rawValue: "Issue")))
    }

    @Test func eventTarget_opensDay() async {
        let list = TaskListModel(providers: [])
        let navigator = NotificationNavigator()
        let day = PlanDay(year: 2026, month: 11, day: 20)
        navigator.receive(NotificationPayload.userInfo(for: .event(id: "e", day: day)))
        #expect(navigator.takeRoute(taskList: list) == .day(day))
    }
}
