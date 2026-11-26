import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct ProjectProgressStoreTests {
    private let github = ProjectProgressReference(kind: .gitHubProject, id: "PVT_1", title: "Projekt")
    private let list = ProjectProgressReference(kind: .remindersList, id: "list-1", title: "Liste")
    private let calendar = testCalendar()

    /// Counts the loads per project and answers from `answers`; a missing answer fails.
    @MainActor
    final class Recorder {
        var loads: [String: Int] = [:]
        var answers: [String: Result<ProjectFactsLoad, ProjectLoadFailure>] = [:]
        var catalog = ProjectCatalog(references: [], gitHubConnected: true, remindersAccess: true)
        var clock = testNow()
        var gate: Gate?

        func sources() -> ProjectProgressSources {
            ProjectProgressSources(
                catalog: { self.catalog },
                facts: { reference in
                    self.loads[reference.key, default: 0] += 1
                    if let gate = self.gate { await gate.wait() }
                    switch self.answers[reference.key] {
                    case .success(let load)?: return load
                    case .failure(let failure)?: throw failure
                    case nil: throw ProjectLoadFailure.other
                    }
                })
        }
    }

    private func load(_ facts: [ProjectItemFact] = [], at date: Date = testNow()) -> ProjectFactsLoad {
        ProjectFactsLoad(facts: facts, fetchedAt: date)
    }

    private func makeStore(_ recorder: Recorder) -> ProjectProgressStore {
        ProjectProgressStore(sources: recorder.sources(), now: { recorder.clock })
    }

    @Test func load_storesTheFacts() async {
        let recorder = Recorder()
        recorder.answers[github.key] = .success(load([ProjectItemFact(id: "a", title: "A")]))
        let store = makeStore(recorder)
        await store.load(github)
        #expect(store.facts(of: github)?.facts.map(\.id) == ["a"])
        if case .loaded = store.state(of: github) {} else { Issue.record("expected loaded") }
    }

    @Test func load_aFreshResultIsNotLoadedAgain() async {
        let recorder = Recorder()
        recorder.answers[github.key] = .success(load())
        let store = makeStore(recorder)
        await store.load(github)
        recorder.clock = recorder.clock.addingTimeInterval(ProjectProgressStore.maxAge - 1)
        await store.load(github)
        #expect(recorder.loads[github.key] == 1)
    }

    @Test func load_anOldResultIsLoadedAgain_andForceAlwaysLoads() async {
        let recorder = Recorder()
        recorder.answers[github.key] = .success(load(at: recorder.clock))
        let store = makeStore(recorder)
        await store.load(github)
        await store.load(github, force: true)
        #expect(recorder.loads[github.key] == 2)
        recorder.clock = recorder.clock.addingTimeInterval(ProjectProgressStore.maxAge + 1)
        await store.load(github)
        #expect(recorder.loads[github.key] == 3)
    }

    @Test func load_twoCallsAtOnceStartOneRequest() async {
        let recorder = Recorder()
        recorder.answers[github.key] = .success(load())
        let gate = Gate()
        recorder.gate = gate
        let store = makeStore(recorder)
        async let first: Void = store.load(github)
        async let second: Void = store.load(github)
        await Task.yield()
        gate.open()
        _ = await (first, second)
        #expect(recorder.loads[github.key] == 1)
    }

    @Test func load_failureWithoutEarlierResult_hasNoFacts() async {
        let recorder = Recorder()
        recorder.answers[github.key] = .failure(.offline)
        let store = makeStore(recorder)
        await store.load(github)
        #expect(store.state(of: github) == .failed(.offline, stale: nil))
        #expect(store.facts(of: github) == nil)
    }

    @Test func load_failureKeepsTheEarlierResult() async {
        let recorder = Recorder()
        let first = load([ProjectItemFact(id: "a", title: "A")], at: recorder.clock)
        recorder.answers[github.key] = .success(first)
        let store = makeStore(recorder)
        await store.load(github)
        recorder.answers[github.key] = .failure(.rateLimited)
        await store.load(github, force: true)
        #expect(store.state(of: github) == .failed(.rateLimited, stale: first))
        #expect(store.facts(of: github) == first)
    }

    @Test func loadAll_readsTheCatalogAndEveryProject() async {
        let recorder = Recorder()
        recorder.catalog.references = [github, list]
        recorder.answers[github.key] = .success(load())
        recorder.answers[list.key] = .failure(.noAccess)
        let store = makeStore(recorder)
        #expect(!store.isCatalogLoaded)
        await store.loadAll()
        #expect(store.isCatalogLoaded)
        #expect(store.catalog.references == [github, list])
        #expect(store.state(of: github) == .loaded(load()))
        #expect(store.state(of: list) == .failed(.noAccess, stale: nil), "a project without access shows its reason and does not stop the others")
    }

    @Test func loadAll_withoutGitHub_stillListsTheOtherSources() async {
        let recorder = Recorder()
        recorder.catalog = ProjectCatalog(references: [list], gitHubConnected: false, remindersAccess: true)
        recorder.answers[list.key] = .success(load())
        let store = makeStore(recorder)
        await store.loadAll()
        #expect(store.catalog.gitHubConnected == false)
        #expect(recorder.loads[github.key] == nil)
    }

    @Test func entrySubtitle_isNilUntilSomethingIsLoaded_andNeverStartsALoad() async {
        let recorder = Recorder()
        recorder.catalog.references = [github]
        let store = makeStore(recorder)
        #expect(store.entrySubtitle(calendar: calendar) == nil)
        #expect(recorder.loads.isEmpty)
    }

    @Test func entrySubtitle_countsProjectsAndRestingOnes() async {
        let recorder = Recorder()
        recorder.catalog.references = [github, list]
        let now = recorder.clock
        let old = now.addingTimeInterval(-30 * 86_400)
        recorder.answers[github.key] = .success(load([ProjectItemFact(id: "a", title: "A", createdAt: now.addingTimeInterval(-86_400))]))
        recorder.answers[list.key] = .success(load([ProjectItemFact(id: "b", title: "B", createdAt: old)]))
        let store = makeStore(recorder)
        await store.loadAll()
        let subtitle = store.entrySubtitle(calendar: calendar)
        #expect(subtitle?.contains("2") == true)
        #expect(subtitle?.contains("1") == true)
    }
}
