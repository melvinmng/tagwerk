import AIKit
import Foundation
import GitHubKit
import HealthBridge
import Network
import Observation
import RemindersKit
import SwiftData
import TagwerkCore

/// Creates the long-lived objects once and wires them together.
@MainActor
@Observable
final class AppEnvironment {
    let modelContainer: ModelContainer
    let gateway: EventKitGateway
    /// Reminders for tasks, planning, the weekly review and the shopping list; the gateway unless a test passes a fake.
    let reminderStore: any ReminderStore
    let settings: AppSettings
    /// Categories of the shopping list and the learned assignments (phase 5).
    let shoppingCategories: ShoppingCategoryStore
    /// The shopping list; reads and writes the chosen reminder list.
    let shopping: ShoppingModel
    /// "Mit ChatGPT sortieren"; sends item names only after consent and on the user's tap.
    let shoppingSorter: ShoppingSorter
    let recipeImporter: RecipeImporter
    let recipeTranslator: RecipeTranslator
    /// "Artikel übersetzen"; one checked request with item names only, after the same consent as sorting and on the user's tap.
    let shoppingTranslator: ShoppingTranslator
    /// Items the share extension left for the app (#165); read when the app becomes active, confirmed by the user.
    let shareInbox: ShareInboxModel
    /// "Mit ChatGPT zusammenfassen" on a shared mail (#166); sends only after consent and on the user's tap.
    let mailSummarizer: MailSummarizer
    /// Notes stored on this device only (phase 5); never sent to ChatGPT.
    let notes: NoteStore
    let backup: BackupService
    /// The lock session of the notes (NL1a): hides locked notes and private folders until the device owner is checked.
    let noteLock: NoteLock
    let taskList: TaskListModel
    let planning: PlanningModel
    /// Travel times before events with a place; asks Apple Maps only for addresses (#168).
    let travelTimes: TravelTimeService
    /// Address completion for the home address in the settings; the simulator can answer with fixed suggestions.
    let addressSuggester: any AddressSuggesting
    let gitHubTokens: TokenManager
    let gitHubLoginClient: DeviceFlowClient
    let gitHub: GitHubTaskProvider
    /// ChatGPT session, client and model choice. Creating it sends nothing (§8.4).
    let ai: AIEnvironment
    /// "Tag/Woche/Monat planen" with ChatGPT; calls only on the user's tap.
    let planner: AIPlanner
    /// The assistant chat (design §8.3); sends only what the user writes.
    let assistant: AssistantModel
    /// Reads answers aloud (plan voice-chat).
    let voiceOutput: VoiceOutputModel
    /// A fresh recognizer per conversation; the demo launch argument replaces it with a scripted one.
    let makeRecognizer: @MainActor () -> SpeechRecognizing
    /// The voice mode of the assistant chat (SP5a).
    let voiceMode: VoiceModeController
    /// Per-entry reminder lists that replace the default reminders (plan P4).
    let reminderOverrides: ReminderOverrideStore
    /// Deadline notifications (design 2b §9); never calls an AI feature.
    let notifications: NotificationScheduler
    /// Target of a tapped notification until the app shows it.
    let notificationNavigator = NotificationNavigator()
    /// Target of a `tagwerk://` link or a shortcut until the app shows it (phase 4).
    let router = AppRouter()
    /// Delegate of the system notification center; held here because the center keeps it weakly.
    @ObservationIgnored private(set) lazy var notificationDelegate = NotificationDelegate(
        navigator: notificationNavigator, router: router, skipBibleStudy: { [weak self] in await self?.skipBibleStudyToday() })
    /// Meals, water and workouts (phase 3); mirrored to Health only after the user allowed it.
    let intake: IntakeStore
    /// Goal plans ("Zielstände"); the plan of a day is the goal that holds on it.
    let goals: GoalStore
    /// The Health values kept for each day, and the budget that follows from them (one place for every screen).
    let dayHealth: DayHealthStore
    let budgets: DayBudgets
    let health: any HealthStoring
    let healthMirror: HealthMirror
    let capture: CaptureModel
    /// Habits of the "Erfassen" tab, their counter in "Planen" and in the widget (phase 7).
    let habits: HabitsModel
    /// Day entries and the evening checklist of the routines (phase 7).
    let routineStore: RoutineStore
    /// The routine sheets, the evening line and the evening wrap-up (phase 7).
    let routines: RoutinesModel
    /// Repeating evening (and morning) reminders; their own scheduler outside the 50-slot deadline budget.
    let routineNotifications: RoutineNotificationScheduler
    /// Meal estimates with ChatGPT; only after consent and a tap (main design §7).
    let mealEstimator: MealEstimator
    /// Focus timer sessions and the collection (plan P3, #161); stays on this device.
    let focusStore: FocusStore
    /// The focus timer: one session at a time, Live Activity and one notification at the end of the phase.
    let focus: FocusTimerModel
    /// Measures the actual effort when a task is completed and cuts a block that ended early (plan P3, #162).
    let effort: EffortTracker
    /// Writes the snapshot file the widget reads (phase 4); `directory == nil` in tests and unsigned builds.
    let snapshotWriter: WidgetSnapshotWriter
    /// What the controls read while the app is closed (App Group); `nil` in tests and without the group.
    let controlState: ControlState?
    /// Reads events for the search away from the main thread; its own read-only store.
    let eventSearcher: any EventSearching
    /// Reminders as tasks; also the source of the completed ones for the search.
    private let remindersProvider: RemindersTaskProvider
    /// The search sheet is open. Set through `openSearch()`; assistant, notifications and links close it.
    var isSearchPresented = false
    /// The model of the open (or last) search sheet; it holds nothing after `close()`.
    @ObservationIgnored private(set) var activeSearch: SearchModel?
    /// Set by `DemoData` once the sample data is created; the UI tests wait for the marker view it drives.
    var isDemoDataReady = false
    /// Number of EventKit changes `startObservingChanges()` has finished handling, and whether one is being handled now.
    /// The UI test mode waits for them (`StoreChangeSettle`) before it reports the app as ready.
    @ObservationIgnored private(set) var storeChangesHandled = 0
    @ObservationIgnored private(set) var isHandlingStoreChange = false
    /// A tab another view asks to show (e.g. "Mit KI planen" from the task list jumps to "Planen").
    var requestedTab: Int?
    /// Pages on top of the task list (shopping list, notes); a deep link sets it to open the shopping list.
    var tasksPath: [TasksDestination] = []
    /// Pages on top of the settings (`SettingsDestination`); set by the UI test mode to open a settings page at launch.
    var settingsPath: [SettingsDestination] = []
    private let gitHubCache: SwiftDataGitHubCache
    private let gitHubCatalogStore: SwiftDataGitHubCatalogStore
    /// Age after which the repository/project catalog is fetched again.
    static let catalogMaxAge: TimeInterval = 5 * 60
    @ObservationIgnored private var changeObservation: Task<Void, Never>?
    @ObservationIgnored private var reconnectWatch: Task<Void, Never>?
    @ObservationIgnored private var pathMonitor: NWPathMonitor?
    @ObservationIgnored private var routineUpdates: Task<Void, Never>?
    @ObservationIgnored private var focusUpdates: Task<Void, Never>?
    @ObservationIgnored private var habitSourceUpdates: Task<Void, Never>?
    @ObservationIgnored private var notificationUpdates: Task<Void, Never>?
    @ObservationIgnored private var gitHubRegistration: Task<Void, Never>?
    @ObservationIgnored private var snapshotUpdates: Task<Void, Never>?
    @ObservationIgnored private var pendingSnapshot: Task<Void, Never>?

    /// `notificationCenter` defaults to the system center, `health` to HealthKit and `reminderStore` to the
    /// EventKit gateway; tests and demo data pass fakes.
    /// The travel time service; the simulator can answer with fixed demo times (`-TagwerkDemoTravel`).
    private static func makeTravelTimes() -> TravelTimeService {
        #if DEBUG && targetEnvironment(simulator)
        if DemoTravelEstimator.isRequested { return TravelTimeService(estimator: DemoTravelEstimator(), cacheURL: nil) }
        #endif
        return TravelTimeService()
    }

    /// The device check of the note lock; the UI tests can fix its answer.
    private static func makeDeviceOwnerAuthenticator() -> any DeviceOwnerAuthenticating {
        #if DEBUG && targetEnvironment(simulator)
        if let answers = UITestMode.lockAuthentication { return FixedDeviceOwnerAuthenticator(answers: answers) }
        #endif
        return SystemDeviceOwnerAuthenticator()
    }

    private static func makeAddressSuggester() -> any AddressSuggesting {
        #if DEBUG && targetEnvironment(simulator)
        if DemoTravelEstimator.isRequested { return DemoAddressSuggester() }
        #endif
        return MapKitAddressSuggester()
    }

    init(modelContainer: ModelContainer, notificationCenter: (any NotificationCenterClient)? = nil,
         health: (any HealthStoring)? = nil, snapshotWriter: WidgetSnapshotWriter? = nil,
         reminderStore: (any ReminderStore)? = nil, eventSearcher: (any EventSearching)? = nil,
         focusNotificationCenter: (any FocusNotificationCenter)? = nil,
         travelTimes: TravelTimeService? = nil, addressSuggester: (any AddressSuggesting)? = nil, shareInbox: ShareInbox? = nil,
         controlState: ControlState? = nil, controlReloader: ControlReloading? = nil,
         deviceOwnerAuthenticator: (any DeviceOwnerAuthenticating)? = nil) throws {
        self.modelContainer = modelContainer
        self.controlState = controlState
        self.snapshotWriter = snapshotWriter ?? WidgetSnapshotWriter(directory: nil, reload: {})
        let context = modelContainer.mainContext
        let settings = try AppSettings.current(in: context)
        settings.migrateWorkoutGoalIfNeeded()
        settings.migrateVoiceAnswerLanguageIfNeeded()
        let gateway = EventKitGateway()
        let reminderStore: any ReminderStore = reminderStore ?? gateway
        let reminders = RemindersTaskProvider(store: reminderStore, estimates: SwiftDataEstimateStore(context: context),
                                              selectedListIDs: { settings.selectedReminderListIDs.map(Set.init) },
                                              excludedListID: { settings.shoppingListID })
        self.settings = settings
        self.gateway = gateway
        self.reminderStore = reminderStore
        let searcher: any EventSearching = eventSearcher ?? EventSearchReader()
        self.eventSearcher = searcher
        self.remindersProvider = reminders
        let attachments = NoteAttachmentStore(context: context)
        let noteStore = NoteStore(context: context, attachments: attachments)
        // The fixed folders must exist before the first frame; a restore may bring notes without them.
        noteStore.ensureDefaultFolders()
        attachments.purgeOrphans(existingNoteIDs: Set(noteStore.allNotes().map(\.id)))
        self.notes = noteStore
        let authenticator: any DeviceOwnerAuthenticating = deviceOwnerAuthenticator ?? Self.makeDeviceOwnerAuthenticator()
        self.noteLock = NoteLock(settings: settings, authenticator: authenticator)
        self.backup = BackupService(context: context, settings: settings, attachments: attachments,
                                    canProtectNotes: { authenticator.canAuthenticate() }, afterRestore: { [noteStore] in
            noteStore.ensureDefaultFolders()
            noteStore.save()
        })
        let shoppingCategories = ShoppingCategoryStore(context: context, settings: settings)
        self.shoppingCategories = shoppingCategories
        self.shopping = ShoppingModel(store: reminderStore, settings: settings, categories: shoppingCategories)
        let taskList = TaskListModel(providers: [reminders, LocalTaskProvider(context: context)])
        self.taskList = taskList
        let planStore = PlanStore(context: context)
        let suggestionStore = SuggestionStore(context: context)
        let blockPlanner = BlockPlanner(store: gateway, planStore: planStore, links: EventLinkStore(context: context),
                                        settings: settings, calendar: .tagwerk)
        let travelTimes = travelTimes ?? Self.makeTravelTimes()
        self.travelTimes = travelTimes
        self.addressSuggester = addressSuggester ?? Self.makeAddressSuggester()
        self.planning = PlanningModel(taskList: taskList, calendarStore: gateway, reminderStore: reminderStore, planStore: planStore,
                                      efforts: RecurringEffortStore(context: context), blocks: blockPlanner, settings: settings,
                                      marks: EventMarkStore(context: context), suggestions: suggestionStore,
                                      now: { UITestMode.now() }, travelTimes: travelTimes)

        let clientID = Bundle.main.object(forInfoDictionaryKey: "GitHubClientID") as? String ?? ""
        // GitHub requests fail after 15 s instead of the default 60 s, so the cache appears quickly offline.
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        let transport = URLSessionTransport(session: URLSession(configuration: configuration))
        let loginClient = DeviceFlowClient(clientID: clientID, transport: transport)
        let tokens = TokenManager(store: KeychainCredentialStore(), client: loginClient)
        self.gitHubLoginClient = loginClient
        self.gitHubTokens = tokens
        let cache = SwiftDataGitHubCache(context: context)
        let catalogStore = SwiftDataGitHubCatalogStore(context: context)
        self.gitHubCache = cache
        self.gitHubCatalogStore = catalogStore
        self.gitHub = GitHubTaskProvider(
            api: GitHubAPI(transport: transport, tokens: tokens),
            tokens: tokens,
            cache: cache,
            catalogStore: catalogStore,
            selectedProjectIDs: { settings.selectedProjectIDs.map(Set.init) }
        )
        let ai = AIEnvironment.make(settings: settings)
        self.ai = ai
        self.planner = AIPlanner(responder: ai.client, model: { try await ai.selectedModel() }, planning: planning,
                                 store: suggestionStore, consumeModelFallback: {
                                     defer { ai.modelFallbackNotice = false }
                                     return ai.modelFallbackNotice
                                 })
        planner.workAhead = { settings.aiWorkAhead }
        planner.longerDays = { AIPlanner.LongerDays(rawValue: settings.aiLongerDays) ?? .forDeadlines }
        planner.preferences = { settings.aiPlanningRules }
        let tools = AppTools(taskList: taskList, planning: planning, planner: planner,
                             events: { interval in gateway.events(in: interval, calendarIDs: nil) },
                             gitHub: { [taskList] in taskList.provider(for: .github) as? GitHubTaskProvider },
                             shopping: shopping,
                             search: SearchToolSources(
                                 events: Self.searchEventSource(searcher: searcher, store: reminderStore, planning: planning, settings: settings),
                                 calendarNames: Self.searchCalendarNames(planning: planning),
                                 completedTasks: Self.searchCompletedSource(reminders: reminders, taskList: taskList),
                                 // The only source of notes for the assistant: `NoteToolAccess` leaves private notes out.
                                 notes: { [noteStore] in Self.assistantSearchNotes(store: noteStore) },
                                 shopping: Self.searchShoppingSource(shopping: shopping),
                                 searchOnline: Self.searchOnlineSource(taskList: taskList),
                                 notesAllowed: { settings.noteAssistantConsent }),
                             noteAccess: NoteToolAccess(store: noteStore))
        self.assistant = AssistantModel(responder: ai.client, tools: tools, model: { try await ai.selectedModel() },
                                        store: ChatStore(context: context), planning: planning)
        self.voiceOutput = VoiceOutputModel(speaker: SystemSpeaker(), audio: SystemVoiceAudioSession.shared, preferences: {
            VoiceOutputModel.Preferences(germanVoiceID: settings.voiceGermanVoiceID, englishVoiceID: settings.voiceEnglishVoiceID,
                                         rate: settings.voiceRate)
        })
        let voiceOutput = self.voiceOutput
        // Withdrawing the consent ends the note session, from the settings screen as well as from a backup restore.
        assistant.watchNoteConsent { settings.noteAssistantConsent }
        // Locking a note ends the note session: the chat forgets what it read of notes before.
        noteStore.onNoteLocked = { [weak assistant] in assistant?.endNoteSession() }
        // The notes chat: the tools wrap the app tools and select notes only through `NoteToolAccess`.
        let noteAccess = NoteToolAccess(store: noteStore)
        assistant.noteTools = NoteChatTools(base: tools, access: noteAccess, hasConsent: { settings.noteAssistantConsent })
        assistant.hasNoteConsent = { settings.noteAssistantConsent }
        assistant.readPolicy = { ReadAloudPolicy(rawValue: settings.voiceReadAloud) ?? .never }
        assistant.announcesActions = { settings.voiceAnnounceActions }
        assistant.fixedVoiceLanguage = { settings.contentLanguages.fixedAnswerLanguage }
        assistant.shoppingLanguage = { settings.contentLanguages.shoppingLanguage() }
        assistant.readAutomatically = { id, text, fallback in voiceOutput.speak(id: id, text: text, explicit: false, fallback: fallback) }
        let demoVoice = ProcessInfo.processInfo.arguments.contains("-TagwerkDemoVoice")
        let makeRecognizer: @MainActor () -> SpeechRecognizing = {
            demoVoice ? DemoSpeechRecognizer() as SpeechRecognizing : AppleSpeechRecognizer(kind: .dictation)
        }
        self.makeRecognizer = makeRecognizer
        self.voiceMode = VoiceModeController(
            assistant: assistant, makeRecognizer: makeRecognizer, output: voiceOutput, tone: SystemTonePlayer(),
            audio: SystemVoiceAudioSession.shared,
            settings: {
                VoiceModeController.Settings(language: settings.contentLanguages.dictationLanguage(at: .chat),
                                             sendDelay: settings.voiceModeSendDelay, silenceLimit: settings.voiceModeSilenceLimit)
            })
        let gitHubProvider = self.gitHub
        assistant.reader = GitHubRepositoryReader(api: gitHubProvider.api)
        let shopping = self.shopping
        assistant.shoppingItemName = { id in shopping.openItems.first { $0.id == id }?.name }
        assistant.gitHubDirectory = { [taskList] in taskList.provider(for: .github) as? GitHubTaskProvider }
        assistant.issueReference = { id in
            gitHubProvider.issueReference(for: id).map { IssueReference(repository: $0.repository, number: $0.number, nodeID: $0.nodeID) }
        }
        let deadlineMarks = self.planning.deadlineMarks
        let reminderOverrides = ReminderOverrideStore(context: context)
        self.reminderOverrides = reminderOverrides
        taskList.reminderMarkInputs = { [reminderOverrides, settings] in (reminderOverrides.overrides(), settings.reminderDefaults) }
        self.notifications = NotificationScheduler(
            center: notificationCenter ?? SystemNotificationCenter(), taskList: taskList,
            deadlineEvents: { interval, ids in
                gateway.calendarAccessState == .fullAccess ? gateway.events(in: interval, calendarIDs: ids) : nil
            },
            markedDeadlines: MarkedDeadlineSource(calendarIDs: { Set(deadlineMarks.marks().map(\.calendarID)) },
                                                  markedIDs: { deadlineMarks.markedIDs(in: $0) }),
            settings: settings, reminderOverrides: reminderOverrides)
        let healthStore = health ?? HealthKitStore()
        let intake = IntakeStore(context: context)
        let mirror = HealthMirror(store: intake, health: healthStore)
        self.health = healthStore
        self.intake = intake
        let goals = GoalStore(context: context, settings: settings, calendar: .tagwerk)
        goals.migrateIfNeeded()
        // Goals edited in the settings before the plans took over (one plan, never updated) carry over once; later it is a no-op.
        goals.reconcileWithSettings()
        self.goals = goals
        self.healthMirror = mirror
        let dayHealth = DayHealthStore(context: context)
        self.dayHealth = dayHealth
        let budgets = DayBudgets(intake: intake, goals: goals, dayHealth: dayHealth, health: healthStore, settings: settings,
                                 calendar: .tagwerk, now: Date.init)
        self.budgets = budgets
        self.capture = CaptureModel(store: intake, mirror: mirror, health: healthStore, settings: settings, budgets: budgets)
        self.routineStore = RoutineStore(context: context)
        // The habit sources of the routines read the evening wrap-ups, the journal and the Bible Study sessions.
        let routineDays = self.routineStore
        let noteDays = self.notes
        self.habits = HabitsModel(store: HabitStore(context: context), intake: intake, health: healthStore, settings: settings,
                                  daySources: HabitDaySources(closedDays: { routineDays.closedDays(in: $0) },
                                                              journalDays: { noteDays.journalDays(in: $0) },
                                                              bibleStudyDays: { noteDays.completedSessionDays(in: $0) }))
        self.mealEstimator = MealEstimator(responder: ai.client, model: { try await ai.selectedModel() },
                                           hasConsent: { settings.mealEstimationConsent })
        self.shoppingSorter = ShoppingSorter(responder: ai.client, model: { try await ai.selectedModel() },
                                             hasConsent: { settings.hasShoppingSortConsent })
        self.shoppingTranslator = ShoppingTranslator(responder: ai.client, model: { try await ai.selectedModel() },
                                                     hasConsent: { settings.hasShoppingSortConsent })
        self.recipeImporter = RecipeImporter(responder: ai.client, model: { try await ai.selectedModel() },
                                             hasConsent: { settings.shoppingRecipeConsent })
        self.recipeTranslator = RecipeTranslator(responder: ai.client, model: { try await ai.selectedModel() },
                                                 hasConsent: { settings.shoppingRecipeConsent })
        self.shareInbox = ShareInboxModel(inbox: shareInbox, isSetupCompleted: { settings.setupCompleted })
        self.mailSummarizer = MailSummarizer(responder: ai.client, model: { try await ai.selectedModel() },
                                             hasConsent: { settings.mailSummaryConsent })
        let planning = self.planning
        let localTasks = LocalTaskProvider(context: context)
        self.routines = RoutinesModel(
            store: routineStore, planning: planning, taskList: taskList, habits: habits, settings: settings,
            completedCount: { interval in
                // Same readers as the weekly review: reminders (without the shopping list) and local tasks.
                let listIDs = ShoppingListFilter.taskListIDs(selected: settings.selectedReminderListIDs.map(Set.init),
                                                             all: reminderStore.lists().map(\.id), shopping: settings.shoppingListID)
                return await reminderStore.completionDates(in: interval, listIDs: listIDs).count
                    + localTasks.completionDates(in: interval).count
            },
            // GitHub issues closed that day; `nil` while GitHub is not connected (asked at every use).
            closedIssueCount: { [taskList] in
                guard let gitHub = taskList.provider(for: .github) as? GitHubTaskProvider else { return nil }
                return { interval in try await gitHub.closedIssueCount(in: interval) }
            })
        // The Bible Study reminder reads the sessions of the notes: which days are done and where reading goes on.
        let bibleStudyNotes = self.notes
        self.routineNotifications = RoutineNotificationScheduler(
            center: notificationCenter ?? SystemNotificationCenter(), store: routineStore, settings: settings,
            bibleStudyCompletedDays: { bibleStudyNotes.completedSessionDays(in: $0) },
            bibleStudyNextPassage: { showsPassage, locale in
                let continuation = bibleStudyNotes.reminderContinuation()
                return BibleStudyReminders.nextPassageText(bookName: continuation?.book.name(locale: locale), next: continuation?.next,
                                                           showsPassage: showsPassage, locale: locale)
            })
        let routines = self.routines
        let routineNotifications = self.routineNotifications
        // A started or completed session changes the verse the reminder names and the days that get one.
        bibleStudyNotes.onBibleStudyChanged = { Task { await routineNotifications.reschedule() } }
        // A checked point must not remind on that evening any more; unchecking plans the reminder again while it is ahead.
        routines.onChecklistToggled = { id, day, isChecked in
            if isChecked {
                await routineNotifications.itemChecked(id, on: day)
            } else {
                await routineNotifications.reschedule()
            }
        }
        let focusStore = FocusStore(context: context)
        self.focusStore = focusStore
        let focus = FocusTimerModel(store: focusStore, settings: { settings.focusTimerSettings }, activity: FocusActivityController(),
                                    notifications: FocusNotificationScheduler(center: focusNotificationCenter),
                                    controlState: controlState, controlReloader: controlReloader,
                                    asksDurationAtStart: { settings.focusAsksDurationAtStart })
        self.focus = focus
        focus.postponeTask = { key in
            guard let id = TaskID(key: key) else { return }
            await planning.assign(id, to: planning.planDay(for: .tomorrow), moveBlocks: true)
        }
        focus.installIntentHandler()
        let effort = EffortTracker(store: focusStore, blocks: blockPlanner, calendarStore: gateway, settings: settings)
        self.effort = effort
        // Only the expected minutes per task go to the planning, and only while the setting is on.
        planner.expectedMinutes = { effort.expectedMinutes(for: $0) }
        planning.trimmedBlockLookup = { effort.trimmedBlocks(among: $0) }
        taskList.onCompletedItem = { item, date in
            // A timer running for the task ends first, so its focus time counts for this completion.
            await focus.didComplete(taskKey: item.id.key)
            if await effort.didComplete(item, at: date) { await planning.reload() }
        }
        taskList.onCompletionChanged = { id, isCompleted in
            // "Rückgängig": the sample goes and a block that was cut gets its end back, before the plan reads again.
            if !isCompleted, await effort.didReopen(id) { await planning.reload() }
            await planning.didChangeCompletion(id, isCompleted: isCompleted)
            await MainActor.run { routines.focusChanged(id, isCompleted: isCompleted) }
        }
        taskList.onHandedOver = { id in await planning.didHandOver(id) }
        // An ended GitHub sign-in (expired or revoked) forgets the cached issues of that account.
        taskList.onSignedOut = { source in
            if source == .github {
                cache.clear()
                catalogStore.clear()
            }
        }
        // "Erledigt" on the Live Activity can start the app in the background, where no list is loaded yet: the tasks
        // are loaded first (with GitHub registered), because completing needs the displayed item and its version.
        focus.completeTask = { [weak self] key in
            guard let self, let id = TaskID(key: key) else { return }
            if !taskList.items.contains(where: { $0.id == id }) { await loadTasksInBackground() }
            await taskList.complete(id)
        }
        // Closing the lock rebuilds the rows of an open search, so no passage of a hidden note stays in the model (NL4a).
        noteLock.onLock = { [weak self] in self?.activeSearch?.evaluate() }
        // A locked note is open to the assistant while the lock session is open (NoteStore.lockHoldsBack). When the session ends,
        // the assistant's note session ends with it, so no text of an unlocked note stays in the chat.
        noteLock.attach(to: noteStore, endingNoteSessionOf: assistant)
        noteStore.onLockMarksChanged = { [weak self] in self?.activeSearch?.evaluate() }
    }

    /// The model of the sheet "Mail zu Aufgabe" for a shared item: the mail if the extension parsed one, else its text.
    func makeMailTaskModel(for item: ShareInboxItem) -> MailTaskModel {
        let settings = self.settings
        let consent: @MainActor () -> Bool = { settings.mailSummaryConsent }
        let grant: @MainActor () -> Void = { settings.mailSummaryConsent = true }
        if let mail = item.mail {
            return MailTaskModel(mail: mail, summarizer: mailSummarizer, hasConsent: consent, grantConsent: grant)
        }
        return makeMailTaskModel(text: item.text ?? item.title)
    }

    /// The model for a mail copied as text (selected in Mail, or pasted from the clipboard).
    func makeMailTaskModel(text: String) -> MailTaskModel {
        let settings = self.settings
        return MailTaskModel(text: text, summarizer: mailSummarizer, hasConsent: { settings.mailSummaryConsent },
                             grantConsent: { settings.mailSummaryConsent = true })
    }

    /// A model for the suggestions of one thoughts note; the sheet drops it when it closes (design §9.3).
    func makeNoteSuggestionModel() -> NoteSuggestionModel {
        let settings = self.settings
        let planning = self.planning, taskList = self.taskList, gateway = self.gateway, ai = self.ai
        return NoteSuggestionModel(
            responder: ai.client, model: { try await ai.selectedModel() }, tools: assistant.tools,
            describer: ActionCardDescriber(planning: planning, gitHubDirectory: assistant.gitHubDirectory,
                                           shoppingItemName: assistant.shoppingItemName),
            notes: notes, hasConsent: { settings.noteSuggestionConsent },
            context: {
                NoteSuggestionContext.make(taskList: taskList, planning: planning,
                                           events: { gateway.events(in: $0, calendarIDs: planning.readableCalendarIDs()) },
                                           planCalendarID: settings.planCalendarID, now: .now)
            },
            gitHubDirectory: { [assistant] in assistant.gitHubDirectory() },
            editorContext: { [assistant] in assistant.proposalEditorContext() })
    }

    /// The background refresh: GitHub is registered without the catalog, every source loads once, then the
    /// notifications are rescheduled. Nothing here reaches an AI feature (§8.4).
    func makeBackgroundRefresh() -> BackgroundRefresh {
        BackgroundRefresh(
            prepare: { [weak self] in
                await self?.registerGitHubIfSignedIn() ?? false  // a registration loads all sources
            },
            reload: { [weak self] in await self?.taskList.reload() },
            reschedule: { [weak self] in
                await self?.notifications.reschedule()
                // The dated evening reminders run out after three days: fill them up as well.
                await self?.routineNotifications.reschedule()
            },
            writeSnapshot: { [weak self] in self?.writeSnapshot() },
            nextRefill: { [weak self] in self?.notifications.nextRefill })
    }

    /// Loads every source once, registering GitHub first when signed in; for work that runs without the app's first
    /// screen, like a Focus filter. Does not read the GitHub catalog.
    func loadTasksInBackground() async {
        if await !registerGitHubIfSignedIn() { await taskList.reload() }
    }

    /// Adds GitHub to the task list when credentials exist.
    func activateGitHubIfSignedIn() async {
        guard await registerGitHubIfSignedIn() else { return }
        // Refresh repositories and project links at every start, so creating an issue needs no wait.
        _ = await gitHub.catalog(maxAge: 0)
    }

    /// Registers GitHub once, also when start, foreground and background refresh ask at the same time.
    /// Returns `true` only to the caller whose registration loaded the sources.
    private func registerGitHubIfSignedIn() async -> Bool {
        if let running = gitHubRegistration {
            await running.value
            return false
        }
        guard taskList.provider(for: .github) == nil else { return false }
        let registration = Task { @MainActor [weak self] in
            guard let self, await gitHubTokens.isSignedIn, taskList.provider(for: .github) == nil else { return }
            await taskList.register(gitHub)
        }
        gitHubRegistration = registration
        await registration.value
        gitHubRegistration = nil
        return taskList.provider(for: .github) != nil
    }

    /// Removes GitHub from the task list after signing out and forgets cached issues.
    func deactivateGitHub() async {
        gitHubCache.clear()
        gitHubCatalogStore.clear()
        settings.selectedProjectIDs = nil
        await taskList.unregister(.github)
        // After a voluntary sign-out GitHub has no state, so the scheduler would keep its notifications.
        await notifications.removeNotifications(of: .github)
    }

    var isGitHubActive: Bool { taskList.provider(for: .github) != nil }

    func makeGitHubLoginModel() -> GitHubLoginModel {
        GitHubLoginModel(
            login: gitHubLoginClient,
            tokens: gitHubTokens,
            onSignedIn: { [weak self] in
                await self?.activateGitHubIfSignedIn()
                return self?.gitHub.login
            },
            onSignedOut: { [weak self] in await self?.deactivateGitHub() }
        )
    }

    func makeSetupModel() -> SetupModel {
        let notifications = self.notifications
        return SetupModel(store: reminderStore, settings: settings, calendarStore: gateway, isChatGPTSignedIn: ai.isSignedIn,
                          notificationsAllowed: notifications.authorization == .authorized,
                          requestNotifications: { await notifications.requestAuthorization() })
    }

    /// Current authorization of a source that needs system permission; `nil` for sources without one.
    func accessState(for source: TaskSource) -> AccessState? {
        source == .reminders ? reminderStore.accessState : nil
    }

    /// Asks the system for access (only possible while it is undetermined) and reloads the list.
    func requestAccess(for source: TaskSource) async {
        guard source == .reminders else { return }
        _ = try? await reminderStore.requestAccess()
        await taskList.reload()
    }

    // MARK: Shopping list (phase 5)

    /// The reminder lists that feed tasks and the weekly review: the selection without the shopping list.
    /// `nil` means all lists; an empty set means none.
    func taskReminderListIDs() -> Set<String>? {
        ShoppingListFilter.taskListIDs(selected: settings.selectedReminderListIDs.map(Set.init),
                                       all: reminderStore.lists().map(\.id), shopping: settings.shoppingListID)
    }

    /// Shows the shopping page in the "Aufgaben" tab, or its settings page while no list is chosen.
    /// Replaces whatever was pushed there; used by the deep link and the shortcut.
    func openShopping() {
        tasksPath = [settings.shoppingListID == nil ? .shoppingSettings : .shopping]
        requestedTab = 1
    }

    /// "Heute nicht" on the Bible Study reminder: the calendar day is remembered and the reminder of today goes at once. The
    /// planner leaves the day out from now on, so the next run does not bring it back.
    func skipBibleStudyToday() async {
        let today = PlanDay(date: Date(), calendar: planning.calendar)
        settings.bibleStudySkippedDayKey = today.dayKey
        try? modelContainer.mainContext.save()
        await routineNotifications.removeBibleStudyReminder(on: today)
        await routineNotifications.reschedule()
    }

    /// Shows the list of the Bible Study folder in the "Aufgaben" tab; it opens the start sheet once
    /// (`AppRouter.bibleStudyStartRequested`).
    func openBibleStudyStart() {
        let folder = notes.ensureBibleStudyFolder()
        tasksPath = [.notes, .notesFolder(.folder(folder.id))]
        requestedTab = 1
    }

    /// Shows the notes of "Brain Dump" in the "Aufgaben" tab; the list starts a recording (`AppRouter.dictationRequested`).
    /// The note is created by the list's own send action, so nothing is written here.
    func openDictatedNote() {
        if notes.folder(role: .brainDump) == nil { notes.ensureDefaultFolders() }
        guard let folder = notes.folder(role: .brainDump) else {
            // No folder to record into: show the notes overview and drop the request, so no later list starts recording.
            _ = router.takeDictationRequest()
            tasksPath = [.notes]
            requestedTab = 1
            return
        }
        tasksPath = [.notes, .notesFolder(.folder(folder.id))]
        requestedTab = 1
    }

    /// Creates an empty note in "Brain Dump" and opens it for writing from anywhere in the app (the plus button of the
    /// folder overview). The editor removes the note again when it closes without text, so a tap that is not followed
    /// by writing leaves nothing behind. Replaces whatever was pushed in the tab "Aufgaben".
    func openNewBrainDumpNote() {
        if notes.folder(role: .brainDump) == nil { notes.ensureDefaultFolders() }
        guard let folder = notes.folder(role: .brainDump) else {
            tasksPath = [.notes]
            requestedTab = 1
            return
        }
        let note = notes.createBlank(folderID: folder.id)
        tasksPath = [.notes, .notesFolder(.folder(folder.id)), .note(note.id)]
        requestedTab = 1
    }

    /// Opens a notes list in the tab "Aufgaben", on top of the folder overview. Replaces whatever was pushed there.
    /// A locked folder asks for Face ID in its list like at every other opening.
    func showNotes(_ scope: NotesScope) {
        tasksPath = [.notes, .notesFolder(scope)]
        requestedTab = 1
    }

    /// The list "Im Ordner zeigen" opens for a note: its folder; "Notizen" for a note without a folder or whose folder is
    /// gone (where `NoteStore` lists it, but only own notes, not thought notes); "Zuletzt gelöscht" for a note in the trash.
    /// "Alle Notizen" is the fallback for a note that does not exist or would not appear in "Notizen".
    func notesScope(ofNote noteID: UUID) -> NotesScope {
        guard let note = notes.note(id: noteID) else { return .all }
        if note.deletedAt != nil { return .trash }
        if let folderID = note.folderID, notes.folder(id: folderID) != nil { return .folder(folderID) }
        return note.kind == .free ? .standard : .all
    }

    /// The only place that changes the shopping list. Everything that shows reminders as tasks follows at once:
    /// the task list, the plan, the notifications and the widget snapshot.
    func setShoppingList(_ id: String?) async {
        settings.shoppingListID = id
        await taskList.reload(only: [.reminders])
        await planning.reload()
        await shopping.reload()
        notifications.scheduleSoon()
        scheduleSnapshot()
    }

    // MARK: Search

    /// Opens the search sheet with a fresh model; the previous one is closed.
    func openSearch() {
        activeSearch?.close()
        activeSearch = makeSearchModel()
        isSearchPresented = true
    }

    /// Closes the sheet and stops the model; what it loaded is dropped.
    func closeSearch() {
        isSearchPresented = false
        activeSearch?.close()
    }

    /// Folder names by id, the label of a note in a folder.
    static func folderNames(_ notes: NoteStore) -> [UUID: String] {
        Dictionary(notes.folders().map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    /// Open items of a list that is set up; completed ones stay out (spec F7). Shared by the search sheet and the assistant.
    static func searchShoppingSource(shopping: ShoppingModel) -> @MainActor () -> [ShoppingSearchItem] {
        {
            guard shopping.state == .ready else { return [] }
            return shopping.openItems.map { ShoppingSearchItem(id: $0.id, name: $0.name, quantity: $0.quantity) }
        }
    }

    /// The online issue search of the search sheet and the assistant; reads the GitHub provider when it runs, so a
    /// sign-in after the start counts. Throws `IssueSearchError.signedOut` without one.
    static func searchOnlineSource(taskList: TaskListModel) -> @MainActor (String) async throws -> [OnlineIssue] {
        { [weak taskList] text in
            guard let taskList, let gitHub = taskList.provider(for: .github) as? GitHubTaskProvider else {
                throw IssueSearchError.signedOut
            }
            // Issues that are among the tasks already stay out; the search adds closed and unassigned ones.
            let loaded = Set(taskList.items.filter { $0.id.source == .github }.map(\.id.rawValue))
            return try await gitHub.searchOnline(text, excluding: loaded)
        }
    }

    /// A note as the search sees it. The search reads the plain text only: no Markdown, no HTML, no attachment references.
    /// `gratitude` is the gratitude of the day of a morning note; the app search appends it to the text, the assistant never gets it.
    /// A hidden note (`isConcealed`: protected and not unlocked) carries its title line only, and no gratitude and no scan text, so the
    /// search finds it by its title and nothing of the note stays in the search model (NL4a).
    /// `scanText` is the text recognised in the scans of the note; the app search passes it, the assistant never does.
    static func searchItem(for note: NoteRecord, folderNames: [UUID: String], gratitude: [String] = [], scanText: String = "",
                           isConcealed: Bool = false) -> NoteSearchItem {
        let folderName = note.kind == .free ? note.folderID.flatMap { folderNames[$0] } : nil
        let text = isConcealed ? NoteText.title(note.text)
            : ([MarkdownText.plainText(note.text)] + gratitude).joined(separator: "\n")
        return NoteSearchItem(id: note.id, text: text, kindLabel: folderName ?? kindLabel(of: note.kind),
                              updatedAt: note.updatedAt, dayKey: note.kind == .free || note.kind == .bibleStudy ? nil : note.dayKey,
                              isConcealed: isConcealed, scanText: isConcealed ? "" : scanText)
    }

    /// The notes the assistant's `search` may read: only what `NoteToolAccess` shows, never the gratitude of a day.
    static func assistantSearchNotes(store: NoteStore) -> [NoteSearchItem] {
        let access = NoteToolAccess(store: store)
        let folderNames = folderNames(store)
        return access.visibleNotes().map { searchItem(for: $0, folderNames: folderNames) }
    }

    /// What the app search reads (not the assistant): the live notes, the gratitude of a day with a morning note appended to that
    /// note's text, and every day that only has gratitude as an item of its own. `scanTexts` gives the text recognised in the
    /// scans of a note (by note ID); the search finds a scan by it.
    static func appSearchNotes(live: [NoteRecord], folderNames: [UUID: String], gratitudeDays: [PlanDay: [String]],
                               calendar: Calendar, scanTexts: [UUID: String] = [:],
                               isConcealed: (NoteRecord) -> Bool = { _ in false }) -> [NoteSearchItem] {
        var morningDays = Set<PlanDay>()
        var items = live.map { note -> NoteSearchItem in
            var gratitude: [String] = []
            let concealed = isConcealed(note)
            if note.kind == .morning, let day = note.dayKey.flatMap(NoteDayKey.day) {
                morningDays.insert(day)
                gratitude = concealed ? [] : gratitudeDays[day] ?? []
            }
            return searchItem(for: note, folderNames: folderNames, gratitude: gratitude, scanText: scanTexts[note.id] ?? "",
                              isConcealed: concealed)
        }
        items += gratitudeSearchItems(gratitudeDays: gratitudeDays, morningNoteDays: morningDays, calendar: calendar)
        return items
    }

    /// The text recognised in the scans of each note that has any, by note ID.
    static func scanTexts(of notes: [NoteRecord], attachments: NoteAttachmentStore?) -> [UUID: String] {
        guard let attachments else { return [:] }
        let index = attachments.index()
        return notes.reduce(into: [:]) { result, note in
            let text = NoteAttachmentStore.scanText(text: note.text, index: index)
            if !text.isEmpty { result[note.id] = text }
        }
    }

    /// The days that only have gratitude, one search item each: "Dankbar für: A · B", labelled "Tagesstart", with an id derived
    /// from the day so it stays the same between two searches. Days with a morning note are left out (their gratitude is part of
    /// the note's item). Only the app search uses these items.
    static func gratitudeSearchItems(gratitudeDays: [PlanDay: [String]], morningNoteDays: Set<PlanDay>,
                                     calendar: Calendar) -> [NoteSearchItem] {
        gratitudeDays.filter { !morningNoteDays.contains($0.key) && !$0.value.isEmpty }
            .sorted { $0.key > $1.key }
            .map { day, entries in
                NoteSearchItem(id: gratitudeItemID(for: day), text: NotesListView.gratitudeLine(entries),
                               kindLabel: kindLabel(of: .morning), updatedAt: day.startDate(in: calendar), dayKey: day.dayKey,
                               routineDay: day)
            }
    }

    /// A fixed prefix plus year, month and day: the same day always gives the same id.
    static func gratitudeItemID(for day: PlanDay) -> UUID {
        let year = UInt16(clamping: day.year)
        return UUID(uuid: (0x54, 0x57, 0x47, 0x52, 0x41, 0x54, 0x49, 0x54, UInt8(year >> 8), UInt8(year & 0xFF),
                           UInt8(clamping: day.month), UInt8(clamping: day.day), 0, 0, 0, 0))
    }

    /// "Tagesstart" of the day in "Aufgaben": the page of a day that only has gratitude, on top of the folder.
    func showMorningDay(_ day: PlanDay) {
        guard let folder = notes.folder(role: .morningRoutine) else { return }
        tasksPath = [.notes, .notesFolder(.folder(folder.id)), .morningDay(day)]
        requestedTab = 1
    }

    /// Name of a note's kind in a search row.
    static func kindLabel(of kind: NoteKind) -> String {
        switch kind {
        case .free: String(localized: "Notiz")
        case .morning: String(localized: "Tagesstart")
        case .evening: String(localized: "Tagesabschluss")
        case .dream: String(localized: "Dream Log")
        case .journal: String(localized: "Tagebuch")
        case .bibleStudy: String(localized: "Bible Study")
        }
    }

    /// Events for the search sheet and the assistant: the calendars "Planen" reads, fetched off the main thread,
    /// time blocks dropped, duplicates merged like in "Planen". `nil` without calendar access.
    private static func searchEventSource(searcher: any EventSearching, store: any ReminderStore, planning: PlanningModel,
                                          settings: AppSettings) -> @MainActor (DateInterval) async -> [CalendarEvent]? {
        { interval in
            guard store.calendarAccessState == .fullAccess else { return nil }
            let raw = await searcher.events(in: interval, calendarIDs: planning.readableCalendarIDs())
            return SearchEvents.prepare(raw, planCalendarID: settings.planCalendarID, merge: settings.mergeDuplicateEvents)
        }
    }

    private static func searchCalendarNames(planning: PlanningModel) -> @MainActor () -> [String: String] {
        { Dictionary(planning.eventCalendars.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first }) }
    }

    /// Completed reminders of the last 12 months plus all completed local tasks.
    private static func searchCompletedSource(reminders: RemindersTaskProvider, taskList: TaskListModel) -> @MainActor () async -> [CompletedTask] {
        {
            let now = Date.now
            let start = Calendar.tagwerk.date(byAdding: .month, value: -12, to: now) ?? now
            // The end lies slightly ahead, so a reminder completed this very moment is not cut off.
            let interval = DateInterval(start: start, end: now.addingTimeInterval(60))
            let local = (taskList.provider(for: .local) as? LocalTaskProvider)?.completedTasks() ?? []
            return await reminders.completedTasks(in: interval) + local
        }
    }

    /// Wires a search model to the app's sources. Tasks are read from the loaded list, events through the
    /// search reader in the calendars "Planen" reads, completed reminders of the last 12 months and all
    /// completed local tasks on demand.
    func makeSearchModel() -> SearchModel {
        let planning = self.planning
        let taskList = self.taskList
        let settings = self.settings
        let reminderStore = self.reminderStore
        let searcher = self.eventSearcher
        let reminders = self.remindersProvider
        let searchOnline = isGitHubActive ? Self.searchOnlineSource(taskList: taskList) : nil
        let notes = self.notes
        let noteLock = self.noteLock
        let routines = self.routines
        let shopping = self.shopping
        var sources = SearchSources(
            openTasks: { sortedTasks(taskList.items, calendar: planning.calendar) },
            events: Self.searchEventSource(searcher: searcher, store: reminderStore, planning: planning, settings: settings),
            calendarNames: Self.searchCalendarNames(planning: planning),
            completedTasks: Self.searchCompletedSource(reminders: reminders, taskList: taskList),
            notes: {
                // A note in a folder shows the folder name as its label; the trash is not searched. The gratitude of the
                // morning routine is searched here and nowhere else (never by the assistant).
                let folderNames = Self.folderNames(notes)
                // Hidden notes are found by their title only, until the lock is open (NL4a).
                let privateFolderIDs = NoteFolderRules.privateFolderIDs(in: notes.folders().map(\.info))
                let live = notes.notes()
                return Self.appSearchNotes(live: live, folderNames: folderNames, gratitudeDays: routines.gratitudeDays(),
                                           calendar: planning.calendar, scanTexts: Self.scanTexts(of: live, attachments: notes.attachments),
                                           isConcealed: { noteLock.isConcealed($0, privateFolderIDs: privateFolderIDs) })
            },
            shopping: Self.searchShoppingSource(shopping: shopping),
            searchOnline: searchOnline)
        if settings.shoppingListID != nil {
            // A failed write leaves the item on the list; the model reads the rows again either way.
            sources.checkOffShopping = { id in try? await shopping.checkOff(id: id) }
        }
        return SearchModel(sources: sources, calendar: planning.calendar)
    }

    /// After a restore replaced the data: everything that keeps a copy in memory reads again.
    func reloadAfterRestore() async {
        notes.save()
        habits.refreshLocal()
        await taskList.reload()
        await planning.reload()
        await shopping.reload()
        await capture.reload()
        writeSnapshot()
    }

    func restartSetup() {
        settings.setupCompleted = false
    }

    /// Keeps GitHub from staying offline: retries with growing pauses while it is offline or failing,
    /// and at once when the network comes back.
    func startReconnectWatch() {
        guard reconnectWatch == nil else { return }
        let reconnector = Reconnector(model: taskList, source: .github)
        reconnectWatch = Task { [weak self] in
            while !Task.isCancelled {
                if let self, ReconnectPolicy.needsRetry(self.taskList.sourceStates[.github]) {
                    await reconnector.runUntilOnline()
                }
                try? await Task.sleep(for: .seconds(15))
            }
        }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in await self?.retryGitHubIfNeeded() }
        }
        monitor.start(queue: DispatchQueue(label: "de.tagwerk.network"))
        pathMonitor = monitor
    }

    /// Immediate retry, e.g. when the network returns or the app comes to the foreground.
    func retryGitHubIfNeeded() async {
        guard ReconnectPolicy.needsRetry(taskList.sourceStates[.github]) else { return }
        await taskList.reload(only: [.github])
    }

    /// Reloads the list whenever Reminders or Calendar report a change.
    func startObservingChanges() {
        guard changeObservation == nil else { return }
        let changes = gateway.changes
        changeObservation = Task { [weak self] in
            for await _ in changes {
                self?.isHandlingStoreChange = true
                // EventKit changes concern Reminders only; GitHub and local tasks stay as they are.
                await self?.taskList.reload(only: [.reminders])
                await self?.planning.reload()
                // The open search fetches its events again.
                self?.activeSearch?.eventStoreChanged()
                // The shopping list follows here, because the stream has room for one consumer only.
                await self?.shopping.reload()
                // Deadline calendar events may have changed; this is the only consumer of `changes`.
                self?.notifications.scheduleSoon()
                // Today's events may have changed while "Planen" shows another period.
                self?.scheduleSnapshot()
                self?.storeChangesHandled += 1
                self?.isHandlingStoreChange = false
            }
        }
    }

    /// Reschedules notifications whenever tasks, source states or notification settings change.
    /// The first value arrives at once and schedules after the start.
    /// Re-plans the routine reminders when the bedtime, the checklist or one of the switches changes.
    func startRoutineReminderUpdates() {
        guard routineUpdates == nil else { return }
        // An untouched three-point list of an earlier version is replaced before the first reminders are planned.
        routineStore.replaceLegacySuggestion()
        // Once per installation: "Helle Lichter ausmachen" of an untouched five-point list reminds 60 minutes before bedtime.
        if !settings.lightsOffsetUpgradeDone {
            settings.lightsOffsetUpgradeDone = true
            routineStore.upgradeLightsOffset()
        }
        let changes = Observations { @MainActor [weak self] () -> Int in
            guard let self else { return 0 }
            var hasher = Hasher()
            hasher.combine(settings.bedtimeMinutes)
            hasher.combine(settings.eveningRemindersEnabled)
            hasher.combine(settings.morningReminderEnabled)
            hasher.combine(settings.morningReminderMinutes)
            hasher.combine(settings.weekPlanningReminderEnabled)
            hasher.combine(settings.weekPlanningReminderWeekday)
            hasher.combine(settings.weekPlanningReminderMinutes)
            hasher.combine(settings.bibleStudyReminderEnabled)
            hasher.combine(settings.bibleStudyReminderTimesData)
            hasher.combine(settings.bibleStudyReminderShowsPassage)
            hasher.combine(settings.bibleStudySkippedDayKey)
            hasher.combine(routineStore.checklist())
            return hasher.finalize()
        }
        routineUpdates = Task { [weak self] in
            var last: Int?
            for await value in changes where value != last {
                last = value
                await self?.routineNotifications.reschedule()
            }
        }
    }

    /// The habit sources of the routines (a closed wrap-up, a written journal entry, a completed Bible Study session) live in
    /// other stores. Every write there bumps a `revision`; the habits read their facts again, so the rows and the counter follow
    /// without opening the tab or relaunching.
    func startHabitSourceUpdates() {
        guard habitSourceUpdates == nil else { return }
        let changes = Observations { @MainActor [weak self] () -> Int in
            guard let self else { return 0 }
            var hasher = Hasher()
            hasher.combine(notes.revision)
            hasher.combine(routineStore.revision)
            return hasher.finalize()
        }
        habitSourceUpdates = Task { [weak self] in
            var last: Int?
            for await value in changes where value != last {
                last = value
                self?.habits.refreshLocal()
            }
        }
    }

    /// Keeps today's focus marks in line with the tasks after every load (design: a task that left the list is done once
    /// its source has answered).
    func startFocusUpdates() {
        guard focusUpdates == nil else { return }
        let changes = Observations { @MainActor [weak self] () -> Int in
            guard let self else { return 0 }
            var hasher = Hasher()
            hasher.combine(taskList.items.map { "\($0.id.key)|\($0.title)" })
            hasher.combine(taskList.sourceStates.mapValues { String(describing: $0) })
            hasher.combine(taskList.loadingSources)
            return hasher.finalize()
        }
        focusUpdates = Task { [weak self] in
            var last: Int?
            for await value in changes where value != last {
                last = value
                self?.routines.refreshFocus()
            }
        }
    }

    func startNotificationUpdates() {
        guard notificationUpdates == nil else { return }
        // "Only this one" lists of repeating tasks are useless once the series moved on.
        reminderOverrides.removeStaleOnlyDue(today: PlanDay(date: .now, calendar: planning.calendar))
        // Marking or unmarking a deadline event changes the notifications and the widget's deadline rows.
        planning.onDeadlinesChanged = { [weak self] in
            self?.notifications.scheduleSoon()
            self?.scheduleSnapshot()
        }
        let changes = Observations { @MainActor [weak self] () -> Int in
            guard let self else { return 0 }
            var hasher = Hasher()
            hasher.combine(taskList.items)
            hasher.combine(taskList.sourceStates.mapValues { String(describing: $0) })
            hasher.combine(settings.leadTimeMinutes)
            hasher.combine(settings.reminderDefaultsData)
            hasher.combine(reminderOverrides.revision)
            hasher.combine(settings.deadlineCalendarNotifications)
            hasher.combine(settings.notifiedTaskSources)
            hasher.combine(settings.deadlineCalendarIDs)
            // Quiet hours; the bedtime counts while the window starts at it.
            hasher.combine(settings.quietHoursEnabled)
            hasher.combine(settings.quietHoursStartsAtBedtime)
            hasher.combine(settings.quietStartMinutes)
            hasher.combine(settings.quietEndMinutes)
            hasher.combine(settings.bedtimeMinutes)
            hasher.combine(settings.focusQuietSince)
            return hasher.finalize()
        }
        notificationUpdates = Task { [weak self] in
            var last: Int?
            for await value in changes where value != last {
                last = value
                self?.notifications.scheduleSoon()
            }
        }
    }

    /// The weekly review (phase 4); completed reminders only from the selected lists and with full access.
    func makeWeekReviewModel() -> WeekReviewModel {
        let reminderStore = self.reminderStore
        let settings = self.settings
        let local = LocalTaskProvider(context: modelContainer.mainContext)
        var closedIssueDates: (@MainActor (DateInterval) async throws -> [Date])?
        if let gitHub = taskList.provider(for: .github) as? GitHubTaskProvider {
            closedIssueDates = { interval in try await gitHub.closedIssueDates(in: interval) }
        }
        return WeekReviewModel(store: intake, health: health, settings: settings, budgets: budgets, calendar: capture.calendar,
                               completedReminders: { [weak self] interval in
                                   await reminderStore.completionDates(in: interval, listIDs: self?.taskReminderListIDs())
                               },
                               completedLocalTasks: { interval in local.completionDates(in: interval) },
                               habits: habits, routineStore: routineStore,
                               openPlanWeek: { [weak self] week in
                                   guard let self else { return }
                                   planning.scope = .week
                                   planning.anchor = week
                                   requestedTab = 0
                               },
                               // Closed GitHub issues of the week; `nil` while GitHub is not connected.
                               closedIssueDates: closedIssueDates)
    }

    /// The guided weekly planning (#164): the weekly review moved to the reviewed week, plus the deadlines of the planned one.
    func makeWeekPlanningModel() -> WeekPlanningModel {
        let taskList = self.taskList, planning = self.planning
        return WeekPlanningModel(
            weekReview: makeWeekReviewModel(), calendar: capture.calendar,
            tasks: { taskList.items.filter { !$0.isCompleted } },
            deadlineEvents: { range in
                await planning.planInputs(in: range).flatMap { day in
                    day.events.filter(\.deadline).map { WeekPlanningModel.DeadlineEvent(title: $0.title, day: day.day) }
                }
            })
    }

    // MARK: Widget snapshot (phase 4 design §4.1)

    /// The snapshot for today and the next two days; reads EventKit and SwiftData, never the network.
    func makeSnapshot(now: Date = .now) -> WidgetSnapshot {
        let today = PlanDay(date: now, calendar: planning.calendar)
        return WidgetSnapshot.make(createdAt: now, days: planning.snapshotInput(from: today, days: 3),
                                   todayIntake: snapshotIntake(on: today),
                                   todayHabits: snapshotHabits(existing: snapshotWriter.current(), now: now),
                                   showsNutrition: settings.widgetShowsNutrition, calendar: planning.calendar)
    }

    /// Today's habit counter. While Health values are not current (a cold start, a background run, a failed read) a
    /// counter calculated without them could be lower than the real one; then the last written counter of the same day
    /// is kept when it is higher (design §10: "last known values").
    private func snapshotHabits(existing: WidgetSnapshot?, now: Date) -> SnapshotHabits? {
        habits.refreshLocal(notify: false)
        let calendar = planning.calendar
        guard habits.today == PlanDay(date: now, calendar: calendar), let counter = habits.todayCounter else { return nil }
        if !habits.hasCurrentHealthFacts, let old = existing?.habits(at: now, calendar: calendar), old.total == counter.total {
            return SnapshotHabits(done: max(old.done, counter.done), total: counter.total)
        }
        return counter
    }

    /// The day's figures straight from the stores: correct after midnight and on a background launch without a reload. The budget
    /// comes from the same place as the head of "Erfassen" (`DayBudgets`), so the widget shows the same number. Steps come from the
    /// last Health read of the capture model and only while they belong to today; like calories and water they stay out of the
    /// file when the nutrition switch is off.
    private func snapshotIntake(on day: PlanDay) -> SnapshotIntake? {
        guard settings.widgetShowsNutrition else { return nil }
        let figures = budgets.figures(on: day)
        let steps = day == capture.today ? capture.todaySteps : nil
        return SnapshotIntake(kcal: figures.totals.kcal, hasEstimate: figures.totals.hasEstimate, goalKcal: figures.plan.kcal,
                              waterMilliliters: figures.totals.waterMilliliters, goalWaterMilliliters: figures.plan.waterMilliliters,
                              steps: steps, goalSteps: figures.plan.stepsPerDay, creditedKcal: figures.budget.credited)
    }

    /// Writes the snapshot. The plan part is only written from loaded task sources; otherwise (Siri in the
    /// background, a refresh that ran out of time) only today's intake of the existing file is replaced.
    func writeSnapshot(now: Date = .now) {
        guard settings.setupCompleted else {
            snapshotWriter.write(WidgetSnapshot(createdAt: now, days: []))
            return
        }
        if taskList.allSourcesSettled {
            snapshotWriter.write(makeSnapshot(now: now))
        } else if let existing = snapshotWriter.current() {
            let today = PlanDay(date: now, calendar: planning.calendar)
            snapshotWriter.write(existing.replacingToday(intake: snapshotIntake(on: today),
                                                         habits: snapshotHabits(existing: existing, now: now),
                                                         on: today, createdAt: now))
        }
    }

    /// Writes the snapshot one second after the last change (several changes arrive together).
    func scheduleSnapshot() {
        pendingSnapshot?.cancel()
        pendingSnapshot = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.writeSnapshot()
        }
    }

    /// The habits active today, as names and symbols only, for the configuration dialog of the habit control (#167).
    func writeControlHabits() {
        guard let controlState else { return }
        let today = habits.today
        controlState.writeHabits(habits.habits.filter { HabitRules.isActive($0, on: today, today: today) }
            .map { ControlHabit(id: $0.id, name: $0.name, symbol: $0.symbol) })
    }

    /// Rewrites the snapshot whenever the plan, tasks, today's intake or the widget-relevant settings change.
    func startSnapshotUpdates() {
        guard snapshotUpdates == nil else { return }
        capture.onTodayChanged = { [weak self] in
            self?.habits.refreshLocal()
            self?.scheduleSnapshot()
        }
        habits.onChanged = { [weak self] in self?.scheduleSnapshot() }
        habits.onListChanged = { [weak self] in
            TagwerkShortcuts.updateAppShortcutParameters()
            self?.writeControlHabits()
        }
        writeControlHabits()
        // Refreshes the speakable article names once at start; later changes are reported by the hook that
        // `TagwerkApp` installs at launch (it must also exist when an intent launches the app in the background).
        TagwerkShortcuts.updateAppShortcutParameters()
        let changes = Observations { @MainActor [weak self] () -> Int in
            guard let self else { return 0 }
            var hasher = Hasher()
            for day in planning.days {
                for event in day.events + day.blocks {
                    hasher.combine(event.id)
                    hasher.combine(event.title)
                    hasher.combine(event.start)
                    hasher.combine(event.end)
                }
                hasher.combine(day.deadlines)
            }
            hasher.combine(taskList.items)
            hasher.combine(taskList.sourceStates.mapValues { String(describing: $0) })
            hasher.combine(settings.setupCompleted)
            hasher.combine(settings.widgetShowsNutrition)
            hasher.combine(settings.goalKilocalories)
            hasher.combine(settings.goalWaterMilliliters)
            // The budget follows the plan, the Health values of today and the switches; a change there rewrites the file.
            hasher.combine(capture.todayFigures)
            hasher.combine(settings.selectedCalendarIDs)
            hasher.combine(settings.planCalendarID)
            hasher.combine(settings.deadlineCalendarIDs)
            hasher.combine(capture.todayIntake)
            hasher.combine(capture.todaySteps)
            hasher.combine(settings.goalStepsPerDay)
            hasher.combine(habits.todayCounter)
            return hasher.finalize()
        }
        snapshotUpdates = Task { [weak self] in
            var last: Int?
            for await value in changes where value != last {
                last = value
                self?.scheduleSnapshot()
            }
        }
    }
}
