import AIKit
import Foundation
import GitHubKit
import TagwerkCore

/// Repository, number and node ID of the issue a chat is about.
struct IssueReference: Equatable, Sendable {
    let repository: String
    let number: Int
    let nodeID: String
}

/// Read access to GitHub for the issue chat; `GitHubAPI` in the app, a fake in tests.
@MainActor
protocol RepositoryReading: AnyObject {
    func issueComments(repository: String, number: Int) async throws -> [IssueComment]
    func issueNeighbours(nodeID: String, selfNumber: Int) async throws -> IssueNeighbours
    func readme(repository: String) async throws -> String
    func file(repository: String, path: String) async throws -> RepositoryContent
    func searchCode(repository: String, query: String) async throws -> [String]
    func pullRequest(repository: String, number: Int) async throws -> PullRequestSummary
}

/// `RepositoryReading` backed by the GitHub API.
@MainActor
final class GitHubRepositoryReader: RepositoryReading {
    private let api: GitHubAPI

    init(api: GitHubAPI) {
        self.api = api
    }

    func issueComments(repository: String, number: Int) async throws -> [IssueComment] {
        try await api.issueComments(repository: repository, number: number)
    }
    func issueNeighbours(nodeID: String, selfNumber: Int) async throws -> IssueNeighbours {
        try await api.issueNeighbours(nodeID: nodeID, selfNumber: selfNumber)
    }
    func readme(repository: String) async throws -> String { try await api.readme(repository: repository) }
    func file(repository: String, path: String) async throws -> RepositoryContent {
        try await api.file(repository: repository, path: path)
    }
    func searchCode(repository: String, query: String) async throws -> [String] {
        try await api.searchCode(repository: repository, query: query)
    }
    func pullRequest(repository: String, number: Int) async throws -> PullRequestSummary {
        try await api.pullRequest(repository: repository, number: number)
    }
}

/// The functions of a chat about one task: all app functions, plus for GitHub issues the read-only
/// repository functions, bound to the issue's repository (they take no repository argument).
@MainActor
final class TaskChatTools: ToolHandler {
    static let repositoryTools: Set<String> = [
        "get_issue_comments", "get_repository_readme", "get_repository_file", "search_repository", "get_pull_request",
    ]
    /// Repository texts are cut to keep the conversation small; `Conversation` clips at 16 KB as well.
    static let maxTextLength = 12_000

    let base: AppTools
    private let reader: RepositoryReading
    private let reference: IssueReference?

    init(base: AppTools, reader: RepositoryReading, reference: IssueReference?) {
        self.base = base
        self.reader = reader
        self.reference = reference
    }

    var definitions: [ToolDefinition] {
        base.definitions + (reference == nil ? [] : Self.repositoryDefinitions)
    }

    func kind(of name: String) -> ToolKind {
        Self.repositoryTools.contains(name) ? .read : base.kind(of: name)
    }

    func storedForm(of call: ToolCall, output: String?) -> (arguments: String, output: String?) {
        base.storedForm(of: call, output: output)
    }

    func showsActivity(_ name: String) -> Bool { base.showsActivity(name) }

    func run(_ call: ToolCall) async -> String {
        guard Self.repositoryTools.contains(call.name) else { return await base.run(call) }
        guard let reference else { return AppTools.error("Diese Aufgabe ist kein GitHub-Issue.") }
        let args = (try? JSONSerialization.jsonObject(with: call.arguments) as? [String: Any]) ?? [:]
        do {
            switch call.name {
            case "get_issue_comments":
                let comments = try await reader.issueComments(repository: reference.repository, number: reference.number)
                return AppTools.json(["comments": comments.map { ["author": $0.author, "body": Self.cut($0.body), "date": $0.createdAt] }])
            case "get_repository_readme":
                return AppTools.json(["readme": Self.cut(try await reader.readme(repository: reference.repository))])
            case "get_repository_file":
                guard let path = args["path"] as? String, !path.isEmpty else { return AppTools.error("Der Pfad fehlt.") }
                switch try await reader.file(repository: reference.repository, path: path) {
                case .file(let text): return AppTools.json(["path": path, "content": Self.cut(text)])
                case .directory(let entries): return AppTools.json(["path": path, "entries": Array(entries.prefix(200))])
                }
            case "search_repository":
                guard let query = args["query"] as? String, !query.isEmpty else { return AppTools.error("Die Suche fehlt.") }
                return AppTools.json(["files": try await reader.searchCode(repository: reference.repository, query: query)])
            case "get_pull_request":
                guard let number = (args["number"] as? NSNumber)?.intValue else { return AppTools.error("Die Nummer fehlt.") }
                let pull = try await reader.pullRequest(repository: reference.repository, number: number)
                return AppTools.json(["number": pull.number, "title": pull.title, "state": pull.state, "merged": pull.merged,
                                      "author": pull.author, "body": Self.cut(pull.body), "changedFiles": pull.changedFiles,
                                      "additions": pull.additions, "deletions": pull.deletions])
            default:
                return AppTools.error("Unbekannte Funktion \(call.name).")
            }
        } catch {
            return AppTools.error("GitHub ist gerade nicht erreichbar oder lehnt die Anfrage ab.")
        }
    }

    private static func cut(_ text: String) -> String {
        text.count > maxTextLength ? String(text.prefix(maxTextLength)) + " …[gekürzt]" : text
    }

    private static var repositoryDefinitions: [ToolDefinition] {
        func tool(_ name: String, _ description: String, _ properties: [String: [String: Any]]) -> ToolDefinition {
            let schema: [String: Any] = ["type": "object", "additionalProperties": false,
                                         "required": properties.keys.sorted(), "properties": properties]
            let data = (try? JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys])) ?? Data("{}".utf8)
            return ToolDefinition(name: name, description: description, parameters: data, strict: true)
        }
        return [
            tool("get_issue_comments", "Returns the comments of this issue.", [:]),
            tool("get_repository_readme", "Returns the README of this issue's repository.", [:]),
            tool("get_repository_file", "Returns a file or lists a directory of this issue's repository.",
                 ["path": ["type": "string", "description": "Path inside the repository, e.g. Sources/App.swift"]]),
            tool("search_repository", "Searches code in this issue's repository; returns matching file paths.",
                 ["query": ["type": "string"]]),
            tool("get_pull_request", "Returns a pull request of this issue's repository by number.",
                 ["number": ["type": "integer"]]),
        ]
    }
}

/// The context of a chat about one task, put into the instructions (design §8.3): the task, and for GitHub
/// issues comments, labels, projects, epic and neighbours, loaded from GitHub when the chat starts.
enum IssueContext {
    static let repositoryHint = "Du kannst README, Dateien, Suche und Pull Requests des Repos per Funktion holen; tu das, wenn die Frage es braucht."

    @MainActor
    static func load(task: TaskItem, reference: IssueReference?, reader: RepositoryReading?) async -> String {
        var lines: [String] = []
        let id = reference.map { "#\($0.number) in \($0.repository)" } ?? task.id.key
        lines.append("Das Gespräch betrifft die Aufgabe „\(task.title)“ (\(id), id \(task.id.key)).")
        if let due = task.due { lines.append("Fällig: \(AppTools.dueString(due))") }
        if let priority = task.priority { lines.append("Priorität: \(priority.label)") }
        if let minutes = task.estimateMinutes { lines.append("Aufwand: \(CapacityText.duration(minutes))") }
        if let labels = task.labels, !labels.isEmpty { lines.append("Labels: \(labels.joined(separator: ", "))") }
        if !task.subContainers.isEmpty { lines.append("Projects: \(task.subContainers.map(\.name).joined(separator: ", "))") }
        if let notes = task.notes, !notes.isEmpty { lines.append("Beschreibung:\n\(String(notes.prefix(4000)))") }
        guard let reference, let reader else { return lines.joined(separator: "\n") }

        if let neighbours = try? await reader.issueNeighbours(nodeID: reference.nodeID, selfNumber: reference.number) {
            if !neighbours.labels.isEmpty, task.labels?.isEmpty != false {
                lines.append("Labels: \(neighbours.labels.joined(separator: ", "))")
            }
            if let epic = neighbours.epic {
                lines.append("Gehört zu Epic #\(epic.number) „\(epic.title)“.")
                if !neighbours.siblings.isEmpty {
                    let siblings = neighbours.siblings.prefix(20).map { "#\($0.number) \($0.title)\($0.isOpen ? "" : " (geschlossen)")" }
                    lines.append("Weitere Issues im Epic: \(siblings.joined(separator: "; "))")
                }
            }
        }
        if let comments = try? await reader.issueComments(repository: reference.repository, number: reference.number), !comments.isEmpty {
            lines.append("Kommentare (\(comments.count)):")
            lines += comments.suffix(15).map { "- \($0.author): \(String($0.body.prefix(800)))" }
        }
        lines.append(repositoryHint)
        return lines.joined(separator: "\n")
    }
}
