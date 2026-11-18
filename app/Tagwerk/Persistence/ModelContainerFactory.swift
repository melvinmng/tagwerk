import SwiftData

/// Builds the app's SwiftData container.
enum ModelContainerFactory {
    static let schema = Schema([LocalTask.self, AppSettings.self, CachedGitHubIssue.self, GitHubSyncState.self, CachedGitHubCatalog.self,
                                     DayAssignment.self, DayOverrideRecord.self, ReminderEstimateRecord.self, EventTaskLink.self,
                                     RecurringEffortValue.self, RecurringEffortOverride.self, RecurringOccurrenceDone.self,
                                     DayLunchRecord.self, EventAvailabilityMark.self, EventMergeDecision.self,
                                     PlanSuggestionRecord.self, ChatThreadRecord.self,
                                     MealRecord.self, DrinkRecord.self, WorkoutRecord.self, PendingHealthDeletion.self])

    static func make(inMemory: Bool) throws -> ModelContainer {
        try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory))
    }
}
