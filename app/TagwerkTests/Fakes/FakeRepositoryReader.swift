import Foundation
import GitHubKit
@testable import Tagwerk

/// Records which repository each read was for and answers with fixed contents.
@MainActor
final class FakeRepositoryReader: RepositoryReading {
    private(set) var requestedRepositories: [String] = []
    var comments: [IssueComment] = [IssueComment(author: "anna", body: "Sieht gut aus.", createdAt: "2026-11-17T09:00:00Z")]
    var neighbours = IssueNeighbours(labels: ["bug"], epic: IssueSummary(number: 2, title: "Epic", isOpen: true),
                                     siblings: [IssueSummary(number: 41, title: "Nachbar", isOpen: true)])

    func issueComments(repository: String, number: Int) async throws -> [IssueComment] {
        requestedRepositories.append(repository); return comments
    }
    func issueNeighbours(nodeID: String, selfNumber: Int) async throws -> IssueNeighbours { neighbours }
    func readme(repository: String) async throws -> String { requestedRepositories.append(repository); return "# Projekt" }
    func file(repository: String, path: String) async throws -> RepositoryContent {
        requestedRepositories.append(repository); return .file("Inhalt von \(path)")
    }
    func searchCode(repository: String, query: String) async throws -> [String] {
        requestedRepositories.append(repository); return ["Sources/Login.swift"]
    }
    func pullRequest(repository: String, number: Int) async throws -> PullRequestSummary {
        requestedRepositories.append(repository)
        return PullRequestSummary(number: number, title: "Fix", state: "open", merged: false, author: "anna", body: "",
                                  changedFiles: 1, additions: 2, deletions: 0, url: "https://github.com/x")
    }
}
