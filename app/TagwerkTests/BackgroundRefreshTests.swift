import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

struct BackgroundRefreshConfigTests {
    @Test func infoPlist_containsRefreshIdentifierAndFetchMode() {
        let identifiers = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String]
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        #expect(identifiers?.contains(BackgroundRefresh.identifier) == true)
        #expect(modes?.contains("fetch") == true)
    }
}

@MainActor
struct BackgroundRefreshTests {
    let container: ModelContainer
    let settings: AppSettings
    let center = FakeNotificationCenter()
    let local = FakeTaskProvider(source: .local)
    let github = FakeTaskProvider(source: .github)

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        settings = try AppSettings.current(in: container.mainContext)
    }

    private func scheduler(_ list: TaskListModel) -> NotificationScheduler {
        NotificationScheduler(center: center, taskList: list, deadlineEvents: { _, _ in [] }, settings: settings,
                              now: { testNow() }, calendar: testCalendar())
    }

    @Test func run_submitsFirstThenLoadsAndReschedules() async {
        local.tasks = [makeTask("A", source: .local, due: DueDate(year: 2026, month: 11, day: 20))]
        let list = TaskListModel(providers: [local])
        let notifications = scheduler(list)
        var steps: [String] = []
        let refresh = BackgroundRefresh(
            prepare: { steps.append("prepare"); return false },
            reload: { steps.append("reload"); await list.reload() },
            reschedule: { steps.append("reschedule"); await notifications.reschedule() },
            submit: { date in steps.append("submit \(Int(date.timeIntervalSince(testNow())))") },
            now: { testNow() })
        await refresh.run()
        #expect(steps == ["submit 7200", "prepare", "reload", "reschedule"])
        #expect(center.pendingIDs == ["tagwerk.task.local:A"])
    }

    @Test func run_preparedSourceLoadsOnce() async {
        let list = TaskListModel(providers: [local])
        var reloads = 0
        let refresh = BackgroundRefresh(
            prepare: {
                // Registering GitHub loads all sources already.
                await list.register(github)
                return true
            },
            reload: { reloads += 1 },
            reschedule: {}, submit: { _ in }, now: { testNow() })
        await refresh.run()
        #expect(reloads == 0)
        #expect(github.openTasksCalls == 1)
        #expect(local.openTasksCalls == 1)
    }

    @Test func run_withoutGitHubProvider_keepsGitHubNotifications() async {
        center.seed("tagwerk.task.github:Issue", fireDate: testNow().addingTimeInterval(86_400))
        let list = TaskListModel(providers: [local])
        let notifications = scheduler(list)
        let refresh = BackgroundRefresh(prepare: { false }, reload: { await list.reload() },
                                        reschedule: { await notifications.reschedule() }, submit: { _ in },
                                        now: { testNow() })
        await refresh.run()
        #expect(center.pendingIDs.contains("tagwerk.task.github:Issue"))
    }

    @Test func run_slowLoad_reschedulesAfterBudget() async {
        let gate = Gate()
        github.gate = gate
        github.tasks = [makeTask("Issue", source: .github, due: DueDate(year: 2026, month: 11, day: 20))]
        local.tasks = [makeTask("A", source: .local, due: DueDate(year: 2026, month: 11, day: 20))]
        let list = TaskListModel(providers: [local, github])
        let notifications = scheduler(list)
        let refresh = BackgroundRefresh(prepare: { false }, reload: { await list.reload() },
                                        reschedule: { await notifications.reschedule() }, submit: { _ in },
                                        now: { testNow() }, loadBudget: .milliseconds(200))
        await refresh.run()
        // GitHub is still loading: local is scheduled, GitHub keeps what it had (nothing here).
        #expect(center.pendingIDs == ["tagwerk.task.local:A"])
        gate.open()
    }

    @Test func run_submitFails_stillRefreshes() async {
        var rescheduled = false
        let refresh = BackgroundRefresh(prepare: { false }, reload: {}, reschedule: { rescheduled = true },
                                        submit: { _ in throw CancellationError() }, now: { testNow() })
        await refresh.run()
        #expect(rescheduled)
    }
}
