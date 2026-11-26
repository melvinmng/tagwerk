import Foundation
import GitHubKit
import RemindersKit
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct ProjectFactsMappingTests {
    private let created = Date(timeIntervalSince1970: 1_790_000_000)
    private let closed = Date(timeIntervalSince1970: 1_791_000_000)

    private func record(state: ProjectItemState = .open, blockedBy: Int = 0) -> ProjectItemRecord {
        ProjectItemRecord(issueID: "I_1", number: 7, repository: "octo/repo", title: "Titel", url: URL(string: "https://github.com/octo/repo/issues/7")!,
                          state: state, createdAt: created, closedAt: state == .open ? nil : closed, assignees: ["anna"], status: "Blocked",
                          due: DueDate(year: 2026, month: 12, day: 1), openBlockedByCount: blockedBy, openBlockingCount: 2)
    }

    @Test func gitHub_keepsTheFields() {
        let fact = ProjectFactsMapping.fact(record(blockedBy: 1), loadedTaskKeys: [])
        #expect(fact.id == "I_1" && fact.number == 7 && fact.title == "Titel")
        #expect(fact.createdAt == created && fact.closedAt == nil)
        #expect(fact.assignees == ["anna"] && fact.status == "Blocked")
        #expect(fact.openBlockedByCount == 1 && fact.openBlockingCount == 2)
        #expect(fact.isBlocked && fact.isBlocker)
    }

    @Test func gitHub_aLoadedTaskCanBeOpenedByItsKey() {
        let key = TaskID(source: .github, rawValue: "I_1").key
        #expect(ProjectFactsMapping.fact(record(), loadedTaskKeys: [key]).taskKey == key)
        #expect(ProjectFactsMapping.fact(record(), loadedTaskKeys: []).taskKey == nil, "a foreign issue is no task of the user")
    }

    @Test func gitHub_closedStatesStayApart() {
        #expect(ProjectFactsMapping.fact(record(state: .completed), loadedTaskKeys: []).state == .completed)
        #expect(ProjectFactsMapping.fact(record(state: .closedNotPlanned), loadedTaskKeys: []).state == .closedNotPlanned)
    }

    @Test func reminder_openAndCompleted() {
        let open = ReminderRecord(id: "r1", title: "Offen", notes: nil, due: nil, ekPriority: 0, isCompleted: false, listID: "l",
                                  lastModified: nil, createdAt: created)
        let done = ReminderRecord(id: "r2", title: "Fertig", notes: nil, due: nil, ekPriority: 0, isCompleted: true, listID: "l",
                                  lastModified: nil, createdAt: created, completedAt: closed)
        let openFact = ProjectFactsMapping.fact(open), doneFact = ProjectFactsMapping.fact(done)
        #expect(openFact.state == .open && openFact.closedAt == nil && openFact.createdAt == created)
        #expect(doneFact.state == .completed && doneFact.closedAt == closed)
        #expect(openFact.taskKey == "reminders:r1")
    }

    @Test func local_completedWithoutADateHasNoClosingTime() throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let task = LocalTask(title: "Alt", createdAt: created)
        task.isCompleted = true
        container.mainContext.insert(task)
        let fact = ProjectFactsMapping.fact(task)
        #expect(fact.state == .completed && fact.closedAt == nil && fact.createdAt == created)
        task.completedAt = closed
        #expect(ProjectFactsMapping.fact(task).closedAt == closed)
    }

    @Test func failure_mapsTheGitHubErrors() {
        #expect(ProjectFactsMapping.failure(GitHubAPIError.network("x")) == .offline)
        #expect(ProjectFactsMapping.failure(GitHubAPIError.http(403)) == .rateLimited)
        #expect(ProjectFactsMapping.failure(GitHubAPIError.http(429)) == .rateLimited)
        #expect(ProjectFactsMapping.failure(GitHubAPIError.http(500)) == .other)
        #expect(ProjectFactsMapping.failure(GitHubAPIError.graphQL("API rate limit exceeded")) == .rateLimited)
        #expect(ProjectFactsMapping.failure(GitHubAPIError.graphQL("boom")) == .other)
        #expect(ProjectFactsMapping.failure(URLError(.badURL)) == .other)
    }

    @Test func demoSources_giveFixedProjectsWithResting() async throws {
        let now = testNow()
        let sources = ProjectProgressSources.demo(now: { now })
        let catalog = await sources.catalog()
        #expect(catalog.references.count == 4)
        var restingTitles: [String] = []
        for reference in catalog.references {
            let load = try await sources.facts(reference)
            let summary = ProjectProgress.summary(facts: load.facts, period: .fourWeeks, now: now, calendar: Calendar.tagwerk)
            if ProjectProgressTexts.isResting(summary.trend) { restingTitles.append(reference.title) }
        }
        #expect(restingTitles == ["Studium"])
    }
}
