import Testing
@testable import TagwerkCore

struct NotificationBudgetTests {
    @Test func budget_sumStaysWithinSystemLimit() {
        #expect(NotificationBudget.allocated <= NotificationBudget.system)
        #expect(NotificationBudget.system == 64)
    }

    @Test func budget_assignsTheAgreedPlaces() {
        #expect(NotificationBudget.tasksAndDeadlines == 46)
        #expect(NotificationBudget.routines == 14)
        #expect(NotificationBudget.focusTimer == 1)
        #expect(NotificationBudget.reserve == 3)
    }

    @Test func allocated_isExactlyTheSystemLimit() {
        #expect(NotificationBudget.allocated == NotificationBudget.system)
    }

    @Test func routineBudget_matchesTheScheduleLimits() {
        #expect(NotificationBudget.routines == RoutineSchedule.maximumRoutineNotifications)
        #expect(RoutineSchedule.maximumRoutineNotifications == RoutineSchedule.maximumEveningNotifications + 2)
        #expect(RoutineSchedule.maximumEveningNotifications == RoutineSchedule.maximumReminders * RoutineSchedule.eveningHorizonDays)
    }

    @Test func rules_defaultLimitIsTheTaskBudget() {
        #expect(NotificationRules(leadTimeMinutes: 60, includesDeadlineCalendars: true).limit == NotificationBudget.tasksAndDeadlines)
    }
}
