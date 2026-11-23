import Testing
@testable import TagwerkCore

struct NotificationBudgetTests {
    @Test func budget_sumStaysWithinSystemLimit() {
        #expect(NotificationBudget.allocated <= NotificationBudget.system)
        #expect(NotificationBudget.system == 64)
    }

    @Test func budget_assignsTheAgreedPlaces() {
        #expect(NotificationBudget.tasksAndDeadlines == 44)
        #expect(NotificationBudget.routines == 17)
        #expect(NotificationBudget.focusTimer == 1)
        #expect(NotificationBudget.reserve == 2)
    }

    @Test func allocated_isExactlyTheSystemLimit() {
        #expect(NotificationBudget.allocated == NotificationBudget.system)
        // 44 + 17 + 1 + 2 (BS7): Bible Study takes its three places from the tasks (2) and the reserve (1).
        #expect(NotificationBudget.tasksAndDeadlines + NotificationBudget.routines + NotificationBudget.focusTimer + NotificationBudget.reserve == 64)
    }

    @Test func routineBudget_matchesTheScheduleLimits() {
        #expect(NotificationBudget.routines == RoutineSchedule.maximumRoutineNotifications)
        #expect(RoutineSchedule.maximumRoutineNotifications == RoutineSchedule.maximumEveningNotifications + 2 + RoutineSchedule.bibleStudyHorizonDays)
        #expect(RoutineSchedule.maximumEveningNotifications == RoutineSchedule.maximumReminders * RoutineSchedule.eveningHorizonDays)
    }

    @Test func rules_defaultLimitIsTheTaskBudget() {
        #expect(NotificationRules(leadTimeMinutes: 60, includesDeadlineCalendars: true).limit == NotificationBudget.tasksAndDeadlines)
    }
}
