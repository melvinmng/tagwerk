/// GraphQL responses with invented data, shaped like the real GitHub API.
enum Fixtures {
    static let viewerProjects = """
    {"data":{"viewer":{"login":"octo","projectsV2":{"nodes":[
      {"id":"PVT_1","number":1,"title":"App","closed":false,"repositories":{"nodes":[{"nameWithOwner":"beispiel/app"}]},"fields":{"nodes":[
        {"id":"F_status","name":"Status","options":[{"id":"OPT_ready","name":"Ready"},{"id":"OPT_done","name":"Done"}]},
        {"id":"F_prio","name":"Priority","options":[{"id":"OPT_p2","name":"P2 (High)"},{"id":"OPT_p3","name":"P3 (Medium)"}]},
        {"id":"F_due","name":"Due date"},
        {"id":"F_est","name":"Estimate (h)"},
        {"id":"F_title","name":"Title"}
      ]}},
      {"id":"PVT_2","number":2,"title":"Studium","closed":false,"repositories":{"nodes":[{"nameWithOwner":"beispiel/studium"},{"nameWithOwner":"beispiel/app"}]},"fields":{"nodes":[
        {"id":"F2_status","name":"Status","options":[{"id":"OPT2_ready","name":"Ready"},{"id":"OPT2_done","name":"Done"}]},
        {"id":"F2_due","name":"Due date"},
        {"id":"F2_est","name":"Estimate (MDs)"}
      ]}}
    ]}}}}
    """

    static func issueContent(id: String, number: Int, state: String = "OPEN", assignee: String = "octo") -> String {
        """
        {"__typename":"Issue","id":"\(id)","number":\(number),"title":"Issue \(number)","body":"Beschreibung",
         "state":"\(state)","updatedAt":"2026-11-17T10:00:00Z","url":"https://github.com/beispiel/app/issues/\(number)",
         "repository":{"nameWithOwner":"beispiel/app"},"assignees":{"nodes":[{"login":"\(assignee)"}]},
         "labels":{"nodes":[{"name":"bug"}]}}
        """
    }

    /// Search page 1: issue 1 in projects 1 and 2 (plus an archived item), issue 3 in a project of
    /// another owner (readable) and in a closed project.
    static let assignedPage1 = """
    {"data":{"search":{"pageInfo":{"hasNextPage":true,"endCursor":"CURSOR_1"},"nodes":[
      \(issueWithItems(id: "I_1", number: 1, parent: epicParent, items: [
        #"{"id":"PVTI_a","updatedAt":"2026-11-17T11:00:00Z","isArchived":false,"project":{"id":"PVT_1"},"fieldValues":{"nodes":[{"name":"Ready","field":{"name":"Status"}},{"name":"P3 (Medium)","field":{"name":"Priority"}},{"date":"2026-11-20","field":{"name":"Due date"}},{"number":1.5,"field":{"name":"Estimate (h)"}},{}]}}"#,
        #"{"id":"PVTI_c","updatedAt":"2026-11-17T12:00:00Z","isArchived":false,"project":{"id":"PVT_2"},"fieldValues":{"nodes":[{"name":"Ready","field":{"name":"Status"}},{"date":"2026-11-18","field":{"name":"Due date"}},{"number":0.5,"field":{"name":"Estimate (MDs)"}}]}}"#,
        #"{"id":"PVTI_old","updatedAt":"2026-11-01T12:00:00Z","isArchived":true,"project":{"id":"PVT_1"},"fieldValues":{"nodes":[]}}"#,
      ])),
      \(issueWithItems(id: "I_3", number: 3, items: [
        #"{"id":"PVTI_f","updatedAt":"2026-11-17T12:00:00Z","isArchived":false,"project":{"id":"PVT_foreign","number":4,"title":"Team-Board","closed":false,"fields":{"nodes":[{"id":"FF_status","name":"Status","options":[{"id":"OPTF_ready","name":"Ready"},{"id":"OPTF_done","name":"Done"}]},{"id":"FF_due","name":"Due date"}]}},"fieldValues":{"nodes":[{"name":"Ready","field":{"name":"Status"}},{"date":"2026-11-25","field":{"name":"Due date"}}]}}"#,
        #"{"id":"PVTI_g","updatedAt":"2026-11-17T12:00:00Z","isArchived":false,"project":{"id":"PVT_closed","number":7,"title":"Alt","closed":true,"fields":{"nodes":[]}},"fieldValues":{"nodes":[]}}"#,
      ])),
      {}
    ]}}}
    """

    /// Search page 2: issue 2 is "Done" in project 1, issue 4 has only an archived item.
    static let assignedPage2 = """
    {"data":{"search":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
      \(issueWithItems(id: "I_2", number: 2, items: [
        #"{"id":"PVTI_b","updatedAt":"2026-11-17T11:00:00Z","isArchived":false,"project":{"id":"PVT_1"},"fieldValues":{"nodes":[{"name":"Done","field":{"name":"Status"}}]}}"#,
      ])),
      \(issueWithItems(id: "I_4", number: 4, items: [
        #"{"id":"PVTI_x","updatedAt":"2026-11-17T11:00:00Z","isArchived":true,"project":{"id":"PVT_1"},"fieldValues":{"nodes":[]}}"#,
      ]))
    ]}}}
    """

    static let epicParent = #"{"id":"E_1","number":10,"title":"Phase 2","labels":{"nodes":[{"name":"epic"}]},"projectItems":{"nodes":[{"project":{"id":"PVT_1"},"fieldValues":{"nodes":[{"name":"In progress","field":{"name":"Status"}},{"date":"2026-11-30","field":{"name":"Due date"}}]}}]}}"#

    static func issueWithItems(id: String, number: Int, parent: String? = nil, items: [String]) -> String {
        let content = issueContent(id: id, number: number)
        return String(content.trimmingCharacters(in: .whitespacesAndNewlines).dropLast())
            + (parent.map { #","parent":"# + $0 } ?? "")
            + #","projectItems":{"nodes":["# + items.joined(separator: ",") + "]}}"
    }

    /// Viewer with projects 1 and 2, then two pages of assigned issues.
    static func enqueueAssignedIssues(on transport: StubTransport) {
        transport.enqueueJSON("/graphql", viewerProjects)
        transport.enqueueJSON("/graphql", assignedPage1)
        transport.enqueueJSON("/graphql", assignedPage2)
    }

    static let issueNode = """
    {"data":{"node":{"__typename":"Issue","id":"I_1","number":1,"title":"Issue 1","body":"Beschreibung","state":"OPEN",
      "updatedAt":"2026-11-17T13:00:00Z","url":"https://github.com/beispiel/app/issues/1",
      "repository":{"nameWithOwner":"beispiel/app"},"assignees":{"nodes":[{"login":"octo"}]},"labels":{"nodes":[{"name":"bug"}]},
      "projectItems":{"nodes":[
        {"id":"PVTI_a","updatedAt":"2026-11-17T13:00:00Z","isArchived":false,
         "project":{"id":"PVT_1","number":1,"title":"App","closed":false,"fields":{"nodes":[
           {"id":"F_status","name":"Status","options":[{"id":"OPT_ready","name":"Ready"},{"id":"OPT_done","name":"Done"}]},
           {"id":"F_due","name":"Due date"}]}},
         "fieldValues":{"nodes":[{"name":"Done","field":{"name":"Status"}},{"date":"2026-11-21","field":{"name":"Due date"}}]}},
        {"id":"PVTI_closed","updatedAt":"2026-11-17T13:00:00Z","isArchived":false,
         "project":{"id":"PVT_9","number":9,"title":"Alt","closed":true,"fields":{"nodes":[]}},
         "fieldValues":{"nodes":[]}}
      ]}}}}
    """
}

extension Fixtures {
    /// Issue I_1 in project 1 (Status, Priority, Due date, Estimate (h)) and project 2 (Status, Due date, Estimate (MDs)).
    static func issue(state: String = "OPEN", status1: String = "Ready", status2: String = "Ready",
                      updatedAt: String = "2026-11-17T13:00:00Z", title: String = "Issue 1",
                      project2Writable: Bool = true, assignees: [String] = ["octo"]) -> String {
        let assigneeNodes = assignees.map { #"{"login":"\#($0)"}"# }.joined(separator: ",")
        return """
        {"data":{"node":{"__typename":"Issue","id":"I_1","number":1,"title":"\(title)","body":"Beschreibung","state":"\(state)",
          "updatedAt":"\(updatedAt)","url":"https://github.com/beispiel/app/issues/1",
          "repository":{"nameWithOwner":"beispiel/app"},"assignees":{"nodes":[\(assigneeNodes)]},"labels":{"nodes":[{"name":"bug"}]},
          "projectItems":{"nodes":[
            {"id":"PVTI_a","updatedAt":"2026-11-17T13:00:00Z","isArchived":false,
             "project":{"id":"PVT_1","number":1,"title":"App","closed":false,"fields":{"nodes":[
               {"id":"F_status","name":"Status","options":[{"id":"OPT_ready","name":"Ready"},{"id":"OPT_done","name":"Done"}]},
               {"id":"F_prio","name":"Priority","options":[{"id":"OPT_p1","name":"P1 (Very High)"},{"id":"OPT_p2","name":"P2 (High)"}]},
               {"id":"F_due","name":"Due date"},{"id":"F_est","name":"Estimate (h)"}]}},
             "fieldValues":{"nodes":[{"name":"\(status1)","field":{"name":"Status"}},{"date":"2026-11-20","field":{"name":"Due date"}}]}},
            {"id":"PVTI_c","updatedAt":"2026-11-17T13:00:00Z","isArchived":false,
             "project":{"id":"PVT_2","number":2,"title":"Studium","closed":false,"viewerCanUpdate":\(project2Writable),"fields":{"nodes":[
               {"id":"F2_status","name":"Status","options":[{"id":"OPT2_ready","name":"Ready"},{"id":"OPT2_done","name":"Done"}]},
               {"id":"F2_due","name":"Due date"},{"id":"F2_est","name":"Estimate (MDs)"}]}},
             "fieldValues":{"nodes":[{"name":"\(status2)","field":{"name":"Status"}}]}}
          ]}}}}
        """
    }

    static let mutationOK = #"{"data":{"updateProjectV2ItemFieldValue":{"projectV2Item":{"id":"x"}}}}"#
    static let clearOK = #"{"data":{"clearProjectV2ItemFieldValue":{"projectV2Item":{"id":"x"}}}}"#
    static let issuePatchOK = #"{"id":1,"node_id":"I_1","number":1}"#
}

extension Fixtures {
    /// One issue node of the online search: `items` are raw JSON project items.
    static func searchNode(id: String, number: Int, state: String = "OPEN", assignees: [String] = [], items: [String] = []) -> String {
        let people = assignees.map { #"{"login":"\#($0)"}"# }.joined(separator: ",")
        return """
        {"__typename":"Issue","id":"\(id)","number":\(number),"title":"Issue \(number)","body":"",
         "state":"\(state)","updatedAt":"2026-11-17T10:00:00Z","url":"https://github.com/octo/r/issues/\(number)",
         "repository":{"nameWithOwner":"octo/r"},"assignees":{"nodes":[\(people)]},"labels":{"nodes":[]},
         "projectItems":{"nodes":[\(items.joined(separator: ","))]}}
        """
    }

    static func searchResponse(_ nodes: [String]) -> String {
        #"{"data":{"search":{"nodes":["# + nodes.joined(separator: ",") + "]}}}"
    }
}
