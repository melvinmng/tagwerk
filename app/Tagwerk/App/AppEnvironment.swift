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
    /// Items the share extension left for the app (#165); read when the app becomes active, confirmed by the user.
    let shareInbox: ShareInboxModel
    /// "Mit ChatGPT zusammenfassen" on a shared mail (#166); sends only after consent and on the user's tap.
    let mailSummarizer: MailSummarizer
    /// Notes stored on this device only (phase 5); never sent to ChatGPT.
    let notes: NoteStore
    let backup: BackupService
    let taskList: TaskListModel
    let planning: PlanningModel
    /// Travel times before events with a place; asks Apple Maps only for addresses (#168).
    let travelTimes: TravelTimeService
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
    @ObservationIgnored private(set) lazy var notificationDelegate = NotificationDelegate(navigator: notificationNavigator, router: router)
    /// Meals, water and workouts (phase 3); mirrored to Health only after the user allowed it.
    let intake: IntakeStore
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
    /// A tab another view asks to show (e.g. "Mit KI planen" from the task list jumps to "Planen").
    var requestedTab: Int?
    /// Pages on top of the task list (shopping list, notes); a deep link sets it to open the shopping list.
    var tasksPath: [TasksDestination] = []
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

    init(modelContainer: ModelContainer, notificationCenter: (any NotificationCenterClient)? = nil,
         health: (any HealthStoring)? = nil, snapshotWriter: WidgetSnapshotWriter? = nil,
         reminderStore: (any ReminderStore)? = nil, eventSearcher: (any EventSearching)? = nil,
         focusNotificationCenter: (any FocusNotificationCenter)? = nil,
         travelTimes: TravelTimeService? = nil, shareInbox: ShareInbox? = nil,
         controlState: ControlState? = nil, controlReloader: ControlReloading? = nil) throws {
        self.modelContainer = modelContainer
        self.controlState = controlState
        self.snapshotWriter = snapshotWriter ?? WidgetSnapshotWriter(directory: nil, reload: {})
        let context = modelContainer.mainContext
        let settings = try AppSettings.current(in: context)
        settings.migrateWorkoutGoalIfNeeded()
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
        self.backup = BackupService(context: context, settings: settings, attachments: attachments, afterRestore: { [noteStore] in
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
                                 completedTasks: Self.searchCompletedSource(reminders: reminders, taskList: taskList)))
        self.assistant = AssistantModel(responder: ai.client, tools: tools, model: { try await ai.selectedModel() },
                                        store: ChatStore(context: context), planning: planning)
        self.voiceOutput = VoiceOutputModel(speaker: SystemSpeaker(), audio: SystemVoiceAudioSession.shared, preferences: {
            VoiceOutputModel.Preferences(germanVoiceID: settings.voiceGermanVoiceID, englishVoiceID: settings.voiceEnglishVoiceID,
                                         rate: settings.voiceRate)
        })
        let voiceOutput = self.voiceOutput
        assistant.readPolicy = { ReadAloudPolicy(rawValue: settings.voiceReadAloud) ?? .never }
        assistant.announcesActions = { settings.voiceAnnounceActions }
        assistant.fixedVoiceLanguage = { VoiceChatLanguage.fixed(setting: settings.voiceRecognitionLanguage) }
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
                VoiceModeController.Settings(language: VoiceAvailability.recognitionLanguage(setting: settings.voiceRecognitionLanguage),
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
        self.healthMirror = mirror
        self.capture = CaptureModel(store: intake, mirror: mirror, health: healthStore, settings: settings)
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
                                             hasConsent: { settings.shoppingSortConsent })
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
            })
        self.routineNotifications = RoutineNotificationScheduler(center: notificationCenter ?? SystemNotificationCenter(),
                                                                 store: routineStore, settings: settings)
        let routines = self.routines
        let focusStore = FocusStore(context: context)
        self.focusStore = focusStore
        let focus = FocusTimerModel(store: focusStore, settings: { settings.focusTimerSettings }, activity: FocusActivityController(),
                                    notifications: FocusNotificationScheduler(center: focusNotificationCenter),
                                    controlState: controlState, controlReloader: controlReloader)
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
            })
    }

    /// The background refresh: GitHub is registered without the catalog, every source loads once, then the
    /// notifications are rescheduled. Nothing here reaches an AI feature (§8.4).
    func makeBackgroundRefresh() -> BackgroundRefresh {
        BackgroundRefresh(
            prepare: { [weak self] in
                await self?.registerGitHubIfSignedIn() ?? false  // a registration loads all sources
            },
            reload: { [weak self] in await self?.taskList.reload() },
            reschedule: { [weak self] in await self?.notifications.reschedule() },
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

    /// A note as the search sees it. The search reads the plain text only: no Markdown, no HTML, no attachment references.
    static func searchItem(for note: NoteRecord, folderNames: [UUID: String]) -> NoteSearchItem {
        let folderName = note.kind == .free ? note.folderID.flatMap { folderNames[$0] } : nil
        return NoteSearchItem(id: note.id, text: MarkdownText.plainText(note.text), kindLabel: folderName ?? kindLabel(of: note.kind),
                              updatedAt: note.updatedAt, dayKey: note.kind == .free || note.kind == .bibleStudy ? nil : note.dayKey)
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
        var searchOnline: (@MainActor (String) async throws -> [OnlineIssue])?
        if isGitHubActive {
            searchOnline = { [weak self] text in
                guard let self, let gitHub = self.taskList.provider(for: .github) as? GitHubTaskProvider else {
                    throw IssueSearchError.signedOut
                }
                // Issues that are among the tasks already stay out; the search adds closed and unassigned ones.
                let loaded = Set(self.taskList.items.filter { $0.id.source == .github }.map(\.id.rawValue))
                return try await gitHub.searchOnline(text, excluding: loaded)
            }
        }
        let notes = self.notes
        let shopping = self.shopping
        var sources = SearchSources(
            openTasks: { sortedTasks(taskList.items, calendar: planning.calendar) },
            events: Self.searchEventSource(searcher: searcher, store: reminderStore, planning: planning, settings: settings),
            calendarNames: Self.searchCalendarNames(planning: planning),
            completedTasks: Self.searchCompletedSource(reminders: reminders, taskList: taskList),
            notes: {
                // A note in a folder shows the folder name as its label; the trash is not searched.
                let folderNames = Dictionary(notes.folders().map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
                return notes.notes().map { Self.searchItem(for: $0, folderNames: folderNames) }
            },
            shopping: {
                // Only open items of a list that is set up; completed ones stay out (spec F7).
                guard shopping.state == .ready else { return [] }
                return shopping.openItems.map { ShoppingSearchItem(id: $0.id, name: $0.name, quantity: $0.quantity) }
            },
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
        return WeekReviewModel(store: intake, health: health, settings: settings, calendar: capture.calendar,
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
                               })
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

    /// The day's sums straight from the store: correct after midnight and on a background launch without a reload.
    /// Steps come from the last Health read of the capture model and only while they belong to today; like calories
    /// and water they stay out of the file when the nutrition switch is off.
    private func snapshotIntake(on day: PlanDay) -> SnapshotIntake? {
        guard settings.widgetShowsNutrition else { return nil }
        let calendar = capture.calendar
        let intake = IntakeRules.dayIntake(meals: self.intake.meals(on: day, calendar: calendar),
                                           drinks: self.intake.drinks(on: day, calendar: calendar))
        let steps = day == capture.today ? capture.todaySteps : nil
        return SnapshotIntake(kcal: intake.kcal, hasEstimate: intake.hasEstimate, goalKcal: settings.goalKilocalories,
                              waterMilliliters: intake.waterMilliliters, goalWaterMilliliters: settings.goalWaterMilliliters,
                              steps: steps, goalSteps: settings.goalStepsPerDay)
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
