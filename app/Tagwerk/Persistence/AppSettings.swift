import Foundation
import SwiftData
import TagwerkCore

/// User preferences, stored as a single SwiftData object.
/// Schema rule: later attributes must be optional or have a default value.
@Model
final class AppSettings {
    var workdayStartMinutes: Int = 540
    var workdayEndMinutes: Int = 1080
    var lunchStartMinutes: Int = 720
    var lunchDurationMinutes: Int = 60
    var bufferMinutes: Int = 10
    var leadTimeMinutes: Int = 120
    /// `nil` means the default selection (see `CalendarSelection.defaultSelected`).
    var selectedCalendarIDs: [String]? = nil
    /// `nil` means all reminder lists.
    var selectedReminderListIDs: [String]? = nil
    var setupCompleted: Bool = false
    /// `nil` means the default project selection (projects with assigned open issues).
    var selectedProjectIDs: [String]? = nil
    /// JSON of `WeekSchedule`; `nil` means the standard week (Mon–Fri 09:00–18:00).
    var weekScheduleData: Data? = nil
    /// Calendar Tagwerk writes time blocks into.
    var planCalendarID: String? = nil
    /// Calendars whose events count as important deadlines.
    var deadlineCalendarIDs: [String]? = nil
    /// Duration counted for tasks without effort.
    var defaultTaskMinutes: Int = 30
    /// Shows identical events from several calendars as one row (design §13.11).
    var mergeDuplicateEvents: Bool = true
    /// Day timeline as rows with free stretches ("list") or as a to-scale hour grid ("grid"), design §13.4.
    var dayTimelineStyle: String = "list"
    /// The day opens in the row list instead of the hour grid (grid is the default, design §13.15 S1).
    var prefersTimelineList: Bool = false
    /// ChatGPT model for all AI features; `nil` means "Automatisch" (the first model of the list).
    var aiModelSlug: String? = nil
    /// Last model list from ChatGPT (JSON of `[AIModel]`), kept to avoid loading it on every call.
    var aiModelsData: Data? = nil
    var aiModelsFetchedAt: Date? = nil
    /// Reasoning effort for all AI calls; `nil` means the model's own default ("Automatisch").
    var aiReasoningEffort: String? = nil
    /// "Vorarbeiten, wenn Luft ist": AI plans may pull in tasks of the next days.
    var aiWorkAhead: Bool = true
    /// "Längere Tage vorschlagen": `AIPlanner.LongerDays` raw value.
    var aiLongerDays: String = "forDeadlines"
    /// "Planungsvorgaben" (mockup VR1) as JSON: at most five short sentences.
    var aiPlanningRulesData: Data?

    static let maximumPlanningRules = 5

    var aiPlanningRules: [String] {
        get { aiPlanningRulesData.flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? [] }
        set { aiPlanningRulesData = try? JSONEncoder().encode(Array(newValue.prefix(Self.maximumPlanningRules))) }
    }

    var weekSchedule: WeekSchedule {
        get { weekScheduleData.flatMap { try? JSONDecoder().decode(WeekSchedule.self, from: $0) } ?? .standard }
        set { weekScheduleData = try? JSONEncoder().encode(newValue) }
    }

    init() {}

    /// Returns the single settings object, creating it on first access.
    @MainActor
    static func current(in context: ModelContext) throws -> AppSettings {
        if let existing = try context.fetch(FetchDescriptor<AppSettings>()).first {
            return existing
        }
        let settings = AppSettings()
        context.insert(settings)
        try context.save()
        return settings
    }
}
