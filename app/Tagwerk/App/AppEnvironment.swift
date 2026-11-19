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
    /// Notes stored on this device only (phase 5); never sent to ChatGPT.
    let notes: NoteStore
    let taskList: TaskListModel
    let planning: PlanningModel
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
    /// Deadline notifications (design 2b §9); never calls an AI feature.
    let notifications: NotificationScheduler
    /// Target of a tapped notification until the app shows it.
    let notificationNavigator = NotificationNavigator()
    /// Target of a `tagwerk://` link or a shortcut until the app shows it (phase 4).
    let router = AppRouter()
    /// Delegate of the system notification center; held here because the center keeps it weakly.
    @ObservationIgnored private(set) lazy var notificationDelegate = NotificationDelegate(navigator: notificationNavigator)
    /// Meals, water and workouts (phase 3); mirrored to Health only after the user allowed it.
    let intake: IntakeStore
    let health: any HealthStoring
    let healthMirror: HealthMirror
    let capture: CaptureModel
    /// Meal estimates with ChatGPT; only after consent and a tap (main design §7).
    let mealEstimator: MealEstimator
    /// Writes the snapshot file the widget reads (phase 4); `directory == nil` in tests and unsigned builds.
    let snapshotWriter: WidgetSnapshotWriter
    /// Reads events for the search away from the main thread; its own read-only store.
    let eventSearcher: any EventSearching
    /// Reminders as tasks; also the source of the completed ones for the search.
    private let remindersProvider: RemindersTaskProvider
    /// The search sheet is open. Set through `openSearch()`; assistant, notifications and links close it.
    var isSearchPresented = false
    /// The model of the open (or last) search sheet; it holds nothing after `close()`.
    @ObservationIgnored private(set) var activeSearch: SearchModel?
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
    @ObservationIgnored private var notificationUpdates: Task<Void, Never>?
    @ObservationIgnored private var gitHubRegistration: Task<Void, Never>?
    @ObservationIgnored private var snapshotUpdates: Task<Void, Never>?
    @ObservationIgnored private var pendingSnapshot: Task<Void, Never>?

    /// `notificationCenter` defaults to the system center, `health` to HealthKit and `reminderStore` to the
    /// EventKit gateway; tests and demo data pass fakes.
    init(modelContainer: ModelContainer, notificationCenter: (any NotificationCenterClient)? = nil,
         health: (any HealthStoring)? = nil, snapshotWriter: WidgetSnapshotWriter? = nil,
         reminderStore: (any ReminderStore)? = nil, eventSearcher: (any EventSearching)? = nil) throws {
        self.modelContainer = modelContainer
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
        self.notes = NoteStore(context: context)
        let shoppingCategories = ShoppingCategoryStore(context: context, settings: settings)
        self.shoppingCategories = shoppingCategories
        self.shopping = ShoppingModel(store: reminderStore, settings: settings, categories: shoppingCategories)
        let taskList = TaskListModel(providers: [reminders, LocalTaskProvider(context: context)])
        self.taskList = taskList
        let planStore = PlanStore(context: context)
        let suggestionStore = SuggestionStore(context: context)
        let blockPlanner = BlockPlanner(store: gateway, planStore: planStore, links: EventLinkStore(context: context),
                                        settings: settings, calendar: .tagwerk)
        self.planning = PlanningModel(taskList: taskList, calendarStore: gateway, reminderStore: reminderStore, planStore: planStore,
                                      efforts: RecurringEffortStore(context: context), blocks: blockPlanner, settings: settings,
                                      marks: EventMarkStore(context: context), suggestions: suggestionStore)

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
        self.notifications = NotificationScheduler(
            center: notificationCenter ?? SystemNotificationCenter(), taskList: taskList,
            deadlineEvents: { interval, ids in
                gateway.calendarAccessState == .fullAccess ? gateway.events(in: interval, calendarIDs: ids) : nil
            },
            markedDeadlines: MarkedDeadlineSource(calendarIDs: { Set(deadlineMarks.marks().map(\.calendarID)) },
                                                  markedIDs: { deadlineMarks.markedIDs(in: $0) }),
            settings: settings)
        let healthStore = health ?? HealthKitStore()
        let intake = IntakeStore(context: context)
        let mirror = HealthMirror(store: intake, health: healthStore)
        self.health = healthStore
        self.intake = intake
        self.healthMirror = mirror
        self.capture = CaptureModel(store: intake, mirror: mirror, health: healthStore, settings: settings)
        self.mealEstimator = MealEstimator(responder: ai.client, model: { try await ai.selectedModel() },
                                           hasConsent: { settings.mealEstimationConsent })
        self.shoppingSorter = ShoppingSorter(responder: ai.client, model: { try await ai.selectedModel() },
                                             hasConsent: { settings.shoppingSortConsent })
        let planning = self.planning
        taskList.onCompletionChanged = { id, isCompleted in await planning.didChangeCompletion(id, isCompleted: isCompleted) }
        taskList.onHandedOver = { id in await planning.didHandOver(id) }
        // An ended GitHub sign-in (expired or revoked) forgets the cached issues of that account.
        taskList.onSignedOut = { source in
            if source == .github {
                cache.clear()
                catalogStore.clear()
            }
        }
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
            writeSnapshot: { [weak self] in self?.writeSnapshot() })
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

    /// Name of a note's kind in a search row.
    static func kindLabel(of kind: NoteKind) -> String {
        switch kind {
        case .free: String(localized: "Notiz")
        case .morning: String(localized: "Tagesstart")
        case .evening: String(localized: "Tagesabschluss")
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
                notes.notes().map { note in
                    NoteSearchItem(id: note.id, text: note.text, kindLabel: Self.kindLabel(of: note.kind), updatedAt: note.updatedAt,
                                   dayKey: note.kind == .free ? nil : note.dayKey)
                }
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
    func startNotificationUpdates() {
        guard notificationUpdates == nil else { return }
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
            hasher.combine(settings.deadlineCalendarNotifications)
            hasher.combine(settings.notifiedTaskSources)
            hasher.combine(settings.deadlineCalendarIDs)
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
                               completedLocalTasks: { interval in local.completionDates(in: interval) })
    }

    // MARK: Widget snapshot (phase 4 design §4.1)

    /// The snapshot for today and the next two days; reads EventKit and SwiftData, never the network.
    func makeSnapshot(now: Date = .now) -> WidgetSnapshot {
        let today = PlanDay(date: now, calendar: planning.calendar)
        return WidgetSnapshot.make(createdAt: now, days: planning.snapshotInput(from: today, days: 3),
                                   todayIntake: snapshotIntake(on: today), showsNutrition: settings.widgetShowsNutrition,
                                   calendar: planning.calendar)
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
            snapshotWriter.write(existing.replacingIntake(snapshotIntake(on: today), on: today, createdAt: now))
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

    /// Rewrites the snapshot whenever the plan, tasks, today's intake or the widget-relevant settings change.
    func startSnapshotUpdates() {
        guard snapshotUpdates == nil else { return }
        capture.onTodayChanged = { [weak self] in self?.scheduleSnapshot() }
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
