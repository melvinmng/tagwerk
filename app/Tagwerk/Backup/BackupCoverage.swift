import Foundation

/// Every model of the schema is either in the backup (it has a `BackupEntity` value) or named here with the reason it is not. The
/// completeness test compares both lists with `ModelContainerFactory.schema`, so a new model cannot be forgotten.
enum BackupCoverage {
    /// Models left out on purpose, with the reason.
    static let excluded: [String: String] = [
        "CachedGitHubIssue": "Cache of GitHub issues; loaded again after the next sync.",
        "CachedGitHubCatalog": "Cache of the GitHub projects and repositories; loaded again after the next sync.",
        "GitHubSyncState": "Time of the last GitHub sync; belongs to the cache.",
        "PlanSuggestionRecord": "Open suggestions of the AI planning; short-lived and re-created on request.",
        "PendingHealthDeletion": "Open deletions in Health; tied to this device's Health store.",
        "FocusSessionRecord": "Focus timer sessions and the collection; not part of the first backup version of the focus timer (open question, plan P3).",
        "EffortSampleRecord": "Measured effort samples; they build up again with use and stay on this device (plan P3).",
        "ChatThreadRecord": "The chat history with the assistant; not part of the backup by design (open question in the plan).",
    ]
}
