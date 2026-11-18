import AIKit
import Foundation
import Observation

/// The ChatGPT side of the app: session, client, model choice and sign-in.
///
/// Nothing here contacts OpenAI on its own (design §8.4): the model list is loaded only when the
/// user opens the model page, plans or chats.
@MainActor
@Observable
final class AIEnvironment {
    /// The model list is fetched again after this age.
    static let modelListMaxAge: TimeInterval = 24 * 3600

    let session: ChatGPTSessionStore
    let client: ChatGPTClient
    private let settings: AppSettings
    @ObservationIgnored private let now: @Sendable () -> Date

    private(set) var isSignedIn = false
    private(set) var accountEmail: String?
    /// Selectable models in server order, from the last successful fetch.
    private(set) var models: [AIModel] = []
    private(set) var modelsFetchedAt: Date?
    /// Set when the chosen model disappeared and "Automatisch" took over; shown on the next call.
    var modelFallbackNotice = false

    init(session: ChatGPTSessionStore, client: ChatGPTClient, settings: AppSettings,
         now: @escaping @Sendable () -> Date = Date.init) {
        self.session = session
        self.client = client
        self.settings = settings
        self.now = now
        self.models = settings.aiModelsData.flatMap { try? JSONDecoder().decode([AIModel].self, from: $0) } ?? []
        self.modelsFetchedAt = settings.aiModelsFetchedAt
    }

    /// Reads the sign-in state from the keychain; sends nothing.
    func refreshAccount() async {
        isSignedIn = await session.isSignedIn
        accountEmail = await session.accountEmail
    }

    /// The model list, from the cache while it is younger than a day unless `force` is set.
    @discardableResult
    func loadModels(force: Bool = false) async throws -> [AIModel] {
        if !force, !models.isEmpty, let fetchedAt = modelsFetchedAt,
           now().timeIntervalSince(fetchedAt) < Self.modelListMaxAge {
            return models
        }
        let fresh = try await client.models()
        models = fresh
        modelsFetchedAt = now()
        settings.aiModelsData = try? JSONEncoder().encode(fresh)
        settings.aiModelsFetchedAt = modelsFetchedAt
        return fresh
    }

    /// The slug to use for a call: the chosen model if it still exists, otherwise the first one ("Automatisch").
    func selectedModel() async throws -> String {
        guard await session.isSignedIn else { throw ChatGPTError.notSignedIn }
        let list: [AIModel]
        do {
            list = try await loadModels()
        } catch let error as ChatGPTError where !models.isEmpty && error != .invalidUser && error != .notSignedIn {
            // A stale list is better than no call at all.
            list = models
        }
        if let slug = settings.aiModelSlug {
            if list.contains(where: { $0.slug == slug }) { return slug }
            settings.aiModelSlug = nil
            modelFallbackNotice = true
        }
        guard let first = list.first else { throw ChatGPTError.server(200, "no_models") }
        return first.slug
    }

    var selectedModelSlug: String? {
        get { settings.aiModelSlug }
        set { settings.aiModelSlug = newValue }
    }

    func signIn(authenticator: WebAuthenticating) async throws {
        try await ChatGPTLogin(session: session, authenticator: authenticator).signIn()
        await refreshAccount()
    }

    /// Deletes the tokens and forgets the model choice and list.
    func signOut() async {
        try? await session.signOut()
        settings.aiModelSlug = nil
        settings.aiModelsData = nil
        settings.aiModelsFetchedAt = nil
        models = []
        modelsFetchedAt = nil
        modelFallbackNotice = false
        await refreshAccount()
    }
}

extension AIEnvironment {
    /// Production wiring: keychain session and URLSession transport. With `-TagwerkDemoAI` in the
    /// simulator, a signed-in demo session with scripted answers instead.
    static func make(settings: AppSettings) -> AIEnvironment {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains(DemoAITransport.launchArgument) {
            let transport = DemoAITransport()
            let store = InMemoryChatGPTCredentialStore(tokens: DemoAITransport.tokens, clientID: "demo")
            let session = ChatGPTSessionStore(store: store, transport: transport)
            return AIEnvironment(session: session, client: ChatGPTClient(session: session, transport: transport), settings: settings)
        }
        #endif
        let transport = URLSessionAITransport()
        let session = ChatGPTSessionStore(store: KeychainChatGPTCredentialStore(), transport: transport)
        return AIEnvironment(session: session, client: ChatGPTClient(session: session, transport: transport), settings: settings)
    }
}
