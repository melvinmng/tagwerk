import Testing
@testable import TagwerkCore

struct NotificationBudgetTests {
    @Test func budget_sumStaysWithinSystemLimit() {
        #expect(NotificationBudget.allocated <= NotificationBudget.system)
        #expect(NotificationBudget.system == 64)
    }

    @Test func budget_assignsTheAgreedPlaces() {
        #expect(NotificationBudget.tasksAndDeadlines == 50)
        #expect(NotificationBudget.routines == 6)
        #expect(NotificationBudget.focusTimer == 1)
        #expect(NotificationBudget.reserve == 7)
    }

    @Test func rules_defaultLimitIsTheTaskBudget() {
        #expect(NotificationRules(leadTimeMinutes: 60, includesDeadlineCalendars: true).limit == NotificationBudget.tasksAndDeadlines)
    }
}
