import Foundation
import GitHubKit
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
    let gitHubTokens: TokenManager
    let gitHubLoginClient: DeviceFlowClient
    let gitHub: GitHubTaskProvider
    private let gitHubCache: SwiftDataGitHubCache
    @ObservationIgnored private var changeObservation: Task<Void, Never>?

    init(modelContainer: ModelContainer) throws {
        self.modelContainer = modelContainer
        let context = modelContainer.mainContext
        let settings = try AppSettings.current(in: context)
        let gateway = EventKitGateway()
        let reminders = RemindersTaskProvider(store: gateway) {
            settings.selectedReminderListIDs.map(Set.init)
        }
        self.settings = settings
        self.gateway = gateway
        let taskList = TaskListModel(providers: [reminders, LocalTaskProvider(context: context)])
        self.taskList = taskList

        let clientID = Bundle.main.object(forInfoDictionaryKey: "GitHubClientID") as? String ?? ""
        let transport = URLSessionTransport()
        let loginClient = DeviceFlowClient(clientID: clientID, transport: transport)
        let tokens = TokenManager(store: KeychainCredentialStore(), client: loginClient)
        self.gitHubLoginClient = loginClient
        self.gitHubTokens = tokens
        let cache = SwiftDataGitHubCache(context: context)
        self.gitHubCache = cache
        self.gitHub = GitHubTaskProvider(
            api: GitHubAPI(transport: transport, tokens: tokens),
            tokens: tokens,
            cache: cache,
            selectedProjectIDs: { settings.selectedProjectIDs.map(Set.init) }
        )
        // An ended GitHub sign-in (expired or revoked) forgets the cached issues of that account.
        taskList.onSignedOut = { source in
            if source == .github { cache.clear() }
        }
    }

    /// Adds GitHub to the task list when credentials exist.
    func activateGitHubIfSignedIn() async {
        guard await gitHubTokens.isSignedIn, taskList.provider(for: .github) == nil else { return }
        await taskList.register(gitHub)
    }

    /// Removes GitHub from the task list after signing out and forgets cached issues.
    func deactivateGitHub() async {
        gitHubCache.clear()
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

    /// Reloads the list whenever Reminders or Calendar report a change.
    func startObservingChanges() {
        guard changeObservation == nil else { return }
        let changes = gateway.changes
        changeObservation = Task { [weak self] in
            for await _ in changes {
                await self?.taskList.reload()
            }
        }
    }
}
