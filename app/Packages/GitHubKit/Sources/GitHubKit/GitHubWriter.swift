import Foundation
import TagwerkCore

/// Closing or reopening an issue.
public enum IssueStateChange: Sendable, Equatable {
    case close, reopen
    /// Closed as "not planned" – Tagwerk's "delete" for issues, which are never deleted on GitHub.
    case closeNotPlanned
}

/// Value of a project field. Single-select values are given by option name.
public enum ProjectFieldValue: Sendable, Equatable {
    case date(DueDate)
    case singleSelect(String)
    case number(Double)
}

/// Writes issue fields (REST) and project fields (GraphQL).
struct GitHubWriter: Sendable {
    let api: GitHubAPI

    /// One PATCH with only the given fields. `body: .some(nil)` clears the description.
    func updateIssue(_ record: GitHubIssueRecord, title: String?, body: String??, labels: [String]?,
                     state: IssueStateChange?) async throws {
        let patch = IssuePatch(title: title, body: body, labels: labels, state: state)
        guard !patch.isEmpty else { return }
        try await api.rest("PATCH", "repos/\(record.repository)/issues/\(record.number)", body: patch)
    }

    /// Sets or clears (`nil`) a field of one project item. Projects without the field are skipped,
    /// as are single-select values without a matching option.
    func setField(_ placement: ProjectPlacement, fieldName: String, value: ProjectFieldValue?) async throws {
        guard let field = placement.project.field(named: fieldName) else { return }
        guard let value else {
            let _: Ignored = try await api.query(Self.clearMutation, variables: FieldTarget(
                project: placement.project.id, item: placement.itemID, field: field.id))
            return
        }
        let encoded: FieldValue
        switch value {
        case .date(let due):
            encoded = .date(String(format: "%04d-%02d-%02d", due.year, due.month, due.day))
        case .number(let number):
            encoded = .number(number)
        case .singleSelect(let optionName):
            guard let optionID = field.options[optionName] else { return }
            encoded = .option(optionID)
        }
        let _: Ignored = try await api.query(Self.updateMutation, variables: FieldUpdate(
            project: placement.project.id, item: placement.itemID, field: field.id, value: encoded))
    }

    /// Creates an issue assigned to `assignee` and returns its node ID.
    func createIssue(repository: String, title: String, body: String?, assignee: String) async throws -> String {
        struct NewIssue: Encodable, Sendable { let title: String; let body: String?; let assignees: [String] }
        struct Created: Decodable { let node_id: String }
        let data = try await api.rest("POST", "repos/\(repository)/issues",
                                      body: NewIssue(title: title, body: body, assignees: [assignee]))
        do {
            return try JSONDecoder().decode(Created.self, from: data).node_id
        } catch {
            throw GitHubAPIError.decoding(String(describing: error))
        }
    }

    /// Adds an issue to a project and returns the new item ID.
    func addToProject(projectID: String, contentID: String) async throws -> String {
        struct Variables: Encodable, Sendable { let project: String; let content: String }
        struct Result: Decodable {
            struct Payload: Decodable { struct Item: Decodable { let id: String }; let item: Item }
            let addProjectV2ItemById: Payload
        }
        let result: Result = try await api.query(Self.addMutation, variables: Variables(project: projectID, content: contentID))
        return result.addProjectV2ItemById.item.id
    }

    func addComment(_ record: GitHubIssueRecord, body: String) async throws {
        try await api.rest("POST", "repos/\(record.repository)/issues/\(record.number)/comments", body: ["body": body])
    }

    // MARK: GraphQL

    static let updateMutation = """
    mutation($project: ID!, $item: ID!, $field: ID!, $value: ProjectV2FieldValue!) {
      updateProjectV2ItemFieldValue(input: {projectId: $project, itemId: $item, fieldId: $field, value: $value}) {
        projectV2Item { id }
      }
    }
    """

    static let addMutation = """
    mutation($project: ID!, $content: ID!) {
      addProjectV2ItemById(input: {projectId: $project, contentId: $content}) { item { id } }
    }
    """

    static let clearMutation = """
    mutation($project: ID!, $item: ID!, $field: ID!) {
      clearProjectV2ItemFieldValue(input: {projectId: $project, itemId: $item, fieldId: $field}) {
        projectV2Item { id }
      }
    }
    """

    struct Ignored: Decodable {}

    struct FieldTarget: Encodable, Sendable {
        let project: String
        let item: String
        let field: String
    }

    struct FieldUpdate: Encodable, Sendable {
        let project: String
        let item: String
        let field: String
        let value: FieldValue
    }

    enum FieldValue: Encodable, Sendable {
        case date(String), option(String), number(Double)

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: Key.self)
            switch self {
            case .date(let text): try container.encode(text, forKey: .date)
            case .option(let id): try container.encode(id, forKey: .singleSelectOptionId)
            case .number(let number): try container.encode(number, forKey: .number)
            }
        }

        enum Key: String, CodingKey { case date, singleSelectOptionId, number }
    }

    /// PATCH body that contains only the fields being changed.
    struct IssuePatch: Encodable, Sendable {
        let title: String?
        let body: String??
        let labels: [String]?
        let state: IssueStateChange?

        var isEmpty: Bool { title == nil && body == nil && labels == nil && state == nil }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: Key.self)
            try container.encodeIfPresent(title, forKey: .title)
            if let body {
                if let text = body { try container.encode(text, forKey: .body) } else { try container.encodeNil(forKey: .body) }
            }
            try container.encodeIfPresent(labels, forKey: .labels)
            switch state {
            case .close?:
                try container.encode("closed", forKey: .state)
                try container.encode("completed", forKey: .stateReason)
            case .closeNotPlanned?:
                try container.encode("closed", forKey: .state)
                try container.encode("not_planned", forKey: .stateReason)
            case .reopen?:
                try container.encode("open", forKey: .state)
            case nil:
                break
            }
        }

        enum Key: String, CodingKey {
            case title, body, labels, state
            case stateReason = "state_reason"
        }
    }
}
