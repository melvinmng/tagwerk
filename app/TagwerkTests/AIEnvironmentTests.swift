import AIKit
import Foundation
import SwiftData
import Testing
@testable import Tagwerk

@MainActor
struct AIEnvironmentTests {
    let transport = FakeAITransport()
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    /// Held for the whole test: settings objects die with their container.
    let container: ModelContainer

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
    }
    static let modelsBody = #"{"models":[{"slug":"gpt-a","display_name":"GPT-A","visibility":"list"},{"slug":"gpt-b","display_name":"GPT-B","visibility":"list"}]}"#

    func make(signedIn: Bool = true, slug: String? = nil, clock: @escaping @Sendable () -> Date) throws
        -> (AIEnvironment, AppSettings, InMemoryChatGPTCredentialStore) {
        let settings = try AppSettings.current(in: container.mainContext)
        settings.aiModelSlug = slug
        let store = InMemoryChatGPTCredentialStore(tokens: signedIn ? .valid(now: now) : nil, clientID: "oaiapp_test")
        let session = ChatGPTSessionStore(store: store, transport: transport, now: clock)
        let environment = AIEnvironment(session: session, client: ChatGPTClient(session: session, transport: transport),
                                        settings: settings, now: clock)
        return (environment, settings, store)
    }

    func make(signedIn: Bool = true, slug: String? = nil) throws -> (AIEnvironment, AppSettings, InMemoryChatGPTCredentialStore) {
        let now = self.now
        return try make(signedIn: signedIn, slug: slug, clock: { now })
    }

    @Test func creating_sendsNothing() async throws {
        let (environment, _, _) = try make()
        await environment.refreshAccount()
        #expect(environment.isSignedIn)
        #expect(transport.requests.isEmpty)
    }

    @Test func selectedModel_automatic_usesFirst() async throws {
        transport.enqueue("/v1/models", Self.modelsBody)
        let (environment, _, _) = try make()
        #expect(try await environment.selectedModel() == "gpt-a")
    }

    @Test func selectedModel_storedSlug_isUsed() async throws {
        transport.enqueue("/v1/models", Self.modelsBody)
        let (environment, _, _) = try make(slug: "gpt-b")
        #expect(try await environment.selectedModel() == "gpt-b")
        #expect(!environment.modelFallbackNotice)
    }

    @Test func selectedModel_storedSlugMissing_fallsBackToAutomatic() async throws {
        transport.enqueue("/v1/models", Self.modelsBody)
        let (environment, settings, _) = try make(slug: "gpt-gone")
        #expect(try await environment.selectedModel() == "gpt-a")
        #expect(settings.aiModelSlug == nil)
        #expect(environment.modelFallbackNotice)
    }

    @Test func models_cachedForADay_thenFetchedAgain() async throws {
        transport.enqueue("/v1/models", Self.modelsBody)
        transport.enqueue("/v1/models", Self.modelsBody)
        let clock = MutableClock(now)
        let (environment, _, _) = try make(clock: { clock.now })
        _ = try await environment.selectedModel()
        _ = try await environment.selectedModel()
        #expect(transport.requests.count == 1)
        clock.now = now.addingTimeInterval(25 * 3600)
        _ = try await environment.selectedModel()
        #expect(transport.requests.count == 2)
    }

    @Test func models_forceRefresh_fetchesAgain() async throws {
        transport.enqueue("/v1/models", Self.modelsBody)
        transport.enqueue("/v1/models", #"{"models":[{"slug":"gpt-c","display_name":"GPT-C","visibility":"list"}]}"#)
        let (environment, _, _) = try make()
        _ = try await environment.loadModels()
        let refreshed = try await environment.loadModels(force: true)
        #expect(refreshed.map(\.slug) == ["gpt-c"])
        #expect(environment.models.map(\.slug) == ["gpt-c"])
    }

    @Test func models_fetchFails_usesStaleCache() async throws {
        transport.enqueue("/v1/models", Self.modelsBody)
        let clock = MutableClock(now)
        let (environment, _, _) = try make(clock: { clock.now })
        _ = try await environment.loadModels()
        clock.now = now.addingTimeInterval(25 * 3600)
        #expect(try await environment.selectedModel() == "gpt-a")
    }

    @Test func models_survive_newEnvironment() async throws {
        transport.enqueue("/v1/models", Self.modelsBody)
        let settings = try AppSettings.current(in: container.mainContext)
        let now = self.now
        let store = InMemoryChatGPTCredentialStore(tokens: .valid(now: now))
        let session = ChatGPTSessionStore(store: store, transport: transport, now: { now })
        let client = ChatGPTClient(session: session, transport: transport)
        _ = try await AIEnvironment(session: session, client: client, settings: settings, now: { now }).loadModels()
        let second = AIEnvironment(session: session, client: client, settings: settings, now: { now })
        #expect(second.models.map(\.slug) == ["gpt-a", "gpt-b"])
        _ = try await second.selectedModel()
        #expect(transport.requests.count == 1)
    }

    @Test func signOut_clearsTokensAndModel() async throws {
        transport.enqueue("/v1/models", Self.modelsBody)
        let (environment, settings, store) = try make(slug: "gpt-b")
        _ = try await environment.loadModels()
        await environment.signOut()
        #expect(store.tokens == nil)
        #expect(settings.aiModelSlug == nil)
        #expect(environment.models.isEmpty)
        #expect(settings.aiModelsData == nil)
        #expect(!environment.isSignedIn)
    }

    @Test func selectedModel_signedOut_throwsNotSignedIn() async throws {
        let (environment, _, _) = try make(signedIn: false)
        await #expect(throws: ChatGPTError.notSignedIn) { try await environment.selectedModel() }
        #expect(transport.requests.isEmpty)
    }
}

/// A clock tests can move forward.
final class MutableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ start: Date) { value = start }
    var now: Date {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}
