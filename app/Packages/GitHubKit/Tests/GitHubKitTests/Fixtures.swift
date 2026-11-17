/// GraphQL responses with invented data, shaped like the real GitHub API.
enum Fixtures {
    static let viewerProjects = """
    {"data":{"viewer":{"login":"octo","projectsV2":{"nodes":[
      {"id":"PVT_1","number":1,"title":"App","closed":false,"fields":{"nodes":[
        {"id":"F_status","name":"Status","options":[{"id":"OPT_ready","name":"Ready"},{"id":"OPT_done","name":"Done"}]},
        {"id":"F_prio","name":"Priority","options":[{"id":"OPT_p2","name":"P2 (High)"},{"id":"OPT_p3","name":"P3 (Medium)"}]},
        {"id":"F_due","name":"Due date"},
        {"id":"F_est","name":"Estimate (h)"},
        {"id":"F_title","name":"Title"}
      ]}},
      {"id":"PVT_2","number":2,"title":"Studium","closed":false,"fields":{"nodes":[
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

    static let itemsProject1Page1 = """
    {"data":{"node":{"items":{"pageInfo":{"hasNextPage":true,"endCursor":"CURSOR_1"},"nodes":[
      {"id":"PVTI_a","updatedAt":"2026-11-17T11:00:00Z","isArchived":false,"fieldValues":{"nodes":[
        {"name":"Ready","field":{"name":"Status"}},
        {"name":"P3 (Medium)","field":{"name":"Priority"}},
        {"date":"2026-11-20","field":{"name":"Due date"}},
        {"number":1.5,"field":{"name":"Estimate (h)"}},
        {}
      ]},"content":\(issueContent(id: "I_1", number: 1))},
      {"id":"PVTI_draft","updatedAt":"2026-11-17T11:00:00Z","isArchived":false,"fieldValues":{"nodes":[]},
       "content":{"__typename":"DraftIssue"}},
      {"id":"PVTI_pr","updatedAt":"2026-11-17T11:00:00Z","isArchived":false,"fieldValues":{"nodes":[]},
       "content":{"__typename":"PullRequest"}}
    ]}}}}
    """

    static let itemsProject1Page2 = """
    {"data":{"node":{"items":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
      {"id":"PVTI_b","updatedAt":"2026-11-17T11:00:00Z","isArchived":false,"fieldValues":{"nodes":[]},
       "content":\(issueContent(id: "I_2", number: 2, state: "CLOSED"))},
      {"id":"PVTI_archived","updatedAt":"2026-11-17T11:00:00Z","isArchived":true,"fieldValues":{"nodes":[]},
       "content":\(issueContent(id: "I_3", number: 3))}
    ]}}}}
    """

    static let itemsProject2 = """
    {"data":{"node":{"items":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
      {"id":"PVTI_c","updatedAt":"2026-11-17T12:00:00Z","isArchived":false,"fieldValues":{"nodes":[
        {"name":"Ready","field":{"name":"Status"}},
        {"date":"2026-11-18","field":{"name":"Due date"}},
        {"number":0.5,"field":{"name":"Estimate (MDs)"}}
      ]},"content":\(issueContent(id: "I_1", number: 1))}
    ]}}}}
    """

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
