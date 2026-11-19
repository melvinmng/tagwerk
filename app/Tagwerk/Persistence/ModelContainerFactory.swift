import SwiftData

/// Builds the app's SwiftData container.
enum ModelContainerFactory {
    static let schema = Schema([LocalTask.self, LocalOccurrenceCompletion.self, AppSettings.self, CachedGitHubIssue.self, GitHubSyncState.self, CachedGitHubCatalog.self,
                                     DayAssignment.self, DayOverrideRecord.self, ReminderEstimateRecord.self, EventTaskLink.self,
                                     RecurringEffortValue.self, RecurringEffortOverride.self, RecurringOccurrenceDone.self,
                                     DayLunchRecord.self, EventAvailabilityMark.self, EventMergeDecision.self,
                                     PlanSuggestionRecord.self, ChatThreadRecord.self,
                                     EventDeadlineMark.self, DeadlineEventLink.self, DeadlineSuggestionDismissal.self,
                                     MealRecord.self, DrinkRecord.self, WorkoutRecord.self, PendingHealthDeletion.self,
                                     ShoppingCategory.self, ShoppingAssignment.self, NoteRecord.self, NoteFolderRecord.self,
                                     HabitRecord.self, HabitCheckRecord.self,
                                     RoutineDayRecord.self, EveningChecklistItemRecord.self, FocusMarkRecord.self,
                                     WeekReflectionRecord.self])

    static func make(inMemory: Bool) throws -> ModelContainer {
        try ModelContainer(for: schema, configurations: inMemory ? ModelConfiguration(isStoredInMemoryOnly: true)
                                                                 : persistentConfiguration())
    }

    /// The store at its place before phase 4. `groupContainer: .none` is required: with the App Group entitlement the
    /// default (`.automatic`) would open a new, empty store in the group container and the old data would seem lost.
    static func persistentConfiguration() -> ModelConfiguration {
        ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, groupContainer: .none)
    }
}
