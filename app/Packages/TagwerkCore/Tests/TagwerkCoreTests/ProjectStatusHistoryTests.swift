import Foundation
import Testing
@testable import TagwerkCore

struct ProjectStatusHistoryTests {
    let calendar = makeCalendar()
    let project = "gitHubProject:PVT_1"
    /// Wednesday, 25 Nov 2026, 10:00; four weeks start on Monday, 2 Nov.
    var now: Date { instant(2026, 11, 25, 10, 0, in: calendar) }
    var range: ProjectRange { ProjectProgress.range(of: .fourWeeks, now: now, calendar: calendar) }

    private func at(_ month: Int, _ day: Int, _ hour: Int = 12) -> Date { instant(2026, month, day, hour, 0, in: calendar) }

    private func entry(_ kind: TaskActivityKind, _ task: String, at date: Date, from: String? = nil, to: String? = nil,
                       projects: [String]? = nil) -> TaskActivityEntry {
        TaskActivityEntry(kind: kind, taskKey: task, title: task, from: from, to: to, projectKeys: projects ?? [project], occurredAt: date)
    }

    private func history(_ entries: [TaskActivityEntry], closedAt: [String: Date] = [:], range override: ProjectRange? = nil) -> ProjectStatusHistory {
        ProjectStatusHistoryRules.make(entries: entries, projectKey: project, range: override ?? range, closedAt: closedAt, now: now)
    }

    private func hours(_ history: ProjectStatusHistory, _ status: String) -> Double? {
        history.durations.first { $0.status == status }.map { $0.seconds / 3600 }
    }

    // MARK: Time per status

    @Test func durations_runFromAChangeToTheNext() {
        let result = history([
            entry(.statusChanged, "a", at: at(11, 10, 8), from: "Ready", to: "In progress"),
            entry(.statusChanged, "a", at: at(11, 10, 12), from: "In progress", to: "Review"),
            entry(.statusChanged, "a", at: at(11, 11, 12), from: "Review", to: "Done"),
        ], closedAt: ["a": at(11, 11, 12)])
        #expect(hours(result, "In progress") == 4)
        #expect(hours(result, "Review") == 24)
        #expect(hours(result, "Done") == nil, "a closed item spends no time in Done")
        #expect(result.durations.first?.status == "Review", "longest first")
    }

    @Test func durations_theTimeBeforeTheFirstLoggedChangeIsUnknown() {
        let result = history([entry(.statusChanged, "a", at: at(11, 20, 10), from: "Ready", to: "In progress")])
        #expect(hours(result, "Ready") == nil)
        // From the change until now (25 Nov 10:00) the item is still open.
        #expect(hours(result, "In progress") == 120)
    }

    @Test func durations_endAtTheCompletionLoggedInTagwerk() {
        let result = history([
            entry(.statusChanged, "a", at: at(11, 10, 8), from: "Ready", to: "In progress"),
            entry(.completed, "a", at: at(11, 10, 10)),
        ])
        #expect(hours(result, "In progress") == 2)
    }

    @Test func durations_endAtAClosingOutsideTagwerk() {
        let result = history([entry(.statusChanged, "a", at: at(11, 10, 8), from: "Ready", to: "In progress")],
                             closedAt: ["a": at(11, 10, 20)])
        #expect(hours(result, "In progress") == 12)
    }

    @Test func durations_areCutToThePeriod() {
        // The change lies before the period (Monday 2 Nov 00:00); only the part inside counts.
        let result = history([entry(.statusChanged, "a", at: at(10, 30, 0), from: "Ready", to: "In progress"),
                              entry(.statusChanged, "a", at: at(11, 3, 0), from: "In progress", to: "Review")])
        #expect(hours(result, "In progress") == 24)
    }

    @Test func durations_countTasksPerStatusAndKeepTasksApart() {
        let result = history([
            entry(.statusChanged, "a", at: at(11, 10, 8), from: "Ready", to: "In progress"),
            entry(.statusChanged, "b", at: at(11, 10, 9), from: "Ready", to: "In progress"),
            entry(.statusChanged, "a", at: at(11, 10, 10), from: "In progress", to: "Review"),
            entry(.statusChanged, "b", at: at(11, 10, 11), from: "In progress", to: "Review"),
        ], closedAt: ["a": at(11, 10, 12), "b": at(11, 10, 12)])
        #expect(hours(result, "In progress") == 4, "2 h of a plus 2 h of b")
        #expect(result.durations.first { $0.status == "In progress" }?.taskCount == 2)
    }

    // MARK: Transitions, reopen, reschedule

    @Test func transitions_countEachMoveMostFrequentFirst() {
        let result = history([
            entry(.statusChanged, "a", at: at(11, 10), from: "Ready", to: "In progress"),
            entry(.statusChanged, "b", at: at(11, 11), from: "Ready", to: "In progress"),
            entry(.statusChanged, "a", at: at(11, 12), from: "In progress", to: "Ready"),
        ])
        #expect(result.statusChanges == 3)
        #expect(result.transitions.map(\.count) == [2, 1])
        #expect(result.transitions.first == ProjectStatusTransition(from: "Ready", to: "In progress", count: 2))
    }

    @Test func reopen_countsEntriesAndTasks() {
        let result = history([entry(.reopened, "a", at: at(11, 10)), entry(.reopened, "a", at: at(11, 12)), entry(.reopened, "b", at: at(11, 13))])
        #expect(result.reopenCount == 3 && result.reopenedTasks == 2)
    }

    @Test func reschedule_separatesDueDateAndPlannedDay() {
        let result = history([
            entry(.rescheduled, "a", at: at(11, 10), from: "2026-11-12", to: "2026-11-20"),
            entry(.replanned, "a", at: at(11, 11), from: "2026-11-12", to: "2026-11-13"),
            entry(.replanned, "b", at: at(11, 12), from: "2026-11-13", to: "2026-11-16"),
        ])
        #expect(result.dueDateChanges == 1 && result.planDayChanges == 2 && result.rescheduleCount == 3)
        #expect(result.rescheduledTasks == 2)
    }

    // MARK: Scope

    @Test func entriesOfOtherProjectsAndOutsideThePeriodAreIgnored() {
        let result = history([
            entry(.reopened, "a", at: at(11, 10), projects: ["local:local"]),
            entry(.reopened, "b", at: at(10, 1)),
            entry(.reopened, "c", at: at(11, 10)),
        ])
        #expect(result.reopenCount == 1)
    }

    @Test func loggedSince_isTheFirstEntryOfTheWholeLog() {
        let result = history([entry(.reopened, "a", at: at(11, 12)), entry(.created, "z", at: at(11, 3), projects: ["local:local"])])
        #expect(result.loggedSince == at(11, 3))
        #expect(history([]).loggedSince == nil)
    }

    @Test func emptyLogGivesAnEmptyHistory() {
        let result = history([])
        #expect(result.isEmpty && result.durations.isEmpty && result.transitions.isEmpty)
    }

    @Test func restingThreshold_isTheNamedConstant() {
        // Stage 3 gives no data to change it (#332): the value stays the one of the decision until real data is evaluated.
        #expect(ProjectProgress.restingAfterDays == 14)
    }
}
