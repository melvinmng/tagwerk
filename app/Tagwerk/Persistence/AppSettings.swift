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
    /// Daily and weekly goals of the "Erfassen" tab (phase 3 design §8.5: placeholders, not a recommendation).
    var goalKilocalories: Int = 2300
    var goalWaterMilliliters: Int = 2000
    /// Former weekly goal as a number of workouts; no longer shown, kept in the schema (attributes are never removed)
    /// and read once by `migrateWorkoutGoalIfNeeded()`.
    var goalWorkoutsPerWeek: Int = 3
    /// Weekly training time goal in minutes; 0 hides the tile. A placeholder like the other goals, not a recommendation.
    var goalWorkoutMinutesPerWeek: Int = 150
    /// Daily step goal; 0 shows the steps without a goal.
    var goalStepsPerDay: Int = 8000
    /// The one-time takeover of the old workout goal ran.
    var workoutGoalMigrated: Bool = false
    var proteinGoalEnabled: Bool = false
    var goalProteinGrams: Int = 120
    /// The one-time takeover of the single goals as the first goal plan ran (`GoalStore.migrateIfNeeded()`).
    var goalPlansMigrated: Bool = false
    /// Share of the active energy that raises the daily budget, in percent: 0, 50, 75 or 100. Half is the default because
    /// wrist devices estimate the active energy rather coarsely (decision BU1b).
    var activityCreditPercent: Int = 50
    /// Counts the nutrition entries of other apps from Health as eaten ("Einträge anderer Apps mitzählen"); off by default
    /// (decision NU5b).
    var countsForeignNutrition: Bool = false
    /// Further nutrients that can be switched on in the meal sheet, the nutrient card and the Health mirror (decision NU1b: fibre and
    /// sugar are always there, saturated fat and salt are optional).
    var saturatedFatEnabled: Bool = false
    var saltEnabled: Bool = false
    /// The three quick-button portions of the tab ("Trinkportionen"), see `DrinkPresets`. Read and set through `drinkPresets`.
    var drinkPreset1Milliliters: Int = 250
    var drinkPreset2Milliliters: Int = 330
    var drinkPreset3Milliliters: Int = 500
    /// The one-time consent for meal estimates (main design §7). The settings switch binds to it; off means typing values.
    var mealEstimationConsent: Bool = false
    /// Phase 5: the reminder list that serves as the shopping list; `nil` means none. Its reminders are not tasks.
    /// Written only through `AppEnvironment.setShoppingList(_:)`, which reloads everything that depends on it.
    var shoppingListID: String? = nil
    /// The card suggesting a shopping list was answered with "Nicht jetzt".
    var shoppingSuggestionDismissed: Bool = false
    /// The built-in shopping categories were created once; deleting them later does not bring them back.
    var shoppingCategoriesSeeded: Bool = false
    /// The one-time consent for "Mit ChatGPT sortieren" and "Artikel übersetzen"; the settings switch binds to it. It only counts
    /// together with `shoppingSortConsentVersion`.
    var shoppingSortConsent: Bool = false
    /// The version of the text the consent was given for: 0 is the text that named sorting only, so a consent given before
    /// translating existed counts again only after the user agreed to the new text.
    var shoppingSortConsentVersion: Int = 0
    /// The one-time consent for "Rezept hinzufügen" (reading a recipe with ChatGPT); the settings switch binds to it.
    var shoppingRecipeConsent: Bool = false
    /// The one-time consent for "Mit ChatGPT zusammenfassen" on a shared mail (#166); the settings switch binds to it.
    var mailSummaryConsent: Bool = false
    /// The assistant may find non-private notes (title and excerpt), read them in full and, in the notes chat, change them
    /// (issue #173, decision D5). One switch for the whole scope; off by default. Journal, Bible Study and Dream Log never count.
    var noteAssistantConsent: Bool = false
    /// The Health card in the tab was dismissed with "Nicht jetzt".
    var healthCardDismissed: Bool = false
    /// Phase 4: the calories/water line in the head of "Planen" (today's day view, from the first entry).
    var showsIntakeInPlan: Bool = true
    /// Phase 4: calories and water in the "Heute" widget; off keeps the values out of the shared snapshot file.
    var widgetShowsNutrition: Bool = true

    /// Phase 7 routines: target bedtime in minutes after midnight (23:00); the evening checklist counts back from it.
    var bedtimeMinutes: Int = 1380
    /// Notifications of the evening checklist; at most four, one per point with a time anchor.
    var eveningRemindersEnabled: Bool = true
    /// The optional reminder to start the day, off by default.
    var morningReminderEnabled: Bool = false
    var morningReminderMinutes: Int = 450
    /// The optional weekly reminder for the weekly planning (#164): off by default, Sunday (1) at 18:00.
    var weekPlanningReminderEnabled: Bool = false
    var weekPlanningReminderWeekday: Int = 1
    var weekPlanningReminderMinutes: Int = 1080
    /// The day (`PlanDay.dayKey`) on which the card "Wochenplanung" in "Planen" was hidden or the planning was finished; the card
    /// stays away for the rest of that day (RO15b). Not part of the backup.
    var weekPlanningCardDismissedDayKey: String? = nil
    /// Where "Bible Study starten" is offered (`BibleStudyOffer` raw value): the evening wrap-up, as before the choice existed.
    var bibleStudyOfferRaw: String = "evening"
    /// The reminder to read the Bible (BS6): off by default. The times with their weekdays are a JSON list of
    /// `BibleStudyReminderTime`.
    var bibleStudyReminderEnabled: Bool = false
    var bibleStudyReminderTimesData: Data? = nil
    /// The notification names the book and the next verse ("Weiter in Römer ab 3,27"); off, it only says "Zeit für Bible Study.".
    var bibleStudyReminderShowsPassage: Bool = true
    /// The day (`PlanDay.dayKey`) on which "Heute nicht" dropped the reminder. Not part of the backup: it only concerns today.
    var bibleStudySkippedDayKey: String? = nil
    /// "Nicht jetzt" on the suggested reminder time (BS8): no suggestion before this moment. Not part of the backup.
    var bibleStudySuggestionSnoozedUntil: Date? = nil
    /// The suggestions (`BibleStudyHabitTime.Suggestion.key`, comma separated) whose card was already shown after a completed
    /// session: the card comes once per new suggestion; the settings page keeps showing it. Not part of the backup.
    var bibleStudySuggestionShownKeys: String? = nil
    /// The one-time upgrade of "Helle Lichter ausmachen" (offset 60) in an untouched five-point list was done. Not part of the
    /// backup: it only keeps a list that the user changed afterwards from being upgraded again.
    var lightsOffsetUpgradeDone: Bool = false
    /// The routine card and the evening line in "Planen".
    var showsRoutinesInPlan: Bool = true
    /// "Notizen an ChatGPT senden": a thought note may be sent, only on a tap on "Vorschläge holen".
    var noteSuggestionConsent: Bool = false

    /// Order of the note lists (`NoteSortOrder` raw value); one setting for all folders.
    var noteSortOrderRaw: String = "modified"
    /// Turns the order of the note lists around ("Älteste zuerst"; for the title order "Z bis A"). One setting for all folders.
    var noteSortAscending: Bool = false
    /// Date groups ("Heute", "Letzte 7 Tage", months) in the note lists; has no effect on the title order.
    var noteGroupsByDate: Bool = true

    /// The lock of the notes (NL1a). "Mit Face ID schützen": locked notes (and, with the next switch, private folders) stay
    /// hidden until the device owner is checked. These three values belong to this device and are not part of a backup.
    var noteLockEnabled: Bool = false
    /// "Private Ordner sperren": journal, Bible Study and Dream Log are protected like locked notes.
    var noteLockPrivateFolders: Bool = false
    /// The explanation before the first lock was shown (`NoteLockIntroSheet`).
    var noteLockExplained: Bool = false

    /// Data backup (#158). "Tagebuch und Bible Study einschließen" applies to "Jetzt sichern" and the automatic backup.
    var backupIncludesPrivateNotes: Bool = true
    var autoBackupEnabled: Bool = false
    /// Security-scoped bookmark of the folder for automatic backups. Tied to this device, so it is not part of a backup.
    var backupFolderBookmark: Data? = nil
    var lastAutoBackupAt: Date? = nil
    /// Why the last automatic backup failed; shown in the settings, blocks nothing.
    var lastBackupError: String? = nil

    /// Quiet hours (plan quiet-hours, #169): task and deadline notifications that fall into the window move to its end.
    var quietHoursEnabled: Bool = false
    /// The window starts at `bedtimeMinutes`; `quietStartMinutes` applies only while this is off.
    var quietHoursStartsAtBedtime: Bool = true
    var quietStartMinutes: Int = 1380
    var quietEndMinutes: Int = 420

    /// JSON of `ReminderDefaults` (plan P4); `nil` means the defaults that behave like the former lead time.
    var reminderDefaultsData: Data? = nil
    /// Focus filter "Mitteilungen zurückhalten" (runtime state, not a preference): set while a Focus with the filter is
    /// active, and the start kept after it ended until the notifications that came due meanwhile were caught up.
    var focusQuietSince: Date? = nil
    var focusQuietCatchUpFrom: Date? = nil
    var focusQuietCatchUpAt: Date? = nil
    /// Upper bound of the catch-up window, see `FocusQuiet.State.catchUpUntil`.
    var focusQuietCatchUpUntil: Date? = nil

    /// Focus timer (plan P3, #161): durations of the phases, the number of rounds and whether breaks are used at all.
    var focusWorkMinutes: Int = 25
    var focusShortBreakMinutes: Int = 5
    var focusLongBreakMinutes: Int = 15
    var focusRounds: Int = 4
    var focusUsesPomodoro: Bool = true
    /// "Dauer beim Start fragen": the start sheet (FO7b) is shown before a session starts.
    var focusAsksDurationAtStart: Bool = true
    /// Minutes of the last choice in the start sheet; `nil` before the first one.
    var focusLastStartMinutes: Int? = nil
    /// "Erfahrungswerte in der Planung nutzen" (#162): the AI planning gets an expected effort per task.
    var effortHistoryInPlanning: Bool = true

    /// Travel time before events with a place (#168). The home address and its coordinates stay on this device; the
    /// address text goes to Apple Maps only, to look up the way, never to ChatGPT.
    var travelTimeEnabled: Bool = true
    var homeAddress: String? = nil
    var homeLatitude: Double? = nil
    var homeLongitude: Double? = nil
    /// `TravelTransport` raw value.
    var travelTransportRaw: String = "automobile"
    /// "Rückweg anzeigen" (PL15c): the way home after the last event and before a long gap; off by default.
    var travelShowsReturn: Bool = false

    /// Voice: microphone in conversations (plan voice-chat, SP7a).
    var voiceInputEnabled: Bool = true
    /// The one-time explanation before the first recording (SP8a) was confirmed.
    var voiceExplained: Bool = false
    /// "auto" follows the iPhone language; otherwise a `VoiceLanguage` raw value.
    var voiceRecognitionLanguage: String = "auto"
    /// The language recipes are created in (#216): "auto" follows the app language, otherwise a `VoiceLanguage` raw value.
    var recipeLanguage: String = "auto"
    /// The language the voice chat answers in (Einstellungen › Sprachen): "spoken" answers in the language the user speaks,
    /// otherwise a `VoiceLanguage` raw value. `nil` until `migrateVoiceAnswerLanguageIfNeeded()` derived it from the former
    /// shared value `voiceRecognitionLanguage`, which is now the dictation language only.
    var voiceAnswerLanguage: String? = nil
    /// The language of new shopping items: "recipes" follows the recipe language, "auto" the app language, otherwise a
    /// `VoiceLanguage` raw value.
    var shoppingLanguage: String = "recipes"
    /// JSON of `[String: String]`: the language last chosen on the dictation switch per place (`DictationPlace`). Stays on
    /// this device and is not part of the backup.
    var dictationPlaceLanguagesData: Data? = nil
    /// The raw value of the language the open shopping items were last translated into, or kept in with "So lassen" (L6). `nil`
    /// before the first run. Stays on this device and is not part of the backup: after a restore the list adopts its current
    /// language and shows no card.
    var shoppingItemsLanguage: String? = nil
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

    /// The Siri tip above the shopping list / the drink buttons was closed or its shortcut ran once (#188 SI3). Hint state of the
    /// device; not part of the backup.
    var siriTipShoppingDone: Bool = false
    var siriTipWaterDone: Bool = false

    /// The focus timer durations as the rules want them (clamped).
    var focusTimerSettings: FocusTimerSettings {
        get {
            FocusTimerSettings(workMinutes: focusWorkMinutes, shortBreakMinutes: focusShortBreakMinutes,
                               longBreakMinutes: focusLongBreakMinutes, rounds: focusRounds, isPomodoro: focusUsesPomodoro)
        }
        set {
            let clamped = newValue.clamped
            focusWorkMinutes = clamped.workMinutes
            focusShortBreakMinutes = clamped.shortBreakMinutes
            focusLongBreakMinutes = clamped.longBreakMinutes
            focusRounds = clamped.rounds
            focusUsesPomodoro = clamped.isPomodoro
        }
    }

    /// The quick-button portions as the rules want them (three values, each inside the range, in the user's order).
    var drinkPresets: [Int] {
        get { DrinkPresets.resolved([drinkPreset1Milliliters, drinkPreset2Milliliters, drinkPreset3Milliliters]) }
        set {
            let resolved = DrinkPresets.resolved(newValue)
            drinkPreset1Milliliters = resolved[0]
            drinkPreset2Milliliters = resolved[1]
            drinkPreset3Milliliters = resolved[2]
        }
    }

    /// The reminder times of Bible Study; an unreadable or missing list is empty.
    var bibleStudyReminderTimes: [BibleStudyReminderTime] {
        get { bibleStudyReminderTimesData.flatMap { try? JSONDecoder().decode([BibleStudyReminderTime].self, from: $0) } ?? [] }
        set { bibleStudyReminderTimesData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }

    var bibleStudyOffer: BibleStudyOffer {
        get { BibleStudyOffer(rawValue: bibleStudyOfferRaw) ?? .evening }
        set { bibleStudyOfferRaw = newValue.rawValue }
    }

    var noteSortOrder: NoteSortOrder {
        get { NoteSortOrder(rawValue: noteSortOrderRaw) ?? .modified }
        set { noteSortOrderRaw = newValue.rawValue }
    }

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

extension AppSettings {
    /// One-time takeover when the workout goal moved from a count to minutes: a switched-off goal (0) stays off;
    /// any other count keeps the minute default. Runs once, also on a fresh install, so it never touches a later choice.
    func migrateWorkoutGoalIfNeeded() {
        guard !workoutGoalMigrated else { return }
        if goalWorkoutsPerWeek == 0 { goalWorkoutMinutesPerWeek = 0 }
        workoutGoalMigrated = true
    }

    /// The stored language settings as the rules read them.
    var contentLanguages: ContentLanguages {
        ContentLanguages(dictation: voiceRecognitionLanguage, answer: voiceAnswerLanguage, recipe: recipeLanguage,
                         shopping: shoppingLanguage, places: ContentLanguages.decodePlaces(dictationPlaceLanguagesData))
    }

    /// The dictation language at `place`: the language remembered there, else the dictation setting (shopping: its own language).
    func dictationLanguage(at place: DictationPlace) -> VoiceLanguage {
        contentLanguages.dictationLanguage(at: place)
    }

    /// Remembers the language the user switched to while dictating at `place` (SP4b). The switch applies at this place only and
    /// goes away again when it is switched back to the dictation setting. The shopping list has no entry of its own: its switch
    /// is the shopping language (SP5b).
    func rememberDictationLanguage(_ language: VoiceLanguage, at place: DictationPlace) {
        if place == .shopping {
            shoppingLanguage = language.rawValue
        } else {
            dictationPlaceLanguagesData = ContentLanguages.encodePlaces(contentLanguages.places(switching: place, to: language))
        }
    }

    /// The text of the consent for sorting and translating shopping items that is current now (version 1 names translating too).
    static let currentShoppingSortConsentVersion = 1

    /// Whether the user agreed to the current text of the consent; a consent given for an earlier text asks again once.
    var hasShoppingSortConsent: Bool {
        get { shoppingSortConsent && shoppingSortConsentVersion >= Self.currentShoppingSortConsentVersion }
        set {
            shoppingSortConsent = newValue
            shoppingSortConsentVersion = newValue ? Self.currentShoppingSortConsentVersion : 0
        }
    }

    /// The tap on the language mark of the shopping list (SP5b): the other language, stored as a fixed value. From "Wie Rezepte"
    /// or "Wie die App" it also becomes fixed, so a later change of the recipe or app language does not switch the list silently.
    func toggleShoppingLanguage() {
        shoppingLanguage = (contentLanguages.shoppingLanguage() == .german ? VoiceLanguage.english : .german).rawValue
    }

    /// One-time takeover when the voice chat answer language became its own setting: it starts from the former shared value
    /// `voiceRecognitionLanguage`, so the app behaves as before the update. Writes only while the answer language has never
    /// been set, so a later change of the dictation language leaves the answer language alone.
    func migrateVoiceAnswerLanguageIfNeeded() {
        guard voiceAnswerLanguage == nil else { return }
        voiceAnswerLanguage = ContentLanguages.migratedAnswer(fromDictation: voiceRecognitionLanguage)
    }

    /// The quiet hours the settings describe; `nil` when switched off or empty.
    var quietHours: QuietHours? {
        QuietHours.resolved(enabled: quietHoursEnabled, startsAtBedtime: quietHoursStartsAtBedtime, bedtimeMinutes: bedtimeMinutes,
                            startMinutes: quietStartMinutes, endMinutes: quietEndMinutes)
    }

    /// The reminders entries get without a list of their own; `leadTimeMinutes` stays in the schema as the source of the
    /// migrated defaults.
    var reminderDefaults: ReminderDefaults {
        get { ReminderDefaults.decode(reminderDefaultsData, leadTimeMinutes: leadTimeMinutes) }
        set { reminderDefaultsData = newValue.encoded() }
    }

    /// The Focus filter state, see `FocusQuiet`.
    var focusQuietState: FocusQuiet.State {
        get {
            FocusQuiet.State(since: focusQuietSince, catchUpFrom: focusQuietCatchUpFrom, catchUpAt: focusQuietCatchUpAt,
                             catchUpUntil: focusQuietCatchUpUntil)
        }
        set {
            focusQuietSince = newValue.since
            focusQuietCatchUpFrom = newValue.catchUpFrom
            focusQuietCatchUpAt = newValue.catchUpAt
            focusQuietCatchUpUntil = newValue.catchUpUntil
        }
    }

    /// Task sources whose switch for notifications is on.
    var notifiedTaskSources: Set<TaskSource> {
        var sources: Set<TaskSource> = []
        if githubTaskNotifications { sources.insert(.github) }
        if reminderTaskNotifications { sources.insert(.reminders) }
        if localTaskNotifications { sources.insert(.local) }
        return sources
    }
}

extension AppSettings {
    /// The further nutrients the screens show: fiber and sugar always, saturated fat and salt when switched on (decision NU1b).
    var visibleNutrients: [Nutrient] {
        Nutrient.allCases.filter { nutrient in
            switch nutrient {
            case .fiber, .sugar: true
            case .saturatedFat: saturatedFatEnabled
            case .salt: saltEnabled
            }
        }
    }
}
