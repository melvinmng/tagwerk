import AIKit
import Foundation
import GitHubKit
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
    let settings: AppSettings
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
    /// Deadline notifications (design 2b §9); never calls an AI feature.
    let notifications: NotificationScheduler
    /// Target of a tapped notification until the app shows it.
    let notificationNavigator = NotificationNavigator()
    /// Delegate of the system notification center; held here because the center keeps it weakly.
    @ObservationIgnored private(set) lazy var notificationDelegate = NotificationDelegate(navigator: notificationNavigator)
    /// A tab another view asks to show (e.g. "Mit KI planen" from the task list jumps to "Planen").
    var requestedTab: Int?
    private let gitHubCache: SwiftDataGitHubCache
    private let gitHubCatalogStore: SwiftDataGitHubCatalogStore
    /// Age after which the repository/project catalog is fetched again.
    static let catalogMaxAge: TimeInterval = 5 * 60
    @ObservationIgnored private var changeObservation: Task<Void, Never>?
    @ObservationIgnored private var reconnectWatch: Task<Void, Never>?
    @ObservationIgnored private var pathMonitor: NWPathMonitor?
    @ObservationIgnored private var notificationUpdates: Task<Void, Never>?

    /// `notificationCenter` defaults to the system center; tests pass a fake so nothing reaches iOS.
    init(modelContainer: ModelContainer, notificationCenter: (any NotificationCenterClient)? = nil) throws {
        self.modelContainer = modelContainer
        let context = modelContainer.mainContext
        let settings = try AppSettings.current(in: context)
        let gateway = EventKitGateway()
        let reminders = RemindersTaskProvider(store: gateway, estimates: SwiftDataEstimateStore(context: context)) {
            settings.selectedReminderListIDs.map(Set.init)
        }
        self.settings = settings
        self.gateway = gateway
        let taskList = TaskListModel(providers: [reminders, LocalTaskProvider(context: context)])
        self.taskList = taskList
        let planStore = PlanStore(context: context)
        let suggestionStore = SuggestionStore(context: context)
        let blockPlanner = BlockPlanner(store: gateway, planStore: planStore, links: EventLinkStore(context: context),
                                        settings: settings, calendar: .tagwerk)
        self.planning = PlanningModel(taskList: taskList, calendarStore: gateway, reminderStore: gateway, planStore: planStore,
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
                             events: { interval in gateway.events(in: interval, calendarIDs: nil) })
        self.assistant = AssistantModel(responder: ai.client, tools: tools, model: { try await ai.selectedModel() },
                                        store: ChatStore(context: context), planning: planning)
        let gitHubProvider = self.gitHub
        assistant.reader = GitHubRepositoryReader(api: gitHubProvider.api)
        assistant.issueReference = { id in
            gitHubProvider.issueReference(for: id).map { IssueReference(repository: $0.repository, number: $0.number, nodeID: $0.nodeID) }
        }
        self.notifications = NotificationScheduler(
            center: notificationCenter ?? SystemNotificationCenter(), taskList: taskList,
            deadlineEvents: { interval, ids in
                gateway.calendarAccessState == .fullAccess ? gateway.events(in: interval, calendarIDs: ids) : nil
            },
            settings: settings)
        let planning = self.planning
        taskList.onCompletionChanged = { id, isCompleted in await planning.didChangeCompletion(id, isCompleted: isCompleted) }
        // An ended GitHub sign-in (expired or revoked) forgets the cached issues of that account.
        taskList.onSignedOut = { source in
            if source == .github {
                cache.clear()
                catalogStore.clear()
            }
        }
    }

    /// Adds GitHub to the task list when credentials exist.
    func activateGitHubIfSignedIn() async {
        guard await gitHubTokens.isSignedIn, taskList.provider(for: .github) == nil else { return }
        await taskList.register(gitHub)
        // Refresh repositories and project links at every start, so creating an issue needs no wait.
        _ = await gitHub.catalog(maxAge: 0)
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
        return SetupModel(store: gateway, settings: settings, calendarStore: gateway, isChatGPTSignedIn: ai.isSignedIn,
                          notificationsAllowed: notifications.authorization == .authorized,
                          requestNotifications: { await notifications.requestAuthorization() })
    }

    /// Current authorization of a source that needs system permission; `nil` for sources without one.
    func accessState(for source: TaskSource) -> AccessState? {
        source == .reminders ? gateway.accessState : nil
    }

    /// Asks the system for access (only possible while it is undetermined) and reloads the list.
    func requestAccess(for source: TaskSource) async {
        guard source == .reminders else { return }
        _ = try? await gateway.requestAccess()
        await taskList.reload()
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
                // Deadline calendar events may have changed; this is the only consumer of `changes`.
                self?.notifications.scheduleSoon()
            }
        }
    }

    /// Reschedules notifications whenever tasks, source states or notification settings change.
    /// The first value arrives at once and schedules after the start.
    func startNotificationUpdates() {
        guard notificationUpdates == nil else { return }
        let changes = Observations { @MainActor [weak self] () -> Int in
            guard let self else { return 0 }
            var hasher = Hasher()
            hasher.combine(taskList.items)
            hasher.combine(taskList.sourceStates.mapValues { String(describing: $0) })
            hasher.combine(settings.leadTimeMinutes)
            hasher.combine(settings.deadlineCalendarNotifications)
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
}
