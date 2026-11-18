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
    /// Notifications for events of deadline calendars (design 2b §11.13), next to those for tasks.
    var deadlineCalendarNotifications: Bool = true
    /// Notifications for tasks of each source; the Reminders app alerts only at the due moment, if at all.
    var githubTaskNotifications: Bool = true
    var reminderTaskNotifications: Bool = true
    var localTaskNotifications: Bool = true
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
    /// The language each notification source was last planned in (`TaskSource` raw values and "events"), as JSON.
    var notificationLanguagesData: Data?
    /// Daily and weekly goals of the "Erfassen" tab (phase 3 design §8.5: placeholders, not a recommendation).
    var goalKilocalories: Int = 2300
    var goalWaterMilliliters: Int = 2000
    /// 0 hides the weekly counter.
    var goalWorkoutsPerWeek: Int = 3
    var proteinGoalEnabled: Bool = false
    var goalProteinGrams: Int = 120
    /// The one-time consent for meal estimates (main design §7). The settings switch binds to it; off means typing values.
    var mealEstimationConsent: Bool = false
    /// The Health card in the tab was dismissed with "Nicht jetzt".
    var healthCardDismissed: Bool = false
    /// Phase 4: the calories/water line in the head of "Planen" (today's day view, from the first entry).
    var showsIntakeInPlan: Bool = true
    /// Phase 4: calories and water in the "Heute" widget; off keeps the values out of the shared snapshot file.
    var widgetShowsNutrition: Bool = true

    /// Voice: microphone in conversations (plan voice-chat, SP7a).
    var voiceInputEnabled: Bool = true
    /// The one-time explanation before the first recording (SP8a) was confirmed.
    var voiceExplained: Bool = false
    /// "auto" follows the iPhone language; otherwise a `VoiceLanguage` raw value.
    var voiceRecognitionLanguage: String = "auto"
    /// `ReadAloudPolicy` raw value; "never" by default (SP3).
    var voiceReadAloud: String = "never"
    /// Chosen system voices per language; nil picks the best installed voice.
    var voiceGermanVoiceID: String? = nil
    var voiceEnglishVoiceID: String? = nil
    /// `AVSpeechUtterance.rate`, 0...1.
    var voiceRate: Double = 0.5
    /// Read action cards aloud when answers are read (SP4a).
    var voiceAnnounceActions: Bool = true
    /// Voice mode (SP5a, Task 12): seconds of pause before sending, seconds of silence before pausing, and
    /// whether the one-time explanation was shown.
    var voiceModeSendDelay: Double = 2
    var voiceModeSilenceLimit: Double = 30
    var voiceModeExplained: Bool = false

    static let maximumPlanningRules = 5

    var aiPlanningRules: [String] {
        get { aiPlanningRulesData.flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? [] }
        set { aiPlanningRulesData = try? JSONEncoder().encode(Array(newValue.prefix(Self.maximumPlanningRules))) }
    }

    /// Key of the deadline calendar events in `notificationLanguages`.
    static let eventsNotificationKey = "events"

    /// The language the notifications of each source ("github", "reminders", "local", "events") were last planned
    /// in. A source without an entry has not been planned yet, or its requests are older than this record.
    var notificationLanguages: [String: VoiceLanguage] {
        get {
            let raw = notificationLanguagesData.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
            return raw.compactMapValues(VoiceLanguage.init(rawValue:))
        }
        set {
            guard newValue != notificationLanguages else { return }
            notificationLanguagesData = try? JSONEncoder().encode(newValue.mapValues(\.rawValue))
        }
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

extension AppSettings {
    /// Task sources whose switch for notifications is on.
    var notifiedTaskSources: Set<TaskSource> {
        var sources: Set<TaskSource> = []
        if githubTaskNotifications { sources.insert(.github) }
        if reminderTaskNotifications { sources.insert(.reminders) }
        if localTaskNotifications { sources.insert(.local) }
        return sources
    }
}
