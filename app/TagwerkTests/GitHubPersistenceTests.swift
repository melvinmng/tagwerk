import Foundation
import GitHubKit
import SecureStore
import SwiftData
import TagwerkCore
import Testing
@testable import Tagwerk

@MainActor
struct SwiftDataGitHubCacheTests {
    let container: ModelContainer
    let cache: SwiftDataGitHubCache

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        cache = SwiftDataGitHubCache(context: container.mainContext)
    }

    private func record(_ id: String, title: String = "Issue") -> GitHubIssueRecord {
        let project = ProjectInfo(id: "PVT_1", number: 1, title: "App", fields: [ProjectField(id: "F", name: "Due date", options: [:])])
        return GitHubIssueRecord(
            issueID: id, number: 1, repository: "beispiel/app", title: title, body: nil, isOpen: true,
            url: URL(string: "https://github.com/beispiel/app/issues/1")!, updatedAt: Date(timeIntervalSince1970: 10),
            labels: ["bug"], assignees: ["octo"],
            placements: [ProjectPlacement(project: project, itemID: "PVTI", itemUpdatedAt: Date(timeIntervalSince1970: 20),
                                          status: "Ready", priority: .p2, due: DueDate(year: 2026, month: 11, day: 20), estimateMinutes: 60)]
        )
    }

    @Test func cache_emptyInitially() {
        #expect(cache.load() == nil)
    }

    @Test func cache_roundTripsRecords() {
        let fetchedAt = Date(timeIntervalSince1970: 1_000)
        cache.store([record("I_1")], fetchedAt: fetchedAt)
        let loaded = cache.load()
        #expect(loaded?.records == [record("I_1")])
        #expect(loaded?.fetchedAt == fetchedAt)
    }

    @Test func cache_replacesPreviousSnapshot() {
        cache.store([record("I_1"), record("I_2")], fetchedAt: Date(timeIntervalSince1970: 1))
        cache.store([record("I_3", title: "Neu")], fetchedAt: Date(timeIntervalSince1970: 2))
        #expect(cache.load()?.records.map(\.issueID) == ["I_3"])
        #expect(cache.load()?.fetchedAt == Date(timeIntervalSince1970: 2))
    }

    @Test func cache_emptySnapshot_isRememberedAsEmpty() {
        cache.store([], fetchedAt: Date(timeIntervalSince1970: 5))
        #expect(cache.load()?.records.isEmpty == true)
        #expect(cache.load()?.fetchedAt == Date(timeIntervalSince1970: 5))
    }
}

struct KeychainCredentialStoreTests {
    let store = KeychainCredentialStore(secureStore: SecureStore(service: "com.melvinmng.tagwerk.tests.\(UUID().uuidString)"))

    @Test func credentials_roundTrip() throws {
        defer { try? store.delete() }
        let credentials = GitHubCredentials(accessToken: "gho_test", refreshToken: "ghr_test",
                                            accessExpiresAt: Date(timeIntervalSince1970: 100), refreshExpiresAt: nil)
        #expect(try store.load() == nil)
        try store.save(credentials)
        #expect(try store.load() == credentials)
        try store.delete()
        #expect(try store.load() == nil)
    }
}

@MainActor
struct AppSettingsGitHubTests {
    @Test func settings_selectedProjectIDs_defaultsToNil() throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        #expect(try AppSettings.current(in: container.mainContext).selectedProjectIDs == nil)
    }
}
