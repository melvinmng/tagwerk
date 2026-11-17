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
    private let gitHubCache: SwiftDataGitHubCache
    private let gitHubCatalogStore: SwiftDataGitHubCatalogStore
    /// Age after which the repository/project catalog is fetched again.
    static let catalogMaxAge: TimeInterval = 5 * 60
    @ObservationIgnored private var changeObservation: Task<Void, Never>?
    @ObservationIgnored private var reconnectWatch: Task<Void, Never>?
    @ObservationIgnored private var pathMonitor: NWPathMonitor?

    init(modelContainer: ModelContainer) throws {
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
        let blockPlanner = BlockPlanner(store: gateway, planStore: planStore, links: EventLinkStore(context: context),
                                        settings: settings, calendar: .tagwerk)
        self.planning = PlanningModel(taskList: taskList, calendarStore: gateway, reminderStore: gateway, planStore: planStore,
                                      efforts: RecurringEffortStore(context: context), blocks: blockPlanner, settings: settings)

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
        SetupModel(store: gateway, settings: settings)
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
            }
        }
    }
}
